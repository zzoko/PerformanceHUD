import AppKit

/// A custom battery drawing with a continuous fill, rather than a system menu control.
@MainActor
final class HUDBatteryIndicatorView: NSView {
    // Keep the pinned charge column wide enough for its first sample.
    var reservesMissingPowerSpace = false
    private static let horizontalTextInsets = NSTextField(labelWithString: "").alignmentRectInsets
    private var horizontal = false
    private var percentage: Double?
    private var source: BatterySample.Source?
    private var temperature: Double?
    private var power: Double?
    private var flowVisibility = BatteryFlowVisibility()
    private enum ChargeState { case draining, charging, idleOnAdapter }
    private var lastChargeState: ChargeState?
    private var chargeFlashStart: TimeInterval?
    private var chargeRedrawPending = false
    private static let chargeFlashRise: TimeInterval = 0.25
    private static let chargeFlashDuration: TimeInterval = 1
    private var options = HUDPreferences.batteryOptions
    private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
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
                update(percentage: percentage, source: source, temperature: temperature, power: power)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    deinit {
        if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
    }

    func applyStyle(background: HUDBackground) {
        self.background = background
        needsDisplay = true
    }

    func setHorizontal(_ horizontal: Bool) {
        self.horizontal = horizontal
        needsDisplay = true
    }

    func setOptions(_ options: HUDBatteryOptions) {
        if self.options.flowMode != options.flowMode || self.options.enabled != options.enabled {
            flowVisibility = BatteryFlowVisibility()
        }
        self.options = options
        if !options.temperature { temperature = nil }
        if !options.power { power = nil }
        update(percentage: percentage, source: source, temperature: temperature, power: power)
    }

    func update(percentage: Double?, source: BatterySample.Source?, temperature: Double? = nil, power: Double? = nil,
                now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.source = source
        self.temperature = temperature.flatMap { SMCTemperatureReader.validBatteryTemperature($0) }
        self.power = power.flatMap { BatteryPowerRate.valid($0) }
        flowVisibility.update(power: options.enabled && options.power ? self.power : nil, now: now)
        updateChargeFlash(now: now)
        self.percentage = percentage.flatMap { $0.isFinite ? min(100, max(0, $0)) : nil }
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let description = self.percentage.map { "Battery: \(Int($0.rounded()))%" } ?? "Battery unavailable"
        var accessibleValue = description + (source.map { " — Source: " + $0.rawValue } ?? "") + (lowPower ? " — Low Power Mode" : "")
        if options.temperature, let temperature = self.temperature {
            accessibleValue += " — Battery temperature: \(Int(temperature.rounded()))°C"
        }
        if !powerText.isEmpty {
            accessibleValue += " — Battery charge rate: \(powerText)"
        }
        setAccessibilityValue(accessibleValue)
        needsDisplay = true
    }

    private var sourceFont: NSFont {
        return horizontal ? HUDStyle.titleFont(for: .battery)
            : HUDStyle.smallLabelFont()
    }
    private var valueFont: NSFont { HUDStyle.readingFont(highlighted: false) }
    private var detailFont: NSFont { sourceFont }
    private var sourceLabelFont: NSFont { horizontal ? sourceFont : detailFont }
    private var temperatureFont: NSFont {
        HUDStyle.readingFont(highlighted: options.temperatureHighlighted)
    }
    var temperatureColor: NSColor {
        HUDStyle.temperatureColor(options.enabled && options.temperature ? temperature : nil,
                                  warning: options.heatWarning, background: background)
    }
    private var powerFont: NSFont {
        HUDStyle.readingFont(highlighted: options.powerHighlighted)
    }
    private var powerReferenceWidth: CGFloat {
        // Vertical sizing keeps room for the full supported reading range.
        ("+1000.0 W" as NSString).size(withAttributes: [
            .font: HUDStyle.readingFont(highlighted: true)
        ]).width
    }
    private var horizontalPowerWidth: CGFloat {
        HUDStyle.horizontalColumnWidth(text: powerText, reference: HUDStyle.horizontalPowerReference, font: powerFont)
    }
    private var horizontalTemperatureWidth: CGFloat {
        HUDStyle.horizontalColumnWidth(text: temperatureText, reference: HUDStyle.horizontalTemperatureReference,
                                       font: temperatureFont)
    }
    private var horizontalIconWidth: CGFloat {
        max(iconWidth, HUDStyle.horizontalColumnWidth(text: "", reference: HUDStyle.horizontalPercentageReference,
            font: HUDStyle.readingFont(highlighted: false)))
    }
    private var horizontalGap: CGFloat { HUDStyle.metricColumnSpacing }
    private var iconWidth: CGFloat { (34 * 0.85 + 0.5) }

    var sourceText: String {
        guard let source else { return horizontal ? "" : "Source" }
        if horizontal { return source == .powerAdapter ? "ADP" : "BAT" }
        return source == .powerAdapter ? "Source · Adapter" : "Source · Battery"
    }

