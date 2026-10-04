import AppKit

/// A compact presentation of the same readings. It owns no polling or saved
/// metric choices; the controller supplies text and style from the vertical HUD.
@MainActor
final class HUDHorizontalView: NSView {
    struct Reading {
        let id: String
        let text: String
        let reference: String
        let font: NSFont
        let color: NSColor
        let help: String?
        let startsMetric: Bool
        var resourceGroup: HUDResourceGroup? = nil
        var metric: HUDMetric? = nil
        var tightLeading = false
        var leftAligned = false
        var fanMarker: String? = nil
        var symbolName: String? = nil
        var symbolVisible = true
        var barWidth: CGFloat? = nil
        var barFraction: Double? = nil
        var sizingFont: NSFont? = nil
    }

    let battery = HUDBatteryIndicatorView(frame: .zero)
    private(set) var fpsSectionWidth: CGFloat = 0
    private var fpsLabels: [NSTextField] = []

    func setFPSOpacity(_ opacity: CGFloat) {
        fpsLabels.forEach { $0.alphaValue = opacity }
    }

    // Auto Layout pixel-aligns the vertical FPS row. Match that placement after
    // the horizontal host has its final frame, including rounded outer height.
    func alignFPSVertically(heightRounding: CGFloat) {
        for label in fpsLabels {
            let frame = label.frame.offsetBy(dx: 0, dy: heightRounding)
            let aligned = backingAlignedRect(frame, options: .alignAllEdgesNearest)
            label.setFrameOrigin(NSPoint(x: frame.minX, y: aligned.minY))
        }
    }

