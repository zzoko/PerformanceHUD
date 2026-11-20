import AppKit

enum HUDStyle {
    static let stateGreen = NSColor(srgbRed: 0.29, green: 0.90, blue: 0.46, alpha: 1)
    static let pressureRed = NSColor(srgbRed: 1, green: 0.39, blue: 0.36, alpha: 1)
    static let warningYellow = NSColor(srgbRed: 1, green: 0.85, blue: 0.24, alpha: 1)

    static func pressureColor(for level: MemoryPressureMonitor.Level?, background: HUDBackground) -> NSColor {
        switch level {
        case .low: return stateGreen
        case .medium: return warningYellow
        case .high: return pressureRed
        case nil: return readingColor(background: background)
        }
    }

    // Shared history fill: a long, gentle fade with a faint tint at the divider.
    static func historyFillGradient(tint: NSColor) -> NSGradient? {
        let locations = (0...32).map { CGFloat($0) / 32 }
        let colors = locations.map { position in
            tint.withAlphaComponent(0.045 + 0.295 * pow(position, 1.35))
        }
        return NSGradient(colors: colors, atLocations: locations, colorSpace: .deviceRGB)
    }

    static func temperatureColor(_ temperature: Double?, warning: HUDHeatWarningOptions,
                                 background: HUDBackground) -> NSColor {
        warning.isTriggered(by: temperature) ? .systemRed : readingColor(background: background)
    }

    // Keep these names stable when discussing or refining the HUD typography.
    // HUD text shares one size; reading emphasis changes only weight/color.
    enum TextStyle: String {
        case label = "Label"
        case reading = "Reading"
        case emphasizedReading = "Emphasized Reading"

        func font(ofSize size: CGFloat) -> NSFont {
            NSFont.systemFont(ofSize: size, weight: self == .emphasizedReading ? .semibold : .regular)
        }

        func color(background: HUDBackground) -> NSColor {
            let isLight = background == .light
            return NSColor(white: self == .label ? (isLight ? 0.31 : 0.76)
                : (isLight ? 0.10 : 0.96), alpha: 1)
        }
    }

    // MARK: - Base Sizes

    static let valueColumnRight: CGFloat = 148
    static let width: CGFloat = 176

    static let screenEdgeInset: CGFloat = 20

    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 14

    static let rowHeight: CGFloat = 21
    static let rowSpacing: CGFloat = 6

    static let metricColumnSpacing: CGFloat = 8
    static let horizontalPowerReference = "999.9 W"
    static let horizontalTemperatureReference = "149°C"
    static let horizontalPercentageReference = "100%"
    static let horizontalFrequencyReference = "0.0 GHz"

    @MainActor
    static func horizontalColumnWidth(text: String, reference: String, font: NSFont,
                                      sizingFont: NSFont? = nil) -> CGFloat {
        let value = NSTextField(labelWithString: text)
        value.font = font
        let sizing = NSTextField(labelWithString: reference)
        sizing.font = sizingFont ?? font
        return ceil(max(sizing.intrinsicContentSize.width, value.intrinsicContentSize.width))
    }

    struct StorageRateColumns {
        let readLabelWidth: CGFloat
        let valueWidth: CGFloat
        let readValueTrailing: CGFloat

        @MainActor
        init() {
            let label = NSTextField(labelWithString: "Read")
            label.font = HUDStyle.smallLabelFont()
            readLabelWidth = label.intrinsicContentSize.width
            valueWidth = HUDStyle.horizontalColumnWidth(text: "", reference: "999.9 MB/s",
                                                        font: HUDStyle.readingFont(highlighted: true))
            readValueTrailing = readLabelWidth + HUDStyle.metricColumnSpacing + valueWidth
        }
    }

    // Stable full CPU reading area, also shared by history and core details.
    // Live digits and hidden slots do not move the left edge of this reference.
    @MainActor
    static func verticalReadingClusterWidth(power: NSFont,
                                            temperature: NSFont, usage: NSFont) -> CGFloat {
        let field = NSTextField(labelWithString: "0.0 W")
        field.font = power
        return field.intrinsicContentSize.width
            + verticalPowerTrailingInset(temperature: temperature, usage: usage)
    }

