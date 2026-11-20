import AppKit

/// Shared columns for category, reading, mode, emphasis, and menu-bar visibility.
@MainActor
enum HUDCategoryLayout {
    static let categoryLeading: CGFloat = 8
    static let categoryWidth: CGFloat = 116
    static let categoryLabelInset: CGFloat = 38
    static let readingLeading: CGFloat = 136
    static let readingWidth: CGFloat = 148
    static let readingLabelInset: CGFloat = 24
    static let modeLeading: CGFloat = 296
    static var modeWidth: CGFloat {
        let control = NSSegmentedControl(labels: ["Vertical", "Horizontal", "Both"],
                                         trackingMode: .selectOne, target: nil, action: nil)
        control.font = .menuFont(ofSize: 0)
        control.segmentStyle = .rounded
        return max(230, ceil(control.intrinsicContentSize.width))
    }
    static var emphasisLeading: CGFloat { modeLeading + modeWidth + 12 }
    static var menuBarLeading: CGFloat { emphasisLeading + 30 }
    static var width: CGFloat { menuBarLeading + 24 + 14 }
    static let rowHeight: CGFloat = 28
    static let modeHeight: CGFloat = 24
    static let padding: CGFloat = 6
    static let pinConnectionHeight: CGFloat = 4
}

@MainActor
struct HUDCategoryMenuRow {
    let reading: NSView
    var mode: NSView? = nil
    var emphasis: NSView? = nil
    var menuBar: HUDMenuBarButton? = nil
    var fullWidth = false

    var emphasisView: NSView? { emphasis ?? (reading as? HUDReadingCheckbox)?.emphasisControl }
    var height: CGFloat {
        HUDCategoryLayout.rowHeight + (menuBar != nil && mode is NSSegmentedControl ? HUDCategoryLayout.pinConnectionHeight : 0)
    }
}

