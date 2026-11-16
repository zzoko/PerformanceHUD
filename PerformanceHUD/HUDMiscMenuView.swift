import AppKit

@MainActor
final class HUDMiscMenuView: HUDCategoryMenuView {
    var onChange: ((HUDMiscOptions) -> Void)?
    private var options: HUDMiscOptions
    private var alignment: HUDAlignment
    private let master = HUDResourceMasterButton(title: "Misc", target: nil, action: nil)
    private var choices: [HUDMiscPillButton] = []
    private let chip = HUDMiscPillButton(title: "Chip", target: nil, action: nil)
    private let os = HUDMiscPillButton(title: "OS", target: nil, action: nil)
    private let chipModes = HUDChipDisplayMode.selectable.map {
        HUDMiscPillButton(title: $0.title, target: nil, action: nil)
    }

    init(options: HUDMiscOptions, alignment: HUDAlignment = .vertical) {
        self.options = options
        self.alignment = alignment
        super.init()
        setAccessibilityLabel("Misc display options")
        master.target = self; master.action = #selector(toggleCategory)
        master.setAccessibilityLabel("Show Misc")
        setCategory(master)
        let pills = HUDMiscPillRow()
        for (index, reading) in HUDMiscReading.liveReadings.enumerated() {
            let button = HUDMiscPillButton(title: reading.title, target: self, action: #selector(toggleReading(_:)))
            button.tag = index
            button.setAccessibilityRole(.checkBox)
            button.setAccessibilityLabel("Show \(reading.title)")
            choices.append(button)
            pills.addSubview(button)
        }
        chip.target = self; chip.action = #selector(toggleChip)
        chip.setAccessibilityRole(.checkBox)
        chip.setAccessibilityLabel("Show chip information")
        os.target = self; os.action = #selector(toggleOS)
        os.setAccessibilityRole(.checkBox)
        os.setAccessibilityLabel("Show macOS version")
        for (index, button) in chipModes.enumerated() {
            button.target = self; button.action = #selector(changeChipMode(_:))
            button.tag = index
            button.setAccessibilityRole(.radioButton)
            button.setAccessibilityLabel("Chip display mode: \(button.title)")
        }
        let systemPills = HUDMiscPillRow()
        systemPills.stretchesToFill = false
        systemPills.addSubview(os)
        systemPills.addSubview(HUDMiscChipPill(chip: chip, modes: chipModes))
        setRows([.init(reading: pills, fullWidth: true),
                 .init(reading: systemPills, fullWidth: true)])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Use init(options:)") }

    func update(alignment: HUDAlignment) {
        self.alignment = alignment
        refresh()
    }

    private func refresh() {
        let allowed = alignment.allows(.misc)
        master.isEnabled = allowed
        master.state = options.enabled && allowed ? .on : .off
        for (index, reading) in HUDMiscReading.liveReadings.enumerated() {
            choices[index].isEnabled = options.enabled && allowed
            choices[index].state = options.readings.contains(reading) ? .on : .off
        }
        chip.isEnabled = options.enabled && allowed
        os.isEnabled = options.enabled && allowed
        chip.state = options.readings.contains(.chip) ? .on : .off
        os.state = options.readings.contains(.os) ? .on : .off
        for (index, button) in chipModes.enumerated() {
            button.isEnabled = chip.isEnabled && chip.state == .on
            button.state = HUDChipDisplayMode.selectable[index] == options.chipMode ? .on : .off
        }
        chip.superview?.needsDisplay = true
    }

    @objc private func toggleChip() {
        setReading(.chip, selected: chip.state == .on)
    }

    @objc private func toggleOS() {
        setReading(.os, selected: os.state == .on)
    }

    private func setReading(_ reading: HUDMiscReading, selected: Bool) {
        guard alignment.allows(.misc), options.enabled else { return }
        if selected { options.readings.insert(reading) }
        else { options.readings.remove(reading) }
        refresh(); onChange?(options)
    }

    @objc private func changeChipMode(_ sender: NSButton) {
        guard alignment.allows(.misc), options.enabled, options.readings.contains(.chip),
              HUDChipDisplayMode.selectable.indices.contains(sender.tag) else { return }
        options.chipMode = HUDChipDisplayMode.selectable[sender.tag]
        refresh(); onChange?(options)
    }

    @objc private func toggleCategory() {
        guard alignment.allows(.misc) else { return }
        options.enabled = master.state == .on
        refresh(); onChange?(options)
    }

    @objc private func toggleReading(_ sender: NSButton) {
        guard alignment.allows(.misc), options.enabled,
              HUDMiscReading.liveReadings.indices.contains(sender.tag) else { return }
        let reading = HUDMiscReading.liveReadings[sender.tag]
        if sender.state == .on { options.readings.insert(reading) }
        else { options.readings.remove(reading) }
        refresh(); onChange?(options)
    }
}

@MainActor
private final class HUDMiscPillRow: NSView {
    var stretchesToFill = true

    override func layout() {
        super.layout()
        let spacing: CGFloat = 5
        let available = max(0, bounds.width - CGFloat(max(0, subviews.count - 1)) * spacing)
        let total = subviews.reduce(CGFloat(0)) { $0 + $1.intrinsicContentSize.width }
        guard total > 0 else { return }
        var x: CGFloat = 0
        for pill in subviews {
            let width = (stretchesToFill ? available / total : 1) * pill.intrinsicContentSize.width
            let rect = NSRect(x: x, y: (bounds.height - 22) / 2, width: width, height: 22)
            pill.frame = rect
            x += width + spacing
        }
    }
}

/// One shared capsule connects the visibility button and its two display modes.
@MainActor
private final class HUDMiscChipPill: NSView {
    private let chip: HUDMiscPillButton
    private let modes: [HUDMiscPillButton]

    init(chip: HUDMiscPillButton, modes: [HUDMiscPillButton]) {
        self.chip = chip
        self.modes = modes
        super.init(frame: .zero)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Chip information")
        chip.presentation = .labelOnly
        addSubview(chip)
        for button in modes {
            button.presentation = .selection
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) { fatalError("Use init(chip:modes:)") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: chip.intrinsicContentSize.width + 9
            + modes.reduce(CGFloat(0)) { $0 + $1.intrinsicContentSize.width }, height: 22)
    }

    override func layout() {
        super.layout()
        let chipWidth = chip.intrinsicContentSize.width
        chip.frame = NSRect(x: 0, y: 0, width: chipWidth, height: bounds.height)
        var x = chipWidth + 7
        for button in modes {
            let width = button.intrinsicContentSize.width
            button.frame = NSRect(x: x, y: 2, width: width, height: bounds.height - 4)
            x += width
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        HUDMiscPillButton.drawCapsule(in: bounds, enabled: chip.isEnabled, selected: chip.state == .on)
        NSColor.labelColor.withAlphaComponent(chip.isEnabled ? 0.17 : 0.08).setFill()
        NSRect(x: chip.frame.maxX + 2.5, y: 5, width: 0.75, height: max(0, bounds.height - 10)).fill()
    }
}

@MainActor
private final class HUDMiscPillButton: NSButton {
    enum Presentation { case standalone, labelOnly, selection }
    var presentation = Presentation.standalone
    override var state: NSControl.StateValue { didSet { needsDisplay = true } }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil((title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width) + 18,
               height: 22)
    }
    convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        setButtonType(.toggle)
        isBordered = false
    }
    static func drawCapsule(in bounds: NSRect, enabled: Bool, selected: Bool) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let shape = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        NSColor.labelColor.withAlphaComponent(enabled ? (selected ? 0.16 : 0.025) : 0.03).setFill()
        shape.fill()
        NSColor.labelColor.withAlphaComponent(enabled ? (selected ? 0.3 : 0.17) : 0.08).setStroke()
        shape.lineWidth = 0.75
        shape.stroke()
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let shape = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        if presentation == .standalone {
            Self.drawCapsule(in: bounds, enabled: isEnabled, selected: state == .on)
        } else if presentation == .selection && state == .on {
            NSColor.labelColor.withAlphaComponent(isEnabled ? 0.16 : 0.06).setFill()
            shape.fill()
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                             y: (bounds.height - size.height) / 2), withAttributes: attributes)
        if window?.firstResponder === self {
            NSFocusRingPlacement.only.set()
            shape.fill()
        }
    }
}
