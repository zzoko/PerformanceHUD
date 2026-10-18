import AppKit

/// A small native editor for user-created presets; built-ins are never editable.
@MainActor
final class HUDPresetManagerWindowController: NSWindowController,
    NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private struct Row {
        let id: UUID
        var name: String
    }
    private var rows: [Row] = []
    private let table = NSTableView()
    private let nameField = HUDPresetNameField(string: "")
    private let renameButton = NSButton(title: "Rename", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let message = NSTextField(wrappingLabelWithString: "")
    private let onRename: (UUID, String) throws -> Void
    private let onDelete: (UUID) -> Void
    private let onEditingChanged: (Bool) -> Void
    private var editing = false

    init(onRename: @escaping (UUID, String) throws -> Void,
         onDelete: @escaping (UUID) -> Void,
         onEditingChanged: @escaping (Bool) -> Void) {
        self.onRename = onRename
        self.onDelete = onDelete
        self.onEditingChanged = onEditingChanged
        let window = HUDPresetEditingWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 350),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Manage presets"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("Use init(onRename:onDelete:onEditingChanged:)") }

    func update(presets: [HUDSavedPreset]) {
        let selectedID = selectedRow?.id
        rows = presets.map { Row(id: $0.id, name: $0.name) }
        table.reloadData()
        if let selectedID, let index = rows.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else if !rows.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        refreshSelection()
    }

    func show() {
        if !editing { editing = true; onEditingChanged(true) }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(table)
    }

    private func buildContent(in window: NSWindow) {
        let root = NSView()
        window.contentView = root
        let intro = NSTextField(wrappingLabelWithString: "Rename or delete your saved HUD presets.")
        intro.textColor = .secondaryLabelColor
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        table.headerView = nil
        table.rowHeight = 27
        table.allowsMultipleSelection = false
        table.style = .fullWidth
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = "Saved presets"
        column.width = 378
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.delegate = self
        table.dataSource = self
        table.setAccessibilityLabel("Saved presets")
        scroll.documentView = table
        nameField.placeholderString = "Preset name"
        nameField.setAccessibilityLabel("Preset name")
        nameField.delegate = self
        nameField.target = self
        nameField.action = #selector(renameSelected)
        renameButton.target = self
        renameButton.action = #selector(renameSelected)
        renameButton.bezelStyle = .rounded
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected)
        deleteButton.bezelStyle = .rounded
        let done = NSButton(title: "Done", target: self, action: #selector(finish))
        done.bezelStyle = .rounded
        message.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        message.textColor = .secondaryLabelColor
        for view in [intro, scroll, nameField, renameButton, message, deleteButton, done] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            intro.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            intro.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            intro.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            scroll.leadingAnchor.constraint(equalTo: intro.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: intro.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 14),
            scroll.heightAnchor.constraint(equalToConstant: 168),
            nameField.leadingAnchor.constraint(equalTo: intro.leadingAnchor),
            nameField.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 12),
            renameButton.leadingAnchor.constraint(equalTo: nameField.trailingAnchor, constant: 10),
            renameButton.trailingAnchor.constraint(equalTo: intro.trailingAnchor),
            renameButton.centerYAnchor.constraint(equalTo: nameField.centerYAnchor),
            renameButton.widthAnchor.constraint(equalToConstant: 78),
            message.leadingAnchor.constraint(equalTo: intro.leadingAnchor),
            message.trailingAnchor.constraint(equalTo: intro.trailingAnchor),
            message.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 9),
            message.heightAnchor.constraint(equalToConstant: 32),
            deleteButton.leadingAnchor.constraint(equalTo: intro.leadingAnchor),
            deleteButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            done.trailingAnchor.constraint(equalTo: intro.trailingAnchor),
            done.centerYAnchor.constraint(equalTo: deleteButton.centerYAnchor),
            done.widthAnchor.constraint(equalToConstant: 78)
        ])
        refreshSelection()
    }

    private var selectedRow: Row? {
        rows.indices.contains(table.selectedRow) ? rows[table.selectedRow] : nil
    }

    private func refreshSelection() {
        nameField.stringValue = selectedRow?.name ?? ""
        nameField.isEnabled = selectedRow != nil
        renameButton.isEnabled = selectedRow != nil
        deleteButton.isEnabled = selectedRow != nil
        message.textColor = .secondaryLabelColor
        message.stringValue = rows.isEmpty
            ? "Choose Preset → Save current as… to create your first preset."
            : "Deleting a preset keeps your current HUD settings."
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let field = NSTextField(labelWithString: rows[row].name)
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byTruncatingTail
        let cell = NSTableCellView()
        cell.textField = field
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { refreshSelection() }

    func controlTextDidChange(_ notification: Notification) {
        renameButton.isEnabled = selectedRow != nil && !nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc private func renameSelected() {
        guard let row = selectedRow else { return }
        do {
            let name = nameField.stringValue
            try onRename(row.id, name)
            if let index = rows.firstIndex(where: { $0.id == row.id }) {
                rows[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                table.reloadData()
            }
            refreshSelection()
        } catch {
            message.textColor = .systemRed
            message.stringValue = error.localizedDescription
        }
    }

    @objc private func deleteSelected() {
        guard let row = selectedRow else { return }
        let index = table.selectedRow
        onDelete(row.id)
        rows.removeAll { $0.id == row.id }
        table.reloadData()
        if !rows.isEmpty { table.selectRowIndexes(IndexSet(integer: min(index, rows.count - 1)), byExtendingSelection: false) }
        refreshSelection()
    }

    @objc private func finish() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        if editing { editing = false; onEditingChanged(false) }
    }
}

/// Saving is explicit: editing the HUD never overwrites a saved preset.
@MainActor
final class HUDPresetNamePrompt: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private let nameField = HUDPresetNameField(string: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let onSave: (String) throws -> Void
    private let onEditingChanged: (Bool) -> Void
    private var editing = false

    init(suggestedName: String = "", onSave: @escaping (String) throws -> Void,
         onEditingChanged: @escaping (Bool) -> Void) {
        self.onSave = onSave
        self.onEditingChanged = onEditingChanged
        let window = HUDPresetEditingWindow(contentRect: NSRect(x: 0, y: 0, width: 410, height: 180),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Save preset"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let root = NSView()
        window.contentView = root
        let label = NSTextField(labelWithString: "Name")
        nameField.stringValue = suggestedName
        nameField.placeholderString = "My preset"
        nameField.setAccessibilityLabel("Preset name")
        nameField.delegate = self
        nameField.target = self
        nameField.action = #selector(save)
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.isEnabled = !suggestedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        message.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        message.textColor = .secondaryLabelColor
        message.stringValue = "Includes categories, readings, and their options."
        for view in [label, nameField, message, cancel, saveButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            label.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            nameField.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            nameField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            nameField.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 7),
            message.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            message.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            message.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 10),
            message.heightAnchor.constraint(equalToConstant: 34),
            saveButton.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            saveButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            saveButton.widthAnchor.constraint(equalToConstant: 78),
            cancel.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -10),
            cancel.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            cancel.widthAnchor.constraint(equalToConstant: 78)
        ])
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("Use init(suggestedName:onSave:onEditingChanged:)") }

    func show() {
        if !editing { editing = true; onEditingChanged(true) }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        nameField.selectText(nil)
    }

    func controlTextDidChange(_ notification: Notification) {
        saveButton.isEnabled = !nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc private func save() {
        guard saveButton.isEnabled else { return }
        do {
            try onSave(nameField.stringValue)
            window?.close()
        } catch {
            message.textColor = .systemRed
            message.stringValue = error.localizedDescription
        }
    }

    @objc private func cancel() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        if editing { editing = false; onEditingChanged(false) }
    }
}

