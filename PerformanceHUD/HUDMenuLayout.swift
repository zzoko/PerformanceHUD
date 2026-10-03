import AppKit

@MainActor
enum HUDMenuLayout {
    // AppKit drops the native state column when its last checkmark turns off.
    // Custom category buttons do not count, so Chip & OS must reserve its empty
    // state too (including while unavailable in Horizontal alignment).
    static func reserveStateColumn(for item: NSMenuItem) {
        let side = NSFont.menuFont(ofSize: 0).pointSize
        item.offStateImage = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in true }
    }

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
