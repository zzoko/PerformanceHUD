import AppKit

enum HUDFPSDisplayMode: String, CaseIterable {
    case value, history, both
    var title: String { rawValue.capitalized }
}

struct HUDFPSOptions {
    var enabled: Bool
    var mode: HUDFPSDisplayMode

    func visibleMetrics(alignment: HUDAlignment) -> Set<HUDMetric> {
        guard enabled else { return [] }
        // Horizontal has no graph; retain the selected vertical mode separately.
        guard alignment == .vertical else { return [.fps] }
        switch mode {
        case .value: return [.fps]
        case .history: return [.fpsGraph]
        case .both: return [.fps, .fpsGraph]
        }
    }
}

@MainActor
final class HUDFPSMenuView: NSView {
    var onDynamicChange: ((Bool) -> Void)?
    private var dynamic: Bool
    private let presentation = NSSegmentedControl(labels: ["Static", "Dynamic"],
        trackingMode: .selectOne, target: nil, action: nil)
    var onChange: ((HUDFPSOptions) -> Void)?
    private var options: HUDFPSOptions
    private var alignment: HUDAlignment
    private let master = HUDResourceMasterButton(title: "FPS", target: nil, action: nil)
    private let control = NSSegmentedControl(labels: HUDFPSDisplayMode.allCases.map(\.title),
        trackingMode: .selectOne, target: nil, action: nil)

    init(options: HUDFPSOptions, alignment: HUDAlignment, dynamic: Bool? = nil) {
        self.options = options
        self.alignment = alignment
        self.dynamic = dynamic ?? HUDPreferences.dynamicFPS
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 34))
        autoresizingMask = [.width]
        master.target = self
        master.action = #selector(toggleCategory)
        master.setAccessibilityLabel("Show FPS")
        control.font = .menuFont(ofSize: 0)
        control.segmentStyle = .rounded
        control.target = self
        control.action = #selector(modeChanged)
        control.setAccessibilityLabel("FPS display mode")
        presentation.font = .menuFont(ofSize: 0)
        presentation.segmentStyle = .rounded
        presentation.target = self
        presentation.action = #selector(presentationChanged)
        presentation.setAccessibilityLabel("FPS presentation")
        for view in [master, control, presentation] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            master.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            master.widthAnchor.constraint(equalToConstant: HUDResourceMenuView.masterWidth),
            master.topAnchor.constraint(equalTo: topAnchor),
            master.bottomAnchor.constraint(equalTo: bottomAnchor),
            control.leadingAnchor.constraint(equalTo: master.trailingAnchor, constant: 8),
            control.centerYAnchor.constraint(equalTo: centerYAnchor),
            control.widthAnchor.constraint(equalToConstant: HUDResourceMenuView.readingsChoicesWidth),
            // Match the Usage group’s leading edge in the resource rows below.
            presentation.leadingAnchor.constraint(equalTo: control.trailingAnchor, constant: 4),
            presentation.centerYAnchor.constraint(equalTo: centerYAnchor),
            presentation.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])
        setFrameSize(NSSize(width: 8 + HUDResourceMenuView.masterWidth + 8
            + HUDResourceMenuView.readingsChoicesWidth + 4 + presentation.intrinsicContentSize.width + 12, height: 34))
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Use init(options:alignment:)") }

    func update(options: HUDFPSOptions, alignment: HUDAlignment, dynamic: Bool? = nil) {
        self.options = options
        self.alignment = alignment
        self.dynamic = dynamic ?? HUDPreferences.dynamicFPS
        refresh()
    }

    private func refresh() {
        presentation.selectedSegment = dynamic ? 1 : 0
        presentation.isEnabled = options.enabled
        master.state = options.enabled ? .on : .off
        control.selectedSegment = alignment == .horizontal ? 0
            : HUDFPSDisplayMode.allCases.firstIndex(of: options.mode)!
        control.isEnabled = options.enabled
        control.setEnabled(options.enabled, forSegment: 0)
        for index in [1, 2] { control.setEnabled(options.enabled && alignment == .vertical, forSegment: index) }
    }

    @objc private func presentationChanged() {
        guard presentation.isEnabled else { refresh(); return }
        dynamic = presentation.selectedSegment == 1
        refresh()
        onDynamicChange?(dynamic)
    }

    @objc private func toggleCategory() {
        options.enabled = master.state == .on
        refresh()
        onChange?(options)
    }

    @objc private func modeChanged() {
        guard options.enabled, alignment == .vertical,
              HUDFPSDisplayMode.allCases.indices.contains(control.selectedSegment) else { refresh(); return }
        options.mode = HUDFPSDisplayMode.allCases[control.selectedSegment]
        refresh()
        onChange?(options)
    }
}
