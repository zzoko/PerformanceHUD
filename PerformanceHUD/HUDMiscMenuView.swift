import AppKit

@MainActor
final class HUDMiscMenuView: HUDCategoryMenuView {
    var onChange: ((HUDMiscOptions) -> Void)?
    private var options: HUDMiscOptions
    private var alignment: HUDAlignment
    private let master = HUDResourceMasterButton(title: "Misc", target: nil, action: nil)
    private var choices: [HUDMiscPillButton] = []

    init(options: HUDMiscOptions, alignment: HUDAlignment = .vertical) {
        self.options = options
        self.alignment = alignment
        super.init()
        setAccessibilityLabel("Misc display options")
        master.target = self; master.action = #selector(toggleCategory)
        master.setAccessibilityLabel("Show Misc")
        setCategory(master)
        let pills = HUDMiscPillRow()
        for (index, reading) in HUDMiscReading.allCases.enumerated() {
            let button = HUDMiscPillButton(title: reading.title, target: self, action: #selector(toggleReading(_:)))
            button.tag = index
            button.setAccessibilityRole(.checkBox)
            button.setAccessibilityLabel("Show \(reading.title)")
            choices.append(button)
            pills.addSubview(button)
        }
        setRows([.init(reading: pills, fullWidth: true)])
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
        for (index, reading) in HUDMiscReading.allCases.enumerated() {
            choices[index].isEnabled = options.enabled && allowed
            choices[index].state = options.readings.contains(reading) ? .on : .off
        }
    }

    @objc private func toggleCategory() {
        guard alignment.allows(.misc) else { return }
        options.enabled = master.state == .on
        refresh(); onChange?(options)
    }

    @objc private func toggleReading(_ sender: NSButton) {
        guard alignment.allows(.misc), options.enabled,
              HUDMiscReading.allCases.indices.contains(sender.tag) else { return }
        let reading = HUDMiscReading.allCases[sender.tag]
        if sender.state == .on { options.readings.insert(reading) }
        else { options.readings.remove(reading) }
        refresh(); onChange?(options)
    }
}

@MainActor
private final class HUDMiscPillRow: NSView {
    override func layout() {
        super.layout()
        let spacing: CGFloat = 5
        let available = max(0, bounds.width - CGFloat(max(0, subviews.count - 1)) * spacing)
        let total = subviews.reduce(CGFloat(0)) { $0 + $1.intrinsicContentSize.width }
        guard total > 0 else { return }
        var x: CGFloat = 0
        for pill in subviews {
            let width = available * pill.intrinsicContentSize.width / total
            pill.frame = NSRect(x: x, y: (bounds.height - 22) / 2, width: width, height: 22)
            x += width + spacing
        }
    }
}

@MainActor
private final class HUDMiscPillButton: NSButton {
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
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let shape = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        NSColor.labelColor.withAlphaComponent(isEnabled ? (state == .on ? 0.16 : 0.025) : 0.03).setFill()
        shape.fill()
        NSColor.labelColor.withAlphaComponent(isEnabled ? (state == .on ? 0.3 : 0.17) : 0.08).setStroke()
        shape.lineWidth = 0.75
        shape.stroke()
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

@MainActor
final class HUDDeviceInfoMenuView: HUDCategoryMenuView {
    var onChange: ((HUDDeviceInfoOptions) -> Void)?
    private var options: HUDDeviceInfoOptions
    private var allowed: Bool
    private let master = HUDResourceMasterButton(title: "Mac", target: nil, action: nil)
    private let reading = NSTextField(labelWithString: "Chip")
    private let chipMode = NSSegmentedControl(labels: HUDChipDisplayMode.allCases.map(\.title),
        trackingMode: .selectOne, target: nil, action: nil)
    private let os = HUDReadingCheckbox(title: "OS", supportsEmphasis: false)

    init(options: HUDDeviceInfoOptions, enabled: Bool) {
        self.options = options
        allowed = enabled
        super.init()
        setAccessibilityLabel("Mac display options")
        master.target = self; master.action = #selector(changed)
        master.setAccessibilityLabel("Show Mac information")
        reading.font = .menuFont(ofSize: 0)
        chipMode.target = self; chipMode.action = #selector(modeChanged)
        chipMode.setAccessibilityLabel("Chip display mode")
        os.target = self; os.action = #selector(osChanged)
        os.setControlAccessibilityLabel("Show macOS version")
        setCategory(master)
        setRows([.init(reading: reading, mode: chipMode), .init(reading: os)])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("Use init(options:enabled:)") }
    func update(options: HUDDeviceInfoOptions, enabled: Bool) {
        self.options = options
        allowed = enabled
        refresh()
    }
    private func refresh() {
        master.isEnabled = allowed
        master.state = options.enabled && allowed ? .on : .off
        let active = allowed && options.enabled
        reading.textColor = active ? .labelColor : .disabledControlTextColor
        chipMode.isEnabled = active
        chipMode.selectedSegment = HUDChipDisplayMode.allCases.firstIndex(of: options.chipMode) ?? 0
        os.isEnabled = active
        os.state = options.os ? .on : .off
    }
    @objc private func changed() {
        guard allowed else { return }
        options.enabled = master.state == .on
        refresh(); onChange?(options)
    }
    @objc private func modeChanged() {
        guard allowed, options.enabled, HUDChipDisplayMode.allCases.indices.contains(chipMode.selectedSegment) else { return }
        options.chipMode = HUDChipDisplayMode.allCases[chipMode.selectedSegment]
        refresh(); onChange?(options)
    }
    @objc private func osChanged() {
        guard allowed, options.enabled else { return }
        options.os = os.state == .on
        refresh(); onChange?(options)
    }
}
