import AppKit

@MainActor
final class HUDPositionMenuView: NSView {
    var onReset: (() -> Void)?
    var onResetOptions: (() -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 290, height: 28))
        // Let NSMenu expand this row to its full width.
        autoresizingMask = [.width]
        let label = NSTextField(labelWithString: "Reset")
        label.font = .menuFont(ofSize: 0)
        let button = NSButton(title: "Position", target: self, action: #selector(resetClicked(_:)))
        button.bezelStyle = .rounded
        button.font = .menuFont(ofSize: 0)
        button.setAccessibilityLabel("Reset HUD position")
        let options = NSButton(title: "Options", target: self, action: #selector(optionsClicked(_:)))
        options.bezelStyle = .rounded
        options.font = .menuFont(ofSize: 0)
        options.setAccessibilityLabel("Reset HUD options")
        let actions = NSStackView(views: [button, options])
        actions.orientation = .horizontal
        actions.spacing = 6
        actions.distribution = .fillEqually
        actions.widthAnchor.constraint(equalToConstant: HUDMenuLayout.backgroundOptionsWidth).isActive = true
        let stack = NSStackView(views: [label, actions])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let hint = NSTextField(labelWithString: "⌃⌥⌘ + drag")
        hint.font = .menuFont(ofSize: 0)
        hint.textColor = .secondaryLabelColor
        hint.setAccessibilityLabel("Hold Control, Option, and Command and drag the HUD to move it. Release all three keys after dragging to prevent automatic snapping to the grid.")
        hint.setContentCompressionResistancePriority(.required, for: .horizontal)
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        addSubview(hint)
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: HUDMenuLayout.labelWidth),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 30),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: hint.leadingAnchor, constant: -16),
            hint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            hint.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func optionsClicked(_ sender: NSButton) { onResetOptions?() }

    @objc private func resetClicked(_ sender: NSButton) {
        onReset?()
    }
}
