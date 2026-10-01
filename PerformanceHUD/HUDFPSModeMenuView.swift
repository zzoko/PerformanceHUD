import AppKit

/// One presentation setting shared by the two independently selected FPS rows.
@MainActor
final class HUDFPSModeMenuView: NSView {
    var onChange: ((Bool) -> Void)?
    private let control = NSSegmentedControl(labels: ["Static", "Dynamic"],
        trackingMode: .selectOne, target: nil, action: nil)
    private let label = NSTextField(labelWithString: "FPS + History")

    init(dynamic: Bool, alignment: HUDAlignment) {
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 30))
        autoresizingMask = [.width]
        label.font = .menuFont(ofSize: 0)
        control.font = .menuFont(ofSize: 0)
        control.segmentStyle = .rounded
        control.target = self
        control.action = #selector(changed)
        control.setAccessibilityLabel("FPS and FPS History presentation")
        for view in [label, control] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HUDMenuLayout.labelLeading),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            control.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 14),
            control.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        update(dynamic: dynamic, alignment: alignment)
    }
    required init?(coder: NSCoder) { fatalError("Use init(dynamic:alignment:)") }
    func update(dynamic: Bool, alignment: HUDAlignment) {
        control.isEnabled = alignment == .vertical
        control.selectedSegment = control.isEnabled && dynamic ? 1 : 0
        label.textColor = control.isEnabled ? .labelColor : .disabledControlTextColor
        toolTip = control.isEnabled
            ? "Static keeps the selected FPS rows visible. Dynamic rolls them away after readings become unavailable, and expands them when readings return. Applies to FPS and FPS History together."
            : "Dynamic FPS is available only in Vertical alignment. Your Vertical choice is remembered."
    }
    @objc private func changed() {
        guard control.isEnabled else { return }
        onChange?(control.selectedSegment == 1)
    }
}
