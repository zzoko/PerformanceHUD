import AppKit

/// A compact presentation of the same readings. It owns no polling or saved
/// metric choices; the controller supplies text and style from the vertical HUD.
@MainActor
final class HUDHorizontalView: NSView {
    struct CoreRow {
        let name: String
        let caption: String
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
        var pressureHistory: HUDMemoryPressureHistory? = nil
        var coreRows: [CoreRow]? = nil
    }

    let storage = HUDStorageView(horizontal: true)
    let battery = HUDBatteryIndicatorView(frame: .zero)
    private(set) var fpsSectionWidth: CGFloat = 0
    private var fpsLabels: [NSTextField] = []

    func setFPSOpacity(_ opacity: CGFloat) {
        fpsLabels.forEach { $0.alphaValue = opacity }
    }

    // Snap once the host has its final position and scale. Keep the logical
    // widths used for measurement independent of the display's pixel grid.
    func alignReadingFrames(fpsHeightRounding: CGFloat = 0) {
        for view in subviews where !view.isHidden {
            var frame = view.frame
            if fpsHeightRounding != 0 && fpsLabels.contains(where: { $0 === view }) {
                frame.origin.y += fpsHeightRounding
            }
            // A changing strip origin must not change a reserved column's width.
            var aligned = backingAlignedRect(frame, options: [.alignMinXNearest, .alignMinYNearest,
                                                              .alignWidthNearest, .alignHeightNearest])
            if aligned.width == 0 && frame.width > 0 {
                aligned.size.width = convertFromBacking(NSSize(width: 1, height: 1)).width
            }
            if view.frame != aligned {
                view.frame = aligned
                if view is HUDMemoryPressureHistoryView {
                    view.bounds = NSRect(origin: .zero, size: HUDMemoryPressureHistoryView.menuBarReferenceSize)
                }
            }
        }
    }

    private var labels: [String: NSTextField] = [:]
    private var dividers: [NSView] = []
    private var symbols: [String: NSImageView] = [:]
    private var bars: [String: HUDFanBarView] = [:]
    private var coreBars: [String: HUDCPUCoreBarsView] = [:]
    private var pressureMeters: [String: HUDMemoryPressureMeterView] = [:]
    private var pressureHistories: [String: HUDMemoryPressureHistoryView] = [:]

    override init(frame: NSRect) {
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
        let label = NSTextField(labelWithString: "")
        labels[id] = label
        addSubview(label)
        return label
    }