@MainActor
private final class HUDPresetEditingWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let editor = firstResponder as? HUDPresetFieldEditor, editor.handleShortcut(event) { return true }
        if event.modifierFlags.intersection([.command, .shift, .control, .option]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
private final class HUDPresetNameField: NSTextField {
    override class var cellClass: AnyClass? {
        get { HUDPresetNameFieldCell.self }
        set {}
    }
}

@MainActor
private final class HUDPresetNameFieldCell: NSTextFieldCell {
    private let editor: HUDPresetFieldEditor = {
        let editor = HUDPresetFieldEditor(frame: .zero)
        editor.isFieldEditor = true
        editor.isRichText = false
        editor.allowsUndo = true
        return editor
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
}

@MainActor
private final class HUDPresetFieldEditor: NSTextView {
    override func keyDown(with event: NSEvent) {
        if !handleShortcut(event) { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleShortcut(event) || super.performKeyEquivalent(with: event)
    }

    // Accessory apps have no Edit menu. Keep text shortcuts local to the editor.
    func handleShortcut(_ event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers?.lowercased()
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        guard modifiers == .command || (key == "z" && modifiers == [.command, .shift]) else { return false }
        switch key {
        case "a": selectAll(nil)
        case "c": copy(nil)
        case "v": paste(nil)
        case "x": cut(nil)
        case "z":
            if event.modifierFlags.contains(.shift) { undoManager?.redo() }
            else { undoManager?.undo() }
        default: return false
        }
        return true
    }
}
