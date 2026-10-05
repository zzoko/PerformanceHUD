import AppKit

enum HUDStyle {

    // Keep these names stable when discussing or refining the HUD typography.
    // Font size belongs to the existing layout; each style changes only weight/color.
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

    private static let baseValueColumnRight: CGFloat = 148
    private static let baseWidth: CGFloat = 176

    static func valueColumnRight(
        scale: HUDScale
    ) -> CGFloat {
        baseValueColumnRight
            * CGFloat(scale.rawValue)
    }

    static func width(
        scale: HUDScale
    ) -> CGFloat {
        baseWidth
            * CGFloat(scale.rawValue)
    }
    
    static let screenEdgeInset: CGFloat = 20

    private static let baseHorizontalPadding: CGFloat = 14
    private static let baseVerticalPadding: CGFloat = 14

    private static let baseRowHeight: CGFloat = 21
    private static let baseRowSpacing: CGFloat = 6

    private static let baseMetricColumnSpacing: CGFloat = 8
    static let horizontalLabelGapMultiplier: CGFloat = 1.21

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

    // MARK: - Scaled Sizes

    static func horizontalPadding(
        scale: HUDScale
    ) -> CGFloat {

        baseHorizontalPadding
        * CGFloat(scale.rawValue)
    }

    static func verticalPadding(
        scale: HUDScale
    ) -> CGFloat {

        baseVerticalPadding
        * CGFloat(scale.rawValue)
    }

    static func rowHeight(
        scale: HUDScale
    ) -> CGFloat {

        baseRowHeight
        * CGFloat(scale.rawValue)
    }

    static let memoryLabelValueSpacing: CGFloat = 4
    static let fpsHistoryFadeExtension: CGFloat = 16

    static func rowHeight(for metric: HUDMetric, scale: HUDScale) -> CGFloat {
        // Give the fade its own depth below the stroke, including the former divider gap.
        if metric == .fpsGraph {
            return (24 + fpsHistoryFadeExtension) * CGFloat(scale.rawValue) + rowSpacing(scale: scale)
        }
        if metric == .deviceInfo { return ramDetailHeight(scale: scale) }
        if metric == .battery { return rowHeight(scale: scale) + ramDetailHeight(scale: scale) }
        let detailLines = metric == .ramTotal ? 3 : metric == .ram ? 1 : 0
        let detailGroupSpacing: CGFloat = 0
        return rowHeight(scale: scale) + detailGroupSpacing + CGFloat(detailLines) * ramDetailHeight(scale: scale)
    }

    static func ramDetailHeight(scale: HUDScale) -> CGFloat {
        18 * CGFloat(scale.rawValue)
    }

    static func smallLabelFont(scale: HUDScale) -> NSFont {
        TextStyle.label.font(ofSize: baseReadingFontSize * CGFloat(scale.rawValue))
    }

    static func ramDetailFont(scale: HUDScale) -> NSFont {
        TextStyle.reading.font(ofSize: baseReadingFontSize * CGFloat(scale.rawValue))
    }

    static func readingFont(scale: HUDScale, highlighted: Bool) -> NSFont {
        (highlighted ? TextStyle.emphasizedReading : .reading).font(ofSize: baseReadingFontSize * CGFloat(scale.rawValue))
    }

    static func rowSpacing(
        scale: HUDScale
    ) -> CGFloat {

        baseRowSpacing
        * CGFloat(scale.rawValue)
    }

    static func metricColumnSpacing(
        scale: HUDScale
    ) -> CGFloat {
        baseMetricColumnSpacing
            * CGFloat(scale.rawValue)
    }

    // Widen the shared columns by 50% of a standard RAM-to-percentage gap.
    // Keep the temperature-to-usage spacing and the outer padding unchanged.
    static func expandedValueColumnRight(_ current: CGFloat, scale: HUDScale, gapIncrease: CGFloat = 0.5) -> CGFloat {
        let titleWidth = ("RAM" as NSString).size(withAttributes: [
            .font: titleFont(for: .ramTotal, scale: scale)
        ]).width
        let valueWidth = ("100%" as NSString).size(withAttributes: [
            .font: valueFont(for: .ramTotal, scale: scale)
        ]).width
        let gap = max(metricColumnSpacing(scale: scale), current - titleWidth - valueWidth)
        return current + gap * gapIncrease
    }

    // Share the compact FPS-only column with the FPS section of the horizontal HUD.
    static func compactFPSValueColumnRight(scale: HUDScale) -> CGFloat {
        let title = NSTextField(labelWithString: "FPS")
        title.font = titleFont(for: .fps, scale: scale)
        let value = NSTextField(labelWithString: "60")
        value.font = valueFont(for: .fps, scale: scale)
        let textWidth = title.intrinsicContentSize.width + value.intrinsicContentSize.width
        let expanded = expandedValueColumnRight(valueColumnRight(scale: scale), scale: scale)
        return textWidth + max(metricColumnSpacing(scale: scale), (expanded - textWidth) / 2)
    }

    // MARK: - Fonts

    // Text sizes at 1×; the FPS value matches its label size.
    private static let baseFontSize: CGFloat = 14
    private static let baseReadingFontSize: CGFloat = 12

    static func fpsValueFont(scale: HUDScale, highlighted: Bool) -> NSFont {
        (highlighted ? TextStyle.emphasizedReading : .reading).font(ofSize: baseFontSize * CGFloat(scale.rawValue))
    }

    // Keep the FPS sizing reference at its widest weight so emphasis does not
    // resize the HUD. Visible FPS uses fpsValueFont instead.
    static func valueFont(for metric: HUDMetric, scale: HUDScale) -> NSFont {
        if metric == .fps { return fpsValueFont(scale: scale, highlighted: true) }
        return TextStyle.reading.font(ofSize: baseFontSize * CGFloat(scale.rawValue))
    }

    static func primaryLabelHeight(for metric: HUDMetric, scale: HUDScale) -> CGFloat {
        guard metric == .fps else { return rowHeight(scale: scale) }
        let label = NSTextField(labelWithString: "FPS")
        label.font = titleFont(for: .fps, scale: scale)
        return ceil(label.intrinsicContentSize.height)
    }

    static func titleFont(for metric: HUDMetric, scale: HUDScale) -> NSFont {
        TextStyle.label.font(ofSize: baseFontSize * CGFloat(scale.rawValue))
    }

    // Together with the 6pt stack spacing, match the sample's section positions.
    static func dividerHeight(scale: HUDScale, afterFPS: Bool = true) -> CGFloat {
        (afterFPS ? 7 : 9) * CGFloat(scale.rawValue)
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