    var sourceTextRect: NSRect {
        let text = sourceText
        guard !text.isEmpty else { return .zero }
        let size = (text as NSString).size(withAttributes: [.font: sourceLabelFont])
        let sourceHeight = ("Adapter" as NSString).size(withAttributes: [.font: sourceFont]).height
        let midY = horizontal ? bounds.midY : bounds.minY + 10.5
        let leading = horizontal ? Self.horizontalTextInsets.left : 2
        let rect = NSRect(x: bounds.minX + leading,
                      y: midY - sourceHeight / 2 + sourceLabelFont.descender - sourceFont.descender,
                      width: size.width, height: size.height)
        return alignedTextRect(rect)
    }

    var powerText: String {
        guard options.power, options.flowMode != .auto || flowVisibility.isVisible else { return "" }
        return BatteryPowerRate.text(power)
    }

    private func updateChargeFlash(now: TimeInterval) {
        guard options.enabled, options.power else {
            lastChargeState = nil
            chargeFlashStart = nil
            return
        }
        let state: ChargeState
        if let power, power <= -BatteryFlowVisibility.activeWatts {
            state = .draining
        } else if let power, power >= BatteryFlowVisibility.activeWatts, source == .powerAdapter {
            state = .charging
        } else {
            // Remember the last direction through idle or missing samples. A Mac
            // first seen holding charge on its adapter can still pulse when unplugged.
            if lastChargeState == nil, source == .powerAdapter, let power, abs(power) < BatteryFlowVisibility.activeWatts {
                lastChargeState = .idleOnAdapter
            }
            chargeFlashStart = nil
            return
        }
        switch (lastChargeState, state) {
        case (.draining, .charging), (.charging, .draining), (.idleOnAdapter, .draining):
            chargeFlashStart = now
        default: break
        }
        lastChargeState = state
    }

    func powerColor(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> NSColor {
        let normal = HUDStyle.readingColor(background: background)
        guard let start = chargeFlashStart else { return normal }
        let elapsed = now - start
        guard elapsed > 0, elapsed < Self.chargeFlashDuration else { return normal }
        let progress = elapsed < Self.chargeFlashRise ? elapsed / Self.chargeFlashRise
            : (Self.chargeFlashDuration - elapsed) / (Self.chargeFlashDuration - Self.chargeFlashRise)
        let tint = progress * progress * (3 - 2 * progress)
        let color = lastChargeState == .draining ? HUDStyle.pressureRed : HUDStyle.stateGreen
        return normal.blended(withFraction: tint, of: color) ?? normal
    }

    private func scheduleChargeRedraw(at now: TimeInterval) {
        guard let start = chargeFlashStart, now < start + Self.chargeFlashDuration, !chargeRedrawPending else { return }
        chargeRedrawPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [weak self] in
            guard let self else { return }
            chargeRedrawPending = false
            setNeedsDisplay(powerTextRect)
        }
    }

    /// Whether Charge has content to show according to its display mode. Auto
    /// follows the same flow thresholds and idle delay as the rendered reading.
    var hasVisiblePowerFlow: Bool {
        options.enabled && options.power && (options.flowMode != .auto || flowVisibility.isVisible)
    }

    private var reservesPowerSpace: Bool {
        // Vertical keeps fixed columns. Horizontal also reclaims Auto's slot
        // when Charge is temporarily hidden.
        options.power && (!horizontal || options.flowMode != .auto || flowVisibility.isVisible
            || (reservesMissingPowerSpace && power == nil))
    }

    var powerTextRect: NSRect {
        guard !powerText.isEmpty else { return .zero }
        if horizontal {
            let trailing = horizontalReadingTrailingInset
                + (options.temperature ? horizontalTemperatureWidth + horizontalGap : 0)
            return inlineTextRect(powerText, font: powerFont, trailing: trailing)
        }
        return inlineTextRect(powerText, font: powerFont, trailing: verticalPowerTrailingInset)
    }

    var temperatureText: String {
        guard options.temperature, let temperature else { return "" }
        return "\(Int(temperature.rounded()))°C"
    }

    var temperatureTextRect: NSRect {
        guard !temperatureText.isEmpty else { return .zero }
        if horizontal {
            return inlineTextRect(temperatureText, font: temperatureFont, trailing: horizontalReadingTrailingInset)
        }
        return inlineTextRect(temperatureText, font: temperatureFont, trailing: verticalTemperatureTrailingInset)
    }

    private func inlineTextRect(_ text: String, font: NSFont, trailing: CGFloat) -> NSRect {
        let size = (text as NSString).size(withAttributes: [.font: font])
        let sourceHeight = ("Adapter" as NSString).size(withAttributes: [.font: sourceFont]).height
        let midY = horizontal ? bounds.midY : bounds.minY + 10.5
        let rect = NSRect(x: bounds.maxX - trailing - size.width,
                      y: midY - sourceHeight / 2 + font.descender - sourceFont.descender,
                      width: size.width, height: size.height)
        return alignedTextRect(rect)
    }

    private func alignedTextRect(_ rect: NSRect) -> NSRect {
        horizontal && window != nil ? backingAlignedRect(rect, options: .alignAllEdgesNearest) : rect
    }

