import AppKit

/// Both layouts use the same two-line drive block. Horizontal places blocks side by side.
@MainActor
final class HUDStorageView: NSView {
    private let horizontal: Bool
    private var displayed: [StorageDrive] = []
    private var background: HUDBackground?
    private var rows: [HUDStorageDriveRow] = []
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

    func configure(_ drives: [StorageDrive], options: HUDStorageOptions, background: HUDBackground) {
        guard drives != displayed || options != self.options || background != self.background else { return }
        displayed = drives
        self.background = background
        self.options = options
        separator = HUDStyle.separatorColor(background: background)
        while rows.count > drives.count { rows.removeLast().removeFromSuperview() }
        while rows.count < drives.count {
            let row = HUDStorageDriveRow(horizontal: horizontal)
            rows.append(row)
            addSubview(row)
        }
        for (row, drive) in zip(rows, drives) {
            row.configure(drive, options: options, background: background)
        }
        needsLayout = true
        needsDisplay = true
    }

    private var blockHeight: CGFloat {
        let header = HUDStyle.rowHeight
        guard options.details else { return header }
        let detail = HUDStyle.ramDetailHeight()
        return horizontal ? header + detail : header / 2 + HUDStyle.headingToDetailSpacing(.tight) + detail / 2
    }
    private var gap: CGFloat { horizontal ? 16 : HUDStyle.rowSpacing }
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
        let height = HUDStyle.rowHeight - 4
        for row in rows.dropFirst() {
            let width = hudHairline
            NSRect(x: row.frame.minX - (gap + width) / 2, y: bounds.midY - height / 2, width: width, height: height).fill()
        }
    }
}

@MainActor
private final class HUDStorageDriveRow: NSView {
    private let horizontal: Bool
    private let name = HUDReadingLabel(labelWithString: "")
    private let free = HUDReadingLabel(labelWithString: "")
    private let readLabel = HUDReadingLabel(labelWithString: "Read")
    private let read = HUDReadingLabel(labelWithString: "")
    private let writeLabel = HUDReadingLabel(labelWithString: "Write")
    private let write = HUDReadingLabel(labelWithString: "")
    private(set) var preferredWidth: CGFloat = 0
    private var freeWidth: CGFloat = 0
    private let rateColumns = HUDStyle.StorageRateColumns()

    init(horizontal: Bool) {
        self.horizontal = horizontal
        super.init(frame: .zero)
        for field in [name, free, readLabel, read, writeLabel, write] {
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            addSubview(field)
        }
        for field in [free, read, write] { field.alignment = .right }
    }
    required init?(coder: NSCoder) { fatalError("Use init(horizontal:)") }
    override var isFlipped: Bool { true }

    func configure(_ drive: StorageDrive, options: HUDStorageOptions, background: HUDBackground) {
        name.stringValue = drive.name
        free.stringValue = drive.freeText
        read.stringValue = StorageDrive.rateText(drive.readMBps)
        write.stringValue = StorageDrive.rateText(drive.writeMBps)
        name.font = HUDStyle.titleFont(for: .storage)
        for (field, highlighted) in [(free, options.freeSpaceHighlighted), (read, options.detailsHighlighted), (write, options.detailsHighlighted)] {
            field.font = HUDStyle.readingFont(highlighted: highlighted)
            field.textColor = (highlighted ? HUDStyle.TextStyle.emphasizedReading : .reading).color(background: background)
        }
        for field in [readLabel, writeLabel] { field.font = HUDStyle.smallLabelFont() }
        for field in [name, readLabel, writeLabel] { field.textColor = HUDStyle.TextStyle.label.color(background: background) }
        for field in [readLabel, read, writeLabel, write] { field.isHidden = !options.details }
        let gap = HUDStyle.metricColumnSpacing
        let sizingFont = HUDStyle.readingFont(highlighted: true)
        freeWidth = HUDStyle.horizontalColumnWidth(text: "", reference: "888.8 MB free", font: sizingFont)
        let header = min(name.intrinsicContentSize.width, 120) + freeWidth + gap
        let rates = rateColumns.readValueTrailing + writeLabel.intrinsicContentSize.width + rateColumns.valueWidth + 2 * gap
        preferredWidth = ceil(max(header, options.details ? rates : 0))
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let gap = HUDStyle.metricColumnSpacing
        func place(_ field: NSTextField, left: CGFloat, width: CGFloat, center: CGFloat, baseline: CGFloat? = nil) {
            let h = field.intrinsicContentSize.height
            var frame = field.frame(forAlignmentRect: NSRect(x: left, y: center - h / 2, width: max(0, width), height: h))
            if let baseline { frame.origin.y = baseline - field.firstBaselineOffsetFromTop }
            field.frame = frame
        }
        let detailSpacing = HUDStyle.headingToDetailSpacing(.tight)
        let headingCenter = horizontal && !read.isHidden ? bounds.midY - detailSpacing / 2 : HUDStyle.rowHeight / 2
        place(name, left: 0, width: bounds.width - freeWidth - gap, center: headingCenter)
        place(free, left: bounds.width - freeWidth, width: freeWidth, center: headingCenter)
        guard !read.isHidden else { return }
        let detailCenter = headingCenter + detailSpacing
        let baseline = horizontal ? nil : name.frame.minY + name.firstBaselineOffsetFromTop + detailSpacing
        let rateWidth = rateColumns.valueWidth
        let writeLabelWidth = writeLabel.intrinsicContentSize.width
        place(readLabel, left: 0, width: rateColumns.readLabelWidth, center: detailCenter, baseline: baseline)
        place(read, left: rateColumns.readValueTrailing - rateWidth, width: rateWidth, center: detailCenter, baseline: baseline)
        place(writeLabel, left: bounds.width - rateWidth - gap - writeLabelWidth, width: writeLabelWidth, center: detailCenter, baseline: baseline)
        place(write, left: bounds.width - rateWidth, width: rateWidth, center: detailCenter, baseline: baseline)
    }
}
