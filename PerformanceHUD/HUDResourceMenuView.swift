import AppKit

@MainActor
final class HUDResourceMenuView: HUDCategoryMenuView {
    var onChange: ((HUDResourceOptions) -> Void)?
    var onPowerSetup: (() -> Void)?
    private var powerAvailability: PowerHelperAvailability = .ready
    var onBatteryChange: ((HUDBatteryOptions) -> Void)?
    private let group: HUDResourceGroup?
    private var options: HUDResourceOptions
    private var controls: [Int: NSButton] = [:]
    private var usageModeControl: NSSegmentedControl?
    private var pressureModeControl: NSSegmentedControl?
    private var pressureStyleControl: NSSegmentedControl?
    private var alignment: HUDAlignment
    private var flowControl: NSSegmentedControl?
    private let flowHighlight = HUDEmphasisButton()
    private var flowLabel: NSTextField?
    private let master = HUDResourceMasterButton(title: "", target: nil, action: nil)
    private var flowMode: HUDBatteryFlowMode = .auto

    convenience init(batteryOptions: HUDBatteryOptions) {
        self.init(group: nil, options: HUDResourceOptions(enabled: batteryOptions.enabled,
            temperature: batteryOptions.temperature, totalUse: batteryOptions.charge, focusedApp: false,
            power: batteryOptions.power,
            highlighted: Set([batteryOptions.temperatureHighlighted ? HUDReadingKind.temperature : nil,
                              batteryOptions.powerHighlighted ? HUDReadingKind.power : nil].compactMap { $0 })))
        flowMode = batteryOptions.flowMode
        refresh()
    }

