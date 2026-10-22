import AppKit

@MainActor
final class HUDPackagePowerMenuView: HUDCategoryMenuView {
    var onChange: ((HUDPackagePowerOptions) -> Void)?
    var onPowerSetup: (() -> Void)?
    private var helperAvailability: PowerHelperAvailability = .idle
    private var options: HUDPackagePowerOptions
    private let master = HUDResourceMasterButton(title: "SOC", target: nil, action: nil)
    private let readingLabel = NSTextField(labelWithString: "Combined power")
    private let highlight = HUDEmphasisButton()

    init(options: HUDPackagePowerOptions) {
        self.options = options
        super.init()
        setAccessibilityLabel("SOC display options")
        master.target = self
        master.action = #selector(changed(_:))
        master.setAccessibilityLabel("Show SOC")
        setCategory(master)
        readingLabel.font = .menuFont(ofSize: 0)
        highlight.target = self
        highlight.action = #selector(highlightChanged)
        highlight.setAccessibilityLabel("Emphasize SOC Combined power")
        setRows([.init(reading: readingLabel, emphasis: highlight,
                      menuBar: makeMenuBarButton(for: .socPower, title: "SOC Combined power"))])
        setState(options: options, helper: .idle)
    }

    required init?(coder: NSCoder) { fatalError("Use init(options:)") }

    func setState(options: HUDPackagePowerOptions, helper: PowerHelperAvailability) {
        self.options = options
        helperAvailability = helper
        master.toolTip = helper.explanation
        master.setAccessibilityHelp(helper.explanation)
        readingLabel.toolTip = helper.explanation
        refresh()
    }

    override func refreshMenuBarSelections() {
        super.refreshMenuBarSelections()
        refresh()
    }

    private func refresh() {
        master.state = options.enabled ? .on : .off
        let visible = options.enabled || isMenuBarSelected(.socPower)
        readingLabel.textColor = visible ? .labelColor : .disabledControlTextColor
        readingLabel.alphaValue = helperAvailability.usesNormalAppearance ? 1 : 0.5
        highlight.state = options.highlighted ? .on : .off
        highlight.isEnabled = visible && helperAvailability.allowsPowerToggle
    }

    @objc private func changed(_ sender: NSButton) {
        guard helperAvailability.allowsPowerToggle else { refresh(); onPowerSetup?(); return }
        options.enabled = sender.state == .on
        refresh()
        onChange?(options)
    }
    @objc private func highlightChanged() {
        guard highlight.isEnabled else { return }
        options.highlighted = highlight.state == .on
        refresh()
        onChange?(options)
    }
}
