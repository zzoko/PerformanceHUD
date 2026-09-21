import AppKit

@MainActor
final class HUDBackgroundMenuView: NSView {
    var onBackgroundSelected: ((HUDBackground) -> Void)?
    private var selectedBackground: HUDBackground
    private var buttons: [HUDBackground: NSButton] = [:]

    init(selectedBackground: HUDBackground) {
        self.selectedBackground = selectedBackground
        super.init(frame: NSRect(x: 0, y: 0, width: 290, height: 28))

        let label = NSTextField(labelWithString: "Background")
        label.font = .menuFont(ofSize: 0)
        label.textColor = .labelColor
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(label)

        for (index, background) in HUDBackground.menuOptions.enumerated() {
            let button = NSButton(
                title: background.menuTitle,
                target: self,
                action: #selector(backgroundClicked(_:))
            )
            // Reserve enough width for any selected option's semibold title.
            button.font = .systemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .semibold)
            button.isBordered = false
            button.bezelStyle = .inline
            button.tag = index
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.setAccessibilityLabel("\(background.menuTitle) HUD background")
            buttons[background] = button
            stack.addArrangedSubview(button)
        }

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 30),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])
        setFrameSize(NSSize(width: max(290, ceil(stack.fittingSize.width + 42)), height: 28))
        updateSelection()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func backgroundClicked(_ sender: NSButton) {
        guard HUDBackground.menuOptions.indices.contains(sender.tag) else { return }
        selectedBackground = HUDBackground.menuOptions[sender.tag]
        updateSelection()
        onBackgroundSelected?(selectedBackground)
    }

    private func updateSelection() {
        for (background, button) in buttons {
            let selected = background == selectedBackground
            button.font = selected
                ? .systemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .semibold)
                : .menuFont(ofSize: 0)
            button.state = selected ? .on : .off
        }
    }
}
