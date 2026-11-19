import AppKit

/// Both layouts use the same two-line drive block. Horizontal places blocks side by side.
@MainActor
final class HUDStorageView: NSView {
    private let horizontal: Bool
    private var displayed: [StorageDrive] = []
    private var background: HUDBackground?
    private var rows: [HUDStorageDriveRow] = []
    private var scale = HUDScale.normal
    private var options = HUDStorageOptions()
    private var separator = NSColor.clear

    init(horizontal: Bool) {
        self.horizontal = horizontal
        super.init(frame: .zero)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Storage")
    }

    required init?(coder: NSCoder) { fatalError("Use init(horizontal:)") }
    override var isFlipped: Bool { true }

    func configure(_ drives: [StorageDrive], options: HUDStorageOptions, scale: HUDScale, background: HUDBackground) {
        guard drives != displayed || options != self.options || scale != self.scale || background != self.background else { return }
        displayed = drives
        self.background = background
        self.scale = scale
        self.options = options
        separator = HUDStyle.separatorColor(background: background)
        while rows.count > drives.count { rows.removeLast().removeFromSuperview() }
        while rows.count < drives.count {
            let row = HUDStorageDriveRow(frame: .zero)
            rows.append(row)
            addSubview(row)
        }
        for (row, drive) in zip(rows, drives) {
            row.configure(drive, options: options, scale: scale, background: background)
        }
        needsLayout = true
        needsDisplay = true
    }

    private var blockHeight: CGFloat {
        HUDStyle.rowHeight(scale: scale) + (options.details ? HUDStyle.ramDetailHeight(scale: scale) : 0)
    }
    private var gap: CGFloat { horizontal ? 16 * CGFloat(scale.rawValue) : HUDStyle.rowSpacing(scale: scale) }
    var contentSize: NSSize {
        let gaps = CGFloat(max(0, rows.count - 1)) * gap
        return NSSize(width: horizontal ? rows.reduce(gaps) { $0 + $1.preferredWidth } : bounds.width,
                      height: horizontal ? blockHeight : CGFloat(rows.count) * blockHeight + gaps)
    }

    override func layout() {
        super.layout()
        var offset: CGFloat = 0
        for row in rows {
            let size = NSSize(width: horizontal ? row.preferredWidth : bounds.width, height: blockHeight)
            row.frame = NSRect(origin: NSPoint(x: horizontal ? offset : 0, y: horizontal ? 0 : offset), size: size)
            offset += (horizontal ? size.width : size.height) + gap
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard horizontal else { return }
        separator.setFill()
        let height = HUDStyle.rowHeight(scale: scale) - 4 * CGFloat(scale.rawValue)
        for row in rows.dropFirst() {
            let width = 0.5 * CGFloat(scale.rawValue)
            NSRect(x: row.frame.minX - (gap + width) / 2, y: bounds.midY - height / 2, width: width, height: height).fill()
        }
    }
}

@MainActor
private final class HUDStorageDriveRow: NSView {
    private let name = NSTextField(labelWithString: "")
    private let free = NSTextField(labelWithString: "")
    private let readLabel = NSTextField(labelWithString: "Read")
    private let read = NSTextField(labelWithString: "")
    private let writeLabel = NSTextField(labelWithString: "Write")
    private let write = NSTextField(labelWithString: "")
    private var scale = HUDScale.normal
    private(set) var preferredWidth: CGFloat = 0
    private var freeWidth: CGFloat = 0
    private var rateWidth: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        for field in [name, free, readLabel, read, writeLabel, write] {
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            addSubview(field)
        }
        for field in [free, read, write] { field.alignment = .right }
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    override var isFlipped: Bool { true }

    func configure(_ drive: StorageDrive, options: HUDStorageOptions, scale: HUDScale, background: HUDBackground) {
        self.scale = scale
        name.stringValue = drive.name
        free.stringValue = drive.freeText
        read.stringValue = StorageDrive.rateText(drive.readMBps)
        write.stringValue = StorageDrive.rateText(drive.writeMBps)
        name.font = HUDStyle.titleFont(for: .storage, scale: scale)
        for (field, highlighted) in [(free, options.freeSpaceHighlighted), (read, options.detailsHighlighted), (write, options.detailsHighlighted)] {
            field.font = HUDStyle.readingFont(scale: scale, highlighted: highlighted)
            field.textColor = (highlighted ? HUDStyle.TextStyle.emphasizedReading : .reading).color(background: background)
        }
        for field in [readLabel, writeLabel] { field.font = HUDStyle.smallLabelFont(scale: scale) }
        for field in [name, readLabel, writeLabel] { field.textColor = HUDStyle.TextStyle.label.color(background: background) }
        for field in [readLabel, read, writeLabel, write] { field.isHidden = !options.details }
        let factor = CGFloat(scale.rawValue)
        let gap = HUDStyle.metricColumnSpacing(scale: scale)
        let sizingFont = HUDStyle.readingFont(scale: scale, highlighted: true)
        rateWidth = HUDStyle.horizontalColumnWidth(text: "", reference: "999.9 MB/s", font: sizingFont)
        freeWidth = HUDStyle.horizontalColumnWidth(text: "", reference: "888.8 MB free", font: sizingFont)
        let header = min(name.intrinsicContentSize.width, 120 * factor) + freeWidth + gap
        let rates = readLabel.intrinsicContentSize.width + writeLabel.intrinsicContentSize.width + 2 * rateWidth + 3 * gap
        preferredWidth = ceil(max(header, options.details ? rates : 0))
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let gap = HUDStyle.metricColumnSpacing(scale: scale)
        func place(_ field: NSTextField, left: CGFloat, width: CGFloat, center: CGFloat) {
            let h = field.intrinsicContentSize.height
            field.frame = field.frame(forAlignmentRect: NSRect(x: left, y: center - h / 2, width: max(0, width), height: h))
        }
        let header = HUDStyle.rowHeight(scale: scale)
        place(name, left: 0, width: bounds.width - freeWidth - gap, center: header / 2)
        place(free, left: bounds.width - freeWidth, width: freeWidth, center: header / 2)
        guard !read.isHidden else { return }
        let center = header + HUDStyle.ramDetailHeight(scale: scale) / 2
        let readLabelWidth = readLabel.intrinsicContentSize.width
        let writeLabelWidth = writeLabel.intrinsicContentSize.width
        place(readLabel, left: 0, width: readLabelWidth, center: center)
        place(read, left: readLabelWidth + gap, width: rateWidth, center: center)
        place(writeLabel, left: bounds.width - rateWidth - gap - writeLabelWidth, width: writeLabelWidth, center: center)
        place(write, left: bounds.width - rateWidth, width: rateWidth, center: center)
    }
}
