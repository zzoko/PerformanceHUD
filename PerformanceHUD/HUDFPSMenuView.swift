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
final class HUDFPSMenuView: HUDCategoryMenuView {
    var onChange: ((HUDFPSOptions) -> Void)?
    private var options: HUDFPSOptions
    private var alignment: HUDAlignment
    private let master = HUDResourceMasterButton(title: "FPS", target: nil, action: nil)
    private let control = NSSegmentedControl(labels: HUDFPSDisplayMode.allCases.map(\.title),
        trackingMode: .selectOne, target: nil, action: nil)

    private let valueHighlight = HUDEmphasisButton()
    private let readingLabel = NSTextField(labelWithString: "Frame rate")

    init(options: HUDFPSOptions, alignment: HUDAlignment) {
        self.options = options
        self.alignment = alignment
        super.init()
        setAccessibilityLabel("FPS display options")
        master.target = self
        master.action = #selector(toggleCategory)
        master.setAccessibilityLabel("Show FPS")
        readingLabel.font = .menuFont(ofSize: 0)
        control.font = .menuFont(ofSize: 0)
        control.segmentStyle = .rounded
        control.target = self
        control.action = #selector(modeChanged)
        control.setAccessibilityLabel("FPS display mode")
        valueHighlight.target = self
        valueHighlight.action = #selector(toggleValueHighlight)
        valueHighlight.setAccessibilityLabel("Emphasize FPS number")
        setCategory(master)
        setRows([.init(reading: readingLabel, mode: control, emphasis: valueHighlight)])
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
        readingLabel.textColor = options.enabled ? .labelColor : .disabledControlTextColor
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
