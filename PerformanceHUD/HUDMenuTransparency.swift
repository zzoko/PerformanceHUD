import AppKit

/// NSMenu creates separate windows for its root and each open submenu.
@MainActor
final class HUDMenuTransparency: NSObject {
    private let originalColors = NSMapTable<NSWindow, NSColor>.weakToStrongObjects()

    func setReduced(_ reduced: Bool) {
        let center = NotificationCenter.default
        center.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        if reduced {
            center.addObserver(self, selector: #selector(windowVisibilityChanged(_:)),
                               name: NSWindow.didChangeOcclusionStateNotification, object: nil)
            for window in NSApp.windows { apply(to: window) }
        } else {
            for case let window as NSWindow in originalColors.keyEnumerator() {
                window.backgroundColor = originalColors.object(forKey: window)
            }
            originalColors.removeAllObjects()
        }
    }

    @objc private func windowVisibilityChanged(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.isVisible else { return }
        apply(to: window)
        // AppKit can report visibility on the glass companion before the menu itself.
        if let parent = window.parent { apply(to: parent) }
    }

    private func apply(to window: NSWindow) {
        // Style the popup that hosts the menu rows. AppKit draws the glass
        // and shadow in a separate window extending past the rounded edges.
        guard window.level == .popUpMenu, let content = window.contentView,
              content.subviews.contains(where: { $0 is NSScrollView }),
              originalColors.object(forKey: window) == nil else { return }
        originalColors.setObject(window.backgroundColor, forKey: window)
        window.backgroundColor = .windowBackgroundColor
    }
}
