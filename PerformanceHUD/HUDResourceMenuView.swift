import AppKit

@MainActor
final class HUDResourceMenuView: NSView {
    static var masterWidth: CGFloat {
        ceil(("Apple Neural Engine" as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width) + 24
    }
    static var powerColumnLeading: CGFloat { 8 + masterWidth + 8 + 8 }
    static let choicesWidth: CGFloat = 16 + 90 + 126 + 106 + 145 + 36
    static let readingsChoicesWidth: CGFloat = 8 + 90 + 12 + 126 + 4

    private static let detailsHelp = "Shows physical memory for Total or App RAM; swap and memory pressure are system-wide and appear with Total. Horizontal layout uses PHY and SWP, with an outlined triangle for warning pressure or a filled triangle for critical pressure. Normal pressure has no triangle; unavailable readings stay blank. The attached strip highlights the values, not the labels."

    var onChange: ((HUDResourceOptions) -> Void)?
    var onPowerSetup: (() -> Void)?
    private var powerAvailability: PowerHelperAvailability = .ready
    private var powerToolTip: String?
    var onBatteryChange: ((HUDBatteryOptions) -> Void)?
    private let group: HUDResourceGroup?
    private var options: HUDResourceOptions
    private var controls: [Int: NSButton] = [:]
    private var usageModeControl: NSSegmentedControl?

    convenience init(batteryOptions: HUDBatteryOptions) {
        self.init(group: nil, options: HUDResourceOptions(enabled: batteryOptions.enabled,
            temperature: batteryOptions.temperature, totalUse: batteryOptions.charge, focusedApp: false,
            highlighted: batteryOptions.temperatureHighlighted ? [.temperature] : []))
    }

    init(group: HUDResourceGroup?, options: HUDResourceOptions) {
        self.group = group
        self.options = options
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 34))

        autoresizingMask = [.width]
        let groupTitle = group?.title ?? "Battery"
        let masterWidth = Self.masterWidth

