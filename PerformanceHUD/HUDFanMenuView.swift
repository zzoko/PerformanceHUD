import AppKit

@MainActor
final class HUDFanMenuView: HUDCategoryMenuView {
    var onChange: ((HUDFanOptions) -> Void)?
    private var options: HUDFanOptions
    private var sample: FanSample
    private let master: HUDResourceMasterButton
    private let usage = HUDReadingCheckbox(title: "Use", supportsEmphasis: false)
    private let average = HUDReadingCheckbox(title: "Average", supportsEmphasis: false)
    private let averageMode = NSSegmentedControl(labels: HUDFanAverageMode.allCases.map(\.title),
                                                trackingMode: .selectOne, target: nil, action: nil)
    private let mode = NSSegmentedControl(labels: HUDFanMode.allCases.map(\.title),
                                         trackingMode: .selectOne, target: nil, action: nil)
    private let rpmHighlight = HUDEmphasisButton()
    private let unavailableLabel = NSTextField(labelWithString: "Not available")

    init(options: HUDFanOptions, sample: FanSample) {
        self.options = options
        self.sample = sample
        master = HUDResourceMasterButton(title: "FAN", target: nil, action: nil)
        super.init()
        setAccessibilityLabel("Fan display options")
        setCategory(master)
        unavailableLabel.font = .menuFont(ofSize: 0)
        unavailableLabel.textColor = .disabledControlTextColor
        master.target = self; master.action = #selector(toggleCategory)
        master.setAccessibilityLabel("Show FAN")
        usage.target = self; usage.action = #selector(toggleUsage)
        usage.font = .menuFont(ofSize: 0)
        usage.setControlAccessibilityLabel("Fan Use")
        mode.target = self; mode.action = #selector(changeFanMode)
        mode.segmentStyle = .rounded
        mode.font = .menuFont(ofSize: 0)
        mode.setAccessibilityLabel("Fan display mode")
        rpmHighlight.setButtonType(.toggle)
        rpmHighlight.isBordered = false
        rpmHighlight.target = self
        rpmHighlight.action = #selector(toggleRPMHighlight)
        rpmHighlight.setAccessibilityRole(.checkBox)
        rpmHighlight.setAccessibilityLabel("Emphasize fan RPM")
        average.target = self; average.action = #selector(toggleAverage)
        average.font = .menuFont(ofSize: 0)
        average.setControlAccessibilityLabel("Average")
        averageMode.target = self; averageMode.action = #selector(changeAverageMode)
        averageMode.segmentStyle = .rounded
        averageMode.font = .menuFont(ofSize: 0)
        averageMode.setAccessibilityLabel("Layouts using fan average")
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Use init(options:sample:)") }

    func update(sample: FanSample, options: HUDFanOptions? = nil) {
        if let options { self.options = options }
        self.sample = sample
        refresh()
    }

    private func refresh() {
        let detected = !sample.fans.isEmpty
        unavailableLabel.stringValue = sample.message ?? "Not available"
        setRows(detected ? [.init(reading: average, mode: averageMode),
                            .init(reading: usage, mode: mode, emphasis: rpmHighlight)]
                         : [.init(reading: unavailableLabel, fullWidth: true)])
        master.isEnabled = sample.status != .noFans
        master.state = options.enabled && master.isEnabled ? .on : .off
        usage.state = detected && options.usage ? .on : .off
        usage.isEnabled = options.enabled && detected
        let message = sample.message
        usage.toolTip = message
        usage.setAccessibilityHelp(message)
        mode.selectedSegment = HUDFanMode.allCases.firstIndex(of: options.mode) ?? 0
        mode.isEnabled = usage.isEnabled && options.usage
        rpmHighlight.state = options.rpmHighlighted ? .on : .off
        rpmHighlight.isEnabled = mode.isEnabled && options.mode.showsRPM
        rpmHighlight.needsDisplay = true
        average.state = sample.canAverage && options.average ? .on : .off
        average.isEnabled = options.enabled && sample.canAverage
        let averageMessage = message ?? (sample.fans.count == 1 ? "Average requires at least two fans." : nil)
        average.toolTip = averageMessage
        average.setAccessibilityHelp(averageMessage)
        averageMode.selectedSegment = HUDFanAverageMode.allCases.firstIndex(of: options.averageMode) ?? 1
        averageMode.isEnabled = average.isEnabled && options.average
    }

    @objc private func toggleCategory() {
        guard master.isEnabled else { return }
        options.enabled = master.state == .on
        changed()
    }
    @objc private func toggleUsage() { options.usage = usage.state == .on; changed() }
    @objc private func changeFanMode() {
        guard HUDFanMode.allCases.indices.contains(mode.selectedSegment) else { return }
        options.mode = HUDFanMode.allCases[mode.selectedSegment]; changed()
    }
    @objc private func toggleRPMHighlight() {
        guard rpmHighlight.isEnabled else { return }
        options.rpmHighlighted = rpmHighlight.state == .on
        changed()
    }
    @objc private func toggleAverage() { options.average = average.state == .on; changed() }
    @objc private func changeAverageMode() {
        guard HUDFanAverageMode.allCases.indices.contains(averageMode.selectedSegment) else { return }
        options.averageMode = HUDFanAverageMode.allCases[averageMode.selectedSegment]; changed()
    }
    private func changed() { refresh(); onChange?(options) }
}
