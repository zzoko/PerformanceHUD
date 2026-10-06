import AppKit

@MainActor
final class HUDMiscMenuView: NSView {
    var onChange: ((HUDMiscOptions) -> Void)?
    private var options: HUDMiscOptions
    private var alignment: HUDAlignment
    private let master = HUDResourceMasterButton(title: "Misc", target: nil, action: nil)
    private let choices = NSSegmentedControl(labels: HUDMiscReading.allCases.map(\.title),
                                             trackingMode: .selectAny, target: nil, action: nil)

    init(options: HUDMiscOptions, alignment: HUDAlignment = .vertical) {
        self.options = options
        self.alignment = alignment
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 34))
        autoresizingMask = [.width]
        master.target = self; master.action = #selector(toggleCategory)
        master.setAccessibilityLabel("Show Misc")
        choices.font = .menuFont(ofSize: 0)
        choices.segmentStyle = .rounded
        choices.target = self; choices.action = #selector(toggleReading)
        choices.setAccessibilityLabel("Misc readings; select any combination")
        for view in [master, choices] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            master.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            master.widthAnchor.constraint(equalToConstant: HUDResourceMenuView.masterWidth),
            master.topAnchor.constraint(equalTo: topAnchor),
            master.bottomAnchor.constraint(equalTo: bottomAnchor),
            choices.leadingAnchor.constraint(equalTo: master.trailingAnchor, constant: 8),
            choices.centerYAnchor.constraint(equalTo: centerYAnchor),
            choices.widthAnchor.constraint(equalToConstant: ceil(choices.intrinsicContentSize.width)),
            choices.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])
        setFrameSize(NSSize(width: 8 + HUDResourceMenuView.masterWidth + 8
                           + ceil(choices.intrinsicContentSize.width) + 12, height: 34))
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
        choices.isEnabled = options.enabled && allowed
        for (index, reading) in HUDMiscReading.allCases.enumerated() {
            choices.setSelected(options.readings.contains(reading), forSegment: index)
        }
    }

    @objc private func toggleCategory() {
        guard alignment.allows(.misc) else { return }
        options.enabled = master.state == .on
        refresh(); onChange?(options)
    }

    @objc private func toggleReading() {
        guard alignment.allows(.misc), options.enabled else { return }
        options.readings = Set(HUDMiscReading.allCases.enumerated().compactMap {
            choices.isSelected(forSegment: $0.offset) ? $0.element : nil
        })
        onChange?(options)
    }
}
