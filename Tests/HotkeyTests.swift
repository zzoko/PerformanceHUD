import AppKit
import Carbon

@main
struct HotkeyTests {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let suite = "PerformanceHUD.HotkeyTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        func check(_ condition: @autoclosure () -> Bool, _ description: String) {
            precondition(condition(), description)
        }

        check(HUDHotkeySettings.load(from: store) == .defaults, "Fresh settings use the defaults")
        for action in HUDHotkeyAction.allCases {
            check(action.defaultShortcut.modifiers == UInt32(optionKey), "Defaults have one modifier")
            check(!action.defaultShortcut.menuKey.isEmpty, "Every default has a keyboard-layout label")
        }
        check(HUDHotkeyAction.visibility.defaultShortcut.keyCode == UInt32(kVK_ANSI_H), "HUD default is Option-H")
        check(HUDHotkeyAction.logging.defaultShortcut.keyCode == UInt32(kVK_ANSI_L), "Logging default is Option-L")
        check(HUDHotkeyAction.appearance.defaultShortcut.keyCode == UInt32(kVK_ANSI_A), "Appearance default is Option-A")
        check(HUDHotkeySettings.defaults.dragModifier == .option, "Dragging defaults to Option")
        for modifier in HUDDragModifier.allCases {
            for held in HUDDragModifier.allCases {
                check(HUDPanel.dragModifiersHeld(held.flags, modifier: modifier) == (held == modifier),
                      "Only the chosen single modifier enables dragging")
            }
            check(HUDPanel.dragModifiersHeld(modifier.flags.union([.capsLock, .function]), modifier: modifier),
                  "Caps Lock and Fn do not prevent dragging")
            check(!HUDPanel.dragModifiersHeld([], modifier: modifier)
                  && !HUDPanel.dragModifiersHeld([.control, .option, .command, .shift], modifier: modifier),
                  "Plain clicks and combinations of modifiers remain click-through")
        }

        let cleared = HUDHotkeySettings(visibility: nil, logging: nil, appearance: nil)
        cleared.save(to: store)
        check(HUDHotkeySettings.load(from: store) == cleared, "Cleared shortcuts stay cleared after relaunch")
        var duplicate = HUDHotkeySettings.defaults
        duplicate.logging = duplicate.visibility
        check(duplicate.validationError != nil, "Duplicate shortcuts are rejected")
        duplicate.save(to: store)
        check(HUDHotkeySettings.load(from: store) == cleared, "Invalid settings cannot overwrite saved settings")
        var invalid = HUDHotkeySettings.defaults
        invalid.visibility = HUDShortcut(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(shiftKey))
        check(invalid.validationError != nil, "Shift-only typing cannot become a hotkey")
        invalid.visibility = HUDShortcut(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey))
        check(invalid.validationError != nil, "Quit remains available")
        invalid.visibility = HUDShortcut(keyCode: UInt32(kVK_Command), modifiers: UInt32(cmdKey))
        check(invalid.validationError != nil, "Modifier keys alone are not shortcuts")
        store.set(Data("broken".utf8), forKey: "hud.hotkeys")
        check(HUDHotkeySettings.load(from: store) == .defaults, "Corrupt settings recover to defaults")

        // These are data objects, never posted to the system event stream.
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.option, .capsLock, .function],
            timestamp: 0, windowNumber: 0, context: nil, characters: "å", charactersIgnoringModifiers: "a",
            isARepeat: false, keyCode: UInt16(kVK_ANSI_A))!
        check(HUDShortcut(event: event) == HUDHotkeyAction.appearance.defaultShortcut,
              "Recording ignores Caps Lock, Fn, and Option's alternate characters")

        // Register unusual combinations briefly so this test does not take over
        // the user's normal H/L/A bindings or trigger the installed app.
        let modifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        let custom = HUDHotkeySettings(
            visibility: HUDShortcut(keyCode: UInt32(kVK_F18), modifiers: modifiers),
            logging: HUDShortcut(keyCode: UInt32(kVK_F19), modifiers: modifiers),
            appearance: HUDShortcut(keyCode: UInt32(kVK_F20), modifiers: modifiers), dragModifier: .command)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(custom)) as! [String: Any]
        legacy.removeValue(forKey: "dragModifier")
        store.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "hud.hotkeys")
        var migrated = custom
        migrated.dragModifier = .option
        check(HUDHotkeySettings.load(from: store) == migrated,
              "Existing custom hotkeys survive adding the drag preference")
        legacy["dragModifier"] = "unknown"
        store.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "hud.hotkeys")
        check(HUDHotkeySettings.load(from: store) == migrated,
              "An unknown drag key falls back without discarding keyboard bindings")
        cleared.save(to: store)
        let monitor = HUDHotkeyMonitor(store: store)
        defer { monitor.stop() }
        check(monitor.update(custom) != nil, "Settings can only be changed while editing")
        monitor.beginEditing()
        check(monitor.update(custom) == nil, "Valid custom bindings register successfully")
        check(HUDHotkeySettings.load(from: store) == custom, "Custom bindings survive relaunch")
        check(monitor.update(duplicate) != nil && monitor.settings == custom,
              "Rejected changes leave all previous bindings intact")
        var actions: [HUDHotkeyAction] = []
        monitor.onPress = { actions.append($0) }
        monitor.receive(.visibility, pressed: true)
        check(actions.isEmpty, "Recording cannot trigger a HUD action")
        monitor.endEditing()
        check(HUDHotkeyAction.allCases.allSatisfy { monitor.isActive($0) }, "Closing editor resumes all bindings")
        check(monitor.errors.isEmpty, "All test combinations are available")
        monitor.receive(.visibility, pressed: true)
        monitor.receive(.visibility, pressed: true)
        monitor.receive(.visibility, pressed: false)
        monitor.receive(.visibility, pressed: true)
        monitor.receive(.logging, pressed: true)
        monitor.receive(.logging, pressed: true)
        monitor.receive(.appearance, pressed: true)
        check(actions == [.visibility, .visibility, .logging, .appearance], "Held keys fire only once per press")
        monitor.beginEditing()
        check(HUDHotkeyAction.allCases.allSatisfy { !monitor.isActive($0) }, "Editor releases global bindings")
        check(monitor.update(cleared) == nil, "Every shortcut can be removed")
        monitor.endEditing()
        check(HUDHotkeyAction.allCases.allSatisfy { !monitor.isActive($0) }, "Cleared bindings stay unregistered")
        monitor.beginEditing()
        check(monitor.update(.defaults) == nil, "Restore defaults validates and saves all default bindings")
        check(HUDHotkeySettings.load(from: store) == .defaults, "Restored defaults persist")
        monitor.stop()

        check(HUDBackground.light.next == .dark && HUDBackground.dark.next == .system
            && HUDBackground.system.next == .light, "Appearance cycles in the requested order")

        let editor = HUDHotkeyEditor(hotkeys: monitor)
        let root = editor.window!.contentView!
        editor.window!.appearance = NSAppearance(named: .aqua)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(white: 0.95, alpha: 1).cgColor
        root.updateConstraintsForSubtreeIfNeeded()
        root.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let buttons = descendants(root).compactMap { $0 as? NSButton }
        check(buttons.count == 9, "Three record buttons, three Clear buttons, drag selector, Restore defaults, and Done")
        for button in buttons {
            check(button.frame.width >= 50 && button.frame.height >= 15, "Editor buttons have usable sizes")
            check(root.bounds.contains(button.convert(button.bounds, to: root)), "Editor buttons fit the window")
        }
        let dragSelector = buttons.compactMap { $0 as? NSPopUpButton }.first!
        let position = HUDPositionMenuView()
        monitor.onChange = { position.setDragModifier(monitor.settings.dragModifier) }
        defer { monitor.onChange = nil }
        for (index, modifier) in HUDDragModifier.allCases.enumerated() {
            dragSelector.selectItem(at: index)
            dragSelector.sendAction(dragSelector.action, to: dragSelector.target)
            check(HUDHotkeySettings.load(from: store).dragModifier == modifier,
                  "Choosing a drag key in the editor persists immediately")
            check(monitor.settings.visibility == HUDHotkeyAction.visibility.defaultShortcut,
                  "Changing the drag key preserves the other hotkeys")
            check(descendants(position).compactMap { $0 as? NSTextField }
                .contains { $0.stringValue == "\(modifier.symbol) + drag" },
                  "The menu hint follows each saved drag key")
        }
        buttons.first { $0.title == "Restore defaults" }!.performClick(nil)
        check(monitor.settings.dragModifier == .option && dragSelector.indexOfSelectedItem == 0,
              "Restore defaults resets the saved drag key and editor selection")
        if let output = CommandLine.arguments.dropFirst().first,
           let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
        }
        print("Hotkey tests passed: persistence/migration, drag modifiers and menu hints, validation, registration, editor pause, key repeat, appearance order, and editor layout.")
    }
}
