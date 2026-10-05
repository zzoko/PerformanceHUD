import AppKit

nonisolated private final class TestRefreshListener: NativeGlassRefreshListening {
    var isActive = false
    var callbacks = 0
    var starts = 0
    var stops = 0
    var error: String?
    func start() -> String? {
        starts += 1
        isActive = error == nil
        return error
    }
    func stop() { if isActive { stops += 1 }; isActive = false }
}

@main struct NativeGlassTests {
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }
    @MainActor static func main() {
        _ = NSApplication.shared
        // Native glass, shadow cutout and text clipping have independent layers.
        let view = NativeGlassHUDBackground(frame: .zero)
        let native: NSGlassEffectView = member(view, "glass")
        let shadow: CALayer = member(view, "outsideShadow")
        let cutout: CAShapeLayer = member(view, "shadowCutout")
        precondition(native.style == .regular && native.tintColor == nil)
        if #available(macOS 27, *) { precondition(!native.effectIsInteractive) }
        for dark in [true, false] {
            view.isDark = dark
            for scale in [CGFloat(0.5), 1, 2] {
                for body in [NSSize(width: 230 * scale, height: 390 * scale),
                             NSSize(width: 900 * scale, height: 32 * scale),
                             NSSize(width: 230 * scale, height: 3),
                             NSSize(width: 3, height: 32 * scale), .zero] {
                    view.frame = NSRect(origin: .zero, size: NativeGlassHUDBackground.sizeIncludingShadow(bodySize: body))
                    view.cornerRadius = 16 * scale
                    view.clipsContent = true
                    view.layoutSubtreeIfNeeded()
                    let expected = min(16 * scale, min(body.width, body.height) / 2)
                    precondition(view.bodyFrame.size == body && native.frame == view.bodyFrame)
                    precondition(view.contentView.frame == native.frame && native.cornerRadius == expected)
                    precondition(view.layer?.mask == nil && native.layer?.mask == nil,
                                 "Neither the glass nor its padded root receives a custom shape mask")
                    precondition(view.contentView.layer?.masksToBounds == true && view.contentView.layer?.cornerRadius == expected)
                    precondition(shadow.shadowRadius == 6 && shadow.shadowOpacity == (dark ? 0.32 : 0.17))
                    precondition(shadow.mask === cutout && cutout.fillRule == .evenOdd)
                    if body.width > 0 && body.height > 0 {
                        precondition(shadow.shadowPath?.boundingBoxOfPath == view.bodyFrame)
                        precondition(cutout.path?.contains(NSPoint(x: view.bodyFrame.midX, y: view.bodyFrame.midY), using: .evenOdd) == false,
                                     "Custom shadow must never fill the glass interior")
                    }
                    precondition(cutout.path?.contains(NSPoint(x: 1, y: 1), using: .evenOdd) == true)
                }
            }
        }
        let window = HUDPanel(contentRect: NSRect(x: 20, y: 20, width: 200, height: 80),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let listener = TestRefreshListener()
        var session: NativeGlassSession? = NativeGlassSession(window: window, listener: listener)
        var notifications = 0
        session!.onStateChange = { notifications += 1 }
        session!.setVisible(true) // Host has not ordered the panel in yet.
        precondition(!listener.isActive && session!.status == "Suspended")
        session!.setVisible(false)
        window.orderFrontRegardless()
        session!.setVisible(true)
        precondition(listener.isActive && listener.starts == 1)
        window.setFrameOrigin(NSPoint(x: 30, y: 30))
        window.setContentSize(NSSize(width: 250, height: 90))
        session!.setVisible(true)
        precondition(listener.starts == 1, "Moves, resizes and repeat visibility calls retain one listener")
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        precondition(!listener.isActive && session!.status == "Suspended")
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        precondition(!listener.isActive, "Display wake alone cannot override system sleep")
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        precondition(listener.isActive)
        NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)
        precondition(listener.isActive && listener.starts == 3)
        session!.setVisible(false)
        precondition(!listener.isActive && session!.status == "Stopped")
        window.orderOut(nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        precondition(!listener.isActive, "A wake must not reactivate a manually hidden HUD")
        listener.error = "Simulated registration failure"
        window.orderFrontRegardless()
        session!.setVisible(true)
        precondition(!session!.isActive && session!.failure == listener.error)
        listener.error = nil
        session!.retry()
        precondition(session!.isActive && session!.failure == nil)
        session!.shutdown()
        precondition(!listener.isActive && session!.status == "Stopped")
        session!.setVisible(true)
        window.close()
        precondition(!listener.isActive)
        window.orderFrontRegardless()
        session!.setVisible(true)
        session = nil
        precondition(!listener.isActive && notifications > 0, "Destroying the owner releases the listener")
        window.orderOut(nil)
        print("PASS: native regular glass, scaled corners, separate shadow cutout and content clipping; listener visibility/sleep/display lifecycle, failure/retry, shutdown and deallocation")

        if CommandLine.arguments.contains("--probe") {
            let actual = NativeGlassSession(window: window)
            window.orderFrontRegardless()
            actual.setVisible(true)
            print("Runtime probe: \(actual.status); registered=\(actual.isActive). This does not measure game FPS.")
            precondition(actual.isActive, "Supplied legacy listener could not register on this Mac")
            actual.shutdown()
            precondition(!actual.isActive)
            window.orderOut(nil)
        }
    }
}
