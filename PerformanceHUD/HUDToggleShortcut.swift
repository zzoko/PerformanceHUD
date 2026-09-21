import AppKit
import Carbon

@MainActor
final class HUDToggleShortcut {
    static let menuKey = "h"
    static let menuModifiers: NSEvent.ModifierFlags = [.control, .option, .command]
    private static let hotKeyID = EventHotKeyID(signature: 0x50485544, id: 1) // PHUD

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var isPressed = false
    var onToggle: (() -> Void)?

    func start() -> OSStatus {
        stop()
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                return MainActor.assumeIsolated {
                    let shortcut = Unmanaged<HUDToggleShortcut>.fromOpaque(context).takeUnretainedValue()
                    return shortcut.handle(event)
                }
            },
            events.count, &events,
            Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        guard status == noErr else { return status }
        let registration = RegisterEventHotKey(
            UInt32(kVK_ANSI_H), UInt32(controlKey | optionKey | cmdKey),
            Self.hotKeyID, GetApplicationEventTarget(), 0, &hotKey
        )
        if registration != noErr { stop() }
        return registration
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var identifier = EventHotKeyID()
        let result = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier
        )
        guard result == noErr,
              identifier.signature == Self.hotKeyID.signature,
              identifier.id == Self.hotKeyID.id else { return OSStatus(eventNotHandledErr) }
        if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
            isPressed = false
        } else if GetEventKind(event) == UInt32(kEventHotKeyPressed), !isPressed {
            isPressed = true
            onToggle?()
        }
        return noErr
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        isPressed = false
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
