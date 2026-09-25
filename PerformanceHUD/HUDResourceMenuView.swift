import AppKit

@MainActor
final class HUDResourceMenuView: NSView {
    var onChange: ((HUDResourceOptions) -> Void)?
    var onPowerSetup: (() -> Void)?
    private var powerAvailability: PowerHelperAvailability = .ready
    private var powerToolTip: String?
    var onBatteryChange: ((HUDBatteryOptions) -> Void)?
    private let group: HUDResourceGroup?
    private var options: HUDResourceOptions
    private var controls: [Int: NSButton] = [:]

    convenience init(batteryOptions: HUDBatteryOptions) {
        self.init(group: nil, options: HUDResourceOptions(enabled: batteryOptions.enabled,
            temperature: batteryOptions.temperature, totalUse: batteryOptions.charge, focusedApp: false))
    }

    init(group: HUDResourceGroup?, options: HUDResourceOptions) {
        self.group = group
        self.options = options
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 34))

        autoresizingMask = [.width]
        let groupTitle = group?.title ?? "Battery"

        // Keep the master in the normal menu checkmark/title columns. The inset
        // container makes its subordinate choices read as one related group.
        let master = HUDResourceMasterButton(title: groupTitle, target: self, action: #selector(changed(_:)))
        master.tag = 0
        master.toolTip = "Show or hide this group while keeping its individual choices."
        master.setAccessibilityLabel("Show \(groupTitle)")
        master.translatesAutoresizingMaskIntoConstraints = false
        addSubview(master)
        controls[0] = master

        let choices = HUDResourceChoicesView()
        choices.translatesAutoresizingMaskIntoConstraints = false
        choices.setAccessibilityRole(.group)
        choices.setAccessibilityLabel("\(groupTitle) display options")
        addSubview(choices)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        choices.addSubview(stack)
        let columns = group == nil
            ? [(4, "", 76.0), (1, "Temperature", 112.0), (2, "Energy", 92.0), (3, "", 145.0)]
            : [(4, "Power", 76.0), (1, "Temperature", 112.0), (2, "Total Use", 92.0), (3, "Only focused app", 145.0)]
        for (tag, title, width) in columns {
            if title.isEmpty || (tag == 1 && group?.supportsTemperature == false) || (tag == 4 && group?.supportsPower == false) {
                let spacer = NSView()
                spacer.widthAnchor.constraint(equalToConstant: width).isActive = true
                stack.addArrangedSubview(spacer)
                continue
            }
            let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(changed(_:)))
            button.font = .menuFont(ofSize: 0)
            button.tag = tag
            button.setAccessibilityLabel("\(groupTitle) \(title)")
            button.widthAnchor.constraint(equalToConstant: width).isActive = true
            if group == nil {
                button.toolTip = tag == 1
                    ? "Average of available battery temperature sensors, in °C, with the battery controller reading as a fallback. MacBooks only; unavailable readings stay blank."
                    : "Shows remaining battery charge using the dynamic battery icon."
            } else if tag == 4 {
                button.toolTip = "Estimated total \(groupTitle) power in watts, averaged over the sampling interval. Requires approval for the Power Helper. Enabling both CPU and GPU Power also shows Package: combined CPU, GPU and Neural Engine power, not whole-Mac power. Unavailable readings stay blank."
            } else if tag == 1 {
                button.toolTip = group == .cpu
                    ? "Average of identified CPU temperature sensors for this chip, in °C. Sensor coverage varies by model; unavailable readings stay blank. Not a per-app reading."
                    : "Average of available GPU temperature sensors, in °C. Not a per-app reading."
            } else if tag == 2 {
                button.toolTip = group == .ram
                    ? "Shows system RAM usage, physical memory used, swap, and memory pressure."
                    : "Shows total \(groupTitle) usage across the whole system."
            } else if tag == 3 {
                button.toolTip = "Shows \(groupTitle) usage for the focused app’s tracked process. Helper processes may not be included."
            }
            if tag == 4 { powerToolTip = button.toolTip }
            controls[tag] = button
            stack.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            master.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            master.widthAnchor.constraint(equalToConstant: 82),
            master.topAnchor.constraint(equalTo: topAnchor),
            master.bottomAnchor.constraint(equalTo: bottomAnchor),
            choices.leadingAnchor.constraint(equalTo: master.trailingAnchor, constant: 8),
            choices.centerYAnchor.constraint(equalTo: centerYAnchor),
            choices.heightAnchor.constraint(equalToConstant: 28),
            choices.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: choices.leadingAnchor, constant: 8),
            stack.centerYAnchor.constraint(equalTo: choices.centerYAnchor),
            stack.trailingAnchor.constraint(equalTo: choices.trailingAnchor, constant: -8)
        ])
        setFrameSize(NSSize(width: 8 + 82 + 8 + 16 + 76 + 112 + 92 + 145 + 36 + 12, height: 34))
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Use init(group:options:)") }

    func setPowerState(_ availability: PowerHelperAvailability, selected: Bool) {
        powerAvailability = availability
        options.power = selected
        refresh()
    }

    @objc private func changed(_ sender: NSButton) {
        if sender.tag == 4 && !powerAvailability.allowsPowerToggle {
            refresh()
            onPowerSetup?()
            return
        }
        let value = sender.state == .on
        switch sender.tag {
        case 0: options.enabled = value
        case 1: options.temperature = value
        case 2: options.totalUse = value
        case 3: options.focusedApp = value
        case 4: options.power = value
        default: return
        }
        refresh()
        onChange?(options)
        onBatteryChange?(HUDBatteryOptions(enabled: options.enabled,
            temperature: options.temperature, charge: options.totalUse))
    }

    private func refresh() {
        for (tag, value) in [(0, options.enabled), (1, options.temperature),
                             (2, options.totalUse), (3, options.focusedApp), (4, options.power)] {
            controls[tag]?.state = value ? .on : .off
            controls[tag]?.isEnabled = tag == 0 || options.enabled
        }
        if let power = controls[4] {
            // Visually unavailable, but still actionable: clicking offers setup.
            power.alphaValue = powerAvailability.usesNormalAppearance ? 1 : 0.5
            power.toolTip = powerAvailability.explanation ?? powerToolTip
            power.setAccessibilityHelp(power.toolTip)
        }
    }
}

/// A borderless toggle using AppKit's menu checkmark, rather than a boxed checkbox.
@MainActor
private final class HUDResourceMasterButton: NSButton {
    private let checkmark = NSImageView()
    private let nameLabel: NSTextField

    override var state: NSControl.StateValue {
        didSet { checkmark.isHidden = state != .on }
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
        // The legacy menu template is thinner than current macOS menu ticks.
        checkmark.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .bold))
        checkmark.contentTintColor = .labelColor
        checkmark.imageScaling = .scaleProportionallyDown
        nameLabel.font = .menuFont(ofSize: 0)
        nameLabel.textColor = .labelColor
        for view in [checkmark, nameLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            checkmark.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            checkmark.widthAnchor.constraint(equalToConstant: 12),
            checkmark.heightAnchor.constraint(equalToConstant: 16),
            checkmark.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(title:target:action:)") }

    // The decorative subviews belong to the same toggle hit area.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }
}

@MainActor
private final class HUDResourceChoicesView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSColor.labelColor.withAlphaComponent(0.035).setFill()
        shape.fill()
        NSColor.separatorColor.withAlphaComponent(0.25).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()
    }
}