        // Keep the master in the normal menu checkmark/title columns. The inset
        // container makes its subordinate choices read as one related group.
        let master = HUDResourceMasterButton(title: groupTitle, target: self, action: #selector(changed(_:)))
        master.tag = 0
        master.toolTip = "Show or hide this group while keeping its individual choices."
        master.setAccessibilityLabel("Show \(groupTitle)")
        master.translatesAutoresizingMaskIntoConstraints = false
        addSubview(master)
        controls[0] = master

        let choices = NSView()
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
        let columns = group == .ram
            ? [(5, "Details", 90.0), (1, "", 126.0), (7, "Usage", 106.0), (8, "", 145.0)]
            : group == nil
            ? [(6, "Energy", 90.0), (1, "Temperature", 126.0), (2, "", 106.0), (3, "", 145.0)]
            : [(4, "Power", 90.0), (1, "Temperature", 126.0), (7, "Usage", 106.0), (8, "", 145.0)]
        for (tag, title, width) in columns {
            if tag == 8, let group, group.supportsTotalUse {
                let control = NSSegmentedControl(labels: ["Total", "App", "Both"], trackingMode: .selectOne,
                                                 target: self, action: #selector(usageModeChanged(_:)))
                control.segmentStyle = .rounded
                control.font = .menuFont(ofSize: 0)
                control.widthAnchor.constraint(equalToConstant: width).isActive = true
                control.setAccessibilityLabel("\(groupTitle) usage mode")
                let help = "Total: usage across the whole system. App: usage for the focused app’s tracked process; helper processes may not be included. Both: shows the total and app readings together. The Usage checkbox controls visibility; its attached strip controls boldness. Power and temperature remain system-wide."
                let modeHelp = help + (group == .cpu ? " App CPU uses 100% per fully used logical core, so it can exceed 100%; Total CPU is 0–100% across all cores." : "")
                control.toolTip = modeHelp
                control.setAccessibilityHelp(modeHelp)
                for segment in 0..<3 { control.setToolTip(modeHelp, forSegment: segment) }
                usageModeControl = control
                stack.addArrangedSubview(control)
                continue
            }
            if title.isEmpty || (tag == 1 && group?.supportsTemperature == false) || (tag == 4 && group?.supportsPower == false) || (tag == 7 && group?.supportsTotalUse == false) {
                let spacer = NSView()
                spacer.widthAnchor.constraint(equalToConstant: width).isActive = true
                stack.addArrangedSubview(spacer)
                continue
            }
            let button = HUDReadingCheckbox(title: title, supportsEmphasis: readingKind(for: tag) != nil || tag == 7)
            button.target = self
            button.action = #selector(changed(_:))
            button.onHighlight = { [weak self] in self?.highlightChanged(tag: tag) }
            button.font = .menuFont(ofSize: 0)
            button.tag = tag
            button.setControlAccessibilityLabel("\(groupTitle) \(title)")
            button.widthAnchor.constraint(equalToConstant: width).isActive = true
            if group == nil {
                button.toolTip = tag == 1
                    ? "Average of available battery temperature sensors, in °C, with the battery controller reading as a fallback. MacBooks only; unavailable readings stay blank."
                    : "Shows battery charge with a dynamic icon. A bolt indicates external power; yellow indicates Low Power Mode."
            } else if tag == 4 {
                button.toolTip = "Estimated total \(groupTitle) power in watts, averaged over the sampling interval. Requires approval for the Power Helper. Package independently shows combined CPU, GPU and Neural Engine power, not whole-Mac power. Unavailable readings stay blank."
            } else if tag == 1 {
                button.toolTip = group == .cpu
                    ? "Average of identified CPU temperature sensors for this chip, in °C. Sensor coverage varies by model; unavailable readings stay blank. Not a per-app reading."
                    : "Average of available GPU temperature sensors, in °C. Not a per-app reading."
            } else if tag == 7 {
                button.toolTip = "Shows \(groupTitle) usage for the selected Total, App or Both mode."
            } else if tag == 5 {
                button.toolTip = Self.detailsHelp
            }
            if readingKind(for: tag) != nil || tag == 7 {
                button.toolTip = (button.toolTip ?? "") + " Use the checkbox to show or hide; the attached strip toggles bold values independently and remembers the choice while hidden."
            }
            if tag == 4 { powerToolTip = button.toolTip }
            controls[tag] = button
            stack.addArrangedSubview(button)
        }
        // Split the backgrounds without shifting the shared checkbox columns.
        if group?.supportsTotalUse == true {
            let readingsBar = HUDResourceChoicesView()
            let usageBar = HUDResourceChoicesView()
            for bar in [readingsBar, usageBar] {
                bar.translatesAutoresizingMaskIntoConstraints = false
                choices.addSubview(bar, positioned: .below, relativeTo: stack)
                NSLayoutConstraint.activate([
                    bar.topAnchor.constraint(equalTo: choices.topAnchor),
                    bar.bottomAnchor.constraint(equalTo: choices.bottomAnchor)
                ])
            }
            NSLayoutConstraint.activate([
                readingsBar.leadingAnchor.constraint(equalTo: choices.leadingAnchor),
                readingsBar.trailingAnchor.constraint(equalTo: stack.arrangedSubviews[1].trailingAnchor, constant: 4),
                usageBar.leadingAnchor.constraint(equalTo: stack.arrangedSubviews[2].leadingAnchor, constant: -4),
                usageBar.trailingAnchor.constraint(equalTo: choices.trailingAnchor)
            ])
        } else {
            let bar = HUDResourceChoicesView()
            bar.translatesAutoresizingMaskIntoConstraints = false
            choices.addSubview(bar, positioned: .below, relativeTo: stack)
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: choices.leadingAnchor),
                bar.widthAnchor.constraint(equalToConstant: Self.readingsChoicesWidth),
                bar.topAnchor.constraint(equalTo: choices.topAnchor),
                bar.bottomAnchor.constraint(equalTo: choices.bottomAnchor)
            ])
        }
        NSLayoutConstraint.activate([
            master.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            master.widthAnchor.constraint(equalToConstant: masterWidth),
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
        setFrameSize(NSSize(width: 8 + masterWidth + 8 + Self.choicesWidth + 12, height: 34))
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
        default: return
        }
        refresh()
        onChange?(options)
        onBatteryChange?(HUDBatteryOptions(enabled: options.enabled,
            temperature: options.temperature, charge: options.totalUse,
            temperatureHighlighted: options.highlighted.contains(.temperature)))
    }

    private func highlightChanged(tag: Int) {
        guard let control = controls[tag], control.isEnabled, control.state == .on else { return }
        if tag == 4 && !powerAvailability.allowsPowerToggle { return }
        if tag == 7 {
            options.setUsagePresentation(visible: true, highlighted: !options.usageHighlighted)
        } else if let kind = readingKind(for: tag) {
            if options.highlighted.contains(kind) { options.highlighted.remove(kind) }
            else { options.highlighted.insert(kind) }
        } else { return }
        refresh()
        onChange?(options)
        onBatteryChange?(HUDBatteryOptions(enabled: options.enabled,
            temperature: options.temperature, charge: options.totalUse,
            temperatureHighlighted: options.highlighted.contains(.temperature)))
    }

    @objc private func usageModeChanged(_ sender: NSSegmentedControl) {
        guard HUDUsageMode.allCases.indices.contains(sender.selectedSegment) else { return }
        options.selectUsageMode(HUDUsageMode.allCases[sender.selectedSegment])
        refresh()
        onChange?(options)
    }

    private func readingKind(for tag: Int) -> HUDReadingKind? {
        if group == nil { return tag == 1 ? .temperature : nil }
        switch tag {
        case 1: return .temperature
        case 4: return .power
        case 5: return .details
        default: return nil
        }
    }

    private func refresh() {
        for (tag, value) in [(0, options.enabled), (1, options.temperature),
                             (4, options.power), (5, options.details), (6, options.totalUse), (7, options.usageVisible)] {
            controls[tag]?.state = value ? .on : .off
            controls[tag]?.isEnabled = tag == 0 || options.enabled
            if let button = controls[tag] as? HUDReadingCheckbox, let kind = readingKind(for: tag) {
                button.emphasized = options.highlighted.contains(kind)
                button.setAccessibilityValue(!value ? "Off" : button.emphasized ? "Highlighted" : "Faint")
            }
        }
        usageModeControl?.selectedSegment = HUDUsageMode.allCases.firstIndex(of: options.selectedUsageMode) ?? 0
        usageModeControl?.isEnabled = options.enabled
        if group == .ram {
            controls[5]?.state = options.showsDetails ? .on : .off
            controls[5]?.isEnabled = options.detailsAvailable
            if let details = controls[5] as? HUDReadingCheckbox {
                details.emphasized = options.highlighted.contains(.details)
                details.setAccessibilityValue(!options.showsDetails ? "Off" : details.emphasized ? "Highlighted" : "Faint")
            }
            controls[5]?.toolTip = options.detailsAvailable
                ? Self.detailsHelp
                : "Enable RAM and Usage to show Details. Your Details selection is remembered."
        }
        if let usage = controls[7] as? HUDReadingCheckbox {
            usage.emphasized = options.usageHighlighted
            usage.setAccessibilityValue(!options.usageVisible ? "Off" : usage.emphasized ? "Highlighted" : "Faint")
        }
        if let power = controls[4] as? HUDReadingCheckbox {
            power.highlightAvailable = powerAvailability.allowsPowerToggle
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
final class HUDResourceChoicesView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSColor.labelColor.withAlphaComponent(0.035).setFill()
        shape.fill()
        NSColor.separatorColor.withAlphaComponent(0.25).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()
    }
}

