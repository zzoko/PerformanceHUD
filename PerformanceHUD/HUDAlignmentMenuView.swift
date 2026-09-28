import AppKit

@MainActor
final class HUDAlignmentMenuView: NSView {
    var onAlignmentSelected: ((HUDAlignment) -> Void)?
    private let control: NSSegmentedControl

    init(selected: HUDAlignment) {
        control = NSSegmentedControl(labels: ["Vertical", "Horizontal"], trackingMode: .selectOne, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 290, height: 28))
        autoresizingMask = [.width]
        let label = NSTextField(labelWithString: "Alignment")
        label.font = .menuFont(ofSize: 0)
        control.segmentStyle = .rounded
        control.font = .menuFont(ofSize: 0)
        control.selectedSegment = selected == .vertical ? 0 : 1
        control.target = self
        control.action = #selector(changed)
        control.setAccessibilityLabel("HUD alignment")
        let help = "Vertical stacks the categories; Horizontal places them in one row. FPS History and Device Info are hidden in Horizontal and restored when you return to Vertical."
        control.toolTip = help
        control.setAccessibilityHelp(help)
        for segment in 0..<2 { control.setToolTip(help, forSegment: segment) }
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

    required init?(coder: NSCoder) { fatalError("Use init(selected:)") }
    @objc private func changed() { onAlignmentSelected?(control.selectedSegment == 0 ? .vertical : .horizontal) }
}
