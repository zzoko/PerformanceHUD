import AppKit

/// Individual fans share rows in pairs. A single fan or the average stays inline.
@MainActor
final class HUDFanView: NSView {
    struct CellFrames {
        let badge: NSRect
        let rpm: NSRect?
        let bar: NSRect?
    }

    override var isFlipped: Bool { true }
    private(set) var sample = FanSample.checking
    private var readings: [FanDisplayReading] = []
    private var options = HUDFanOptions()
    private var background = HUDBackground.dark
    private var preferredBarWidth: CGFloat?
    private var swapValueTrailing: CGFloat?
    private static let labelInset = NSTextField(labelWithString: "").alignmentRectInsets.left
    private let rpmColumnWidth = HUDStyle.horizontalColumnWidth(text: "", reference: FanDisplayReading.rpmWidthReference,
                                      font: HUDStyle.readingFont(highlighted: true))

    func setMemoryColumns(barWidth: CGFloat, swapValueTrailing: CGFloat) {
        guard preferredBarWidth != barWidth || self.swapValueTrailing != swapValueTrailing else { return }
        preferredBarWidth = barWidth
        self.swapValueTrailing = swapValueTrailing
        needsDisplay = true
    }

    private var paired: Bool { readings.count > 1 }
    var rowCount: Int { max(1, (readings.count + 1) / 2) }

    private func barLineHeight() -> CGFloat {
        paired && options.mode.showsBar ? (HUDFanBarView.verticalSize.height + 4) : 0
    }

    func height() -> CGFloat {
        ceil(CGFloat(rowCount) * (HUDStyle.rowHeight + barLineHeight())
            + CGFloat(rowCount - 1) * HUDStyle.rowSpacing)
    }

    var barWidth: CGFloat {
        preferredBarWidth ?? HUDFanBarView.verticalSize.width
    }

    func frames(forFanAt index: Int) -> CellFrames {
        let infoHeight = HUDStyle.rowHeight
        let barLine = barLineHeight()
        let rowY = CGFloat(index / 2) * (infoHeight + barLine + HUDStyle.rowSpacing)
        let infoY = rowY + barLine
        let rightStart = bounds.maxX - barWidth
        let leftColumn = index.isMultiple(of: 2)
        let columnStart = leftColumn ? bounds.minX + Self.labelInset : rightStart
        let columnEnd = paired && leftColumn ? columnStart + barWidth : bounds.maxX

        let side = HUDFanIcon.side
        let badgeX = columnStart - HUDFanIcon.inkInset
        let badge = NSRect(x: badgeX, y: infoY + (infoHeight - side) / 2, width: side, height: side)
        let rpmEnd = !paired && options.mode == .both ? bounds.minX + (swapValueTrailing ?? barWidth) : columnEnd
        let rpm = options.mode.showsRPM
            ? NSRect(x: rpmEnd - rpmColumnWidth, y: infoY, width: rpmColumnWidth, height: infoHeight) : nil
        let barHeight = HUDFanBarView.verticalSize.height
        let bar = options.mode.showsBar ? NSRect(x: paired ? columnStart : rightStart,
            y: barLine > 0 ? rowY : rowY + (infoHeight - barHeight) / 2, width: barWidth, height: barHeight) : nil
        return CellFrames(badge: badge, rpm: rpm, bar: bar)
    }

    func update(sample: FanSample, options: HUDFanOptions, background: HUDBackground) {
        self.sample = sample; self.options = options; self.background = background
        readings = sample.displayReadings(averaged: options.averages(in: .vertical))
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Fans")
        setAccessibilityValue(sample.fans.isEmpty ? sample.message : readings.map { fan in
            let value = options.mode.showsRPM ? fan.rpmText : fan.fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? ""
            return "\(fan.title): \(value.isEmpty ? "unavailable" : value)"
        }.joined(separator: ", "))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let statusFont = HUDStyle.smallLabelFont()
        let color = HUDStyle.titleColor(for: .fans, background: background)
        let statusAttributes: [NSAttributedString.Key: Any] = [.font: statusFont, .foregroundColor: HUDStyle.TextStyle.label.color(background: background)]
        let rpmFont = HUDStyle.readingFont(highlighted: options.rpmHighlighted)
        let rpmStyle: HUDStyle.TextStyle = options.rpmHighlighted ? .emphasizedReading : .reading
        let rpmAttributes: [NSAttributedString.Key: Any] = [.font: rpmFont, .foregroundColor: rpmStyle.color(background: background)]
        let rowHeight = HUDStyle.rowHeight
        let textHeight = ("FAN" as NSString).size(withAttributes: statusAttributes).height
        if sample.fans.isEmpty {
            ((sample.message ?? "Fan readings unavailable") as NSString).draw(
                at: NSPoint(x: 2, y: (rowHeight - textHeight) / 2), withAttributes: statusAttributes)
            return
        }
        for (index, fan) in readings.enumerated() {
            let cell = frames(forFanAt: index)
            HUDFanIcon.draw(in: cell.badge, marker: fan.iconMarker, color: color)
            if let rpm = cell.rpm {
                let text = fan.rpmText as NSString
                let size = text.size(withAttributes: rpmAttributes)
                text.draw(at: NSPoint(x: rpm.maxX - size.width, y: rpm.midY - size.height / 2), withAttributes: rpmAttributes)
            }
            if let bar = cell.bar {
                HUDFanBarView.drawBar(in: bar, color: color, fraction: fan.fraction)
            }
        }
    }
}