/// Two independent targets: the checkbox controls visibility, the attached strip
/// controls emphasis. Plain options retain the native single checkbox.
@MainActor
final class HUDReadingCheckbox: NSButton {
    private let visibility = HUDVisibilityButton(checkboxWithTitle: "", target: nil, action: nil)
    private let highlight = HUDHighlightButton()
    private let supportsEmphasis: Bool
    var onHighlight: (() -> Void)?
    var emphasized = false { didSet { updateControls() } }
    var highlightAvailable = true { didSet { updateControls() } }

    override var state: NSControl.StateValue { didSet { updateControls() } }
    override var isEnabled: Bool { didSet { updateControls() } }
    override var font: NSFont? { didSet { visibility.font = font } }
    override var toolTip: String? { didSet { visibility.toolTip = toolTip } }

    init(title: String, supportsEmphasis: Bool = true) {
        self.supportsEmphasis = supportsEmphasis
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        setAccessibilityElement(false)
        visibility.title = title
        visibility.split = supportsEmphasis
        visibility.target = self
        visibility.action = #selector(toggleVisibility)
        highlight.setButtonType(.toggle)
        highlight.isBordered = false
        highlight.target = self
        highlight.action = #selector(toggleHighlight)
        highlight.toolTip = "Highlight this value in the HUD. The checkbox separately controls visibility."
        highlight.setAccessibilityRole(.checkBox)
        addSubview(visibility)
        if supportsEmphasis { addSubview(highlight) }
        setControlAccessibilityLabel(title)
        updateControls()
    }

