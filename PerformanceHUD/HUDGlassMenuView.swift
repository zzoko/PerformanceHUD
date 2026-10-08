import AppKit

@MainActor
final class HUDGlassMenuView: NSView {
    var onChange: ((HUDGlassOptions) -> Void)?
    private var options: HUDGlassOptions
    private var systemStrength: Double
    private let control = NSSegmentedControl(labels: ["Strength", "Follow macOS"],
        trackingMode: .selectOne, target: nil, action: nil)
    private let slider = HUDFillSlider()
    private let clearLabel = NSTextField(labelWithString: "Clear")
    private let frostedLabel = NSTextField(labelWithString: "Frosted")
    private let valueLabel = NSTextField(labelWithString: "")

    init(options: HUDGlassOptions, systemStrength: Double) {
        self.options = options
        self.systemStrength = systemStrength
        let width = HUDMenuLayout.labelLeading + HUDMenuLayout.labelWidth + HUDMenuLayout.spacing
            + HUDMenuLayout.backgroundOptionsWidth + HUDMenuLayout.sliderValueSpacing + 44 + 12
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 62))
        autoresizingMask = [.width]
        let label = NSTextField(labelWithString: "Liquid Glass")
        label.font = .menuFont(ofSize: 0)
        control.segmentStyle = .rounded
        control.font = .menuFont(ofSize: 0)
        control.target = self
        control.action = #selector(modeChanged)
        control.setAccessibilityLabel("Liquid Glass mode")
        slider.controlSize = .small
        slider.minValue = 0
        slider.maxValue = 100
        slider.valueStep = 1
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(strengthChanged)
        slider.setAccessibilityLabel("Liquid Glass, Clear to Frosted")
        for endpoint in [clearLabel, frostedLabel] {
            endpoint.font = .menuFont(ofSize: 0)
            endpoint.setContentHuggingPriority(.required, for: .horizontal)
            endpoint.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .regular)
        valueLabel.alignment = .center
        for view in [label, control, clearLabel, slider, frostedLabel, valueLabel] {
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
            clearLabel.trailingAnchor.constraint(equalTo: slider.leadingAnchor, constant: -HUDMenuLayout.spacing),
            clearLabel.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: control.leadingAnchor),
            slider.widthAnchor.constraint(equalTo: control.widthAnchor),
            slider.topAnchor.constraint(equalTo: control.bottomAnchor, constant: 6),
            slider.heightAnchor.constraint(equalToConstant: 24),
            valueLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: HUDMenuLayout.sliderValueSpacing),
            valueLabel.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 44),
            frostedLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: HUDMenuLayout.spacing),
            frostedLabel.centerYAnchor.constraint(equalTo: slider.centerYAnchor)
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Use init(options:systemStrength:)") }

    func update(options: HUDGlassOptions, systemStrength: Double) {
        self.options = options
        self.systemStrength = systemStrength
        refresh()
    }

    @objc private func modeChanged() {
        guard (0...1).contains(control.selectedSegment) else { refresh(); return }
        options.select(control.selectedSegment == 0 ? .strength : .system, system: systemStrength)
        refresh()
        onChange?(options)
    }

    @objc private func strengthChanged() {
        guard options.mode == .strength else { refresh(); return }
        options.strength = HUDGlassOptions.clamped(slider.doubleValue.rounded() / 100)
        refresh()
        onChange?(options)
    }

    private func refresh() {
        control.selectedSegment = options.mode == .strength ? 0 : 1
        slider.isEnabled = options.mode == .strength
        let strength = options.resolvedStrength(system: systemStrength) * 100
        slider.doubleValue = strength
        let percentage = "\(Int(strength.rounded()))%"
        valueLabel.stringValue = percentage
        slider.setAccessibilityValueDescription("\(percentage) strength")
        slider.needsDisplay = true
        for label in [clearLabel, frostedLabel, valueLabel] {
            label.textColor = slider.isEnabled ? .labelColor : .disabledControlTextColor
        }
    }
}
