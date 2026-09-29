import AppKit

@MainActor
final class HUDBackgroundMenuView: NSView {
    var onBackgroundSelected: ((HUDBackground) -> Void)?
    private let control: NSSegmentedControl

    init(selectedBackground: HUDBackground) {
        control = NSSegmentedControl(labels: HUDBackground.menuOptions.map(\.menuTitle),
                                     trackingMode: .selectOne, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 290, height: 28))
        autoresizingMask = [.width]
        let label = NSTextField(labelWithString: "Appearance")
        label.font = .menuFont(ofSize: 0)
        control.segmentStyle = .rounded
        control.font = .menuFont(ofSize: 0)
        control.selectedSegment = HUDBackground.menuOptions.firstIndex(of: selectedBackground) ?? -1
        control.target = self
        control.action = #selector(changed)
        control.setAccessibilityLabel("HUD background")
        let help = "Choose Clear, Light or Dark glass. All three use screen recording permission to draw the background behind the HUD."
        control.toolTip = help
        control.setAccessibilityHelp(help)
        for segment in HUDBackground.menuOptions.indices { control.setToolTip(help, forSegment: segment) }
        for view in [label, control] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HUDMenuLayout.labelLeading),
            label.widthAnchor.constraint(equalToConstant: HUDMenuLayout.labelWidth),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            control.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: HUDMenuLayout.spacing),
            control.centerYAnchor.constraint(equalTo: centerYAnchor),
            control.widthAnchor.constraint(equalToConstant: HUDMenuLayout.backgroundOptionsWidth)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(selectedBackground:)") }

    @objc private func changed() {
        guard HUDBackground.menuOptions.indices.contains(control.selectedSegment) else { return }
        onBackgroundSelected?(HUDBackground.menuOptions[control.selectedSegment])
    }
}