    private var labels: [String: NSTextField] = [:]
    private var dividers: [NSView] = []
    private var symbols: [String: NSImageView] = [:]
    private var bars: [String: HUDFanBarView] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        battery.setHorizontal(true)
        addSubview(battery)
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(sections: [[Reading]], showsBattery: Bool, scale: HUDScale, background: HUDBackground) -> NSSize {
        fpsSectionWidth = 0
        fpsLabels.removeAll()
        let factor = CGFloat(scale.rawValue)
        let reference = NSTextField(labelWithString: "FPS")
        reference.font = HUDStyle.titleFont(for: .fps, scale: scale)
        let height = HUDStyle.rowHeight(scale: scale)
        let gap = HUDStyle.metricColumnSpacing(scale: scale)
        let referenceHeight = reference.intrinsicContentSize.height
        let baseline = (height - referenceHeight) / 2 + referenceHeight - reference.firstBaselineOffsetFromTop
        labels.values.forEach { $0.isHidden = true }
        symbols.values.forEach { $0.isHidden = true }
        bars.values.forEach { $0.isHidden = true }
        dividers.forEach { $0.isHidden = true }
        battery.isHidden = !showsBattery
        battery.applyStyle(scale: scale, background: background)
        var x: CGFloat = 0
        var dividerIndex = 0
        func addDivider(compact: Bool = false, faint: Bool = false) {
            guard x > 0 else { return }
            let width = (faint ? 0.5 : 1.5) * factor
            // Keep the existing 16pt gap between resources.
            let padding = compact ? (16 * factor - width) / 2 : 12 * factor
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
            let compactFPSWidth = section.first?.metric == .fps
                ? HUDStyle.compactFPSValueColumnRight(scale: scale) : nil
            var previousResource: HUDResourceGroup?
            for (index, reading) in section.enumerated() {
                if index > 0 {
                    if reading.startsMetric {
                        let sameFanCategory = reading.metric == .fans && section[index - 1].metric == .fans
                        addDivider(compact: true, faint: sameFanCategory
                            || (reading.resourceGroup != nil && reading.resourceGroup == previousResource))
                    } else {
                        // Fan badge/bar/RPM use the same compact gap on both sides of the bar.
                        let followsLabel = section[index - 1].startsMetric && reading.metric != .fps && reading.metric != .fans
                        let labelGap = followsLabel && reading.resourceGroup == .ram && reading.text == "PHY"
                            ? 2 : HUDStyle.horizontalLabelGapMultiplier
                        let bordersSymbol = reading.symbolName != nil || section[index - 1].symbolName != nil
                        // A compact fixed slot: the triangle fits between the
                        // readings without adding space when pressure changes.
                        x += reading.tightLeading ? HUDStyle.memoryLabelValueSpacing * factor : gap * (bordersSymbol ? 0.25 : followsLabel ? labelGap : 1)
                    }
                }
                previousResource = reading.resourceGroup
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
                if let symbolName = reading.symbolName {
                    let symbol = symbols[reading.id] ?? NSImageView()
                    if symbols[reading.id] == nil { symbols[reading.id] = symbol; addSubview(symbol) }
                    symbol.isHidden = !reading.symbolVisible
                    symbol.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: reading.help)?
                        .withSymbolConfiguration(.init(pointSize: reading.font.pointSize, weight: .regular))
                    symbol.contentTintColor = reading.color
                    symbol.setAccessibilityHelp(reading.help)
                    let side = ceil(reading.font.pointSize + 2 * factor)
                    symbol.imageScaling = .scaleProportionallyUpOrDown
                    // SF Symbols include baseline padding. Center their alignment
                    // rectangle on the capital letters, rather than the image canvas.
                    // A small optical lift compensates for AppKit’s symbol placement.
                    var opticalOffset: CGFloat = 0.75 * factor
                    if let image = symbol.image, image.size.width > 0, image.size.height > 0 {
                        let fit = min(side / image.size.width, side / image.size.height)
                        opticalOffset += (image.size.height / 2 - image.alignmentRect.midY) * fit
                    }
                    symbol.frame = NSRect(x: x, y: baseline + (reading.font.capHeight - side) / 2 + opticalOffset,
                                          width: side, height: side)
                    x += side
                    continue
                }
                let label: NSTextField
                if let existing = labels[reading.id] { label = existing }
                else {
                    label = NSTextField(labelWithString: "")
                    labels[reading.id] = label
                    addSubview(label)
                }
                label.isHidden = false
                label.alphaValue = 1
                if reading.metric == .fps { fpsLabels.append(label) }
                label.stringValue = reading.text
                label.font = reading.font
                label.textColor = reading.color
                label.setAccessibilityHelp(reading.help)
                label.alignment = reading.startsMetric || reading.leftAligned ? .left : .right
                let sizing = NSTextField(labelWithString: reading.reference)
                sizing.font = reading.sizingFont ?? reading.font
                let width = ceil(max(sizing.intrinsicContentSize.width, label.intrinsicContentSize.width))
                let labelHeight = ceil(label.intrinsicContentSize.height)
                if reading.tightLeading && reading.leftAligned, index > 0,
                   let title = labels[section[index - 1].id] {
                    // Reserve a stable value column, but move its short label with
                    // the right-aligned value to retain the tight label/value gap.
                    // This never changes the row width or screen-capture geometry.
                    let unusedWidth = width - label.intrinsicContentSize.width
                    title.frame.origin.x += unusedWidth
                    label.alignment = .right
                }
                if reading.metric == .fans, index > 0,
                   let bar = bars[section[index - 1].id], !bar.isHidden {
                    // RPM ends at the same trailing column as other readings.
                    // Split its unused reserved width around the bar so both
                    // visible gaps remain equal without resizing the capture.
                    let unusedWidth = max(0, width - label.intrinsicContentSize.width)
                    bar.frame.origin.x += unusedWidth / 2
                }
                if let compactFPSWidth, !reading.startsMetric {
                    x = max(x, sectionStart + compactFPSWidth - width - label.alignmentRectInsets.right)
                }
                // Intrinsic size describes the alignment rectangle. NSTextField
                // also needs its side insets in the frame, or it clips glyphs.
                // Match the vertical FPS title's standard label inset.
                let titleInset = reading.metric == .fps && reading.startsMetric ? label.alignmentRectInsets.left : 0
                let alignmentRect = NSRect(x: x + titleInset, y: baseline - labelHeight + label.firstBaselineOffsetFromTop,
                                           width: width, height: labelHeight)
                label.frame = label.frame(forAlignmentRect: alignmentRect)
                x += width
            }
            if let compactFPSWidth {
                x = max(x, sectionStart + compactFPSWidth)
                fpsSectionWidth = x - sectionStart
            }
        }
        if showsBattery {
            addDivider(compact: sections.last?.last?.resourceGroup == .ram)
            let width = ceil(battery.minimumRowWidth)
            battery.frame = NSRect(x: x, y: 0, width: width, height: height)
            x += width
        }
        return NSSize(width: x, height: height)
    }
}
