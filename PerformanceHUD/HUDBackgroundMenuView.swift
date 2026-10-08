import AppKit

@MainActor
final class HUDBackgroundMenuView: NSView {
    var onBackgroundSelected: ((HUDBackground) -> Void)?
    private let control: NSSegmentedControl
    private let shortcutLabel = NSTextField(labelWithString: "")
    private static let choices: [HUDBackground] = [.light, .dark, .system]

    init(selectedBackground: HUDBackground) {
        control = NSSegmentedControl(labels: Self.choices.map(\.menuTitle),
                                     trackingMode: .selectOne, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: HUDMenuLayout.labelLeading + HUDMenuLayout.labelWidth
            + HUDMenuLayout.spacing + HUDMenuLayout.backgroundOptionsWidth + 72, height: 28))
        autoresizingMask = [.width]
        let label = NSTextField(labelWithString: "Appearance")
        label.font = .menuFont(ofSize: 0)
        shortcutLabel.font = .menuFont(ofSize: 0)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.alignment = .right
        shortcutLabel.setAccessibilityLabel("Cycle appearance shortcut")
        control.segmentStyle = .rounded
        control.font = .menuFont(ofSize: 0)
        control.target = self
        control.action = #selector(changed)
        control.setAccessibilityLabel("HUD appearance")
        for view in [label, control, shortcutLabel] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HUDMenuLayout.labelLeading),
            label.widthAnchor.constraint(equalToConstant: HUDMenuLayout.labelWidth),
            label.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            control.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: HUDMenuLayout.spacing),
            control.centerYAnchor.constraint(equalTo: centerYAnchor),
            control.widthAnchor.constraint(equalToConstant: HUDMenuLayout.backgroundOptionsWidth),
            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            shortcutLabel.leadingAnchor.constraint(greaterThanOrEqualTo: control.trailingAnchor, constant: 12),
            shortcutLabel.centerYAnchor.constraint(equalTo: control.centerYAnchor)
        ])
        select(selectedBackground)
    }

    required init?(coder: NSCoder) { fatalError("Use init(selectedBackground:)") }

    @objc private func changed() {
        guard Self.choices.indices.contains(control.selectedSegment) else { return }
        let background = Self.choices[control.selectedSegment]
        select(background)
        onBackgroundSelected?(background)
    }

    func select(_ background: HUDBackground) {
        control.selectedSegment = Self.choices.firstIndex(of: background) ?? 2
    }

    func setShortcut(_ shortcut: HUDShortcut?) {
        shortcutLabel.stringValue = shortcut?.displayName ?? ""
        shortcutLabel.isHidden = shortcut == nil
    }
}
