import AppKit
import Carbon

@MainActor
final class HUDHotkeyEditor: NSWindowController, NSWindowDelegate {
    private let hotkeys: HUDHotkeyMonitor
    private var recording: HUDHotkeyAction?
    private var buttons: [HUDHotkeyAction: NSButton] = [:]
    private var clearButtons: [HUDHotkeyAction: NSButton] = [:]
    private let message = NSTextField(wrappingLabelWithString: "")
    private let dragKey = NSPopUpButton(frame: .zero, pullsDown: false)

    init(hotkeys: HUDHotkeyMonitor) {
        self.hotkeys = hotkeys
        let window = HUDHotkeyWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 364),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Edit hotkeys"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.recordKey = { [weak self] event in self?.record(event) ?? false }
        let root = NSView()
        window.contentView = root
        let intro = NSTextField(wrappingLabelWithString:
            "Click a shortcut, then press your new combination. Escape cancels; Delete clears it.")
        intro.textColor = .secondaryLabelColor
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 12
        for action in HUDHotkeyAction.allCases {
            let label = NSTextField(labelWithString: action.title)
            let record = NSButton(title: "", target: self, action: #selector(startRecording(_:)))
            record.bezelStyle = .rounded
            record.tag = Int(action.identifier)
            record.setAccessibilityLabel("Record shortcut for \(action.title)")
            let clear = NSButton(title: "Clear", target: self, action: #selector(clearShortcut(_:)))
            clear.bezelStyle = .rounded
            clear.tag = Int(action.identifier)
            clear.setAccessibilityLabel("Clear shortcut for \(action.title)")
            let row = NSStackView(views: [label, record, clear])
            row.spacing = 12
            label.widthAnchor.constraint(equalToConstant: 190).isActive = true
            record.widthAnchor.constraint(equalToConstant: 190).isActive = true
            clear.widthAnchor.constraint(equalToConstant: 60).isActive = true
            rows.addArrangedSubview(row)
            buttons[action] = record
            clearButtons[action] = clear
        }
        let dragLabel = NSTextField(labelWithString: "Move HUD")
        dragKey.addItems(withTitles: HUDDragModifier.allCases.map { "\($0.symbol) \($0.name)" })
        dragKey.target = self
        dragKey.action = #selector(changeDragKey(_:))
        dragKey.setAccessibilityLabel("Key held while dragging the HUD with the left mouse button")
        let dragSuffix = NSTextField(labelWithString: "+ drag")
        dragSuffix.textColor = .secondaryLabelColor
        let dragRow = NSStackView(views: [dragLabel, dragKey, dragSuffix])
        dragRow.spacing = 12
        dragLabel.widthAnchor.constraint(equalToConstant: 190).isActive = true
        dragKey.widthAnchor.constraint(equalToConstant: 190).isActive = true
        dragSuffix.widthAnchor.constraint(equalToConstant: 60).isActive = true
        rows.addArrangedSubview(dragRow)
        message.font = .systemFont(ofSize: 12)
        let note = NSTextField(wrappingLabelWithString:
            "Hotkeys work across apps and are paused while this window is open. Option-letter shortcuts replace their usual typing symbols while the app runs.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        let restore = NSButton(title: "Restore defaults", target: self, action: #selector(restoreDefaults))
        restore.bezelStyle = .rounded
        let done = NSButton(title: "Done", target: self, action: #selector(finish))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        for view in [intro, rows, message, note, restore, done] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            intro.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            intro.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            intro.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            rows.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 18),
            rows.leadingAnchor.constraint(equalTo: intro.leadingAnchor),
            message.topAnchor.constraint(equalTo: rows.bottomAnchor, constant: 12),
            message.leadingAnchor.constraint(equalTo: intro.leadingAnchor),
            message.trailingAnchor.constraint(equalTo: intro.trailingAnchor),
            message.heightAnchor.constraint(equalToConstant: 34),
            note.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 8),
            note.leadingAnchor.constraint(equalTo: intro.leadingAnchor),
            note.trailingAnchor.constraint(equalTo: intro.trailingAnchor),
            restore.leadingAnchor.constraint(equalTo: intro.leadingAnchor),
            restore.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            done.trailingAnchor.constraint(equalTo: intro.trailingAnchor),
            done.centerYAnchor.constraint(equalTo: restore.centerYAnchor),
            done.widthAnchor.constraint(equalToConstant: 80)
        ])
        refresh()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("Use init(hotkeys:)") }

