import AppKit

@MainActor
final class HUDPositionMenuView: NSView {
    var onReset: (() -> Void)?
    var onResetSize: (() -> Void)?
    var onResetOptions: (() -> Void)?
    private let hint = NSTextField(labelWithString: "")

    init(dragModifier: HUDDragModifier = .option) {
        super.init(frame: NSRect(x: 0, y: 0, width: 290, height: 32))
        // Let NSMenu expand this row to its full width.
        autoresizingMask = [.width]
        let label = NSTextField(labelWithString: "Reset")
        label.font = .menuFont(ofSize: 0)
        let button = NSButton(title: "Position", target: self, action: #selector(resetClicked(_:)))
        button.bezelStyle = .rounded
        button.font = .menuFont(ofSize: 0)
        button.setAccessibilityLabel("Reset HUD position")
        let size = NSButton(title: "Size", target: self, action: #selector(sizeClicked(_:)))
        size.bezelStyle = .rounded
        size.font = .menuFont(ofSize: 0)
        size.setAccessibilityLabel("Reset HUD size to 1×")
        let options = NSButton(title: "All", target: self, action: #selector(optionsClicked(_:)))
        options.bezelStyle = .rounded
        options.font = .menuFont(ofSize: 0)
        options.setAccessibilityLabel("Reset all HUD options, including size and position")
        let actions = NSStackView(views: [button, size, options])
        actions.orientation = .horizontal
        actions.spacing = 6
        actions.distribution = .fillEqually
        actions.widthAnchor.constraint(equalToConstant: HUDMenuLayout.actionOptionsWidth).isActive = true
        let stack = NSStackView(views: [label, actions])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        hint.font = .menuFont(ofSize: 0)
        // Match the faint native keyboard equivalent beside Enable/Disable.
        hint.textColor = .tertiaryLabelColor
        setDragModifier(dragModifier)
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
            hint.centerYAnchor.constraint(equalTo: actions.centerYAnchor)
        ])
        setFrameSize(NSSize(width: HUDMenuLayout.labelLeading + HUDMenuLayout.labelWidth
            + HUDMenuLayout.spacing + HUDMenuLayout.actionOptionsWidth + 16
            + ceil(hint.intrinsicContentSize.width) + 18, height: 32))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setDragModifier(_ modifier: HUDDragModifier) {
        hint.stringValue = "\(modifier.symbol) + drag"
        hint.setAccessibilityLabel("Hold \(modifier.name) and drag the HUD with the left mouse button to move it. Release \(modifier.name) after dragging to prevent automatic snapping to the grid.")
    }

    @objc private func sizeClicked(_ sender: NSButton) { onResetSize?() }

    @objc private func optionsClicked(_ sender: NSButton) { onResetOptions?() }

    @objc private func resetClicked(_ sender: NSButton) {
        onReset?()
    }
}
