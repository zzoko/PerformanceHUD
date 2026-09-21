import AppKit

@MainActor
final class HUDResourceMenuView: NSView {
    var onChange: ((HUDResourceOptions) -> Void)?
    private let group: HUDResourceGroup
    private var options: HUDResourceOptions
    private var controls: [Int: NSButton] = [:]

    init(group: HUDResourceGroup, options: HUDResourceOptions) {
        self.group = group
        self.options = options
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 34))

        autoresizingMask = [.width]

        // Keep the master in the normal menu checkmark/title columns. The inset
        // container makes its subordinate choices read as one related group.
        let master = HUDResourceMasterButton(title: group.title, target: self, action: #selector(changed(_:)))
        master.tag = 0
        master.toolTip = "Show or hide this group while keeping its individual choices."
        master.setAccessibilityLabel("Show \(group.title)")
        master.translatesAutoresizingMaskIntoConstraints = false
        addSubview(master)
        controls[0] = master

        let choices = HUDResourceChoicesView()
        choices.translatesAutoresizingMaskIntoConstraints = false
        choices.setAccessibilityRole(.group)
        choices.setAccessibilityLabel("\(group.title) display options")
        addSubview(choices)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        choices.addSubview(stack)
        for (tag, title, width) in [(1, "Temperature", 112.0),
                                     (2, "Total Use", 92.0), (3, "Only focused app", 145.0)] {
            if tag == 1 && !group.supportsTemperature {
                let spacer = NSView()
                spacer.widthAnchor.constraint(equalToConstant: width).isActive = true
                stack.addArrangedSubview(spacer)
                continue
            }
            let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(changed(_:)))
            button.font = .menuFont(ofSize: 0)
            button.tag = tag
            button.setAccessibilityLabel("\(group.title) \(title)")
            button.widthAnchor.constraint(equalToConstant: width).isActive = true
            if tag == 1 {
                button.toolTip = group == .cpu
                    ? "Average of identified CPU temperature sensors for this chip, in °C. Sensor coverage varies by model; unavailable readings stay blank. Not a per-app reading."
                    : "Average of available GPU temperature sensors, in °C. Not a per-app reading."
            } else if tag == 2 {
                button.toolTip = group == .ram
                    ? "Shows system RAM usage, physical memory used, swap, and memory pressure."
                    : "Shows total \(group.title) usage across the whole system."
            } else if tag == 3 {
                button.toolTip = "Shows \(group.title) usage for the focused app’s tracked process. Helper processes may not be included."
            }
            controls[tag] = button
            stack.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            master.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            master.widthAnchor.constraint(equalToConstant: 68),
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
        setFrameSize(NSSize(width: 8 + 68 + 8 + 16 + 112 + 92 + 145 + 24 + 12, height: 34))
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Use init(group:options:)") }

    @objc private func changed(_ sender: NSButton) {
        let value = sender.state == .on
        switch sender.tag {
        case 0: options.enabled = value
        case 1: options.temperature = value
        case 2: options.totalUse = value
        case 3: options.focusedApp = value
        default: return
        }
        refresh()
        onChange?(options)
    }

    private func refresh() {
        for (tag, value) in [(0, options.enabled), (1, options.temperature),
                             (2, options.totalUse), (3, options.focusedApp)] {
            controls[tag]?.state = value ? .on : .off
            controls[tag]?.isEnabled = tag == 0 || options.enabled
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