    init(group: HUDResourceGroup?, options: HUDResourceOptions, alignment: HUDAlignment = .vertical) {
        self.group = group
        self.options = options
        self.alignment = alignment
        super.init()
        let title = group?.title ?? "Battery"
        setAccessibilityLabel("\(title) display options")
        master.setName(title)
        master.target = self
        master.action = #selector(changed(_:))
        master.tag = 0
        master.setAccessibilityLabel("Show \(title)")
        controls[0] = master
        setCategory(master)

        let readings: [(Int, String)] = group == .ram ? [(8, "Pressure"), (5, "Details"), (7, "Use")]
            : group == .ane ? [(4, "Power")]
            : group == nil ? [(4, "Charge"), (1, "Temperature"), (6, "Energy")]
            : [(4, "Power"), (1, "Temperature"), (7, "Use")]
        var rows: [HUDCategoryMenuRow] = []
        for (tag, name) in readings {
            if group == nil && tag == 4 {
                let label = NSTextField(labelWithString: name)
                label.font = .menuFont(ofSize: 0)
                flowLabel = label
                let control = NSSegmentedControl(labels: HUDBatteryFlowMode.allCases.map(\.title),
                    trackingMode: .selectOne, target: self, action: #selector(flowModeChanged(_:)))
                control.font = .menuFont(ofSize: 0)
                control.segmentStyle = .rounded
                control.setAccessibilityLabel("Battery Charge mode")
                flowControl = control
                flowHighlight.target = self
                flowHighlight.action = #selector(flowHighlightChanged)
                flowHighlight.setAccessibilityLabel("Emphasize Battery Charge")
                rows.append(.init(reading: label, mode: control, emphasis: flowHighlight))
                continue
            }
            let button = HUDReadingCheckbox(title: name, supportsEmphasis: readingKind(for: tag) != nil || tag == 7)
            button.target = self
            button.action = #selector(changed(_:))
            button.tag = tag
            button.setControlAccessibilityLabel("\(title) \(name)")
            button.onHighlight = { [weak self] in self?.highlightChanged(tag: tag) }
            controls[tag] = button
            var row = HUDCategoryMenuRow(reading: button)
            if group == .ram && tag == 8 {
                let control = NSSegmentedControl(labels: ["Text", "Graph"],
                    trackingMode: .selectOne, target: self, action: #selector(pressureModeChanged(_:)))
                control.font = .menuFont(ofSize: 0)
                control.segmentStyle = .rounded
                control.setAccessibilityLabel("Memory pressure display")
                pressureModeControl = control
                row.mode = control
            }
            if tag == 7 {
                let control = NSSegmentedControl(labels: ["Total", "App", "Both"], trackingMode: .selectOne,
                    target: self, action: #selector(usageModeChanged(_:)))
                control.font = .menuFont(ofSize: 0)
                control.segmentStyle = .rounded
                control.setAccessibilityLabel("\(title) usage mode")
                usageModeControl = control
                row.mode = control
            }
            rows.append(row)
            if group == .ram && tag == 8 {
                let styles = NSSegmentedControl(labels: ["A1", "A2", "B1", "B2"],
                    trackingMode: .selectOne, target: self, action: #selector(pressureStyleChanged(_:)))
                styles.setAccessibilityLabel("Pressure style: A1 Meter, A2 Colored meter, B1 Graph, B2 Colored graph")
                pressureStyleControl = styles
                rows.append(.init(reading: NSView(), mode: styles))
            }
        }
        setRows(rows)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Use init(group:options:)") }

    func update(alignment: HUDAlignment) {
        self.alignment = alignment
        refresh()
    }

    @objc private func pressureModeChanged(_ sender: NSSegmentedControl) {
        guard sender.isEnabled, (0...1).contains(sender.selectedSegment) else { return }
        options.selectPressureMode(sender.selectedSegment == 0 ? .text : options.selectedPressureGraphStyle)
        refresh()
        onChange?(options)
    }

    @objc private func pressureStyleChanged(_ sender: NSSegmentedControl) {
        guard sender.isEnabled, HUDMemoryPressureMode.graphStyles.indices.contains(sender.selectedSegment),
              sender.isEnabled(forSegment: sender.selectedSegment) else { refresh(); return }
        let mode = HUDMemoryPressureMode.graphStyles[sender.selectedSegment]
        guard alignment != .horizontal || !mode.isHistory else { refresh(); return }
        options.selectPressureMode(mode)
        refresh()
        onChange?(options)
    }

    @objc private func flowModeChanged(_ sender: NSSegmentedControl) {
        guard options.enabled, HUDBatteryFlowMode.allCases.indices.contains(sender.selectedSegment) else { return }
        flowMode = HUDBatteryFlowMode.allCases[sender.selectedSegment]
        options.power = flowMode != .off
        refresh()
        notifyBatteryChange()
    }

    @objc private func flowHighlightChanged() {
        guard flowHighlight.isEnabled else { return }
        if options.highlighted.contains(.power) { options.highlighted.remove(.power) }
        else { options.highlighted.insert(.power) }
        refresh()
        notifyBatteryChange()
    }

    func setPowerState(_ availability: PowerHelperAvailability, selected: Bool) {
        powerAvailability = availability
        options.power = selected
        refresh()
    }

    @objc private func changed(_ sender: NSButton) {
        if group != nil && sender.tag == 4 && !powerAvailability.allowsPowerToggle {
            refresh()
            onPowerSetup?()
            return
        }
        if sender.tag == 7 {
            options.setUsagePresentation(visible: sender.state == .on,
                                         highlighted: options.usageHighlighted)
            refresh()
            onChange?(options)
            return
        }
        let value = sender.state == .on
        switch sender.tag {
        case 0: options.enabled = value
        case 1: options.temperature = value
        case 4: options.power = value
        case 5: options.details = value
        case 6: options.totalUse = value
        case 8: options.pressure = value
        default: return
        }
        refresh()
        onChange?(options)
        notifyBatteryChange()
    }

    private func highlightChanged(tag: Int) {
        guard let control = controls[tag], control.isEnabled, control.state == .on else { return }
        if tag == 8 && options.pressureMode != .text { return }
        if group != nil && tag == 4 && !powerAvailability.allowsPowerToggle { return }
        if tag == 7 {
            options.setUsagePresentation(visible: true, highlighted: !options.usageHighlighted)
        } else if let kind = readingKind(for: tag) {
            if options.highlighted.contains(kind) { options.highlighted.remove(kind) }
            else { options.highlighted.insert(kind) }
        } else { return }
        refresh()
        onChange?(options)
        notifyBatteryChange()
    }

    private func notifyBatteryChange() {
        guard group == nil else { return }
        onBatteryChange?(HUDBatteryOptions(enabled: options.enabled,
            temperature: options.temperature, charge: options.totalUse,
            temperatureHighlighted: options.highlighted.contains(.temperature),
            powerHighlighted: options.highlighted.contains(.power), flowMode: flowMode))
    }

    @objc private func usageModeChanged(_ sender: NSSegmentedControl) {
        guard HUDUsageMode.allCases.indices.contains(sender.selectedSegment) else { return }
        options.selectUsageMode(HUDUsageMode.allCases[sender.selectedSegment])
        refresh()
        onChange?(options)
    }

    private func readingKind(for tag: Int) -> HUDReadingKind? {
        if group == nil { return tag == 1 ? .temperature : tag == 4 ? .power : nil }
        switch tag {
        case 1: return .temperature
        case 4: return .power
        case 5: return .details
        case 8: return .pressure
        default: return nil
        }
    }

    private func refresh() {
        pressureModeControl?.selectedSegment = options.pressureMode == .text ? 0 : 1
        pressureModeControl?.isEnabled = options.showsPressure
        let style = options.selectedPressureGraphStyle.resolved(for: alignment)
        pressureStyleControl?.selectedSegment = HUDMemoryPressureMode.graphStyles.firstIndex(of: style) ?? 3
        pressureStyleControl?.isEnabled = options.showsPressure && options.pressureMode != .text
        for (index, mode) in HUDMemoryPressureMode.graphStyles.enumerated() {
            pressureStyleControl?.setEnabled(alignment != .horizontal || !mode.isHistory, forSegment: index)
        }
        flowControl?.selectedSegment = HUDBatteryFlowMode.allCases.firstIndex(of: flowMode) ?? 1
        flowControl?.isEnabled = options.enabled
        flowLabel?.textColor = options.enabled ? .labelColor : .disabledControlTextColor
        flowHighlight.state = options.highlighted.contains(.power) ? .on : .off
        flowHighlight.isEnabled = options.enabled && flowMode != .off
        for (tag, value) in [(0, options.enabled), (1, options.temperature),
                             (4, options.power), (5, options.details), (6, options.totalUse), (7, options.usageVisible),
                             (8, options.pressure)] {
            controls[tag]?.state = value ? .on : .off
            controls[tag]?.isEnabled = tag == 0 || options.enabled
            if let button = controls[tag] as? HUDReadingCheckbox, let kind = readingKind(for: tag) {
                button.emphasized = options.highlighted.contains(kind)
                button.setAccessibilityValue(!value ? "Off" : button.emphasized ? "Highlighted" : "Faint")
            }
        }
        controls[8]?.isEnabled = options.enabled && options.selectedUsageMode != .app
        (controls[8] as? HUDReadingCheckbox)?.highlightAvailable = options.pressureMode == .text
        usageModeControl?.selectedSegment = HUDUsageMode.allCases.firstIndex(of: options.selectedUsageMode) ?? 0
        usageModeControl?.isEnabled = options.enabled
        if let usage = controls[7] as? HUDReadingCheckbox {
            usage.emphasized = options.usageHighlighted
            usage.setAccessibilityValue(!options.usageVisible ? "Off" : usage.emphasized ? "Highlighted" : "Faint")
        }
        if group != nil, let power = controls[4] as? HUDReadingCheckbox {
            power.highlightAvailable = powerAvailability.allowsPowerToggle
            // Visually unavailable, but still actionable: clicking offers setup.
            power.alphaValue = powerAvailability.usesNormalAppearance ? 1 : 0.5
            power.toolTip = powerAvailability.explanation
            power.setAccessibilityHelp(power.toolTip)
        }
    }
}

/// A compact, neutral switch with the category label sharing its click target.
@MainActor
final class HUDResourceMasterButton: NSButton {
    private let nameLabel: NSTextField

    override var state: NSControl.StateValue {
        didSet { needsDisplay = true }
    }

    override var isEnabled: Bool {
        didSet {
            let color: NSColor = isEnabled ? .labelColor : .disabledControlTextColor
            nameLabel.textColor = color
            needsDisplay = true
        }
    }

    init(title: String, target: AnyObject?, action: Selector?) {
        nameLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        self.title = ""
        self.target = target
        self.action = action
        setButtonType(.pushOnPushOff)
        isBordered = false
        focusRingType = .default
        setAccessibilityRole(.checkBox)
        nameLabel.font = .systemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .semibold)
        nameLabel.textColor = .labelColor
        addSubview(nameLabel)
    }

    required init?(coder: NSCoder) { fatalError("Use init(title:target:action:)") }

    func setName(_ name: String) { nameLabel.stringValue = name; needsLayout = true }

    override func layout() {
        super.layout()
        // Menu views may be measured at zero width before the category assigns its frame.
        let height = nameLabel.intrinsicContentSize.height
        nameLabel.frame = NSRect(x: 38, y: (bounds.height - height) / 2,
                                width: max(0, bounds.width - 38), height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        let trackRect = NSRect(x: 4, y: (bounds.height - 16) / 2, width: 26, height: 16)
        let track = NSBezierPath(roundedRect: trackRect, xRadius: 8, yRadius: 8)
        // Keep the same neutral palette as the menu's other controls, independent
        // of the system accent color. Thumb position also communicates the state.
        NSColor.labelColor.withAlphaComponent(isEnabled ? (selected ? 0.30 : 0.10) : 0.05).setFill()
        track.fill()
        NSColor.labelColor.withAlphaComponent(isEnabled ? 0.16 : 0.06).setStroke()
        track.lineWidth = 0.5
        track.stroke()
        let thumbRect = NSRect(x: trackRect.minX + (selected ? 12 : 2), y: trackRect.minY + 2,
                               width: 12, height: 12)
        let thumb = NSBezierPath(ovalIn: thumbRect)
        NSColor.white.withAlphaComponent(isEnabled ? 0.95 : 0.25).setFill()
        thumb.fill()
        NSColor.black.withAlphaComponent(isEnabled ? 0.12 : 0.04).setStroke()
        thumb.lineWidth = 0.5
        thumb.stroke()
        if window?.firstResponder === self {
            NSFocusRingPlacement.only.set()
            track.fill()
        }
    }

    // The decorative subviews belong to the same toggle hit area.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }
}
