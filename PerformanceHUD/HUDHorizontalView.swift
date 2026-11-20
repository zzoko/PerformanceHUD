import AppKit

/// A compact presentation of the same readings. It owns no polling or saved
/// metric choices; the controller supplies text and style from the vertical HUD.
@MainActor
final class HUDHorizontalView: NSView {
    struct CoreRow {
        let name: String
        var caption: String {
            switch name {
            case "Super": return "S"
            case "Efficiency": return "E"
            case "Performance": return "P"
            default: return name
            }
        }
        let frequency: String?
        let activity: [Double?]
    }

    struct Reading {
        let id: String
        let text: String
        let reference: String
        let font: NSFont
        let color: NSColor
        let help: String?
        let startsMetric: Bool
        var metric: HUDMetric? = nil
        var leadingGap: CGFloat? = nil // Points at normal HUD scale.
        var leftAligned = false
        var fanMarker: String? = nil
        var barWidth: CGFloat? = nil
        var barFraction: Double? = nil
        var sizingFont: NSFont? = nil
        var pressureMode: HUDMemoryPressureMode? = nil
        var coreRows: [CoreRow]? = nil
    }

    static func memoryDetails(swap: String, physical: String, valueFont: NSFont, background: HUDBackground) -> [Reading] {
        let metric = HUDMetric.ramTotal
        return [("SWP", swap, "System swap used."), ("PHY", physical, "System physical memory used.")].flatMap { caption, value, help in
            let prefix = "\(metric.rawValue).\(caption)"
            return [
                Reading(id: "\(prefix).title", text: caption, reference: caption,
                    font: HUDStyle.smallLabelFont(), color: HUDStyle.TextStyle.label.color(background: background),
                    help: help, startsMetric: false, metric: metric, leftAligned: true),
                Reading(id: "\(prefix).value", text: value, reference: "999.99 GB",
                    font: valueFont, color: HUDStyle.readingColor(background: background), help: help,
                    startsMetric: false, metric: metric, leadingGap: HUDStyle.memoryLabelValueSpacing, leftAligned: true)
            ]
        }
    }

    static func fanReadings(sample: FanSample, options: HUDFanOptions, background: HUDBackground, barWidth: CGFloat? = nil) -> [Reading] {
        let fans = sample.displayReadings(averaged: options.averages(in: .horizontal))
        guard !fans.isEmpty else {
            return [Reading(id: "fan.status", text: sample.message ?? "Fan readings unavailable",
                reference: "Fan readings unavailable", font: HUDStyle.smallLabelFont(),
                color: HUDStyle.TextStyle.label.color(background: background), help: nil, startsMetric: true, metric: .fans)]
        }
        let color = HUDStyle.titleColor(for: .fans, background: background)
        return fans.flatMap { fan -> [Reading] in
            var values = [Reading(id: "fan.\(fan.id).title", text: fan.title, reference: fan.title,
                font: HUDStyle.titleFont(for: .fans), color: color,
                help: fan.id == "average" ? "Average fan speed" : fan.title,
                startsMetric: true, metric: .fans, fanMarker: fan.iconMarker)]
            if options.mode.showsRPM {
                values.append(Reading(id: "fan.\(fan.id).rpm", text: fan.rpmText, reference: FanDisplayReading.rpmWidthReference,
                    font: HUDStyle.readingFont(highlighted: options.rpmHighlighted),
                    color: HUDStyle.readingColor(background: background), help: nil, startsMetric: false, metric: .fans,
                    sizingFont: HUDStyle.readingFont(highlighted: true)))
            }
            if options.mode.showsBar, let barWidth {
                values.append(Reading(id: "fan.\(fan.id).bar", text: "", reference: "",
                    font: HUDStyle.readingFont(highlighted: false), color: color,
                    help: "\(fan.title) speed relative to maximum", startsMetric: false, metric: .fans,
                    barWidth: barWidth, barFraction: fan.fraction))
            }
            return values
        }
    }

    let storage = HUDStorageView(horizontal: true)
    let battery = HUDBatteryIndicatorView(frame: .zero)
    private(set) var fpsSectionWidth: CGFloat = 0
    private var fpsLabels: [NSTextField] = []

