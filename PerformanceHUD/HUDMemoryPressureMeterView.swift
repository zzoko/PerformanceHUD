import AppKit

@MainActor
final class HUDMemoryPressureMeterView: NSView {
    private(set) var currentLevel: MemoryPressureMonitor.Level?
    private var mode: HUDMemoryPressureMode = .meter
    private var scale: CGFloat = 1
    private var background: HUDBackground = .dark
    private var stacked = false
    private static let segmentThickness: CGFloat = 5

    var activeSegmentCount: Int { currentLevel.map { $0.rawValue + 1 } ?? 0 }
    override var intrinsicContentSize: NSSize {
        NSSize(width: (stacked ? 21.78 : 72.6) * scale,
               height: (stacked ? 3 * Self.segmentThickness + 4 : 12) * scale)
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Memory pressure")
        setAccessibilityHelp("One segment means normal, two warning, and three critical.")
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    func configure(mode: HUDMemoryPressureMode, scale: HUDScale, background: HUDBackground,
                   stacked: Bool = false) {
        self.mode = mode
        self.background = background
        if self.scale != CGFloat(scale.rawValue) || self.stacked != stacked {
            self.scale = CGFloat(scale.rawValue)
            self.stacked = stacked
            invalidateIntrinsicContentSize()
        }
        needsDisplay = true
    }

    func update(_ value: String) {
        currentLevel = MemoryPressureMonitor.Level(displayText: value)
        setAccessibilityValue(currentLevel.map { "\($0.displayText), \(activeSegmentCount) of 3 segments" } ?? "Unavailable")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard mode != .text, let currentLevel else { return }
        let neutral = HUDStyle.readingColor(background: background)
        let colors = [
            NSColor(srgbRed: 0.29, green: 0.90, blue: 0.46, alpha: 1),
            NSColor(srgbRed: 1, green: 0.85, blue: 0.24, alpha: 1),
            NSColor(srgbRed: 1, green: 0.39, blue: 0.36, alpha: 1)
        ]
        let gap = (stacked ? 2 : 3) * scale
        let width = stacked ? bounds.width : (bounds.width - 2 * gap) / 3
        let height = Self.segmentThickness * scale
        for index in 0..<3 {
            let isActive = index < activeSegmentCount
            let active = mode == .colorMeter ? colors[currentLevel.rawValue] : neutral
            // Inactive segments progress from lighter grey in the middle to
            // darker grey at the end. Active bars share the current state's colour.
            let inactiveAlpha: CGFloat = index == 2 ? (background == .light ? 0.22 : 0.10) : 0.16
            let activeAlpha: CGFloat = mode == .colorMeter ? 1 : 0.75
            (isActive ? active : neutral).withAlphaComponent(isActive ? activeAlpha : inactiveAlpha).setFill()
            let rect = NSRect(x: stacked ? 0 : CGFloat(index) * (width + gap),
                              y: stacked ? CGFloat(index) * (height + gap) : (bounds.height - height) / 2,
                              width: width, height: height)
            NSBezierPath(roundedRect: rect, xRadius: 2 * scale, yRadius: 2 * scale).fill()
        }
    }
}
