import AppKit

@MainActor
final class HUDPackagePowerMenuView: NSView {
    var onChange: ((HUDPackagePowerOptions) -> Void)?
    var onPowerSetup: (() -> Void)?
    private var helperAvailability: PowerHelperAvailability = .idle
    private var options: HUDPackagePowerOptions
    private let checkbox = HUDReadingCheckbox(title: "SoC combined")

    init(options: HUDPackagePowerOptions) {
        self.options = options
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 34))
        let choices = HUDResourceChoicesView()
        choices.translatesAutoresizingMaskIntoConstraints = false
        addSubview(choices)
        checkbox.font = .menuFont(ofSize: 0)
        checkbox.target = self
        checkbox.action = #selector(changed)
        checkbox.setControlAccessibilityLabel("SoC combined")
        checkbox.onHighlight = { [weak self] in self?.highlightChanged() }
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkbox)
        NSLayoutConstraint.activate([
            choices.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HUDResourceMenuView.powerColumnLeading - 8),
            choices.centerYAnchor.constraint(equalTo: centerYAnchor),
            choices.widthAnchor.constraint(equalToConstant: HUDResourceMenuView.readingsChoicesWidth),
            choices.heightAnchor.constraint(equalToConstant: 28),
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HUDResourceMenuView.powerColumnLeading),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkbox.widthAnchor.constraint(equalToConstant: 145)
        ])
        setState(options: options, helper: .idle)
    }

    required init?(coder: NSCoder) { fatalError("Use init(options:)") }

    func setState(options: HUDPackagePowerOptions, helper: PowerHelperAvailability) {
        self.options = options
        helperAvailability = helper
        checkbox.toolTip = helper.explanation
        checkbox.setAccessibilityHelp(checkbox.toolTip)
        refresh()
    }

    private func refresh() {
        checkbox.isEnabled = true
        checkbox.alphaValue = helperAvailability.usesNormalAppearance ? 1 : 0.5
        checkbox.state = options.enabled ? .on : .off
        checkbox.emphasized = options.highlighted
        checkbox.highlightAvailable = helperAvailability.allowsPowerToggle
        checkbox.setAccessibilityValue(!options.enabled ? "Off" : options.highlighted ? "Highlighted" : "Faint")
    }

    @objc private func changed() {
        guard helperAvailability.allowsPowerToggle else { refresh(); onPowerSetup?(); return }
        options.enabled = checkbox.state == .on
        refresh()
        onChange?(options)
    }
    private func highlightChanged() {
        guard options.enabled, helperAvailability.allowsPowerToggle else { return }
        options.highlighted.toggle()
        refresh()
        onChange?(options)
    }
}

/// A single menu view keeps the connector continuous between its four rows.
@MainActor
final class HUDPowerGroupMenuView: NSView {
    private let rows: [NSView]

    init(rows: [HUDResourceMenuView], package: HUDPackagePowerMenuView) {
        self.rows = rows + [package]
        super.init(frame: NSRect(x: 0, y: 0, width: rows.map { $0.frame.width }.max() ?? 480,
                                height: CGFloat(self.rows.count) * 34))
        autoresizingMask = [.width]
        for row in self.rows { addSubview(row) }
        layoutRows()
    }

    required init?(coder: NSCoder) { fatalError("Use init(rows:package:)") }

    private func layoutRows() {
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: 0, y: bounds.height - CGFloat(index + 1) * 34, width: bounds.width, height: 34)
        }
    }

    override func layout() {
        super.layout()
        layoutRows()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let first = rows.first, let last = rows.last else { return }
        let x = HUDResourceMenuView.powerColumnLeading - 12
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: first.frame.midY))
        path.line(to: NSPoint(x: x, y: last.frame.midY))
        for row in rows {
            path.move(to: NSPoint(x: x, y: row.frame.midY))
            path.line(to: NSPoint(x: HUDResourceMenuView.powerColumnLeading - 4, y: row.frame.midY))
        }
        NSColor.secondaryLabelColor.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 1
        path.lineCapStyle = .round
        path.stroke()
    }
}
