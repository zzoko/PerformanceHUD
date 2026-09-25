import AppKit

@MainActor
enum HUDMenuLayout {
    static let labelLeading: CGFloat = 30
    static let spacing: CGFloat = 10

    static var labelWidth: CGFloat {
        let label = NSTextField(labelWithString: "Background")
        label.font = .menuFont(ofSize: 0)
        return ceil(label.intrinsicContentSize.width)
    }

    static func backgroundButtonWidth(_ background: HUDBackground) -> CGFloat {
        let button = NSButton(title: background.menuTitle, target: nil, action: nil)
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = .systemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .semibold)
        return ceil(button.intrinsicContentSize.width)
    }

    static var backgroundOptionsWidth: CGFloat {
        HUDBackground.menuOptions.reduce(0) { $0 + backgroundButtonWidth($1) }
            + CGFloat(max(0, HUDBackground.menuOptions.count - 1)) * spacing
    }
}