    func setFPSOpacity(_ opacity: CGFloat) {
        fpsLabels.forEach { $0.alphaValue = opacity }
    }

    // The HUD supplies its untransformed viewport to preserve the 1× grid.
    // Status items use their own final backing grid, as their native layout requires.
    func alignReadingFrames(on baseGrid: NSView? = nil, fpsHeightRounding: CGFloat = 0) {
        let referenceGrid = baseGrid ?? self
        for view in subviews where !view.isHidden {
            var frame = view.frame
            if fpsHeightRounding != 0 && fpsLabels.contains(where: { $0 === view }) {
                frame.origin.y += fpsHeightRounding
            }
            // A changing strip origin must not change a reserved column's width.
            // The gap before RPM is measured from the fan badge’s trailing edge.
            let horizontalEdge: AlignmentOptions = view is NSImageView ? .alignMaxXNearest : .alignMinXNearest
            var aligned = referenceGrid.backingAlignedRect(frame, options: [horizontalEdge, .alignMinYNearest,
                                                              .alignWidthNearest, .alignHeightNearest])
            if aligned.width == 0 && frame.width > 0 {
                aligned.size.width = referenceGrid.convertFromBacking(NSSize(width: 1, height: 1)).width
            }
            if view.frame != aligned {
                view.frame = aligned
            }
        }
        if baseGrid != nil {
            dividerFrames = dividers.prefix { !$0.isHidden }.map(\.frame)
            updateHairlines()
        }
    }

    private var labels: [String: NSTextField] = [:]
    private var dividers: [NSView] = []
    private var dividerFrames: [NSRect] = []

    func updateHairlines() {
        guard window != nil else { return }
        let pixel = convertFromBacking(NSSize(width: 1, height: 1)).width
        for (divider, base) in zip(dividers, dividerFrames) {
            var rect = base
            if base.width < pixel {
                rect.origin.x = base.midX - pixel / 2
                rect.size.width = pixel
                rect.origin.x = backingAlignedRect(rect, options: [.alignAllEdgesNearest]).minX
            }
            if rect != divider.frame { divider.frame = rect }
        }
        storage.needsDisplay = true
    }
    private var symbols: [String: NSImageView] = [:]
    private var bars: [String: HUDFanBarView] = [:]
    private var coreBars: [String: HUDCPUCoreBarsView] = [:]
    private var pressureMeters: [String: HUDMemoryPressureMeterView] = [:]

    private let makeReadingLabel: @MainActor () -> NSTextField

