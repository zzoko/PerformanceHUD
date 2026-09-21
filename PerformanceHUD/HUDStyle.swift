import AppKit

enum HUDStyle {

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

    static func rowHeight(for metric: HUDMetric, scale: HUDScale) -> CGFloat {
        if metric == .fpsGraph { return 24 * CGFloat(scale.rawValue) }
        if metric == .deviceInfo { return ramDetailHeight(scale: scale) }
        let detailLines = metric == .ramTotal ? 3 : metric == .ram ? 1 : 0
        let detailGroupSpacing = detailLines > 0 ? rowSpacing(scale: scale) : 0
        return rowHeight(scale: scale) + detailGroupSpacing + CGFloat(detailLines) * ramDetailHeight(scale: scale)
    }

    static func ramDetailHeight(scale: HUDScale) -> CGFloat {
        18 * CGFloat(scale.rawValue)
    }

    static func ramDetailFont(scale: HUDScale) -> NSFont {
        NSFont.systemFont(ofSize: 12 * CGFloat(scale.rawValue), weight: .regular)
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

    // MARK: - Fonts

    // Match PerformanceHUDSampleTextView's 1× typography; scale only by the HUD size.
    private static let baseFontSize: CGFloat = 14

    static func valueFont(for metric: HUDMetric, scale: HUDScale) -> NSFont {
        NSFont.systemFont(ofSize: baseFontSize * CGFloat(scale.rawValue),
                          weight: metric == .fps ? .semibold : .regular)
    }

    static func titleFont(for metric: HUDMetric, scale: HUDScale) -> NSFont {
        valueFont(for: metric, scale: scale)
    }

    // Together with the 6pt stack spacing, match the sample's section positions.
    static func dividerHeight(scale: HUDScale, afterFPS: Bool = true) -> CGFloat {
        (afterFPS ? 7 : 9) * CGFloat(scale.rawValue)
    }

    // MARK: - Text Colors

    static func valueColor(background: HUDBackground) -> NSColor {
        NSColor(white: background == .light ? 0.10 : 0.96, alpha: 1)
    }

    static func titleColor(for metric: HUDMetric, background: HUDBackground) -> NSColor {
        metric == .fps ? valueColor(background: background)
            : NSColor(white: background == .light ? 0.31 : 0.76, alpha: 1)
    }

    static func separatorColor(background: HUDBackground) -> NSColor {
        NSColor(white: background == .light ? 0 : 1,
                alpha: background == .light ? 0.11 : 0.12)
    }

    // MARK: - Window Behaviour

    static let windowLevel:
        NSWindow.Level = .screenSaver
}
