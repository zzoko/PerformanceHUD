import Foundation
import Darwin

/// Read-only experiment. macOS 27's gamepolicyd publishes its GameModeStatus
/// enum through this Darwin notification: 0 off, 1 on, 2 paused. Paused means
/// the performance mode is inactive, so the HUD shows off, like gamepolicyctl.
/// The notification name/state contract is undocumented; unknown values and
/// registration/read failures remain unavailable. No Xcode tool, game process
/// inspection, helper, system-log access, or Game Mode setting changes.
@MainActor
final class GameModeMonitor {
    var onUpdate: ((Bool?) -> Void)?
    private let name: String
    private let api = GameModeNotifyAPI.load()
    private var token: Int32?
    private var generation = UUID()
    var isRunning: Bool { token != nil }

    init(notificationName: String = "com.apple.system.game_mode_status_changed") {
        name = notificationName
    }

    func configure(enabled: Bool) {
        guard enabled else { stop(); return }
        guard token == nil else { return }
        guard let api else { onUpdate?(nil); return }
        let ticket = UUID()
        generation = ticket
        var registration: Int32 = -1
        let result = api.register(name, &registration, .main) { [weak self] deliveredToken in
            MainActor.assumeIsolated {
                guard let self, self.generation == ticket, self.token == deliveredToken else { return }
                self.read()
            }
        }
        guard result == 0 else { onUpdate?(nil); return }
        token = registration
        read()
    }

    func stop() {
        generation = UUID()
        if let token { _ = api?.cancel(token) }
        token = nil
        onUpdate?(nil)
    }

    private func read() {
        guard let token, let api else { return }
        var state: UInt64 = 0
        let status = api.read(token, &state)
        onUpdate?(status == 0 ? Self.enabledState(rawValue: state) : nil)
    }

    static func enabledState(rawValue: UInt64) -> Bool? {
        switch rawValue {
        case 0, 2: return false
        case 1: return true
        default: return nil
        }
    }

    deinit { if let token { _ = api?.cancel(token) } }
}

// notify.h is not imported by this Swift SDK. Resolve the standard libSystem
// C entry points, checking availability before calling with their C signatures.
nonisolated private struct GameModeNotifyAPI: @unchecked Sendable {
    typealias Register = @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<Int32>, DispatchQueue,
                                         @escaping @convention(block) (Int32) -> Void) -> UInt32
    typealias Read = @convention(c) (Int32, UnsafeMutablePointer<UInt64>) -> UInt32
    typealias Cancel = @convention(c) (Int32) -> UInt32
    let register: Register
    let read: Read
    let cancel: Cancel

    static func load() -> Self? {
        guard let library = dlopen(nil, RTLD_LAZY) else { return nil }
        defer { dlclose(library) } // libSystem stays loaded for the process lifetime.
        guard let register = dlsym(library, "notify_register_dispatch"),
              let read = dlsym(library, "notify_get_state"),
              let cancel = dlsym(library, "notify_cancel") else { return nil }
        return Self(register: unsafeBitCast(register, to: Register.self),
                    read: unsafeBitCast(read, to: Read.self),
                    cancel: unsafeBitCast(cancel, to: Cancel.self))
    }
}