@MainActor
class HUDCategoryMenuView: NSView {
    private var category: NSView?
    private var rows: [HUDCategoryMenuRow] = []
    private var menuBarButtons: [HUDMenuBarReading: HUDMenuBarButton] = [:]
    var onHeightChange: (() -> Void)?
    var onMenuBarChange: (() -> Void)?
    var shouldAllowMenuBarSelection: ((Set<HUDMenuBarReading>) -> Bool)?
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: HUDCategoryLayout.width, height: 40))
        autoresizingMask = [.width]
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    func makeMenuBarButton(for reading: HUDMenuBarReading, title: String) -> HUDMenuBarButton {
        if let button = menuBarButtons[reading] { return button }
        let button = HUDMenuBarButton(reading: reading)
        button.setAccessibilityLabel("Show \(title) in menu bar")
        button.state = isMenuBarSelected(reading) ? .on : .off
        button.onChange = { [weak self] selected in
            guard let self else { return }
            var options = HUDPreferences.menuBarOptions
            if selected {
                options.readings.insert(reading)
                guard shouldAllowMenuBarSelection?(options.readings) != false else {
                    refreshMenuBarSelections()
                    return
                }
            } else { options.readings.remove(reading) }
            HUDPreferences.menuBarOptions = options
            refreshMenuBarSelections()
            onMenuBarChange?()
        }
        menuBarButtons[reading] = button
        return button
    }

    func isMenuBarSelected(_ reading: HUDMenuBarReading) -> Bool {
        HUDPreferences.menuBarOptions.readings.contains(reading)
    }

    func refreshMenuBarSelections() {
        for (reading, button) in menuBarButtons {
            button.state = isMenuBarSelected(reading) ? .on : .off
        }
    }

    func setCategory(_ view: NSView) {
        category?.removeFromSuperview()
        category = view
        addSubview(view)
    }

    func setRows(_ newRows: [HUDCategoryMenuRow]) {
        for row in newRows {
            if let control = row.mode as? NSSegmentedControl {
                // Normalize native bezel sizing before applying the shared row frame.
                control.controlSize = .regular
                control.font = .menuFont(ofSize: 0)
                control.segmentStyle = .rounded
                if let pin = row.menuBar {
                    control.segmentDistribution = .fillEqually
                    pin.modeControl = control
                }
                control.sizeToFit()
            }
        }
        let oldViews = rows.flatMap { [$0.reading, $0.mode, $0.emphasisView, $0.menuBar].compactMap { $0 } }
        let newViews = newRows.flatMap { [$0.reading, $0.mode, $0.emphasisView, $0.menuBar].compactMap { $0 } }
        if oldViews.map(ObjectIdentifier.init) != newViews.map(ObjectIdentifier.init) {
            oldViews.forEach { $0.removeFromSuperview() }
            newViews.forEach { addSubview($0) }
        }
        rows = newRows
        let height = rows.reduce(2 * HUDCategoryLayout.padding) { $0 + $1.height }
        let changed = frame.height != height
        setFrameSize(NSSize(width: frame.width, height: height))
        needsLayout = true
        needsDisplay = true
        if changed { onHeightChange?() }
    }

    override func layout() {
        super.layout()
        let grid = HUDCategoryLayout.self
        category?.frame = NSRect(x: grid.categoryLeading, y: grid.padding,
                                 width: grid.categoryWidth, height: grid.rowHeight)
        let fullWidthEnd = rows.contains { $0.emphasisView != nil } ? grid.modeLeading + grid.modeWidth : bounds.width - 14
        var y = grid.padding
        for row in rows {
            let label = row.reading as? NSTextField
            let inset: CGFloat = label == nil ? 0 : grid.readingLabelInset
            let height = label?.intrinsicContentSize.height ?? (grid.rowHeight - 4)
            row.reading.frame = NSRect(x: grid.readingLeading + inset, y: y + (grid.rowHeight - height) / 2,
                width: (row.fullWidth ? fullWidthEnd - grid.readingLeading : grid.readingWidth) - inset,
                height: height)
            if let mode = row.mode {
                // Apply native alignment insets so every selector's visible bezel shares a column.
                mode.frame = mode.frame(forAlignmentRect: NSRect(x: grid.modeLeading,
                    y: y + (grid.rowHeight - grid.modeHeight) / 2,
                    width: (mode as? HUDReadingCheckbox)?.intrinsicContentSize.width ?? grid.modeWidth,
                    height: grid.modeHeight))
            }
            row.emphasisView?.frame = NSRect(x: grid.emphasisLeading, y: y + 3, width: 22, height: 22)
            row.menuBar?.frame = NSRect(x: grid.menuBarLeading, y: y + 3, width: 22, height: 22)
            y += row.height
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.065).setFill()
        NSRect(x: 30, y: bounds.height - 0.5, width: bounds.width - 44, height: 0.5).fill()
        if let first = rows.first(where: { $0.menuBar != nil })?.menuBar,
           let last = rows.last(where: { $0.menuBar != nil })?.menuBar {
            let grid = HUDCategoryLayout.self
            let x = (grid.emphasisLeading + 22 + grid.menuBarLeading) / 2 - 0.25
            NSRect(x: x, y: first.frame.minY, width: 0.5, height: last.frame.maxY - first.frame.minY).fill()
        }
        for row in rows {
            guard let pin = row.menuBar, let mode = pin.modeControl else { continue }
            drawPinConnection(from: mode, to: pin)
        }
    }

    private func drawPinConnection(from mode: NSSegmentedControl, to pin: HUDMenuBarButton) {
        let supported = Set((0..<mode.segmentCount).compactMap { pin.reading.outputSegment(for: $0) }).sorted()
        guard let first = supported.first else { return }
        let rect = mode.alignmentRect(forFrame: mode.frame)
        func center(_ segment: Int) -> CGFloat {
            rect.minX + (CGFloat(segment) + 0.5) * rect.width / CGFloat(mode.segmentCount)
        }
        // Run below the controls so the line passes the B button without touching it.
        let railY = rect.maxY + HUDCategoryLayout.pinConnectionHeight + 0.5
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center(first), y: railY))
        path.line(to: NSPoint(x: pin.frame.midX, y: railY))
        path.line(to: NSPoint(x: pin.frame.midX, y: pin.frame.maxY))
        for segment in supported {
            path.move(to: NSPoint(x: center(segment), y: railY))
            path.line(to: NSPoint(x: center(segment), y: rect.maxY - 1))
        }
        path.lineWidth = 1
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.labelColor.withAlphaComponent(pin.state == .on ? 0.55 : 0.36).setStroke()
        path.stroke()
        if let active = pin.reading.outputSegment(for: mode.selectedSegment) {
            NSColor.labelColor.withAlphaComponent(pin.state == .on ? 0.9 : 0.7).setFill()
            let dot = NSRect(x: center(active) - 2, y: rect.maxY - 0.5, width: 4, height: 4)
            NSBezierPath(ovalIn: dot).fill()
        }
    }
}

