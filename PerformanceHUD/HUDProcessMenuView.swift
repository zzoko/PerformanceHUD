import AppKit

@MainActor
final class HUDProcessMenuView: HUDCategoryMenuView {
    var onChange: ((HUDProcessOptions) -> Void)?
    private var options: HUDProcessOptions
    private var alignment: HUDAlignment
    private let master = HUDResourceMasterButton(title: "Process", target: nil, action: nil)
    private var controls: [HUDProcessReading: HUDReadingCheckbox] = [:]

    init(options: HUDProcessOptions, alignment: HUDAlignment) {
        self.options = options; self.alignment = alignment
        super.init()
        setAccessibilityLabel("Process display options")
        master.target = self; master.action = #selector(toggleCategory)
        master.setAccessibilityLabel("Show selected process")
        setCategory(master)
        setRows(HUDProcessReading.allCases.enumerated().map { index, reading in
            let button = HUDReadingCheckbox(title: reading.title, supportsEmphasis: true)
            button.tag = index; button.target = self; button.action = #selector(toggleReading(_:))
            button.setControlAccessibilityLabel("Process \(reading.title)")
            button.onHighlight = { [weak self] in
                guard let self else { return }
                if self.options.highlighted.contains(reading) { self.options.highlighted.remove(reading) }
                else { self.options.highlighted.insert(reading) }
                self.refresh(); self.onChange?(self.options)
            }
            controls[reading] = button
            return .init(reading: button)
        })
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("Use init(options:alignment:)") }
    func update(alignment: HUDAlignment) { self.alignment = alignment; refresh() }
    private func refresh() {
        let allowed = alignment == .vertical
        master.isEnabled = allowed; master.state = allowed && options.enabled ? .on : .off
        for (reading, button) in controls {
            button.isEnabled = allowed && options.enabled
            button.state = options.readings.contains(reading) ? .on : .off
            button.emphasized = options.highlighted.contains(reading)
        }
    }
    @objc private func toggleCategory() {
        options.enabled = master.state == .on; refresh(); onChange?(options)
    }
    @objc private func toggleReading(_ sender: NSButton) {
        let reading = HUDProcessReading.allCases[sender.tag]
        if sender.state == .on { options.readings.insert(reading) } else { options.readings.remove(reading) }
        refresh(); onChange?(options)
    }
}
