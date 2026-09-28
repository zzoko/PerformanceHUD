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
        var symbolName: String? = nil
        var symbolVisible = true
    }

    let battery = HUDBatteryIndicatorView(frame: .zero)
    private var labels: [String: NSTextField] = [:]
    private var dividers: [NSView] = []
    private var symbols: [String: NSImageView] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        battery.setHorizontal(true)
        addSubview(battery)
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(sections: [[Reading]], showsBattery: Bool, scale: HUDScale, background: HUDBackground) -> NSSize {
        let factor = CGFloat(scale.rawValue)
        let reference = NSTextField(labelWithString: "FPS")
        reference.font = HUDStyle.valueFont(for: .fps, scale: scale)
        let height = HUDStyle.rowHeight(scale: scale)
        let gap = HUDStyle.metricColumnSpacing(scale: scale)
        let referenceHeight = reference.intrinsicContentSize.height
        let baseline = (height - referenceHeight) / 2 + referenceHeight - reference.firstBaselineOffsetFromTop
        labels.values.forEach { $0.isHidden = true }
        symbols.values.forEach { $0.isHidden = true }
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
                        addDivider(compact: true, faint: reading.resourceGroup == previousResource)
                    } else {
                        let followsLabel = section[index - 1].startsMetric && reading.metric != .fps
                        let labelGap = followsLabel && reading.resourceGroup == .ram && reading.text == "PHY"
                            ? 2 : HUDStyle.horizontalLabelGapMultiplier
                        let bordersSymbol = reading.symbolName != nil || section[index - 1].symbolName != nil
                        // A compact fixed slot: the triangle fits between the
                        // readings without adding space when pressure changes.
                        x += reading.tightLeading ? 2 * factor : gap * (bordersSymbol ? 0.25 : followsLabel ? labelGap : 1)
                    }
                }
                previousResource = reading.resourceGroup
                if let symbolName = reading.symbolName {
                    let symbol = symbols[reading.id] ?? NSImageView()
                    if symbols[reading.id] == nil { symbols[reading.id] = symbol; addSubview(symbol) }
                    symbol.isHidden = !reading.symbolVisible
                    symbol.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: reading.help)?
                        .withSymbolConfiguration(.init(pointSize: reading.font.pointSize, weight: .regular))
                    symbol.contentTintColor = reading.color
                    symbol.toolTip = reading.help
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
                label.stringValue = reading.text
                label.font = reading.font
                label.textColor = reading.color
                label.toolTip = reading.help
                label.alignment = reading.startsMetric || reading.leftAligned ? .left : .right
                let sizing = NSTextField(labelWithString: reading.reference)
                sizing.font = reading.font
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
                if let compactFPSWidth, !reading.startsMetric {
                    x = max(x, sectionStart + compactFPSWidth - width - label.alignmentRectInsets.right)
                }
                // Intrinsic size describes the alignment rectangle. NSTextField
                // also needs its side insets in the frame, or it clips glyphs.
                let alignmentRect = NSRect(x: x, y: baseline - labelHeight + label.firstBaselineOffsetFromTop,
                                           width: width, height: labelHeight)
                label.frame = label.frame(forAlignmentRect: alignmentRect)
                x += width
            }
            if let compactFPSWidth { x = max(x, sectionStart + compactFPSWidth) }
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
