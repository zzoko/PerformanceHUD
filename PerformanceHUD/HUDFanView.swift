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
        let reserved = ("FAN AVG" as NSString).size(withAttributes: [.font: HUDStyle.titleFont(for: .fans, scale: scale)]).width
            + gap + 4 * factor
            + (options.mode.showsRPM ? ("99999 RPM" as NSString).size(withAttributes: [.font: font]).width + gap : 0)
        // Total alone uses a longer bar without following other metric columns.
        // Stable reference widths keep live RPM values and emphasis from resizing it.
        let target = options.mode.showsRPM ? HUDFanBarView.verticalSize.width : HUDFanBarView.verticalBarOnlyWidth
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
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: HUDStyle.titleFont(for: .fans, scale: scale),
            .foregroundColor: HUDStyle.primaryTitleColor(for: .fans, background: background)
        ]
        let rowHeight = HUDStyle.rowHeight(scale: scale)
        let factor = CGFloat(scale.rawValue)
        let textHeight = ("FAN" as NSString).size(withAttributes: attributes).height
        if sample.fans.isEmpty {
            ((sample.message ?? "Fan readings unavailable") as NSString).draw(
                at: NSPoint(x: 2 * factor, y: (rowHeight - textHeight) / 2), withAttributes: attributes)
            return
        }
        let titleSize = ("FAN AVG" as NSString).size(withAttributes: titleAttributes)
        let labelWidth = titleSize.width
        let rpmWidth = ("99999 RPM" as NSString).size(withAttributes: [
            .font: HUDStyle.readingFont(scale: scale, highlighted: true)
        ]).width
        let gap = HUDStyle.metricColumnSpacing(scale: scale)
        for (index, fan) in readings.enumerated() {
            let y = CGFloat(index) * (rowHeight + HUDStyle.rowSpacing(scale: scale))
            (fan.title as NSString).draw(at: NSPoint(x: 2 * factor, y: y + (rowHeight - titleSize.height) / 2), withAttributes: titleAttributes)
            guard options.usage else { continue }
            if options.mode.showsRPM {
                let text = fan.rpmText as NSString
                let size = text.size(withAttributes: rpmAttributes)
                text.draw(at: NSPoint(x: bounds.width - size.width - 2 * factor, y: y + (rowHeight - size.height) / 2), withAttributes: rpmAttributes)
            }
            if options.mode.showsBar {
                let left = 2 * factor + labelWidth + gap
                let right = bounds.width - 2 * factor - (options.mode.showsRPM ? rpmWidth + gap : 0)
                let width = barWidth
                let height = HUDFanBarView.verticalSize.height * factor
                let x = options.mode.showsRPM ? left + max(0, right - left - width) / 2 : right - width
                let rect = NSRect(x: x,
                                  y: y + (rowHeight - height) / 2, width: width, height: height)
                HUDFanBarView.drawBar(in: rect, color: color, fraction: fan.fraction)
            }
        }
    }
}
