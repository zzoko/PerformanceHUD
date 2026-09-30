import AppKit

@MainActor
final class HUDBackgroundMenuView: NSView {
    var onBackgroundSelected: ((HUDBackground) -> Void)?
    private let control: NSSegmentedControl
    private let systemControl = NSSegmentedControl(labels: ["Follow system"], trackingMode: .selectOne, target: nil, action: nil)

    init(selectedBackground: HUDBackground) {
        control = NSSegmentedControl(labels: HUDBackground.menuOptions.map(\.menuTitle),
                                     trackingMode: .selectOne, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 290, height: 56))
        autoresizingMask = [.width]
        let label = NSTextField(labelWithString: "Appearance")
        label.font = .menuFont(ofSize: 0)
        control.segmentStyle = .rounded
        control.font = .menuFont(ofSize: 0)
        control.target = self
        control.action = #selector(changed)
        control.setAccessibilityLabel("HUD background")
        systemControl.segmentStyle = .rounded
        systemControl.font = .menuFont(ofSize: 0)
        systemControl.target = self
        systemControl.action = #selector(followSystem)
        systemControl.setAccessibilityLabel("Follow system appearance")
        for view in [label, control, systemControl] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HUDMenuLayout.labelLeading),
            label.widthAnchor.constraint(equalToConstant: HUDMenuLayout.labelWidth),
            label.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            control.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: HUDMenuLayout.spacing),
            control.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            control.widthAnchor.constraint(equalToConstant: HUDMenuLayout.backgroundOptionsWidth),
            systemControl.leadingAnchor.constraint(equalTo: control.leadingAnchor),
            systemControl.widthAnchor.constraint(equalTo: control.widthAnchor),
            systemControl.topAnchor.constraint(equalTo: control.bottomAnchor, constant: 4)
        ])
        select(selectedBackground)
    }

    required init?(coder: NSCoder) { fatalError("Use init(selectedBackground:)") }

    @objc private func changed() {
        guard HUDBackground.menuOptions.indices.contains(control.selectedSegment) else { return }
        let background = HUDBackground.menuOptions[control.selectedSegment]
        select(background)
        onBackgroundSelected?(background)
    }

    @objc private func followSystem() {
        select(.system)
        onBackgroundSelected?(.system)
    }

    private func select(_ background: HUDBackground) {
        control.selectedSegment = HUDBackground.menuOptions.firstIndex(of: background) ?? -1
        systemControl.selectedSegment = background == .system ? 0 : -1
    }
}
