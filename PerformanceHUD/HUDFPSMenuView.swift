import AppKit

enum HUDFPSDisplayMode: String, CaseIterable {
    case value, history, both
    var title: String { rawValue.capitalized }
}

struct HUDFPSOptions {
    var enabled: Bool
    var mode: HUDFPSDisplayMode
    var valueHighlighted = true

    func visibleMetrics(alignment: HUDAlignment) -> Set<HUDMetric> {
        guard enabled else { return [] }
        // Horizontal has no graph; retain the selected vertical mode separately.
        guard alignment == .vertical else { return [.fps] }
        switch mode {
        case .value: return [.fps]
        case .history: return [.fpsGraph]
        case .both: return [.fps, .fpsGraph]
        }
    }
}

@MainActor
final class HUDFPSMenuView: NSView {
    var onChange: ((HUDFPSOptions) -> Void)?
    private var options: HUDFPSOptions
    private var alignment: HUDAlignment
    private let master = HUDResourceMasterButton(title: "FPS", target: nil, action: nil)
    private let control = NSSegmentedControl(labels: HUDFPSDisplayMode.allCases.map(\.title),
        trackingMode: .selectOne, target: nil, action: nil)

    private let valueHighlight = HUDHighlightLine()

    init(options: HUDFPSOptions, alignment: HUDAlignment) {
        self.options = options
        self.alignment = alignment
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 40))
        autoresizingMask = [.width]
        master.target = self
        master.action = #selector(toggleCategory)
        master.setAccessibilityLabel("Show FPS")
        control.font = .menuFont(ofSize: 0)
        control.segmentStyle = .rounded
        control.target = self
        control.action = #selector(modeChanged)
        control.setAccessibilityLabel("FPS display mode")
        valueHighlight.setButtonType(.toggle)
        valueHighlight.isBordered = false
        valueHighlight.target = self
        valueHighlight.action = #selector(toggleValueHighlight)
        valueHighlight.setAccessibilityRole(.checkBox)
        valueHighlight.setAccessibilityLabel("Emphasize FPS number")
        for view in [master, control, valueHighlight] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            master.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            master.widthAnchor.constraint(equalToConstant: HUDResourceMenuView.masterWidth),
            master.topAnchor.constraint(equalTo: topAnchor),
            master.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            valueHighlight.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 2),
            valueHighlight.widthAnchor.constraint(equalTo: control.widthAnchor, multiplier: 1.0 / 3.0, constant: -4),
            valueHighlight.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            valueHighlight.heightAnchor.constraint(equalToConstant: 6),
            control.leadingAnchor.constraint(equalTo: master.trailingAnchor, constant: 8),
            control.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -3),
            control.widthAnchor.constraint(equalToConstant: HUDResourceMenuView.readingsChoicesWidth),
            control.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])
        setFrameSize(NSSize(width: 8 + HUDResourceMenuView.masterWidth + 8
            + HUDResourceMenuView.readingsChoicesWidth + 12, height: 40))
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Use init(options:alignment:)") }

    func update(options: HUDFPSOptions, alignment: HUDAlignment) {
        self.options = options
        self.alignment = alignment
        refresh()
    }

    private func refresh() {
        master.state = options.enabled ? .on : .off
        control.selectedSegment = alignment == .horizontal ? 0
            : HUDFPSDisplayMode.allCases.firstIndex(of: options.mode)!
        valueHighlight.state = options.valueHighlighted ? .on : .off
        valueHighlight.isEnabled = options.visibleMetrics(alignment: alignment).contains(.fps)
        valueHighlight.needsDisplay = true
        control.isEnabled = options.enabled
        control.setEnabled(options.enabled, forSegment: 0)
        for index in [1, 2] { control.setEnabled(options.enabled && alignment == .vertical, forSegment: index) }
    }

    @objc private func toggleValueHighlight() {
        guard valueHighlight.isEnabled else { return }
        options.valueHighlighted = valueHighlight.state == .on
        refresh()
        onChange?(options)
    }

    @objc private func toggleCategory() {
        options.enabled = master.state == .on
        refresh()
        onChange?(options)
    }

    @objc private func modeChanged() {
        guard options.enabled, alignment == .vertical,
              HUDFPSDisplayMode.allCases.indices.contains(control.selectedSegment) else { refresh(); return }
        options.mode = HUDFPSDisplayMode.allCases[control.selectedSegment]
        refresh()
        onChange?(options)
    }
}