    private func placeCoreRows(_ rows: ArraySlice<CoreRow>, at x: CGFloat, centerY: CGFloat,
                               reading: Reading, scale: HUDScale, background: HUDBackground) -> CGFloat {
        let factor = CGFloat(scale.rawValue)
        let labelFont = HUDStyle.smallLabelFont(scale: scale)
        let widestCaption = rows.map {
            HUDStyle.horizontalColumnWidth(text: $0.caption, reference: $0.caption, font: labelFont)
        }.max() ?? 0
        let pitch = (rows.count == 3 ? HUDCoreBarLayout.rowStride : 18) * factor
        let frequencyStart = x + widestCaption + HUDStyle.memoryLabelValueSpacing * factor
        let frequencyWidth = HUDStyle.horizontalColumnWidth(text: "", reference: HUDStyle.horizontalFrequencyReference,
            font: HUDStyle.readingFont(scale: scale, highlighted: true))
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
                barStart += frequencyWidth + HUDStyle.metricColumnSpacing(scale: scale)
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
            let width = (count * HUDCoreBarLayout.barWidth + max(0, count - 1) * HUDCoreBarLayout.columnGap) * factor
            let h = HUDCoreBarLayout.barHeight * factor
            bars.frame = NSRect(x: barStart, y: y - h / 2, width: width, height: h)
            bars.scale = factor
            bars.tint = reading.color
            bars.values = row.activity
            bars.setAccessibilityValue(row.activity.map { $0.map { "\(Int($0.rounded()))%" } ?? "unavailable" }.joined(separator: ", "))
            bars.isHidden = false
            end = max(end, bars.frame.maxX)
        }
        return end
    }

    func configure(sections: [[Reading]], showsBattery: Bool, scale: HUDScale, background: HUDBackground,
                   fpsValueSize: HUDFPSValueSize = .standard) -> NSSize {
        fpsSectionWidth = 0
        fpsLabels.removeAll()
        let factor = CGFloat(scale.rawValue)
        let reference = NSTextField(labelWithString: "FPS")
        reference.font = HUDStyle.titleFont(for: .fps, scale: scale)
        let hasFPSValue = sections.joined().contains { $0.metric == .fps && !$0.startsMetric }
        let fpsSize = hasFPSValue ? fpsValueSize : .standard
        // The enlarged number can extend into the strip’s vertical padding, like the core bars.
        let height = HUDStyle.rowHeight(scale: scale)
        let gap = HUDStyle.metricColumnSpacing(scale: scale)
        let referenceHeight = reference.intrinsicContentSize.height
        let baseline = (height - referenceHeight) / 2 + referenceHeight - reference.firstBaselineOffsetFromTop
        labels.values.forEach { $0.isHidden = true }
        symbols.values.forEach { $0.isHidden = true }
        coreBars.values.forEach { $0.isHidden = true }
        bars.values.forEach { $0.isHidden = true }
        pressureMeters.values.forEach { $0.isHidden = true }
        pressureHistories.values.forEach { $0.isHidden = true }
        dividers.forEach { $0.isHidden = true }
        storage.isHidden = true
        battery.isHidden = !showsBattery
        battery.applyStyle(scale: scale, background: background)
        var x: CGFloat = 0
        var dividerIndex = 0
        func addDivider(faint: Bool = false) {
            guard x > 0 else { return }
            let width = (faint ? 0.5 : 1.5) * factor
            let padding = (16 * factor - width) / 2
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
            divider.frame = NSRect(x: x, y: 2 * factor, width: width, height: max(0, height - 4 * factor))
            x += padding + width
        }
        for section in sections where !section.isEmpty {
            addDivider()
            let sectionStart = x
            for (index, reading) in section.enumerated() {
                if index > 0 {
                    if reading.startsMetric {
                        let sameFanCategory = reading.metric == .fans && section[index - 1].metric == .fans
                        addDivider(faint: sameFanCategory)
                    } else {
                        // Fan badge/bar/RPM use the same compact gap on both sides of the bar.
                        let followsLabel = section[index - 1].startsMetric && reading.metric != .fps && reading.metric != .fans
                        if let leadingGap = reading.leadingGap { x += leadingGap * factor }
                        else { x += followsLabel && reading.leftAligned ? 2 * gap : gap }
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
                    for start in stride(from: 0, to: rows.count, by: 3) {
                        if start > 0 { x += gap }
                        x = placeCoreRows(rows[start..<min(start + 3, rows.count)], at: x,
                            centerY: height / 2, reading: reading, scale: scale, background: background)
                    }
                    continue
                }
                if let mode = reading.pressureMode, mode.isHistory {
                    let graph = pressureHistories[reading.id] ?? HUDMemoryPressureHistoryView()
                    if pressureHistories[reading.id] == nil {
                        pressureHistories[reading.id] = graph
                        graph.translatesAutoresizingMaskIntoConstraints = true
                        addSubview(graph)
                    }
                    let reference = HUDMemoryPressureHistoryView.menuBarReferenceSize
                    let graphHeight = HUDStyle.rowHeight(scale: scale)
                    let graphWidth = reference.width * graphHeight / reference.height
                    graph.configure(mode: mode, scale: .normal, background: background, width: reference.width)
                    graph.setHistory(reading.pressureHistory ?? .init())
                    graph.showsBaseline = true
                    graph.isHidden = false
                    graph.frame = NSRect(x: x, y: (height - graphHeight) / 2, width: graphWidth, height: graphHeight)
                    graph.bounds = NSRect(origin: .zero, size: reference)
                    x += graphWidth
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
                    meter.configure(mode: mode, scale: scale, background: background, stacked: true)
                    meter.update(reading.text)
                    let size = meter.intrinsicContentSize
                    // Centre the compact bars in a normal-pressure word slot.
                    // This padding is stable across states and text emphasis.
                    let normalFont = HUDStyle.readingFont(scale: scale, highlighted: false)
                    let slotWidth = max(size.width, HUDStyle.horizontalColumnWidth(
                        text: "normal", reference: "normal", font: normalFont))
                    let capHeight = HUDStyle.readingFont(scale: scale, highlighted: false).capHeight
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
                    let barHeight = HUDFanBarView.horizontalSize.height * factor
                    bar.frame = NSRect(x: x, y: baseline + (reading.font.capHeight - barHeight) / 2,
                                       width: barWidth * factor, height: barHeight)
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
                    let side = HUDFanIcon.side * factor
                    icon.frame = NSRect(x: x, y: (height - side) / 2, width: side, height: side)
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
                if reading.metric == .fans, index > 0, section[index - 1].fanMarker != nil,
                   section.indices.contains(index + 1), section[index + 1].barWidth != nil {
                    // Split the reserved RPM column's spare space equally
                    // between the fan icon and its following bar.
                    label.alignment = .center
                }
                let width = HUDStyle.horizontalColumnWidth(text: reading.text, reference: reading.reference,
                    font: reading.font, sizingFont: reading.sizingFont)
                let labelHeight = ceil(label.intrinsicContentSize.height)
                if reading.leadingGap != nil && reading.leftAligned, index > 0,
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
                if index == 0 || reading.startsMetric { x += label.alignmentRectInsets.left }
                let isLargeFPS = reading.metric == .fps && !reading.startsMetric && fpsSize == .enlarged
                let y = isLargeFPS ? (height - labelHeight) / 2
                    : baseline - labelHeight + label.firstBaselineOffsetFromTop
                let alignmentRect = NSRect(x: x, y: y,
                                           width: width, height: labelHeight)
                label.frame = label.frame(forAlignmentRect: alignmentRect)
                x += width
                if index == section.count - 1 || section[index + 1].startsMetric {
                    x += label.alignmentRectInsets.right
                }
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
