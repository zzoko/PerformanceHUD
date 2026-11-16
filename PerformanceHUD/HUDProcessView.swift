import AppKit

@MainActor
final class HUDProcessView: NSView {
    private let name = NSTextField(labelWithString: "Process")
    private var values: [HUDProcessReading: NSTextField] = [:]
    private var options = HUDProcessOptions()
    private var scale = HUDScale.normal
    private var background = HUDBackground.dark

    override init(frame: NSRect) {
        super.init(frame: frame)
        name.lineBreakMode = .byTruncatingTail
        name.maximumNumberOfLines = 1
        addSubview(name)
        for reading in HUDProcessReading.allCases {
            let field = NSTextField(labelWithString: reading == .memory ? "—" : "\(reading.title) —")
            field.alignment = .right; field.maximumNumberOfLines = 1
            field.setAccessibilityLabel("Process \(reading.title)")
            values[reading] = field; addSubview(field)
        }
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    func configure(options: HUDProcessOptions, scale: HUDScale, background: HUDBackground) {
        self.options = options; self.scale = scale; self.background = background
        name.font = HUDStyle.titleFont(for: .cpuTotal, scale: scale)
        name.textColor = HUDStyle.TextStyle.label.color(background: background)
        for (reading, field) in values {
            field.isHidden = !options.readings.contains(reading)
            applyReadingStyle(to: field, for: reading)
        }
        needsLayout = true
    }
    func setName(_ value: String?) {
        name.stringValue = value.flatMap { $0.isEmpty ? nil : $0 } ?? "Process"
        name.setAccessibilityLabel(name.stringValue)
    }
    func setValue(_ text: String?, for reading: HUDProcessReading) {
        guard let field = values[reading] else { return }
        let value = text.flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        field.stringValue = reading == .memory ? value : "\(reading.title) \(value)"
        applyReadingStyle(to: field, for: reading)
        needsLayout = true
    }

    private func applyReadingStyle(to field: NSTextField, for reading: HUDProcessReading) {
        let font = HUDStyle.readingFont(scale: scale, highlighted: options.highlighted.contains(reading))
        let color = HUDStyle.readingColor(background: background)
        field.font = font
        field.textColor = color
        guard reading != .memory else { return }

        // GPU/CPU are supporting labels; B emphasizes only their percentage.
        // Keep each label/value pair in its existing reserved column.
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineBreakMode = field.lineBreakMode
        let text = NSMutableAttributedString(string: field.stringValue,
            attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
        text.addAttributes([.font: HUDStyle.smallLabelFont(scale: scale),
                            .foregroundColor: HUDStyle.TextStyle.label.color(background: background)],
            range: NSRange(location: 0, length: reading.title.utf16.count))
        field.attributedStringValue = text
    }

    override func layout() {
        super.layout()
        let gap = HUDStyle.metricColumnSpacing(scale: scale)
        let sizingFont = HUDStyle.readingFont(scale: scale, highlighted: true)
        // CPU and GPU now share a bounded percentage range. Equal, fixed slots
        // keep the name and gaps stable through digit and emphasis changes.
        let percentageWidth = ["GPU 100%", "CPU 100%"].map {
            HUDStyle.horizontalColumnWidth(text: "", reference: $0, font: sizingFont)
        }.max()!
        var x = bounds.width - name.alignmentRectInsets.right
        for reading in HUDProcessReading.allCases.reversed() where options.readings.contains(reading) {
            guard let field = values[reading] else { continue }
            // Larger memory readings can still borrow name space without
            // resizing the HUD; percentage readings never require extra digits.
            let width = reading == .memory
                ? HUDStyle.horizontalColumnWidth(text: field.stringValue, reference: "99.99 GB",
                    font: field.font!, sizingFont: sizingFont)
                : percentageWidth
            let height = field.intrinsicContentSize.height
            field.frame = field.frame(forAlignmentRect: NSRect(x: x - width, y: (bounds.height - height) / 2, width: width, height: height))
            x -= width + gap
        }
        let h = name.intrinsicContentSize.height
        name.frame = name.frame(forAlignmentRect: NSRect(x: name.alignmentRectInsets.left, y: (bounds.height - h) / 2,
            width: max(0, x - name.alignmentRectInsets.left), height: h))
    }
}