    private var sharedVerticalPowerTrailingInset: CGFloat?
    private var sharedVerticalTemperatureTrailingInset: CGFloat?

    func alignVerticalReadings(powerTrailingInset: CGFloat?, temperatureTrailingInset: CGFloat?) {
        sharedVerticalPowerTrailingInset = powerTrailingInset
        sharedVerticalTemperatureTrailingInset = temperatureTrailingInset
        needsDisplay = true
    }

    private var verticalTemperatureTrailingInset: CGFloat {
        options.charge ? verticalMiddleTrailingInset : 2
    }

    private var verticalMiddleTrailingInset: CGFloat {
        if let sharedVerticalTemperatureTrailingInset { return sharedVerticalTemperatureTrailingInset }
        let usage = NSTextField(labelWithString: "100%")
        usage.font = valueFont
        return usage.intrinsicContentSize.width + 8 + usage.alignmentRectInsets.right
    }

    private var verticalPowerTrailingInset: CGFloat {
        // Pack enabled readings from the right. Auto keeps its slot reserved
        // while temporarily blank; only an explicit Off selection removes it.
        let readingsToRight = (options.temperature ? 1 : 0) + (options.charge ? 1 : 0)
        if readingsToRight == 0 { return 2 }
        if readingsToRight == 1, options.charge { return verticalMiddleTrailingInset }
        if readingsToRight == 2, let sharedVerticalPowerTrailingInset { return sharedVerticalPowerTrailingInset }
        let temperatureWidth = ("149°C" as NSString).size(withAttributes: [
            .font: HUDStyle.readingFont(highlighted: true)
        ]).width
        return verticalTemperatureTrailingInset + temperatureWidth + 8
    }

    private var horizontalReadingTrailingInset: CGFloat {
        options.charge ? horizontalIconWidth + horizontalGap : Self.horizontalTextInsets.right
    }

    // Useful for standalone previews; the HUD itself has a fixed vertical width.
    var minimumAlignedRowWidth: CGFloat {
        let titleWidth = ("Source · Adapter" as NSString).size(withAttributes: [.font: detailFont]).width
        return 2 + titleWidth + 8 + powerReferenceWidth + verticalPowerTrailingInset
    }

    var minimumRowWidth: CGFloat {
        if horizontal {
            let title = source == .battery ? "BAT" : "ADP"
            let titleWidth = HUDStyle.horizontalColumnWidth(text: title, reference: "ADP", font: sourceFont)
            let widths: [CGFloat] = [reservesPowerSpace ? horizontalPowerWidth : nil,
                options.temperature ? horizontalTemperatureWidth : nil,
                options.charge ? horizontalIconWidth : nil].compactMap { $0 }
            let gaps = horizontalGap * CGFloat(widths.count)
            return Self.horizontalTextInsets.left + titleWidth + gaps + widths.reduce(0, +)
                + (options.charge ? 0 : Self.horizontalTextInsets.right)
        }
        // Keep the baseline reference independent of enabled readings. The full
        // row is fitted separately, after the controller's spacing expansion.
        let titleWidth = ("Source · Adapter" as NSString).size(withAttributes: [.font: detailFont]).width
        let usage = NSTextField(labelWithString: "100%")
        usage.font = valueFont
        let sizingInset = usage.intrinsicContentSize.width + 8 + usage.alignmentRectInsets.right
        let sizingFont = HUDStyle.readingFont(highlighted: true)
        let valueWidth = ("99°C" as NSString).size(withAttributes: [.font: sizingFont]).width + sizingInset
        return titleWidth + 10 + valueWidth
    }

    override func draw(_ dirtyRect: NSRect) {
        let rowMidY = horizontal ? bounds.midY : bounds.minY + 10.5
        if !powerText.isEmpty {
            let now = ProcessInfo.processInfo.systemUptime
            (powerText as NSString).draw(at: powerTextRect.origin, withAttributes: [
                .font: powerFont, .foregroundColor: powerColor(at: now)
            ])
            scheduleChargeRedraw(at: now)
        }
        if !sourceText.isEmpty {
            (sourceText as NSString).draw(at: sourceTextRect.origin, withAttributes: [
                .font: sourceLabelFont,
                .foregroundColor: HUDStyle.primaryTitleColor(for: .battery, background: background)
            ])
        }
        if !temperatureText.isEmpty {
            (temperatureText as NSString).draw(at: temperatureTextRect.origin, withAttributes: [
                .font: temperatureFont,
                .foregroundColor: temperatureColor
            ])
        }
        guard options.charge, let percentage else { return }
        let iconScale = CGFloat(0.85)
        let foreground = HUDStyle.valueColor(background: background)
        let lowBattery = percentage <= 10
        let fillColor: NSColor = lowPower ? HUDStyle.warningYellow : lowBattery ? .systemRed : foreground
        let filledTextColor = lowBattery || lowPower || background != .light
            ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.98, alpha: 1)
        let body = NSRect(x: bounds.maxX - 34 * iconScale - 0.5, y: rowMidY - 8.5 * iconScale,
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