    init(frame: NSRect, makeReadingLabel: @escaping @MainActor () -> NSTextField = { NSTextField(labelWithString: "") }) {
        self.makeReadingLabel = makeReadingLabel
        super.init(frame: frame)
        battery.setHorizontal(true)
        storage.isHidden = true
        addSubview(storage)
        addSubview(battery)
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    private func label(for id: String) -> NSTextField {
        if let existing = labels[id] { return existing }
        let label = makeReadingLabel()
        labels[id] = label
        addSubview(label)
        return label
    }

    private func placeCoreRows(_ rows: ArraySlice<CoreRow>, at x: CGFloat, centerY: CGFloat,
                               reading: Reading, background: HUDBackground) -> CGFloat {
        let labelFont = HUDStyle.smallLabelFont()
        let widestCaption = rows.map {
            HUDStyle.horizontalColumnWidth(text: $0.caption, reference: $0.caption, font: labelFont)
        }.max() ?? 0
        let pitch = (rows.count == 3 ? HUDCoreBarLayout.rowStride : 18)
        let frequencyStart = x + widestCaption + HUDStyle.memoryLabelValueSpacing
        let frequencyWidth = HUDStyle.horizontalColumnWidth(text: "", reference: HUDStyle.horizontalFrequencyReference,
            font: HUDStyle.readingFont(highlighted: true))
        var end = x
        for (index, row) in rows.enumerated() {
            let y = centerY + (CGFloat(rows.count - 1) / 2 - CGFloat(index)) * pitch
            let prefix = "\(HUDMetric.cpuCores.rawValue).\(row.name)"
            func place(_ role: String, _ text: String, _ font: NSFont, _ color: NSColor,
                       _ left: CGFloat, _ width: CGFloat) {
                let field = label(for: "\(prefix).\(role)")
                field.stringValue = text
                field.font = font
                field.textColor = color
                field.alignment = role == "value" ? .right : .left
                field.isHidden = false
                field.setAccessibilityLabel(role == "value" ? "\(row.name) frequency" : row.name)
                let h = field.intrinsicContentSize.height
                field.frame = field.frame(forAlignmentRect: NSRect(x: left, y: y - h / 2, width: width, height: h))
            }
            place("title", row.caption, labelFont, HUDStyle.TextStyle.label.color(background: background), x, widestCaption)
            var barStart = frequencyStart
            if let frequency = row.frequency {
                place("value", frequency, reading.font, reading.color, frequencyStart, frequencyWidth)
                barStart += frequencyWidth + HUDStyle.metricColumnSpacing
            }
            let bars = coreBars[prefix] ?? HUDCPUCoreBarsView()
            if coreBars[prefix] == nil {
                coreBars[prefix] = bars
                bars.singleRow = true
                bars.setAccessibilityElement(true)
                bars.setAccessibilityLabel("\(row.name) core activity")
                addSubview(bars)
            }
            let count = CGFloat(row.activity.count)
            let width = (count * HUDCoreBarLayout.barWidth + max(0, count - 1) * HUDCoreBarLayout.columnGap)
            let h = HUDCoreBarLayout.barHeight
            bars.frame = NSRect(x: barStart, y: y - h / 2, width: width, height: h)
            bars.tint = reading.color
            bars.values = row.activity
            bars.setAccessibilityValue(row.activity.map { $0.map { "\(Int($0.rounded()))%" } ?? "unavailable" }.joined(separator: ", "))
            bars.isHidden = false
            end = max(end, bars.frame.maxX)
        }
        return end
    }

    func configure(sections: [[Reading]], showsBattery: Bool, background: HUDBackground,
                   fpsValueSize: HUDFPSValueSize = .standard, reservedFPSContentWidth: CGFloat? = nil,
                   inMenuBar: Bool = false) -> NSSize {
        fpsSectionWidth = 0
        fpsLabels.removeAll()
        let reference = NSTextField(labelWithString: "FPS")
        reference.font = HUDStyle.titleFont(for: .fps)
        let hasFPSValue = sections.joined().contains { $0.metric == .fps && !$0.startsMetric }
        let fpsSize = hasFPSValue ? fpsValueSize : .standard
        // The enlarged number can extend into the strip’s vertical padding, like the core bars.
        let height = HUDStyle.rowHeight
        let gap = HUDStyle.metricColumnSpacing
        let referenceHeight = reference.intrinsicContentSize.height
        let baseline = (height - referenceHeight) / 2 + referenceHeight - reference.firstBaselineOffsetFromTop
        labels.values.forEach { $0.isHidden = true }
        symbols.values.forEach { $0.isHidden = true }
        coreBars.values.forEach { $0.isHidden = true }
        bars.values.forEach { $0.isHidden = true }
        pressureMeters.values.forEach { $0.isHidden = true }
        dividers.forEach { $0.isHidden = true }
        storage.isHidden = true
        battery.isHidden = !showsBattery
        battery.applyStyle(background: background)
        var x: CGFloat = 0
        var dividerIndex = 0
        func addDivider(faint: Bool = false) {
            guard x > 0 else { return }
            let width: CGFloat = faint ? 0.5 : 1.5
            let padding = (16 - width) / 2
            x += padding
            if dividerIndex == dividers.count {
                let divider = NSView()
                divider.wantsLayer = true
                dividers.append(divider)
                addSubview(divider)
            }
            let divider = dividers[dividerIndex]
            dividerIndex += 1
            divider.isHidden = false
            let color = HUDStyle.separatorColor(background: background)
            divider.layer?.backgroundColor = (faint ? color : color.withAlphaComponent(0.4)).cgColor
            divider.frame = NSRect(x: x, y: 2, width: width, height: max(0, height - 4))
            x += padding + width
        }
        func placeRow(_ section: ArraySlice<Reading>, offsetY: CGFloat = 0) {
            let rowStart = x
            for index in section.indices {
                let reading = section[index]
                if index > section.startIndex {
                    if reading.startsMetric {
                        let sameFanCategory = reading.metric == .fans && section[index - 1].metric == .fans
                        addDivider(faint: sameFanCategory)
                    } else {
                        let followsLabel = section[index - 1].startsMetric && reading.metric != .fps
                        let usesLabelGap = followsLabel && (reading.leftAligned || reading.barWidth != nil)
                        if let leadingGap = reading.leadingGap { x += leadingGap }
                        else { x += usesLabelGap ? 2 * gap : gap }
                    }
                }
                if reading.metric == .storage {
                    let size = storage.contentSize
                    storage.frame = NSRect(x: x, y: (height - size.height) / 2, width: size.width, height: size.height)
                    storage.isHidden = false
                    x += size.width
                    continue
                }
                if let rows = reading.coreRows {
                    let rowsPerColumn = inMenuBar ? 1 : 3
                    for start in stride(from: 0, to: rows.count, by: rowsPerColumn) {
                        if start > 0 { x += gap }
                        x = placeCoreRows(rows[start..<min(start + rowsPerColumn, rows.count)], at: x,
                            centerY: height / 2, reading: reading, background: background)
                    }
                    continue
                }
                if let mode = reading.pressureMode, mode.display == .meter {
                    let meter = pressureMeters[reading.id] ?? HUDMemoryPressureMeterView()
                    if pressureMeters[reading.id] == nil {
                        pressureMeters[reading.id] = meter
                        meter.translatesAutoresizingMaskIntoConstraints = true
                        addSubview(meter)
                    }
                    meter.isHidden = false
                    meter.configure(mode: mode, background: background, stacked: true)
                    meter.update(reading.text)
                    let size = meter.intrinsicContentSize
                    // Centre the compact bars in a normal-pressure word slot.
                    // This padding is stable across states and text emphasis.
                    let normalFont = HUDStyle.readingFont(highlighted: false)
                    let slotWidth = max(size.width, HUDStyle.horizontalColumnWidth(
                        text: "normal", reference: "normal", font: normalFont))
                    let capHeight = HUDStyle.readingFont(highlighted: false).capHeight
                    meter.frame = NSRect(x: x + (slotWidth - size.width) / 2,
                                         y: baseline + (capHeight - size.height) / 2,
                                         width: size.width, height: size.height)
                    x += slotWidth
                    continue
                }
                if let barWidth = reading.barWidth {
                    let bar = bars[reading.id] ?? HUDFanBarView()
                    if bars[reading.id] == nil { bars[reading.id] = bar; addSubview(bar) }
                    bar.isHidden = false
                    bar.color = reading.color
                    bar.fraction = reading.barFraction
                    bar.setAccessibilityElement(true)
                    bar.setAccessibilityRole(.levelIndicator)
                    bar.setAccessibilityLabel(reading.help ?? "Fan speed")
                    bar.setAccessibilityValue(reading.barFraction.map { NSNumber(value: $0) })
                    let barHeight = HUDFanBarView.horizontalSize.height
                    bar.frame = NSRect(x: x, y: offsetY + baseline + (reading.font.capHeight - barHeight) / 2,
                                       width: barWidth, height: barHeight)
                    bar.needsDisplay = true
                    x += bar.frame.width
                    continue
                }
                if let marker = reading.fanMarker {
                    let icon = symbols[reading.id] ?? NSImageView()
                    if symbols[reading.id] == nil { symbols[reading.id] = icon; addSubview(icon) }
                    icon.isHidden = false
                    icon.image = HUDFanIcon.image(marker: marker)
                    icon.contentTintColor = reading.color
                    icon.imageScaling = .scaleProportionallyUpOrDown
                    icon.setAccessibilityElement(true)
                    icon.setAccessibilityRole(.image)
                    icon.setAccessibilityLabel(reading.help ?? reading.text)
                    let side = HUDFanIcon.side
                    icon.frame = NSRect(x: x, y: offsetY + (height - side) / 2, width: side, height: side)
                    x += side
                    continue
                }
                let label = label(for: reading.id)
                label.isHidden = false
                label.alphaValue = 1
                if reading.metric == .fps { fpsLabels.append(label) }
                label.stringValue = reading.text
                label.font = reading.font
                label.textColor = reading.color
                label.setAccessibilityHelp(reading.help)
                label.alignment = reading.startsMetric || reading.leftAligned ? .left : .right
                if !inMenuBar, index > section.startIndex, section[index - 1].fanMarker != nil {
                    // Keep RPM centered in the same slot whether the HUD shows its bar or not.
                    label.alignment = .center
                }
                let width: CGFloat
                if let reservedFPSContentWidth, reading.metric == .fps, !reading.startsMetric {
                    // Keep the FPS reading at the same trailing edge as sections are appended.
                    width = reservedFPSContentWidth - (x - rowStart) - label.alignmentRectInsets.right
                } else {
                    width = HUDStyle.horizontalColumnWidth(text: reading.text, reference: reading.reference,
                        font: reading.font, sizingFont: reading.sizingFont)
                }
                let labelHeight = ceil(label.intrinsicContentSize.height)
                if reading.leadingGap != nil && reading.leftAligned, index > section.startIndex,
                   let title = labels[section[index - 1].id] {
                    // Reserve a stable value column, but move its short label with
                    // the right-aligned value to retain the tight label/value gap.
                    // This never changes the row width or window geometry.
                    let unusedWidth = width - label.intrinsicContentSize.width
                    title.frame.origin.x += unusedWidth
                    label.alignment = .right
                }
                // Intrinsic size describes the alignment rectangle. NSTextField
                // also needs its side insets in the frame, or it clips glyphs.
                // At divider and outer edges, keep the full label frame inside its section.
                if index == section.startIndex || reading.startsMetric { x += label.alignmentRectInsets.left }
                let isLargeFPS = reading.metric == .fps && !reading.startsMetric && fpsSize == .enlarged
                let y = isLargeFPS ? (height - labelHeight) / 2
                    : baseline - labelHeight + label.firstBaselineOffsetFromTop
                let alignmentRect = NSRect(x: x, y: offsetY + y,
                                           width: width, height: labelHeight)
                label.frame = label.frame(forAlignmentRect: alignmentRect)
                x += width
                if index + 1 == section.endIndex || section[index + 1].startsMetric {
                    x += label.alignmentRectInsets.right
                }
            }
        }
        for section in sections where !section.isEmpty {
            addDivider()
            let sectionStart = x
            let fanStarts = !inMenuBar && section.first?.metric == .fans
                ? section.indices.filter { section[$0].startsMetric } : []
            if fanStarts.count > 1 {
                // Two 20 pt badges share the strip's padding, with 3 pt between them.
                let rowOffset = (HUDFanIcon.side + 3) / 2
                for first in stride(from: 0, to: fanStarts.count, by: 2) {
                    if first > 0 { addDivider(faint: true) }
                    let columnStart = x
                    var columnEnd = x
                    for fan in first..<min(first + 2, fanStarts.count) {
                        let end = fan + 1 < fanStarts.count ? fanStarts[fan + 1] : section.endIndex
                        x = columnStart
                        placeRow(section[fanStarts[fan]..<end], offsetY: fan == first ? rowOffset : -rowOffset)
                        columnEnd = max(columnEnd, x)
                    }
                    x = columnEnd
                }
            } else {
                placeRow(section[...])
            }
            if section.first?.metric == .fps {
                fpsSectionWidth = x - sectionStart
            }
        }
        if showsBattery {
            addDivider()
            let width = ceil(battery.minimumRowWidth)
            battery.frame = NSRect(x: x, y: 0, width: width, height: height)
            x += width
        }
        return NSSize(width: x, height: height)
    }
}
