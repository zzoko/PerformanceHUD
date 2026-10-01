import AppKit

/// Fixed columns and a fixed row per detected fan keep RPM updates from changing
/// the panel/capture size. Only discovery, user options or scale affect geometry.
@MainActor
final class HUDFanView: NSView {
    override var isFlipped: Bool { true }
    private(set) var sample = FanSample.checking
    private var options = HUDFanOptions()
    private var scale = HUDScale.normal
    private var background = HUDBackground.transparent

    private var readings: [FanDisplayReading] { sample.displayReadings(averaged: options.averages(in: .vertical)) }
    var rowCount: Int { max(1, readings.count) }
    func height(scale: HUDScale) -> CGFloat {
        ceil(CGFloat(rowCount) * HUDStyle.rowHeight(scale: scale)
            + CGFloat(rowCount - 1) * HUDStyle.rowSpacing(scale: scale))
    }
    var barWidth: CGFloat {
        let factor = CGFloat(scale.rawValue)
        let font = HUDStyle.readingFont(scale: scale, highlighted: true)
        let gap = HUDStyle.metricColumnSpacing(scale: scale)
        let reserved = HUDFanIcon.side * factor
            + gap + 4 * factor
            + ("99999 RPM" as NSString).size(withAttributes: [.font: font]).width + gap
        // Reserve the same columns in every mode so hiding RPM only moves the
        // bar; its width stays unchanged across readings and emphasis changes.
        let target = HUDFanBarView.verticalSize.width
        return min(target * factor, max(0, bounds.width - reserved))
    }

    func update(sample: FanSample, options: HUDFanOptions, scale: HUDScale, background: HUDBackground) {
        self.sample = sample; self.options = options; self.scale = scale; self.background = background
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Fans")
        setAccessibilityValue(sample.fans.isEmpty ? sample.message : readings.map {
            "\($0.title): \(options.usage ? ($0.rpmText.isEmpty ? "unavailable" : $0.rpmText) : "readings hidden")"
        }.joined(separator: ", "))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let font = HUDStyle.readingFont(scale: scale, highlighted: false)
        let color = HUDStyle.titleColor(for: .fans, background: background)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let rpmFont = HUDStyle.readingFont(scale: scale, highlighted: options.rpmHighlighted)
        let rpmAttributes: [NSAttributedString.Key: Any] = [.font: rpmFont, .foregroundColor: color]
        let rowHeight = HUDStyle.rowHeight(scale: scale)
        let factor = CGFloat(scale.rawValue)
        let textHeight = ("FAN" as NSString).size(withAttributes: attributes).height
        if sample.fans.isEmpty {
            ((sample.message ?? "Fan readings unavailable") as NSString).draw(
                at: NSPoint(x: 2 * factor, y: (rowHeight - textHeight) / 2), withAttributes: attributes)
            return
        }
        let labelWidth = HUDFanIcon.side * factor
        for (index, fan) in readings.enumerated() {
            let y = CGFloat(index) * (rowHeight + HUDStyle.rowSpacing(scale: scale))
            HUDFanIcon.draw(in: NSRect(x: 2 * factor, y: y + (rowHeight - labelWidth) / 2,
                                      width: labelWidth, height: labelWidth), marker: fan.iconMarker, color: color)
            guard options.usage else { continue }
            if options.mode.showsRPM {
                let text = fan.rpmText as NSString
                let size = text.size(withAttributes: rpmAttributes)
                text.draw(at: NSPoint(x: bounds.width - size.width - 2 * factor, y: y + (rowHeight - size.height) / 2), withAttributes: rpmAttributes)
            }
            if options.mode.showsBar {
                let left = 2 * factor + labelWidth
                let rpmText = fan.rpmText.isEmpty ? "99999 RPM" : fan.rpmText
                let rpmWidth = (rpmText as NSString).size(withAttributes: rpmAttributes).width
                let right = bounds.width - 2 * factor - (options.mode.showsRPM ? rpmWidth : 0)
                let width = barWidth
                let height = HUDFanBarView.verticalSize.height * factor
                let x = options.mode.showsRPM ? (left + right - width) / 2 : right - width
                let rect = NSRect(x: x,
                                  y: y + (rowHeight - height) / 2, width: width, height: height)
                HUDFanBarView.drawBar(in: rect, color: color, fraction: fan.fraction)
            }
        }
    }
}
