import AppKit
import Carbon

enum HUDHotkeyAction: String, CaseIterable, Codable {
    case visibility, logging, appearance

    var title: String {
        switch self {
        case .visibility: return "Show / hide HUD"
        case .logging: return "Start / stop logging"
        case .appearance: return "Cycle appearance"
        }
    }

    var identifier: UInt32 {
        switch self {
        case .visibility: return 1
        case .logging: return 2
        case .appearance: return 3
        }
    }

    var defaultShortcut: HUDShortcut {
        let key: Int
        switch self {
        case .visibility: key = kVK_ANSI_H
        case .logging: key = kVK_ANSI_L
        case .appearance: key = kVK_ANSI_A
        }
        return HUDShortcut(keyCode: UInt32(key), modifiers: UInt32(optionKey))
    }
}

struct HUDShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let allowedModifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        let flags = event.modifierFlags
        modifiers = (flags.contains(.control) ? UInt32(controlKey) : 0)
            | (flags.contains(.option) ? UInt32(optionKey) : 0)
            | (flags.contains(.shift) ? UInt32(shiftKey) : 0)
            | (flags.contains(.command) ? UInt32(cmdKey) : 0)
    }

    var isValid: Bool {
        keyCode < 128 && !(54...63).contains(keyCode)
            && modifiers & ~Self.allowedModifiers == 0
            && modifiers & UInt32(controlKey | optionKey | cmdKey) != 0
    }

    var menuModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    private static let specialKeys: [UInt32: (String, String)] = [
        UInt32(kVK_Space): ("Space", " "), UInt32(kVK_Return): ("Return", "\r"),
        UInt32(kVK_Tab): ("Tab", "\t"), UInt32(kVK_Delete): ("Delete", "\u{8}"),
        UInt32(kVK_Escape): ("Esc", "\u{1b}"), UInt32(kVK_ForwardDelete): ("⌦", "\u{f728}"),
        UInt32(kVK_LeftArrow): ("←", "\u{f702}"), UInt32(kVK_RightArrow): ("→", "\u{f703}"),
        UInt32(kVK_UpArrow): ("↑", "\u{f700}"), UInt32(kVK_DownArrow): ("↓", "\u{f701}"),
        UInt32(kVK_Home): ("Home", "\u{f729}"), UInt32(kVK_End): ("End", "\u{f72b}"),
        UInt32(kVK_PageUp): ("Page Up", "\u{f72c}"), UInt32(kVK_PageDown): ("Page Down", "\u{f72d}")
    ]

    private var functionNumber: Int? {
        let codes = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
                     kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
                     kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        return codes.firstIndex(of: Int(keyCode)).map { $0 + 1 }
    }

    // Translate the physical key using the current layout, without Option's
    // alternate symbol or dead-key behavior. Carbon registration uses key codes.
    var menuKey: String {
        if let special = Self.specialKeys[keyCode] { return special.1 }
        if let functionNumber { return String(UnicodeScalar(0xf703 + functionNumber)!) }
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        let fallback = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
                ?? TISGetInputSourceProperty(fallback, kTISPropertyUnicodeKeyLayoutData) else { return "" }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKey: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKey,
            characters.count, &length, &characters)
        guard status == noErr, length > 0 else { return "" }
        return String(utf16CodeUnits: characters, count: length).lowercased()
    }

    var displayName: String {
        let flags = menuModifiers
        let prefix = (flags.contains(.control) ? "⌃" : "")
            + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "")
            + (flags.contains(.command) ? "⌘" : "")
        let key = Self.specialKeys[keyCode]?.0
            ?? functionNumber.map { "F\($0)" }
            ?? (menuKey.isEmpty ? "Key \(keyCode)" : menuKey.uppercased())
        return prefix + key
    }
}

enum HUDDragModifier: String, CaseIterable, Codable {
    case option, control, shift, command

    var name: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        case .command: return "⌘"
        }
    }

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .option: return .option
        case .control: return .control
        case .shift: return .shift
        case .command: return .command
        }
    }
}

struct HUDHotkeySettings: Codable, Equatable {
    var visibility: HUDShortcut?
    var logging: HUDShortcut?
    var appearance: HUDShortcut?
    var dragModifier: HUDDragModifier = .option

    private enum CodingKeys: String, CodingKey {
        case visibility, logging, appearance, dragModifier
    }

    static let defaults = HUDHotkeySettings(visibility: HUDHotkeyAction.visibility.defaultShortcut,
        logging: HUDHotkeyAction.logging.defaultShortcut, appearance: HUDHotkeyAction.appearance.defaultShortcut)
    private static let storageKey = "hud.hotkeys"

    subscript(action: HUDHotkeyAction) -> HUDShortcut? {
        get {
            switch action {
            case .visibility: return visibility
            case .logging: return logging
            case .appearance: return appearance
            }
        }
        set {
            switch action {
            case .visibility: visibility = newValue
            case .logging: logging = newValue
            case .appearance: appearance = newValue
            }
        }
    }

    var validationError: String? {
        var used: [HUDShortcut] = []
        for action in HUDHotkeyAction.allCases {
            guard let shortcut = self[action] else { continue }
            guard shortcut.isValid else { return "Include Control, Option, or Command with a key." }
            if shortcut.keyCode == UInt32(kVK_ANSI_Q), shortcut.modifiers == UInt32(cmdKey) {
                return "Command–Q is reserved for Quit. Choose another combination."
            }
            if used.contains(shortcut) { return "Each action needs a different shortcut." }
            used.append(shortcut)
        }
        return nil
    }

    static func load(from store: UserDefaults = .standard) -> Self {
        guard let data = store.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(Self.self, from: data),
              settings.validationError == nil else { return .defaults }
        return settings
    }

    func save(to store: UserDefaults = .standard) {
        guard validationError == nil, let data = try? JSONEncoder().encode(self) else { return }
        store.set(data, forKey: Self.storageKey)
    }
}

extension HUDHotkeySettings {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        visibility = try values.decodeIfPresent(HUDShortcut.self, forKey: .visibility)
        logging = try values.decodeIfPresent(HUDShortcut.self, forKey: .logging)
        appearance = try values.decodeIfPresent(HUDShortcut.self, forKey: .appearance)
        // Older saved hotkeys have no drag setting. Keep those bindings intact.
        dragModifier = (try? values.decode(HUDDragModifier.self, forKey: .dragModifier)) ?? .option
    }
}
