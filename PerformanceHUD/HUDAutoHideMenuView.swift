import AppKit

@MainActor
final class HUDAutoHideMenuView: NSView {
    var onChange: ((HUDAutoHideMode) -> Void)?
    private var selected: HUDAutoHideMode
    private let control = NSSegmentedControl(labels: ["FPS", "Off"],
        trackingMode: .selectOne, target: nil, action: nil)
    private let allControl = NSSegmentedControl(labels: ["All options"],
        trackingMode: .selectOne, target: nil, action: nil)

    init(selected: HUDAutoHideMode) {
        self.selected = selected
        super.init(frame: NSRect(x: 0, y: 0, width: 290, height: 56))
        autoresizingMask = [.width]
        let label = NSTextField(labelWithString: "Auto hide")
        label.font = .menuFont(ofSize: 0)
        for selector in [control, allControl] {
            selector.segmentStyle = .rounded
            selector.font = .menuFont(ofSize: 0)
            selector.target = self
        }
        control.action = #selector(changed)
        control.setAccessibilityLabel("Auto hide mode")
        allControl.action = #selector(allSelected)
        allControl.setAccessibilityLabel("Automatically hide all HUD options")
        for view in [label, control, allControl] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HUDMenuLayout.labelLeading),
            label.widthAnchor.constraint(equalToConstant: HUDMenuLayout.labelWidth),
            label.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            control.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: HUDMenuLayout.spacing),
            control.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            control.widthAnchor.constraint(equalToConstant: HUDMenuLayout.backgroundOptionsWidth),
            allControl.leadingAnchor.constraint(equalTo: control.leadingAnchor),
            allControl.widthAnchor.constraint(equalTo: control.widthAnchor),
            allControl.topAnchor.constraint(equalTo: control.bottomAnchor, constant: 4)
        ])
        select(selected)
    }

    required init?(coder: NSCoder) { fatalError("Use init(selected:)") }

    func select(_ mode: HUDAutoHideMode) {
        selected = mode
        control.selectedSegment = mode == .fps ? 0 : mode == .off ? 1 : -1
        allControl.selectedSegment = mode == .all ? 0 : -1
    }

    @objc private func changed() {
        guard [0, 1].contains(control.selectedSegment) else { select(selected); return }
        request(control.selectedSegment == 0 ? .fps : .off)
    }

    @objc private func allSelected() { request(.all) }

    private func request(_ mode: HUDAutoHideMode) {
        // Selection commits only after the delegate accepts it. Cancelling the
        // All options explanation leaves the previous choice visibly selected.
        select(selected)
        guard mode != selected else { return }
        onChange?(mode)
    }
}
