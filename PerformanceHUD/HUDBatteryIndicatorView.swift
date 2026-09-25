import AppKit

/// A custom battery drawing with a continuous fill, rather than a system menu control.
@MainActor
final class HUDBatteryIndicatorView: NSView {
    private var percentage: Double?
    private var source: BatterySample.Source?
    private var temperature: Double?
    private var options = HUDPreferences.batteryOptions
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
                update(percentage: percentage, source: source, temperature: temperature)
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

    func setOptions(_ options: HUDBatteryOptions) {
        self.options = options
        if !options.temperature { temperature = nil }
        update(percentage: percentage, source: source, temperature: temperature)
    }

    func update(percentage: Double?, source: BatterySample.Source?, temperature: Double? = nil) {
        self.source = source
        self.temperature = temperature.flatMap { SMCTemperatureReader.validBatteryTemperature($0) }
        self.percentage = percentage.flatMap { $0.isFinite ? min(100, max(0, $0)) : nil }
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let description = self.percentage.map { "Battery: \(Int($0.rounded()))%" } ?? "Battery unavailable"
        toolTip = description + (source.map { " — Source: " + $0.rawValue } ?? "") + (lowPower ? " — Low Power Mode" : "")
        if options.temperature, let temperature = self.temperature {
            toolTip = (toolTip ?? "") + " — Battery temperature: \(Int(temperature.rounded()))°C"
        }
        setAccessibilityValue(toolTip)
        needsDisplay = true
    }

    private var sourceFont: NSFont { NSFont.systemFont(ofSize: 14 * scale, weight: .medium) }
    private var valueFont: NSFont { NSFont.systemFont(ofSize: 14 * scale, weight: .regular) }
    private var detailFont: NSFont { NSFont.systemFont(ofSize: 12 * scale, weight: .regular) }
    private var temperatureFont: NSFont { options.charge ? detailFont : valueFont }
    private var sharedTemperatureTrailingInset: CGFloat?

    func alignTemperature(trailingInset: CGFloat?) {
        sharedTemperatureTrailingInset = trailingInset
        needsDisplay = true
    }

    // Reserve the same percentage column used by the CPU/GPU temperature labels.
    private var temperatureTrailingInset: CGFloat {
        guard options.charge else { return 2 * scale }
        if let sharedTemperatureTrailingInset { return sharedTemperatureTrailingInset }
        let usage = NSTextField(labelWithString: "100%")
        usage.font = valueFont
        return usage.intrinsicContentSize.width + 8 * scale + usage.alignmentRectInsets.right
    }

    var minimumRowWidth: CGFloat {
        // Keep the established HUD width when the longer source label is used.
        let titleWidth = ("Adapter" as NSString).size(withAttributes: [.font: valueFont]).width
        let usage = NSTextField(labelWithString: "100%")
        usage.font = valueFont
        let sizingInset = options.charge
            ? usage.intrinsicContentSize.width + 8 * scale + usage.alignmentRectInsets.right : 2 * scale
        let valueWidth = options.temperature
            ? ("99°C" as NSString).size(withAttributes: [.font: temperatureFont]).width + sizingInset
            : options.charge ? (34 * 0.85 + 0.5) * scale : 0
        return titleWidth + 10 * scale + valueWidth
    }

    override func draw(_ dirtyRect: NSRect) {
        let rowMidY = bounds.minY + 10.5 * scale
        let headingAttributes: [NSAttributedString.Key: Any] = [
            .font: detailFont, .foregroundColor: HUDStyle.titleColor(for: .battery, background: background)
        ]
        let heading = "Power source" as NSString
        let headingSize = heading.size(withAttributes: headingAttributes)
        heading.draw(at: NSPoint(x: bounds.minX + 2 * scale,
                                 y: bounds.maxY - 9 * scale - headingSize.height / 2),
                     withAttributes: headingAttributes)
        let sourceHeight = (BatterySample.Source.powerAdapter.rawValue as NSString).size(withAttributes: [.font: sourceFont]).height
        let sourceOriginY = rowMidY - sourceHeight / 2
        if let source {
            let text = source.rawValue
            let attributes: [NSAttributedString.Key: Any] = [
                .font: sourceFont,
                .foregroundColor: HUDStyle.primaryTitleColor(for: .battery, background: background)
            ]
            (text as NSString).draw(at: NSPoint(x: bounds.minX + 2 * scale,
                                               y: sourceOriginY), withAttributes: attributes)
        }
        if options.temperature, let temperature {
            let text = "\(Int(temperature.rounded()))°C" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: temperatureFont,
                .foregroundColor: options.charge
                    ? HUDStyle.titleColor(for: .battery, background: background)
                    : HUDStyle.valueColor(background: background)
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: bounds.maxX - temperatureTrailingInset - size.width,
                                 y: sourceOriginY + temperatureFont.descender - sourceFont.descender),
                      withAttributes: attributes)
        }
        guard options.charge, let percentage else { return }
        let iconScale = scale * 0.85
        let foreground = HUDStyle.valueColor(background: background)
        let fillColor: NSColor = lowPower ? .systemYellow : foreground
        let filledTextColor = lowPower || background != .light
            ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.98, alpha: 1)
        let body = NSRect(x: bounds.maxX - 34 * iconScale - 0.5 * scale, y: rowMidY - 8.5 * iconScale,
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
