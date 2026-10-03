import AppKit

@main struct WindowGeometryTests {
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }
    @MainActor static func main() async {
        _ = NSApplication.shared
        UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "off", "hud.background": "dark",
            "hud.fps.dynamic": false], forName: UserDefaults.argumentDomain)
        let hud = HUDWindowController()
        hud.setHUDEnabled(false)
        hud.setAutoHideMode(.off)
        let panel: HUDPanel = member(hud, "panel")
        let container: NSView = member(hud, "container")
        let center = NotificationCenter.default
        for scale in [HUDScale.small, .normal, .large] {
            hud.setHUDScale(scale)
            for alignment in [HUDAlignment.horizontal, .vertical] {
                hud.setAlignment(alignment == .horizontal ? .vertical : .horizontal)
                let stale = panel.frame.size
                hud.setAlignment(alignment)
                let expected = panel.frame.size
                precondition(stale != expected)
                // Reproduce the captured ordering: backing change first, then
                // macOS restores the old shape, followed by screen parameters.
                center.post(name: NSWindow.didChangeBackingPropertiesNotification, object: panel)
                panel.setFrame(NSRect(origin: panel.frame.origin, size: stale), display: false)
                center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                try? await Task.sleep(for: .milliseconds(250))
                precondition(panel.frame.size == expected, "Old fullscreen frame survived: \(alignment) \(scale)")
                precondition(panel.contentView!.bounds.contains(container.frame), "HUD remains clipped")
                // Late restoration is caught even without another display event.
                panel.setFrame(NSRect(origin: panel.frame.origin, size: stale), display: false)
                try? await Task.sleep(for: .milliseconds(250))
                precondition(panel.frame.size == expected, "Late external resize was not repaired")
                let settled = panel.frame
                center.post(name: NSWindow.didResizeNotification, object: panel)
                try? await Task.sleep(for: .milliseconds(180))
                precondition(panel.frame == settled, "Correct window geometry must remain untouched")
                let task: Task<Void, Never>? = member(hud, "windowGeometryTask")
                precondition(task == nil, "Geometry reconciliation must settle without a resize loop")
            }
        }
        hud.shutdown()
        print("PASS: stale fullscreen frames repaired in both layouts at 0.5×, 1×, and 2×; late resizes recovered; correct frames unchanged; no resize loop")
    }
}
