import AppKit
import CoreGraphics
import Darwin

// Display-refresh listener for native glass compatibility. No image capture.
// The listener API is deprecated/unsupported; the uncapping effect is observed,
// not guaranteed. Registration success does not measure game FPS.

// One retained registration, removed on hide, sleep, close or shutdown.
// The lock protects diagnostic reads; the callback never reads pixels or redraws the HUD.
nonisolated private final class NativeGlassRefreshCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

nonisolated private let nativeGlassRefreshCallback: CGScreenRefreshCallback = { _, _, context in
    guard let context else { return }
    Unmanaged<NativeGlassRefreshCounter>.fromOpaque(context).takeUnretainedValue().increment()
}

nonisolated protocol NativeGlassRefreshListening: AnyObject {
    var isActive: Bool { get }
    var callbacks: Int { get }
    func start() -> String?
    func stop()
}

nonisolated private final class NativeGlassRefreshListener: NativeGlassRefreshListening {
    private typealias Register = @convention(c) (CGScreenRefreshCallback, UnsafeMutableRawPointer?) -> Int32
    private typealias Unregister = @convention(c) (CGScreenRefreshCallback, UnsafeMutableRawPointer?) -> Void
    private var library: UnsafeMutableRawPointer?
    private var unregister: Unregister?
    private var context: UnsafeMutableRawPointer?
    private var counter: NativeGlassRefreshCounter?
    var isActive: Bool { context != nil }
    var callbacks: Int { counter?.value ?? 0 }

    // Swift marks these legacy functions unavailable. Check both runtime symbols;
    // a missing function or failed registration is reported, never treated as success.
    func start() -> String? {
        stop()
        guard let library = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY | RTLD_LOCAL) else {
            return "Legacy refresh library unavailable"
        }
        guard let registerSymbol = dlsym(library, "CGRegisterScreenRefreshCallback"),
              let unregisterSymbol = dlsym(library, "CGUnregisterScreenRefreshCallback") else {
            dlclose(library); return "Legacy refresh entry points unavailable"
        }
        let register = unsafeBitCast(registerSymbol, to: Register.self)
        let counter = NativeGlassRefreshCounter()
        let context = Unmanaged.passRetained(counter).toOpaque()
        let result = register(nativeGlassRefreshCallback, context)
        guard result == 0 else {
            Unmanaged<NativeGlassRefreshCounter>.fromOpaque(context).release()
            dlclose(library); return "Legacy listener registration failed: \(result)"
        }
        self.library = library
        self.unregister = unsafeBitCast(unregisterSymbol, to: Unregister.self)
        self.counter = counter; self.context = context
        return nil
    }

    func stop() {
        if let context {
            unregister?(nativeGlassRefreshCallback, context)
            self.context = nil
            Unmanaged<NativeGlassRefreshCounter>.fromOpaque(context).release()
        }
        counter = nil; unregister = nil
        if let library { dlclose(library); self.library = nil }
    }
    deinit { stop() }
}

@available(macOS 26.0, *)
@MainActor
final class NativeGlassSession: NSObject {
    private weak var window: NSWindow?
    private let listener: any NativeGlassRefreshListening
    private let workspaceNotifications = NSWorkspace.shared.notificationCenter
    private var enabled = false
    private var systemAsleep = false
    private var displayAsleep = false

    var onStateChange: (() -> Void)?
    private(set) var failure: String?
    private(set) var status = "Stopped"
    // Registration success is not proof of another app's presentation mode or FPS.
    var isActive: Bool { listener.isActive }
    var refreshCallbacks: Int { listener.callbacks }

    convenience init(window: NSWindow) {
        self.init(window: window, listener: NativeGlassRefreshListener())
    }

    init(window: NSWindow, listener: any NativeGlassRefreshListening) {
        self.window = window
        self.listener = listener
        super.init()
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceNotifications.addObserver(self, selector: #selector(workspaceChanged(_:)), name: name, object: nil)
        }
        for name in [NSWindow.didChangeScreenNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowChanged(_:)), name: name, object: window)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged(_:)),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // AFTER showing the HUD; BEFORE orderOut. AppKit has no general orderOut notification.
    func setVisible(_ visible: Bool) {
        guard visible != enabled else { return }
        enabled = visible
        refresh()
    }

    func retry() { refresh() }

    // Unregister before AppKit tears down the window or terminates the app.
    func shutdown() {
        enabled = false
        refresh()
    }

    @objc private func workspaceChanged(_ note: Notification) {
        switch note.name {
        case NSWorkspace.willSleepNotification: systemAsleep = true
        case NSWorkspace.didWakeNotification: systemAsleep = false
        case NSWorkspace.screensDidSleepNotification: displayAsleep = true
        case NSWorkspace.screensDidWakeNotification: displayAsleep = false
        default: return
        }
        refresh()
    }

    @objc private func windowChanged(_ note: Notification) {
        if note.name == NSWindow.willCloseNotification { enabled = false }
        refresh()
    }

    @objc private func displaysChanged(_ note: Notification) { refresh() }

    private func refresh() {
        defer { onStateChange?() }
        failure = nil
        listener.stop()
        guard enabled else { status = "Stopped"; return }
        guard !systemAsleep, !displayAsleep,
              window?.isVisible == true, window?.isMiniaturized == false else {
            status = "Suspended"; return
        }
        failure = listener.start()
        status = failure ?? "Screen-change listener active — no image capture"
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        workspaceNotifications.removeObserver(self)
        listener.stop()
    }
}
