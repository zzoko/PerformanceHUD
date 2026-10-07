import AppKit

@MainActor
final class HUDAutoHideMenuView: NSView {
    var onChange: ((HUDAutoHideMode) -> Void)?
    var onAnimatedChange: ((Bool) -> Void)?
    private var selected: HUDAutoHideMode
    private let control = NSSegmentedControl(labels: ["Off", "FPS", "All"],
        trackingMode: .selectOne, target: nil, action: nil)
    private static let modes: [HUDAutoHideMode] = [.off, .fps, .all]

    private let animatedControl = HUDReadingCheckbox(title: "Animation", supportsEmphasis: false)

    init(selected: HUDAutoHideMode, animated: Bool = true) {
        self.selected = selected
        super.init(frame: NSRect(x: 0, y: 0, width: 290, height: 32))
        autoresizingMask = [.width]
        let label = NSTextField(labelWithString: "Auto hide")
        label.font = .menuFont(ofSize: 0)
        control.segmentStyle = .rounded
        control.font = .menuFont(ofSize: 0)
        control.target = self
        control.action = #selector(changed)
        control.setAccessibilityLabel("Auto hide mode")
        animatedControl.font = .menuFont(ofSize: 0)
        animatedControl.state = animated ? .on : .off
        animatedControl.target = self
        animatedControl.action = #selector(animatedChanged)
        animatedControl.setControlAccessibilityLabel("Animate automatic hiding and showing")
        for view in [label, control, animatedControl] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HUDMenuLayout.labelLeading),
            label.widthAnchor.constraint(equalToConstant: HUDMenuLayout.labelWidth),
            label.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            control.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: HUDMenuLayout.spacing),
            control.centerYAnchor.constraint(equalTo: centerYAnchor),
            control.widthAnchor.constraint(equalToConstant: HUDMenuLayout.actionOptionsWidth),
            animatedControl.leadingAnchor.constraint(equalTo: control.trailingAnchor, constant: 10),
            animatedControl.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            animatedControl.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])
        setFrameSize(NSSize(width: HUDMenuLayout.labelLeading + HUDMenuLayout.labelWidth
            + HUDMenuLayout.spacing + HUDMenuLayout.actionOptionsWidth + 10
            + ceil(animatedControl.intrinsicContentSize.width) + 12, height: 32))
        select(selected)
    }

    required init?(coder: NSCoder) { fatalError("Use init(selected:)") }

    func select(_ mode: HUDAutoHideMode) {
        selected = mode
        control.selectedSegment = Self.modes.firstIndex(of: mode) ?? 1
    }

    @objc private func animatedChanged() {
        onAnimatedChange?(animatedControl.state == .on)
    }

    @objc private func changed() {
        guard Self.modes.indices.contains(control.selectedSegment) else { select(selected); return }
        request(Self.modes[control.selectedSegment])
    }

    private func request(_ mode: HUDAutoHideMode) {
        // Selection commits only after the delegate accepts it. Cancelling the
        // All explanation leaves the previous choice visibly selected.
        select(selected)
        guard mode != selected else { return }
        onChange?(mode)
    }
}