/// Uses the emphasis button's neutral treatment for the independent menu-bar output.
@MainActor
final class HUDMenuBarButton: NSButton {
    let reading: HUDMenuBarReading
    weak var modeControl: NSSegmentedControl?
    var onChange: ((Bool) -> Void)?
    override var intrinsicContentSize: NSSize { NSSize(width: 22, height: 22) }
    override var state: NSControl.StateValue { didSet { needsDisplay = true } }
    override var isEnabled: Bool { didSet { needsDisplay = true } }

    init(reading: HUDMenuBarReading) {
        self.reading = reading
        super.init(frame: .zero)
        title = ""
        setButtonType(.toggle)
        isBordered = false
        target = self
        action = #selector(changed)
        setAccessibilityRole(.checkBox)
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    override func accessibilityHelp() -> String? {
        guard let mode = modeControl else { return super.accessibilityHelp() }
        guard let output = reading.outputSegment(for: mode.selectedSegment),
              let label = mode.label(forSegment: output) else { return "The current setting hides this reading." }
        return "Menu bar format: \(label)."
    }

    @objc private func changed() { onChange?(state == .on) }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        let selected = state == .on
        NSColor.labelColor.withAlphaComponent(isEnabled ? (selected ? 0.18 : 0.025) : 0.025).setFill()
        shape.fill()
        NSColor.labelColor.withAlphaComponent(isEnabled ? (selected ? 0.32 : 0.15) : 0.07).setStroke()
        shape.lineWidth = 0.75
        shape.stroke()
        let color: NSColor = !isEnabled ? .disabledControlTextColor : selected ? .labelColor : .secondaryLabelColor
        let screen = NSRect(x: (bounds.width - 13) / 2, y: (bounds.height - 10) / 2, width: 13, height: 10)
        let outline = NSBezierPath(roundedRect: screen, xRadius: 1.5, yRadius: 1.5)
        color.setStroke()
        outline.lineWidth = 1
        outline.stroke()
        color.setFill()
        NSRect(x: screen.minX + 1, y: screen.maxY - 3, width: screen.width - 2, height: 2).fill()
        if window?.firstResponder === self {
            NSFocusRingPlacement.only.set()
            shape.fill()
        }
    }
}

/// Keep general settings and actions reachable when the category list exceeds the display.
@MainActor
final class HUDCategoryListView: NSScrollView {
    private let content = HUDCategoryDocumentView()
    private let categories: [HUDCategoryMenuView]
    private let bottomFade = CAGradientLayer()
    private var maximumHeight: CGFloat = 440

    init(categories: [HUDCategoryMenuView]) {
        self.categories = categories
        super.init(frame: NSRect(x: 0, y: 0, width: HUDCategoryLayout.width, height: 440))
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .none
        wantsLayer = true
        bottomFade.colors = [NSColor.black.cgColor, NSColor.black.withAlphaComponent(0.15).cgColor]
        bottomFade.endPoint = CGPoint(x: 0.5, y: 1)
        documentView = content
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(updateBottomFade),
            name: NSView.boundsDidChangeNotification, object: contentView)
        for category in categories {
            content.addSubview(category)
            category.onHeightChange = { [weak self] in self?.arrangeCategories() }
        }
        arrangeCategories()
    }

    required init?(coder: NSCoder) { fatalError("Use init(categories:)") }

    @objc private func updateBottomFade() {
        guard let layer else { return }
        let remaining = content.bounds.maxY - documentVisibleRect.maxY
        guard remaining > 0, bounds.height > 0 else {
            layer.mask = nil
            return
        }
        let fadeHeight = min(16, remaining)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bottomFade.frame = layer.bounds
        bottomFade.startPoint = CGPoint(x: 0.5, y: 1 - fadeHeight / bounds.height)
        if layer.mask !== bottomFade { layer.mask = bottomFade }
        CATransaction.commit()
    }

    func fit(availableHeight: CGFloat) {
        maximumHeight = max(160, floor(availableHeight))
        arrangeCategories()
    }

    private func arrangeCategories() {
        let y = categories.reduce(CGFloat(0)) { $0 + $1.frame.height }
        content.setFrameSize(NSSize(width: HUDCategoryLayout.width, height: y))
        content.needsLayout = true
        content.layoutSubtreeIfNeeded()
        setFrameSize(NSSize(width: HUDCategoryLayout.width, height: min(y, maximumHeight)))
        contentView.scroll(to: contentView.constrainBoundsRect(contentView.bounds).origin)
        reflectScrolledClipView(contentView)
        updateBottomFade()
    }
}