    func present() {
        hotkeys.beginEditing()
        cancelRecording()
        if let error = HUDHotkeyAction.allCases.compactMap({ hotkeys.errors[$0] }).first {
            setMessage(error, error: true)
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func refresh() {
        dragKey.selectItem(at: HUDDragModifier.allCases.firstIndex(of: hotkeys.settings.dragModifier)!)
        for action in HUDHotkeyAction.allCases {
            buttons[action]?.title = recording == action ? "Press shortcut…"
                : (hotkeys.settings[action]?.displayName ?? "Not set")
            buttons[action]?.contentTintColor = recording == action ? .controlAccentColor : nil
            clearButtons[action]?.isEnabled = hotkeys.settings[action] != nil
        }
    }

    private func setMessage(_ text: String, error: Bool = false) {
        message.stringValue = text
        message.textColor = error ? .systemOrange : .secondaryLabelColor
    }

    @objc private func startRecording(_ sender: NSButton) {
        recording = HUDHotkeyAction.allCases.first { Int($0.identifier) == sender.tag }
        setMessage("Use Control, Option, or Command with a key. Changes are saved immediately.")
        refresh()
    }

    @objc private func clearShortcut(_ sender: NSButton) {
        guard let action = HUDHotkeyAction.allCases.first(where: { Int($0.identifier) == sender.tag }) else { return }
        apply(nil, to: action)
    }

    @objc private func changeDragKey(_ sender: NSPopUpButton) {
        guard HUDDragModifier.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        recording = nil
        var settings = hotkeys.settings
        settings.dragModifier = HUDDragModifier.allCases[sender.indexOfSelectedItem]
        if let error = hotkeys.update(settings) { setMessage(error, error: true) }
        else { setMessage("Hold \(settings.dragModifier.name) and drag with the left mouse button to move the HUD.") }
        refresh()
    }

    private func apply(_ shortcut: HUDShortcut?, to action: HUDHotkeyAction) {
        var settings = hotkeys.settings
        settings[action] = shortcut
        if let error = hotkeys.update(settings) { setMessage(error, error: true); return }
        recording = nil
        setMessage(shortcut == nil ? "Shortcut cleared. The menu control is still available." : "Shortcut saved.")
        refresh()
    }

    private func record(_ event: NSEvent) -> Bool {
        guard let action = recording, event.type == .keyDown else { return false }
        guard !event.isARepeat else { return true }
        if event.keyCode == UInt16(kVK_Escape) { cancelRecording(); return true }
        let shortcut = HUDShortcut(event: event)
        if shortcut.modifiers == 0 && (event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)) {
            apply(nil, to: action)
        } else { apply(shortcut, to: action) }
        return true
    }

    private func cancelRecording() {
        recording = nil
        setMessage("Appearance cycles Light → Dark → Follow system.")
        refresh()
    }

    @objc private func restoreDefaults() {
        recording = nil
        if let error = hotkeys.update(.defaults) { setMessage(error, error: true) }
        else { setMessage("Defaults restored: ⌥H, ⌥L, ⌥A, and ⌥ + drag.") }
        refresh()
    }

    @objc private func finish() { window?.close() }

    func windowDidResignKey(_ notification: Notification) {
        if recording != nil { cancelRecording() }
    }

    func windowWillClose(_ notification: Notification) {
        recording = nil
        hotkeys.endEditing()
    }
}

/// Consume a recorded key before AppKit can interpret it as a menu command.
@MainActor
private final class HUDHotkeyWindow: NSWindow {
    var recordKey: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recordKey?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, recordKey?(event) == true { return }
        super.sendEvent(event)
    }
}
