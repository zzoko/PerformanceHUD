import AppKit
import Carbon

/// Carbon hotkeys work across apps without monitoring arbitrary keyboard input.
@MainActor
final class HUDHotkeyMonitor {
    private static let signature: OSType = 0x50485544 // PHUD
    private var registrations: [HUDHotkeyAction: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var pressed: Set<HUDHotkeyAction> = []
    private let store: UserDefaults
    private(set) var settings: HUDHotkeySettings
    private(set) var errors: [HUDHotkeyAction: String] = [:]
    private(set) var isEditing = false
    var onPress: ((HUDHotkeyAction) -> Void)?
    var onChange: (() -> Void)?

    init(store: UserDefaults = .standard) {
        self.store = store
        settings = .load(from: store)
    }

    func start() {
        stop()
        errors.removeAll()
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                Unmanaged<HUDHotkeyMonitor>.fromOpaque(context).takeUnretainedValue().handle(event)
            }
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
        for action in HUDHotkeyAction.allCases {
            guard let shortcut = settings[action] else { continue }
            var reference: EventHotKeyRef?
            let failure = status == noErr ? Self.reservedError(shortcut) : "Could not install the shortcut handler."
            let result = failure == nil ? Self.register(shortcut, id: action.identifier, reference: &reference) : status
            if failure == nil, result == noErr, let reference {
                registrations[action] = reference
            } else {
                errors[action] = failure ?? "\(shortcut.displayName) is unavailable. Choose another shortcut in Edit hotkeys."
                NSLog("PerformanceHUD: %@ shortcut unavailable (%d)", action.rawValue, result)
            }
        }
        onChange?()
    }

    func stop() {
        for reference in registrations.values { UnregisterEventHotKey(reference) }
        registrations.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        pressed.removeAll()
    }

    func beginEditing() {
        guard !isEditing else { return }
        isEditing = true
        stop()
        onChange?()
    }

    func endEditing() {
        guard isEditing else { return }
        isEditing = false
        start()
    }

    /// Called only while registrations are paused. Probe before saving so a
    /// rejected combination leaves the user's previous settings intact.
    func update(_ candidate: HUDHotkeySettings) -> String? {
        guard isEditing else { return "Open Edit hotkeys before changing shortcuts." }
        if let error = candidate.validationError { return error }
        var probes: [EventHotKeyRef] = []
        defer { for reference in probes { UnregisterEventHotKey(reference) } }
        for action in HUDHotkeyAction.allCases {
            // Let an unavailable old binding be fixed or cleared independently
            // of another unavailable binding. Unchanged keys are retried on close.
            guard candidate[action] != settings[action] else { continue }
            guard let shortcut = candidate[action] else { continue }
            if let error = Self.reservedError(shortcut) { return error }
            var reference: EventHotKeyRef?
            let status = Self.register(shortcut, id: 100 + action.identifier, reference: &reference)
            guard status == noErr, let reference else {
                return "\(shortcut.displayName) could not be registered. Try another combination."
            }
            probes.append(reference)
        }
        for action in HUDHotkeyAction.allCases where candidate[action] != settings[action] {
            errors.removeValue(forKey: action)
        }
        settings = candidate
        candidate.save(to: store)
        onChange?()
        return nil
    }

    func isActive(_ action: HUDHotkeyAction) -> Bool { registrations[action] != nil }

    private static func register(_ shortcut: HUDShortcut, id: UInt32, reference: inout EventHotKeyRef?) -> OSStatus {
        RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: signature, id: id), GetApplicationEventTarget(), 0, &reference)
    }

    private static func reservedError(_ shortcut: HUDShortcut) -> String? {
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == noErr, let array else { return nil }
        let keys = array.takeRetainedValue() as NSArray
        for case let key as NSDictionary in keys {
            if (key[kHISymbolicHotKeyEnabled] as? NSNumber)?.boolValue == true,
               (key[kHISymbolicHotKeyCode] as? NSNumber)?.uint32Value == shortcut.keyCode,
               ((key[kHISymbolicHotKeyModifiers] as? NSNumber)?.uint32Value ?? 0)
                    & HUDShortcut.allowedModifiers == shortcut.modifiers {
                return "\(shortcut.displayName) is assigned in macOS Keyboard Shortcuts. Choose another combination."
            }
        }
        return nil
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var identifier = EventHotKeyID()
        let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
        guard result == noErr, identifier.signature == Self.signature,
              let action = HUDHotkeyAction.allCases.first(where: { $0.identifier == identifier.id }),
              isActive(action), !isEditing else { return OSStatus(eventNotHandledErr) }
        receive(action, pressed: GetEventKind(event) == UInt32(kEventHotKeyPressed))
        return noErr
    }

    // One action per press, including when a key is held down through a dialog.
    func receive(_ action: HUDHotkeyAction, pressed isPressed: Bool) {
        guard !isEditing else { return }
        if isPressed {
            if pressed.insert(action).inserted { onPress?(action) }
        } else { pressed.remove(action) }
    }

    deinit {
        for reference in registrations.values { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
