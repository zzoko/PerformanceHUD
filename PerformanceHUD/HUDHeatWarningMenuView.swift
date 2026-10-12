import AppKit

/// An optional threshold, sharing the same leading edge as the reading mode buttons.
@MainActor
final class HUDHeatWarningMenuView: NSView, NSTextFieldDelegate {
    var onChange: ((HUDHeatWarningOptions) -> Void)?
    private let checkbox = HUDReadingCheckbox(title: "Heat warning", supportsEmphasis: false)
    private let thresholdField = HUDHeatWarningTextField(string: "")
    private let unitLabel = NSTextField(labelWithString: "°C")
    private var options: HUDHeatWarningOptions
    private var isEditing = false
    private var editingThreshold: Int

    init(title: String, options: HUDHeatWarningOptions) {
        self.options = options
        editingThreshold = options.thresholdCelsius
        super.init(frame: .zero)
        checkbox.target = self
        checkbox.action = #selector(toggleWarning)
        checkbox.setControlAccessibilityLabel("\(title) Heat warning")
        thresholdField.font = .monospacedDigitSystemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .regular)
        thresholdField.alignment = .center
        thresholdField.bezelStyle = .roundedBezel
        thresholdField.delegate = self
        thresholdField.onEditingStarted = { [weak self] in self?.beginEditing() }
        thresholdField.target = self
        thresholdField.action = #selector(thresholdEntered)
        thresholdField.setAccessibilityLabel("\(title) Heat warning temperature in degrees Celsius")
        thresholdField.setAccessibilityHelp("Whole numbers from 1 to 149. The temperature turns red at or above this value.")
        unitLabel.font = .menuFont(ofSize: 0)
        addSubview(checkbox)
        addSubview(thresholdField)
        addSubview(unitLabel)
        NotificationCenter.default.addObserver(self, selector: #selector(menuDidEndTracking(_:)),
                                               name: NSMenu.didEndTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidResignActive),
                                               name: NSApplication.didResignActiveNotification, object: nil)
        update(options: options, isEnabled: true)
    }

    required init?(coder: NSCoder) { fatalError("Use init(title:options:)") }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func layout() {
        super.layout()
        checkbox.frame = NSRect(x: 0, y: 0, width: checkbox.intrinsicContentSize.width, height: bounds.height)
        let unitWidth = ceil(unitLabel.intrinsicContentSize.width)
        let fieldWidth: CGFloat = 52
        let fieldHeight: CGFloat = 24
        unitLabel.frame = NSRect(x: bounds.width - unitWidth,
                                 y: (bounds.height - unitLabel.intrinsicContentSize.height) / 2,
                                 width: unitWidth, height: unitLabel.intrinsicContentSize.height)
        thresholdField.frame = NSRect(x: unitLabel.frame.minX - 6 - fieldWidth,
                                      y: (bounds.height - fieldHeight) / 2,
                                      width: fieldWidth, height: fieldHeight)
    }

    func update(options: HUDHeatWarningOptions, isEnabled: Bool) {
        self.options = options
        checkbox.state = options.enabled ? .on : .off
        checkbox.isEnabled = isEnabled
        thresholdField.isEnabled = isEnabled && options.enabled
        thresholdField.textColor = thresholdField.isEnabled ? .labelColor : .disabledControlTextColor
        unitLabel.textColor = thresholdField.isEnabled ? .labelColor : .disabledControlTextColor
        // A regular menu refresh must not replace a partially typed number.
        if !isEditing { thresholdField.stringValue = String(options.thresholdCelsius) }
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        beginEditing()
    }

    func controlTextDidChange(_ notification: Notification) {
        beginEditing()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        completeEditing(cancelled: isEscapeEvent(NSApp.currentEvent))
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        finishEditing(cancelled: true)
        return true
    }

    @objc private func thresholdEntered() {
        finishEditing()
    }

    @objc private func toggleWarning() {
        guard checkbox.isEnabled else { return }
        let enabled = checkbox.state == .on
        commitThreshold()
        options.enabled = enabled
        update(options: options, isEnabled: true)
        onChange?(options)
    }

    @objc private func menuDidEndTracking(_ notification: Notification) {
        guard isEditing else { return }
        // Escape may be consumed by NSMenu before the field editor receives it.
        finishEditing(cancelled: isEscapeEvent(NSApp.currentEvent))
    }

    @objc private func applicationDidResignActive() {
        if isEditing { finishEditing() }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil && isEditing {
            finishEditing()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func beginEditing() {
        if !isEditing { editingThreshold = options.thresholdCelsius }
        isEditing = true
    }

    private func isEscapeEvent(_ event: NSEvent?) -> Bool {
        event?.type == .keyDown && event?.keyCode == 53
    }

    private func completeEditing(cancelled: Bool) {
        if cancelled { thresholdField.stringValue = String(editingThreshold) }
        isEditing = false
        commitThreshold()
        editingThreshold = options.thresholdCelsius
    }

    private func finishEditing(cancelled: Bool = false) {
        completeEditing(cancelled: cancelled)
        window?.makeFirstResponder(nil)
        isEditing = false
    }

    private func commitThreshold() {
        let value = HUDHeatWarningOptions.parsedThreshold(thresholdField.stringValue) ?? options.thresholdCelsius
        thresholdField.stringValue = String(value)
        guard value != options.thresholdCelsius else { return }
        options.thresholdCelsius = value
        editingThreshold = value
        onChange?(options)
    }
}

@MainActor
private final class HUDHeatWarningTextField: NSTextField {
    var onEditingStarted: (() -> Void)?

    override class var cellClass: AnyClass? {
        get { HUDHeatWarningTextFieldCell.self }
        set {}
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onEditingStarted?() }
        return accepted
    }

    override func selectText(_ sender: Any?) {
        super.selectText(sender)
        if currentEditor() != nil { onEditingStarted?() }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if currentEditor() != nil { onEditingStarted?() }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let editor = currentEditor() as? HUDHeatWarningFieldEditor, editor.handleShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
private final class HUDHeatWarningTextFieldCell: NSTextFieldCell {
    private let editor: HUDHeatWarningFieldEditor = {
        let editor = HUDHeatWarningFieldEditor(frame: .zero)
        editor.isFieldEditor = true
        editor.isRichText = false
        editor.allowsUndo = true
        return editor
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
}

@MainActor
private final class HUDHeatWarningFieldEditor: NSTextView {
    override func keyDown(with event: NSEvent) {
        if !handleShortcut(event) { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleShortcut(event) || super.performKeyEquivalent(with: event)
    }

    // The status menu has no Edit menu to supply the standard text shortcuts.
    // Keep these actions inside the active field editor so other menu shortcuts
    // and all ordinary text input retain native AppKit behavior.
    func handleShortcut(_ event: NSEvent) -> Bool {
        let characters = event.charactersIgnoringModifiers?.lowercased()
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        guard modifiers == .command || (characters == "z" && modifiers == [.command, .shift]) else { return false }
        switch characters {
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