@MainActor
private final class HUDCategoryDocumentView: NSView {
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        var y: CGFloat = 0
        for category in subviews {
            category.frame = NSRect(x: 0, y: y, width: bounds.width, height: category.frame.height)
            y += category.frame.height
        }
    }
}

@MainActor
final class HUDEmphasisButton: NSButton {
    override var intrinsicContentSize: NSSize { NSSize(width: 22, height: 22) }
    override var state: NSControl.StateValue { didSet { needsDisplay = true } }
    override var isEnabled: Bool { didSet { needsDisplay = true } }

    init() {
        super.init(frame: .zero)
        title = "B"
        setButtonType(.toggle)
        isBordered = false
        setAccessibilityRole(.checkBox)
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        let selected = state == .on
        NSColor.labelColor.withAlphaComponent(isEnabled ? (selected ? 0.18 : 0.025) : 0.025).setFill()
        shape.fill()
        NSColor.labelColor.withAlphaComponent(isEnabled ? (selected ? 0.32 : 0.15) : 0.07).setStroke()
        shape.lineWidth = 0.75
        shape.stroke()
        let color: NSColor = !isEnabled ? .disabledControlTextColor : selected ? .labelColor : .secondaryLabelColor
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: color
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
final class HUDReadingCheckbox: NSButton {
    private let visibility = HUDVisibilityButton(checkboxWithTitle: "", target: nil, action: nil)
    private let highlight = HUDEmphasisButton()
    private let supportsEmphasis: Bool
    var emphasisControl: NSButton? { supportsEmphasis ? highlight : nil }
    var onHighlight: (() -> Void)?
    var emphasized = false { didSet { updateControls() } }
    var highlightAvailable = true { didSet { updateControls() } }
    var menuBarSelected = false { didSet { updateControls() } }

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
        visibility.font = .menuFont(ofSize: 0)
        visibility.target = self
        visibility.action = #selector(toggleVisibility)
        highlight.target = self
        highlight.action = #selector(toggleHighlight)
        addSubview(visibility)
        setControlAccessibilityLabel(title)
        updateControls()
    }

    required init?(coder: NSCoder) { fatalError("Use init(title:supportsEmphasis:)") }
    override var acceptsFirstResponder: Bool { false }
    override var intrinsicContentSize: NSSize {
        NSSize(width: 24 + ceil((title as NSString).size(withAttributes: [.font: visibility.font!]).width), height: 22)
    }
    override func draw(_ dirtyRect: NSRect) {}
    override func layout() { super.layout(); visibility.frame = bounds }
    func setControlAccessibilityLabel(_ label: String) {
        visibility.setAccessibilityLabel(label)
        highlight.setAccessibilityLabel("Emphasize \(label)")
    }
    private func updateControls() {
        visibility.state = state
        visibility.isEnabled = isEnabled
        highlight.state = emphasized ? .on : .off
        highlight.isEnabled = ((isEnabled && state == .on) || menuBarSelected) && highlightAvailable
        visibility.needsDisplay = true
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
    override func draw(_ dirtyRect: NSRect) {
        let y = (bounds.height - 18) / 2
        let shape = NSBezierPath(roundedRect: NSRect(x: 0.5, y: y + 0.5, width: 17, height: 17), xRadius: 4, yRadius: 4)
        NSColor.labelColor.withAlphaComponent(isEnabled ? (state == .on ? 0.24 : 0.035) : 0.035).setFill()
        shape.fill()
        NSColor.labelColor.withAlphaComponent(isEnabled ? 0.23 : 0.08).setStroke()
        shape.lineWidth = 0.75
        shape.stroke()
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
        (title as NSString).draw(at: NSPoint(x: 24, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        if window?.firstResponder === self {
            NSFocusRingPlacement.only.set()
            shape.fill()
        }
    }
}