    // The complete reading row's watts edge, even if Temperature or Use is
    // hidden. Core GHz stays clear of its bars when other options change.
    @MainActor
    static func verticalPowerTrailingInset(temperature: NSFont, usage: NSFont) -> CGFloat {
        let references: [(String, NSFont)] = [("149°C", temperature), ("100%", usage)]
        return references.reduce(CGFloat.zero) { width, reference in
            let field = NSTextField(labelWithString: reference.0)
            field.font = reference.1
            return width + field.intrinsicContentSize.width
        } + 2 * metricColumnSpacing
    }

    // Anchor the HUD inside a centered 16:9 viewport, including letterboxing.
    static func gameContentFrame(in screenFrame: NSRect) -> NSRect {
        let width = min(screenFrame.width, screenFrame.height * 16 / 9)
        let height = width * 9 / 16
        return NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2,
            width: width,
            height: height
        )
    }

    // MARK: - Layout

    static let memoryLabelValueSpacing: CGFloat = 4
    static let fpsHistoryFadeExtension: CGFloat = 16

    enum HeadingSpacing { case tight, regular }

    // Vertical distance from a category heading's baseline to its first detail baseline.
    static func headingToDetailSpacing(_ spacing: HeadingSpacing = .tight) -> CGFloat {
        spacing == .regular ? rowHeight + rowSpacing : 20
    }

    static func rowHeight(for metric: HUDMetric) -> CGFloat {
        // Give the fade its own depth below the stroke, including the former divider gap.
        if metric == .fpsGraph {
            return (24 + fpsHistoryFadeExtension) + rowSpacing
        }
        if metric == .ramTotal { return headingToDetailSpacing(.tight) + 2 * ramDetailHeight() }
        return rowHeight
    }

    static func ramDetailHeight() -> CGFloat {
        18
    }

    static func pressureHistoryBottomExtension(expanded: Bool = true) -> CGFloat {
        // Reach the next divider's centre, retaining the endpoint halo padding.
        let base = rowSpacing + dividerHeight(afterFPS: false)
            + (0.25 - 5 + 3.5)
        let extra = (ramDetailHeight() + base - 7) * 0.5
        return base + (expanded ? extra : 0)
    }

    static func smallLabelFont() -> NSFont {
        TextStyle.label.font(ofSize: baseReadingFontSize)
    }

    static func ramDetailFont() -> NSFont {
        TextStyle.reading.font(ofSize: baseReadingFontSize)
    }

    static func readingFont(highlighted: Bool) -> NSFont {
        (highlighted ? TextStyle.emphasizedReading : .reading).font(ofSize: baseReadingFontSize)
    }

    // Widen the shared columns by 50% of a standard RAM-to-percentage gap.
    // Keep the temperature-to-usage spacing and the outer padding unchanged.
    static func expandedValueColumnRight(_ current: CGFloat, gapIncrease: CGFloat = 0.5) -> CGFloat {
        let titleWidth = ("RAM" as NSString).size(withAttributes: [
            .font: titleFont(for: .ramTotal)
        ]).width
        let valueWidth = ("100%" as NSString).size(withAttributes: [
            .font: valueFont(for: .ramTotal)
        ]).width
        let gap = max(metricColumnSpacing, current - titleWidth - valueWidth)
        return current + gap * gapIncrease
    }

    static let verticalPanelWidth: CGFloat = 285

    static func verticalValueColumnRight() -> CGFloat {
        verticalPanelWidth - 2 * horizontalPadding
    }

    // Reserve the widest supported frame-time reading up front so hitches never resize the panel.
    private static let enlargedFrameTimeContentWidth: CGFloat = {
        let measure = HUDFPSMeasure.frameTime
        let title = NSTextField(labelWithString: measure.caption)
        title.font = titleFont(for: .fps)
        let value = NSTextField(labelWithString: measure.valueWidthReference)
        value.font = fpsValueFont(highlighted: true, size: .enlarged)
        return ceil(title.intrinsicContentSize.width) + ceil(value.intrinsicContentSize.width)
            + metricColumnSpacing + title.alignmentRectInsets.left + value.alignmentRectInsets.right
    }()

    static func compactFPSContentWidth(measure: HUDFPSMeasure, valueSize: HUDFPSValueSize) -> CGFloat {
        let contentWidth = verticalPanelWidth / 2 - 2 * horizontalPadding
        return measure == .frameTime && valueSize == .enlarged ? max(contentWidth, enlargedFrameTimeContentWidth) : contentWidth
    }

    // MARK: - Fonts

    // Uniform text at 1×; category weight provides hierarchy instead of size.
    private static let baseFontSize: CGFloat = 12
    private static let baseReadingFontSize: CGFloat = baseFontSize

    static func fpsValueFont(highlighted: Bool, size: HUDFPSValueSize = .standard) -> NSFont {
        (highlighted ? TextStyle.emphasizedReading : .reading).font(
            ofSize: baseFontSize * CGFloat(size.rawValue))
    }

    static func fpsValueHeight(size: HUDFPSValueSize) -> CGFloat {
        let value = NSTextField(labelWithString: "9999")
        value.font = fpsValueFont(highlighted: true, size: size)
        return ceil(value.intrinsicContentSize.height)
    }

    static func fpsRowHeight(size: HUDFPSValueSize) -> CGFloat {
        guard size != .standard else { return rowHeight }
        return rowHeight + fpsValueHeight(size: size)
            - fpsValueHeight(size: .standard)
    }

    // Keep the FPS sizing reference at its widest weight so emphasis does not
    // resize the HUD. Visible FPS uses fpsValueFont instead.
    static func valueFont(for metric: HUDMetric) -> NSFont {
        if metric == .fps { return fpsValueFont(highlighted: true) }
        return TextStyle.reading.font(ofSize: baseFontSize)
    }

    static func primaryLabelHeight(for metric: HUDMetric) -> CGFloat {
        guard metric == .fps else { return rowHeight }
        let label = NSTextField(labelWithString: "FPS")
        label.font = titleFont(for: .fps)
        return ceil(label.intrinsicContentSize.height)
    }

    static func titleFont(for metric: HUDMetric) -> NSFont {
        switch metric {
        case .fps, .gpu, .gpuTotal, .cpu, .cpuTotal, .aneTotal, .ram, .ramTotal, .storage, .battery:
            // SOC shares the GPU category style. Detail captions remain regular.
            return NSFont.systemFont(ofSize: baseFontSize, weight: .medium)
        default:
            return TextStyle.label.font(ofSize: baseFontSize)
        }
    }

    // Together with the 6pt stack spacing, match the sample's section positions.
    static func dividerHeight(afterFPS: Bool = true) -> CGFloat {
        (afterFPS ? 7 : 9)
    }

    // MARK: - Text Colors

    static func valueColor(background: HUDBackground) -> NSColor {
        TextStyle.reading.color(background: background)
    }

    static func readingColor(background: HUDBackground) -> NSColor {
        TextStyle.reading.color(background: background)
    }

    // Retain the quieter tint for non-text elements such as the FPS graph,
    // collapsed arrow, fan icons and bars, independently of reading contrast.
    static func titleColor(for metric: HUDMetric, background: HUDBackground) -> NSColor {
        metric == .fps ? valueColor(background: background)
            : NSColor(white: background == .light ? 0.31 : 0.76, alpha: 1)
    }

    static func primaryTitleColor(for metric: HUDMetric, background: HUDBackground) -> NSColor {
        TextStyle.label.color(background: background)
    }

    static func separatorColor(background: HUDBackground) -> NSColor {
        NSColor(white: background == .light ? 0 : 1,
                alpha: background == .light ? 0.11 : 0.12)
    }

    // MARK: - Window Behaviour

    static let windowLevel:
        NSWindow.Level = .screenSaver
}


/// AppKit rounds a field’s intrinsic size on its window's backing grid, which
/// includes ancestor transforms. Measure HUD text once in logical coordinates
/// so that changing the magnification cannot change its typographic metrics.
@MainActor
final class HUDReadingLabel: NSTextField {
    private static let measuringField = NSTextField(labelWithString: "")
    private var measuredFont: NSFont?
    private var measuredText: String?
    private var measuredSize = NSSize.zero

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        if translatesAutoresizingMaskIntoConstraints { superview?.needsLayout = true }
    }

    override var intrinsicContentSize: NSSize {
        guard let font else { return super.intrinsicContentSize }
        if measuredText != stringValue || measuredFont != font {
            measuredText = stringValue
            measuredFont = font
            Self.measuringField.font = font
            Self.measuringField.stringValue = stringValue
            measuredSize = Self.measuringField.intrinsicContentSize
        }
        return measuredSize
    }
}

extension NSView {
    /// Deliberate presentation exception: a separator always covers at least
    /// one device pixel, including on a reduced HUD or a lower-density screen.
    var hudHairline: CGFloat {
        guard window != nil else { return 0.5 }
        return max(0.5, convertFromBacking(NSSize(width: 1, height: 1)).width)
    }
}
