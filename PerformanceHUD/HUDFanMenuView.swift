import AppKit

@MainActor
final class HUDFanMenuView: NSView {
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
    private let rpmHighlight = HUDHighlightLine()

    init(options: HUDFanOptions, sample: FanSample) {
        self.options = options
        self.sample = sample
        master = HUDResourceMasterButton(title: "FAN", target: nil, action: nil)
        let width = 8 + HUDResourceMenuView.masterWidth + 8 + HUDResourceMenuView.choicesWidth + 12
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 40))
        autoresizingMask = [.width]
        let bar = HUDResourceChoicesView()
        let averageBar = HUDResourceChoicesView()
        for view in [master, bar, averageBar, average, averageMode, usage, mode, rpmHighlight] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
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
        rpmHighlight.setAccessibilityLabel("Highlight fan RPM in RPM and Both modes")
        average.target = self; average.action = #selector(toggleAverage)
        average.font = .menuFont(ofSize: 0)
        average.setControlAccessibilityLabel("Average")
        averageMode.target = self; averageMode.action = #selector(changeAverageMode)
        averageMode.segmentStyle = .rounded
        averageMode.font = .menuFont(ofSize: 0)
        averageMode.setAccessibilityLabel("Layouts using fan average")
        let firstWidth = HUDResourceMenuView.firstChoiceWidth
        let secondWidth = HUDResourceMenuView.secondChoiceWidth
        let usageLeading = HUDResourceMenuView.powerColumnLeading + firstWidth + 12 + secondWidth + 12
        NSLayoutConstraint.activate([
            master.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            master.widthAnchor.constraint(equalToConstant: HUDResourceMenuView.masterWidth),
            master.topAnchor.constraint(equalTo: topAnchor),
            master.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            average.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HUDResourceMenuView.powerColumnLeading),
            average.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -3),
            average.widthAnchor.constraint(equalToConstant: firstWidth),
            averageMode.leadingAnchor.constraint(equalTo: average.trailingAnchor, constant: 12),
            averageMode.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -3),
            averageMode.widthAnchor.constraint(equalToConstant: secondWidth),
            averageBar.leadingAnchor.constraint(equalTo: average.leadingAnchor, constant: -8),
            averageBar.trailingAnchor.constraint(equalTo: averageMode.trailingAnchor, constant: 4),
            averageBar.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -3),
            averageBar.heightAnchor.constraint(equalToConstant: 28),
            usage.leadingAnchor.constraint(equalTo: leadingAnchor, constant: usageLeading),
            usage.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -3),
            usage.widthAnchor.constraint(equalToConstant: 106),
            mode.leadingAnchor.constraint(equalTo: usage.trailingAnchor, constant: 12),
            mode.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -3),
            mode.widthAnchor.constraint(equalToConstant: 145),
            rpmHighlight.leadingAnchor.constraint(equalTo: mode.leadingAnchor, constant: 145 / 3 + 2),
            rpmHighlight.widthAnchor.constraint(equalTo: mode.widthAnchor, multiplier: 1.0 / 3.0, constant: -4),
            rpmHighlight.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 2),
            rpmHighlight.heightAnchor.constraint(equalToConstant: 6),
            bar.leadingAnchor.constraint(equalTo: usage.leadingAnchor, constant: -4),
            bar.trailingAnchor.constraint(equalTo: mode.trailingAnchor, constant: 8),
            bar.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -3),
            bar.heightAnchor.constraint(equalToConstant: 28)
        ])
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
        master.state = options.enabled ? .on : .off
        master.isEnabled = true
        usage.state = detected && options.usage ? .on : .off
        usage.isEnabled = options.enabled && detected
        let message = sample.message
        usage.toolTip = message
        usage.setAccessibilityHelp(message)
        mode.selectedSegment = HUDFanMode.allCases.firstIndex(of: options.mode) ?? 2
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

    @objc private func toggleCategory() { options.enabled = master.state == .on; changed() }
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
