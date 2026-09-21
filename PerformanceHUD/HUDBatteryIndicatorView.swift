import AppKit

/// A custom battery drawing with a continuous fill, rather than a system menu control.
@MainActor
final class HUDBatteryIndicatorView: NSView {
    private var percentage: Double?
    private var source: BatterySample.Source?
    private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var scale: CGFloat = 1
    private var background: HUDBackground = .dark
    private var powerObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Battery")
        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                update(percentage: percentage, source: source)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    deinit {
        if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
    }

    func applyStyle(scale: HUDScale, background: HUDBackground) {
        self.scale = CGFloat(scale.rawValue)
        self.background = background
        needsDisplay = true
    }

    func update(percentage: Double?, source: BatterySample.Source?) {
        self.source = source
        self.percentage = percentage.flatMap { $0.isFinite ? min(100, max(0, $0)) : nil }
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let description = self.percentage.map { "Battery: \(Int($0.rounded()))%" } ?? "Battery unavailable"
        toolTip = description + (source.map { " — Source: " + $0.rawValue } ?? "") + (lowPower ? " — Low Power Mode" : "")
        setAccessibilityValue(toolTip)
        needsDisplay = true
    }

    private var sourceFont: NSFont { NSFont.systemFont(ofSize: 14 * scale, weight: .regular) }

    var minimumRowWidth: CGFloat {
        // Reserve the longest source text even while unplugged, avoiding a width
        // jump when the power adapter connects.
        ("Power Adapter" as NSString).size(withAttributes: [.font: sourceFont]).width
            + (2 + 8 + 34 * 0.85 + 0.5) * scale
    }

    override func draw(_ dirtyRect: NSRect) {
        if let source {
            let text = source.rawValue
            let attributes: [NSAttributedString.Key: Any] = [
                .font: sourceFont,
                .foregroundColor: HUDStyle.titleColor(for: .battery, background: background)
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: NSPoint(x: bounds.minX + 2 * scale,
                                               y: bounds.midY - size.height / 2), withAttributes: attributes)
        }
        guard let percentage else { return }
        let iconScale = scale * 0.85
        let foreground = HUDStyle.valueColor(background: background)
        let fillColor: NSColor = lowPower ? .systemYellow : foreground
        let filledTextColor = lowPower || background != .light
            ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.98, alpha: 1)
        let body = NSRect(x: bounds.maxX - 34 * iconScale - 0.5 * scale, y: bounds.midY - 8.5 * iconScale,
                          width: 31 * iconScale, height: 17 * iconScale)
        let shape = NSBezierPath(roundedRect: body, xRadius: 6 * iconScale, yRadius: 6 * iconScale)
        foreground.withAlphaComponent(0.18).setFill()
        shape.fill()
        let fill = NSRect(x: body.minX, y: body.minY,
                          width: body.width * CGFloat(percentage / 100), height: body.height)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        fillColor.setFill()
        fill.fill()
        NSGraphicsContext.restoreGraphicsState()
        foreground.withAlphaComponent(0.35).setStroke()
        shape.lineWidth = 0.65 * iconScale
        shape.stroke()
        foreground.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: NSRect(x: body.maxX + iconScale, y: body.midY - 2.5 * iconScale,
                                        width: 2 * iconScale, height: 5 * iconScale),
                     xRadius: iconScale, yRadius: iconScale).fill()

        let number = String(Int(percentage.rounded()))
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11 * iconScale, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
        let size = (number as NSString).size(withAttributes: attributes)
        // The bolt indicates external power, including when charging is paused
        // or the battery is full. Keep it separate from the percentage digits.
        let showsBolt = source == .powerAdapter
        let boltWidth = 4.5 * iconScale
        let boltGap = 1.2 * iconScale
        let contentWidth = size.width + (showsBolt ? boltGap + boltWidth : 0)
        let origin = NSPoint(x: body.midX - contentWidth / 2, y: body.midY - size.height / 2)
        let bolt = NSBezierPath()
        if showsBolt {
            let x = origin.x + size.width + boltGap
            let y = body.midY - 4.5 * iconScale
            let points: [NSPoint] = [
                NSPoint(x: 0.70, y: 1), NSPoint(x: 0, y: 0.43),
                NSPoint(x: 0.46, y: 0.43), NSPoint(x: 0.26, y: 0),
                NSPoint(x: 1, y: 0.62), NSPoint(x: 0.53, y: 0.62)
            ]
            for (index, point) in points.enumerated() {
                let point = NSPoint(x: x + point.x * boltWidth, y: y + point.y * 9 * iconScale)
                if index == 0 { bolt.move(to: point) } else { bolt.line(to: point) }
            }
            bolt.close()
        }
        (number as NSString).draw(at: origin, withAttributes: attributes)
        foreground.setFill()
        bolt.fill()
        // Invert the digits and bolt over the filled portion so they remain legible
        // even when the fill boundary passes through the middle of a number.
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSBezierPath(rect: fill).addClip()
        (number as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: filledTextColor])
        filledTextColor.setFill()
        bolt.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
