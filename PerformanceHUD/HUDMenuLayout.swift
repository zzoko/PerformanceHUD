import AppKit

@MainActor
enum HUDMenuLayout {
    // AppKit drops the native state column when its last checkmark turns off.
    // Custom category buttons do not count. Reserve the column on the native
    // Enable/Disable item so general menu labels stay aligned in both layouts.
    static func reserveStateColumn(for item: NSMenuItem) {
        let side = NSFont.menuFont(ofSize: 0).pointSize
        item.offStateImage = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in true }
    }

    static let labelLeading: CGFloat = 30
    static let spacing: CGFloat = 10

    // Reserve the glass endpoint label before the shared slider value column.
    static var sliderValueSpacing: CGFloat {
        let label = NSTextField(labelWithString: "Frosted")
        label.font = .menuFont(ofSize: 0)
        return spacing + ceil(label.intrinsicContentSize.width) + spacing
    }

    static var labelWidth: CGFloat {
        ["Appearance", "Liquid Glass"].map { title in
            let label = NSTextField(labelWithString: title)
            label.font = .menuFont(ofSize: 0)
            return ceil(label.intrinsicContentSize.width)
        }.max() ?? 0
    }

    static var actionOptionsWidth: CGFloat {
        let widestButton = ["Position", "Size", "All"].map { title in
            let button = NSButton(title: title, target: nil, action: nil)
            button.bezelStyle = .rounded
            button.font = .menuFont(ofSize: 0)
            return ceil(button.intrinsicContentSize.width)
        }.max() ?? 0
        return max(backgroundOptionsWidth, widestButton * 3 + 12)
    }

    // A shared width keeps Background, Alignment, and the Size track aligned.
    // Measure the actual segmented controls so every title fits at menu font size.
    static var backgroundOptionsWidth: CGFloat {
        [["Light", "Dark", "Follow macOS"], ["Strength", "Follow macOS"], ["Vertical", "Horizontal"]].map { titles in
            let control = NSSegmentedControl(labels: titles, trackingMode: .selectOne, target: nil, action: nil)
            control.segmentStyle = .rounded
            control.font = .menuFont(ofSize: 0)
            return ceil(control.intrinsicContentSize.width)
        }.max() ?? 0
    }
}
