import AppKit

/// Fixed columns and a fixed row per detected fan keep RPM updates from changing
/// the panel size. Only discovery, user options or scale affect geometry.
@MainActor
final class HUDFanView: NSView {
    override var isFlipped: Bool { true }
    private(set) var sample = FanSample.checking
    private var options = HUDFanOptions()
    private var scale = HUDScale.normal
    private var background = HUDBackground.dark
    private var preferredBarWidth: CGFloat?

    func setPreferredBarWidth(_ width: CGFloat) {
        guard preferredBarWidth != width else { return }
        preferredBarWidth = width
        needsDisplay = true
    }

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
        let reserved = (2 + HUDFanIcon.side) * factor
            + gap
            + ("99999 RPM" as NSString).size(withAttributes: [.font: font]).width + gap
        // Reserve the same columns in every mode so the right-aligned bar keeps
        // its width across visibility changes, readings and RPM emphasis. Match
        // the icon's actual 2pt leading inset, with one gap on each side of RPM.
        let target = preferredBarWidth ?? HUDFanBarView.verticalSize.width * factor
        return min(target, max(0, bounds.width - reserved))
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
        let statusFont = HUDStyle.smallLabelFont(scale: scale)
        let color = HUDStyle.titleColor(for: .fans, background: background)
        let statusAttributes: [NSAttributedString.Key: Any] = [.font: statusFont, .foregroundColor: HUDStyle.TextStyle.label.color(background: background)]
        let rpmFont = HUDStyle.readingFont(scale: scale, highlighted: options.rpmHighlighted)
        let rpmStyle: HUDStyle.TextStyle = options.rpmHighlighted ? .emphasizedReading : .reading
        let rpmAttributes: [NSAttributedString.Key: Any] = [.font: rpmFont, .foregroundColor: rpmStyle.color(background: background)]
        let rowHeight = HUDStyle.rowHeight(scale: scale)
        let factor = CGFloat(scale.rawValue)
        let textHeight = ("FAN" as NSString).size(withAttributes: statusAttributes).height
        if sample.fans.isEmpty {
            ((sample.message ?? "Fan readings unavailable") as NSString).draw(
                at: NSPoint(x: 2 * factor, y: (rowHeight - textHeight) / 2), withAttributes: statusAttributes)
            return
        }
        let labelWidth = HUDFanIcon.side * factor
        for (index, fan) in readings.enumerated() {
            let y = CGFloat(index) * (rowHeight + HUDStyle.rowSpacing(scale: scale))
            HUDFanIcon.draw(in: NSRect(x: 2 * factor, y: y + (rowHeight - labelWidth) / 2,
                                      width: labelWidth, height: labelWidth), marker: fan.iconMarker, color: color)
            guard options.usage else { continue }
            let width = barWidth
            let barLeft = bounds.width - width
            if options.mode.showsRPM {
                let text = fan.rpmText as NSString
                let size = text.size(withAttributes: rpmAttributes)
                let x = options.mode.showsBar
                    ? (2 * factor + labelWidth + barLeft - size.width) / 2
                    : bounds.width - 2 * factor - size.width
                text.draw(at: NSPoint(x: x, y: y + (rowHeight - size.height) / 2), withAttributes: rpmAttributes)
            }
            if options.mode.showsBar {
                let height = HUDFanBarView.verticalSize.height * factor
                let rect = NSRect(x: barLeft,
                                  y: y + (rowHeight - height) / 2, width: width, height: height)
                HUDFanBarView.drawBar(in: rect, color: color, fraction: fan.fraction)
            }
        }
    }
}
