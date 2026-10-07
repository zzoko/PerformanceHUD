import AppKit

/// Shared columns for category, reading, mode, and emphasis.
@MainActor
enum HUDCategoryLayout {
    static let categoryLeading: CGFloat = 8
    static let categoryWidth: CGFloat = 116
    static let readingLeading: CGFloat = 136
    static let readingWidth: CGFloat = 148
    static let modeLeading: CGFloat = 296
    static var modeWidth: CGFloat {
        let control = NSSegmentedControl(labels: ["Vertical", "Horizontal", "Both"],
                                         trackingMode: .selectOne, target: nil, action: nil)
        control.font = .menuFont(ofSize: 0)
        control.segmentStyle = .rounded
        return max(230, ceil(control.intrinsicContentSize.width))
    }
    static var emphasisLeading: CGFloat { modeLeading + modeWidth + 12 }
    static var width: CGFloat { emphasisLeading + 24 + 14 }
    static let rowHeight: CGFloat = 28
    static let padding: CGFloat = 6
}

@MainActor
struct HUDCategoryMenuRow {
    let reading: NSView
    var mode: NSView? = nil
    var emphasis: NSView? = nil
    var fullWidth = false

    var emphasisView: NSView? { emphasis ?? (reading as? HUDReadingCheckbox)?.emphasisControl }
}

@MainActor
class HUDCategoryMenuView: NSView {
    private var category: NSView?
    private var rows: [HUDCategoryMenuRow] = []
    var onHeightChange: (() -> Void)?
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: HUDCategoryLayout.width, height: 40))
        autoresizingMask = [.width]
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    func setCategory(_ view: NSView) {
        category?.removeFromSuperview()
        category = view
        addSubview(view)
    }

    func setRows(_ newRows: [HUDCategoryMenuRow]) {
        let oldViews = rows.flatMap { [$0.reading, $0.mode, $0.emphasisView].compactMap { $0 } }
        let newViews = newRows.flatMap { [$0.reading, $0.mode, $0.emphasisView].compactMap { $0 } }
        if oldViews.map(ObjectIdentifier.init) != newViews.map(ObjectIdentifier.init) {
            oldViews.forEach { $0.removeFromSuperview() }
            newViews.forEach { addSubview($0) }
        }
        rows = newRows
        let height = CGFloat(rows.count) * HUDCategoryLayout.rowHeight + 2 * HUDCategoryLayout.padding
        let changed = frame.height != height
        setFrameSize(NSSize(width: frame.width, height: height))
        needsLayout = true
        if changed { onHeightChange?() }
    }

    override func layout() {
        super.layout()
        let grid = HUDCategoryLayout.self
        category?.frame = NSRect(x: grid.categoryLeading, y: grid.padding,
                                 width: grid.categoryWidth, height: grid.rowHeight)
        for (index, row) in rows.enumerated() {
            let y = grid.padding + CGFloat(index) * grid.rowHeight
            let label = row.reading as? NSTextField
            let inset: CGFloat = label == nil ? 0 : 24
            let height = label?.intrinsicContentSize.height ?? (grid.rowHeight - 4)
            row.reading.frame = NSRect(x: grid.readingLeading + inset, y: y + (grid.rowHeight - height) / 2,
                width: (row.fullWidth ? bounds.width - grid.readingLeading - 14 : grid.readingWidth) - inset,
                height: height)
            if let mode = row.mode {
                // Apply native alignment insets so every selector's visible bezel shares a column.
                mode.frame = mode.frame(forAlignmentRect: NSRect(x: grid.modeLeading, y: y + 2,
                                                                 width: grid.modeWidth, height: 24))
            }
            row.emphasisView?.frame = NSRect(x: grid.emphasisLeading, y: y + 3, width: 22, height: 22)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.065).setFill()
        NSRect(x: 30, y: bounds.height - 0.5, width: bounds.width - 44, height: 0.5).fill()
    }
}

/// Keep general settings and actions reachable when the category list exceeds the display.
@MainActor
final class HUDCategoryListView: NSScrollView {
    private let content = HUDCategoryDocumentView()
    private let categories: [HUDCategoryMenuView]
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
        documentView = content
        for category in categories {
            content.addSubview(category)
            category.onHeightChange = { [weak self] in self?.arrangeCategories() }
        }
        arrangeCategories()
    }

    required init?(coder: NSCoder) { fatalError("Use init(categories:)") }

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
        highlight.isEnabled = isEnabled && state == .on && highlightAvailable
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
