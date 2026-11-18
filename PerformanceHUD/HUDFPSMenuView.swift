import AppKit

enum HUDFPSDisplayMode: String, CaseIterable, Codable {
    case value, history, both
    var title: String { rawValue.capitalized }
}

enum HUDFPSValueSize: Int, CaseIterable, Codable {
    case standard = 1, enlarged = 2
    var title: String { "\(rawValue)×" }
}

enum HUDFPSMeasure: String, CaseIterable, Codable {
    case frameRate, frameTime
    var menuTitle: String { self == .frameRate ? "Frame rate" : "Frame time" }
    var caption: String { self == .frameRate ? "FPS" : "FT" }
    var valueWidthReference: String { self == .frameRate ? "9999" : "999.9 ms" }

    func reading(fps: Double?, averageMS: Double?) -> String? {
        switch self {
        case .frameRate: return fps.map { String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), $0.rounded()) }
        case .frameTime: return averageMS.map { String(format: "%.1f ms", locale: Locale(identifier: "en_US_POSIX"), $0) }
        }
    }
}

struct HUDFPSOptions: Codable, Equatable {
    var enabled: Bool
    var mode: HUDFPSDisplayMode
    var valueHighlighted = true
    var valueSize: HUDFPSValueSize = .standard

    var measure: HUDFPSMeasure = .frameRate
    var hitchMarks = true

    init(enabled: Bool, mode: HUDFPSDisplayMode, valueHighlighted: Bool = true,
         valueSize: HUDFPSValueSize = .standard, measure: HUDFPSMeasure = .frameRate, hitchMarks: Bool = true) {
        self.measure = measure
        self.hitchMarks = hitchMarks
        self.enabled = enabled
        self.mode = mode
        self.valueHighlighted = valueHighlighted
        self.valueSize = valueSize
    }

    private enum CodingKeys: String, CodingKey { case enabled, mode, valueHighlighted, valueSize, measure, hitchMarks }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        measure = try values.decodeIfPresent(HUDFPSMeasure.self, forKey: .measure) ?? .frameRate
        hitchMarks = try values.decodeIfPresent(Bool.self, forKey: .hitchMarks) ?? true
        enabled = try values.decode(Bool.self, forKey: .enabled)
        mode = try values.decode(HUDFPSDisplayMode.self, forKey: .mode)
        valueHighlighted = try values.decodeIfPresent(Bool.self, forKey: .valueHighlighted) ?? true
        valueSize = try values.decodeIfPresent(HUDFPSValueSize.self, forKey: .valueSize) ?? .standard
    }

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
    private let valueSizeControl = NSSegmentedControl(labels: HUDFPSValueSize.allCases.map(\.title),
        trackingMode: .selectOne, target: nil, action: nil)

    private let valueHighlight = HUDEmphasisButton()
    private let readingLabel = NSTextField(labelWithString: "Display")
    private let sizeLabel = NSTextField(labelWithString: "Number size")
    private let measureLabel = NSTextField(labelWithString: "Measure")
    private let measureControl = NSSegmentedControl(labels: HUDFPSMeasure.allCases.map(\.menuTitle),
        trackingMode: .selectOne, target: nil, action: nil)
    private let hitchControl = HUDReadingCheckbox(title: "Hitch marks", supportsEmphasis: false)

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
        valueSizeControl.target = self
        valueSizeControl.action = #selector(valueSizeChanged)
        valueSizeControl.setAccessibilityLabel("FPS number size")
        valueHighlight.target = self
        valueHighlight.action = #selector(toggleValueHighlight)
        valueHighlight.setAccessibilityLabel("Emphasize FPS number")
        sizeLabel.font = .menuFont(ofSize: 0)
        measureLabel.font = .menuFont(ofSize: 0)
        measureControl.setAccessibilityLabel("FPS measure")
        measureControl.target = self
        measureControl.action = #selector(measureChanged)
        hitchControl.target = self
        hitchControl.action = #selector(hitchesChanged)
        setCategory(master)
        setRows([.init(reading: readingLabel, mode: control, emphasis: valueHighlight,
                      menuBar: makeMenuBarButton(for: .fps, title: "FPS")),
                 .init(reading: measureLabel, mode: measureControl),
                 .init(reading: sizeLabel, mode: valueSizeControl),
                 .init(reading: NSView(), mode: hitchControl)])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Use init(options:alignment:)") }

    func update(options: HUDFPSOptions, alignment: HUDAlignment) {
        self.options = options
        self.alignment = alignment
        refresh()
    }

    override func refreshMenuBarSelections() {
        super.refreshMenuBarSelections()
        refresh()
    }

    private func refresh() {
        master.state = options.enabled ? .on : .off
        let pinned = isMenuBarSelected(.fps)
        measureControl.selectedSegment = HUDFPSMeasure.allCases.firstIndex(of: options.measure)!
        measureControl.isEnabled = options.enabled || pinned
        measureLabel.textColor = measureControl.isEnabled ? .labelColor : .disabledControlTextColor
        hitchControl.state = options.hitchMarks ? .on : .off
        hitchControl.isEnabled = options.visibleMetrics(alignment: alignment).contains(.fpsGraph)
        readingLabel.textColor = options.enabled || pinned ? .labelColor : .disabledControlTextColor
        control.selectedSegment = alignment == .horizontal ? 0
            : HUDFPSDisplayMode.allCases.firstIndex(of: options.mode)!
        valueHighlight.state = options.valueHighlighted ? .on : .off
        valueHighlight.isEnabled = options.visibleMetrics(alignment: alignment).contains(.fps) || pinned
        valueHighlight.needsDisplay = true
        valueSizeControl.selectedSegment = HUDFPSValueSize.allCases.firstIndex(of: options.valueSize)!
        valueSizeControl.isEnabled = options.visibleMetrics(alignment: alignment).contains(.fps)
        sizeLabel.textColor = valueSizeControl.isEnabled ? .labelColor : .disabledControlTextColor
        control.isEnabled = options.enabled
        control.setEnabled(options.enabled, forSegment: 0)
        for index in [1, 2] { control.setEnabled(options.enabled && alignment == .vertical, forSegment: index) }
    }

    @objc private func measureChanged() {
        guard measureControl.isEnabled, HUDFPSMeasure.allCases.indices.contains(measureControl.selectedSegment) else { return }
        options.measure = HUDFPSMeasure.allCases[measureControl.selectedSegment]
        onChange?(options)
    }

    @objc private func hitchesChanged() {
        guard hitchControl.isEnabled else { return }
        options.hitchMarks = hitchControl.state == .on
        onChange?(options)
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

    @objc private func valueSizeChanged() {
        guard valueSizeControl.isEnabled,
              HUDFPSValueSize.allCases.indices.contains(valueSizeControl.selectedSegment) else { refresh(); return }
        options.valueSize = HUDFPSValueSize.allCases[valueSizeControl.selectedSegment]
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
