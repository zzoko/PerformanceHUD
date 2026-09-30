import AppKit

@MainActor
final class HUDFanBarView: NSView {
    // Desired dimensions; vertical drawing fits within the established HUD width.
    static let verticalSize = NSSize(width: 100, height: 6)
    static let verticalBarOnlyWidth: CGFloat = 130
    static let horizontalSize = NSSize(width: 64, height: 6)
    var fraction: Double?
    var color = NSColor.secondaryLabelColor

    override func draw(_ dirtyRect: NSRect) {
        Self.drawBar(in: bounds, color: color, fraction: fraction)
    }

    static func drawBar(in rect: NSRect, color: NSColor, fraction: Double?) {
        let track = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        color.withAlphaComponent(0.18).setFill()
        track.fill()
        guard let fraction, fraction.isFinite, fraction > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        track.addClip()
        let fill = NSRect(x: rect.minX, y: rect.minY, width: rect.width * min(1, fraction), height: rect.height)
        color.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: fill, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
