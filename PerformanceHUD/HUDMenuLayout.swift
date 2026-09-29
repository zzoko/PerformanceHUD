import AppKit

@MainActor
enum HUDMenuLayout {
    static let labelLeading: CGFloat = 30
    static let spacing: CGFloat = 10

    static var labelWidth: CGFloat {
        let label = NSTextField(labelWithString: "Appearance")
        label.font = .menuFont(ofSize: 0)
        return ceil(label.intrinsicContentSize.width)
    }

    // A shared width keeps Background, Alignment, and the Size track aligned.
    // Measure the actual segmented controls so every title fits at menu font size.
    static var backgroundOptionsWidth: CGFloat {
        [HUDBackground.menuOptions.map(\.menuTitle), ["Vertical", "Horizontal"]].map { titles in
            let control = NSSegmentedControl(labels: titles, trackingMode: .selectOne, target: nil, action: nil)
            control.segmentStyle = .rounded
            control.font = .menuFont(ofSize: 0)
            return ceil(control.intrinsicContentSize.width)
        }.max() ?? 0
    }
}
