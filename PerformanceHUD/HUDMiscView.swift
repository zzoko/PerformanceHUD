import AppKit

@MainActor
final class HUDMiscView: NSView {
    private var fields: [HUDMiscReading: (NSTextField, NSTextField)] = [:]
    private var coreFields: [(NSTextField, NSTextField)] = []
    private let info: HUDDeviceInfo
    private var options = HUDMiscOptions()
    private var scale = HUDScale.normal
    override var isFlipped: Bool { true }

    init(frame: NSRect, info: HUDDeviceInfo = .current) {
        self.info = info
        super.init(frame: frame)
        for reading in HUDMiscReading.allCases {
            let title = NSTextField(labelWithString: reading.title)
            let value = NSTextField(labelWithString: "")
            value.alignment = .right
            value.lineBreakMode = .byTruncatingMiddle
            for field in [title, value] { field.maximumNumberOfLines = 1; addSubview(field) }
            fields[reading] = (title, value)
        }
        for (name, text) in [("CPU cores", info.cpuConfiguration), ("GPU cores", info.gpuConfiguration)] {
            let title = NSTextField(labelWithString: name)
            let value = NSTextField(labelWithString: text)
            value.alignment = .right
            value.lineBreakMode = .byTruncatingMiddle
            value.setAccessibilityLabel(name)
            value.setAccessibilityValue(text)
            for field in [title, value] { field.maximumNumberOfLines = 1; addSubview(field) }
            coreFields.append((title, value))
        }
        update(HUDMiscSample())
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(options: HUDMiscOptions, scale: HUDScale, background: HUDBackground) {
        self.options = options; self.scale = scale
        for (reading, pair) in fields {
            for field in [pair.0, pair.1] {
                field.isHidden = !options.visibleReadings.contains(reading)
            }
        }
        for pair in coreFields {
            pair.0.isHidden = !options.showsCoreCounts
            pair.1.isHidden = !options.showsCoreCounts
        }
        for pair in Array(fields.values) + coreFields {
            pair.0.font = HUDStyle.smallLabelFont(scale: scale)
            pair.0.textColor = HUDStyle.TextStyle.label.color(background: background)
            pair.1.font = HUDStyle.readingFont(scale: scale, highlighted: false)
            pair.1.textColor = HUDStyle.TextStyle.reading.color(background: background)
        }
        needsLayout = true
    }

    func update(_ sample: HUDMiscSample) {
        for (reading, pair) in fields {
            pair.1.stringValue = sample.text(for: reading, info: info)
            pair.1.setAccessibilityLabel(reading.title)
            pair.1.setAccessibilityValue(pair.1.stringValue)
        }
        needsLayout = true
    }

    func height(scale: HUDScale) -> CGFloat {
        CGFloat(options.rowCount) * HUDStyle.ramDetailHeight(scale: scale)
    }

    override func layout() {
        super.layout()
        let rowHeight = HUDStyle.ramDetailHeight(scale: scale)
        var rows: [(NSTextField, NSTextField)] = []
        for reading in options.visibleReadings {
            if let pair = fields[reading] { rows.append(pair) }
            if reading == .chip && options.showsCoreCounts { rows += coreFields }
        }
        for (index, pair) in rows.enumerated() {
            let (title, value) = pair
            let h = title.intrinsicContentSize.height
            let y = CGFloat(index) * rowHeight + (rowHeight - h) / 2
            let titleWidth = title.intrinsicContentSize.width
            let leading = title.alignmentRectInsets.left
            title.frame = title.frame(forAlignmentRect: NSRect(x: leading, y: y, width: titleWidth, height: h))
            let x = leading + titleWidth + HUDStyle.metricColumnSpacing(scale: scale)
            value.frame = value.frame(forAlignmentRect: NSRect(x: x, y: y,
                width: max(0, bounds.width - value.alignmentRectInsets.right - x), height: h))
        }
    }

}