    required init?(coder: NSCoder) { fatalError("Use init(title:supportsEmphasis:)") }
    // Keyboard focus belongs to the two actionable child buttons.
    override var acceptsFirstResponder: Bool { false }
    override var intrinsicContentSize: NSSize {
        NSSize(width: visibility.intrinsicContentSize.width + (supportsEmphasis ? 14 : 0), height: 22)
    }
    override func draw(_ dirtyRect: NSRect) {}
    override func layout() {
        super.layout()
        visibility.frame = bounds
        highlight.frame = NSRect(x: 18, y: (bounds.height - 18) / 2, width: 12, height: 18)
    }
    func setControlAccessibilityLabel(_ label: String) {
        visibility.setAccessibilityLabel(label)
        highlight.setAccessibilityLabel("Highlight \(label)")
    }
    private func updateControls() {
        visibility.state = state
        visibility.isEnabled = isEnabled
        highlight.state = emphasized ? .on : .off
        highlight.isEnabled = isEnabled && state == .on && highlightAvailable
        highlight.toolTip = highlight.isEnabled
            ? "Toggle bold emphasis for this value. Visibility is controlled separately by the checkbox."
            : "Enable this reading to change its bold emphasis. Your emphasis choice is remembered while hidden."
        visibility.needsDisplay = true
        highlight.needsDisplay = true
    }
    override func performClick(_ sender: Any?) { visibility.performClick(sender) }
    @objc private func toggleVisibility() {
        state = visibility.state
        sendAction(action, to: target)
    }
    @objc private func toggleHighlight() {
        guard highlight.isEnabled else { return }
        onHighlight?()
        updateControls()
    }
}

@MainActor
private final class HUDVisibilityButton: NSButton {
    override var isFlipped: Bool { false }
    var split = false
    override func draw(_ dirtyRect: NSRect) {
        guard split else { super.draw(dirtyRect); return }
        let y = (bounds.height - 18) / 2
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: NSRect(x: 0, y: y, width: 30, height: 18), xRadius: 4, yRadius: 4).addClip()
        NSColor.labelColor.withAlphaComponent(isEnabled ? (state == .on ? 0.30 : 0.10) : 0.06).setFill()
        NSRect(x: 0, y: y, width: 18, height: 18).fill()
        NSGraphicsContext.restoreGraphicsState()
        if state == .on {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 4, y: y + 9))
            path.line(to: NSPoint(x: 8, y: y + 5))
            path.line(to: NSPoint(x: 14, y: y + 13))
            NSColor.labelColor.withAlphaComponent(isEnabled ? 1 : 0.3).setStroke()
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.menuFont(ofSize: 0),
            .foregroundColor: isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: 36, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        if window?.firstResponder === self {
            NSFocusRingPlacement.only.set()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
    }
}

@MainActor
private final class HUDHighlightButton: NSButton {
    override var isFlipped: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSBezierPath(rect: bounds).addClip()
        let shape = NSBezierPath(roundedRect: NSRect(x: -18, y: 0, width: 30, height: bounds.height), xRadius: 4, yRadius: 4)
        NSColor.labelColor.withAlphaComponent(isEnabled ? (state == .on ? 0.90 : 0.13) : (state == .on ? 0.18 : 0.05)).setFill()
        shape.fill()
        NSColor.labelColor.withAlphaComponent(isEnabled ? 0.25 : 0.08).setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
        if window?.firstResponder === self {
            NSFocusRingPlacement.only.set()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3).fill()
        }
    }
}
