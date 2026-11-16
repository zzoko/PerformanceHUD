import AppKit

@MainActor
final class HUDCoreDetailView: NSView {
    struct FrequencyColumn {
        let trailingInset: CGFloat
        let width: CGFloat
        let alignment: NSTextAlignment
    }

    private struct Row {
        let type: HUDCPUCoreType
        let label: NSTextField
        let frequency: NSTextField
        let bars: HUDCPUCoreBarsView?
    }
    private var rows: [Row] = []
    private var options = HUDCoreOptions()
    private var scale = HUDScale.normal
    private let topology: CPUCoreTopology
    private var sample = CPUCoreSample.unavailable
    private var frequencies = CPUFrequencySample.unavailable
    private let gpu: Bool
    private var cpuReadingWidth: CGFloat = 0
    private var matchingFrequencyColumn: FrequencyColumn?
    private var gpuFrequency: Double?
    override var isFlipped: Bool { true }

    init(frame: NSRect, gpu: Bool = false, types: [HUDCPUCoreType] = HUDDeviceInfo.current.coreTypes,
         topology: CPUCoreTopology = .current) {
        self.topology = topology
        self.gpu = gpu
        super.init(frame: frame)
        for type in gpu || types.isEmpty ? [.init(name: "Cores", count: 0)] : types {
            let label = NSTextField(labelWithString: type.name)
            let frequency = NSTextField(labelWithString: "—")
            for field in [label, frequency] {
                field.maximumNumberOfLines = 1
                field.lineBreakMode = .byTruncatingTail
                addSubview(field)
            }
            let bars = gpu ? nil : HUDCPUCoreBarsView()
            if let bars {
                bars.setAccessibilityLabel("\(type.name) core activity")
                addSubview(bars)
            }
            rows.append(Row(type: type, label: label, frequency: frequency, bars: bars))
        }
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    func height(scale: HUDScale) -> CGFloat {
        HUDStyle.rowSpacing(scale: scale) + rows.reduce(0) { $0 + rowHeight($1, scale: scale) }
    }
    private func rowHeight(_ row: Row, scale: HUDScale) -> CGFloat {
        let lines = !gpu && options.mode.showsBars ? max(1, (row.type.count + 7) / 8) : 1
        return HUDStyle.ramDetailHeight(scale: scale) + CGFloat(lines - 1) * 14 * CGFloat(scale.rawValue)
    }

    // Both sections use the same column description when CPU GHz is visible.
    // GPU follows future CPU placement changes without duplicating its geometry.
    var frequencyColumn: FrequencyColumn {
        let rightAligned = FrequencyColumn(trailingInset: 0,
            width: 60 * CGFloat(scale.rawValue), alignment: .right)
        if gpu {
            return matchingFrequencyColumn ?? rightAligned
        }
        if options.mode == .value { return rightAligned }
        let inset = 46 * CGFloat(scale.rawValue) + HUDStyle.metricColumnSpacing(scale: scale)
        return FrequencyColumn(trailingInset: inset, width: max(0, cpuReadingWidth - inset), alignment: .left)
    }

    func configure(options: HUDCoreOptions, scale: HUDScale, background: HUDBackground,
                   readingWidth: CGFloat? = nil, matchingFrequencyColumn: FrequencyColumn? = nil) {
        self.options = options; self.scale = scale
        self.matchingFrequencyColumn = matchingFrequencyColumn
        let referenceFont = HUDStyle.readingFont(scale: scale, highlighted: false)
        cpuReadingWidth = readingWidth ?? HUDStyle.verticalReadingClusterWidth(scale: scale,
            power: referenceFont, temperature: referenceFont, usage: referenceFont)
        for row in rows {
            row.label.font = HUDStyle.smallLabelFont(scale: scale)
            row.label.textColor = HUDStyle.TextStyle.label.color(background: background)
            row.frequency.font = HUDStyle.readingFont(scale: scale, highlighted: options.highlighted)
            row.frequency.textColor = HUDStyle.readingColor(background: background)
            row.frequency.isHidden = !gpu && !options.mode.showsValue
            row.frequency.alignment = frequencyColumn.alignment
            row.bars?.isHidden = !options.mode.showsBars
            row.bars?.scale = CGFloat(scale.rawValue)
            row.bars?.tint = HUDStyle.readingColor(background: background)
        }
        if gpu { updateGPU(frequency: gpuFrequency) }
        else { update(sample: sample, frequencies: frequencies) }
        needsLayout = true
    }
    func update(sample: CPUCoreSample, frequencies: CPUFrequencySample) {
        self.sample = sample; self.frequencies = frequencies
        for row in rows {
            guard let bars = row.bars else { continue }
            let ids = topology.groups.first { $0.name == row.type.name }?.ids ?? []
            let ghz = frequencies.average(for: ids)
            row.frequency.stringValue = ghz.map { String(format: "%.1f GHz", $0) } ?? "—"
            row.frequency.setAccessibilityLabel("\(row.type.name) active-time-weighted frequency during sample")
            bars.values = ids.isEmpty ? Array(repeating: nil, count: row.type.count) : ids.map { sample.usage[$0] }
            bars.setAccessibilityValue(bars.values.enumerated().map { index, value in
                "Core \(index + 1): \(value.map { "\(Int($0.rounded())) percent" } ?? "unavailable")"
            }.joined(separator: ", "))
        }
    }
    func updateGPU(frequency: Double?) {
        guard gpu, let row = rows.first else { return }
        gpuFrequency = frequency
        row.frequency.stringValue = frequency.map { String(format: "%.1f GHz", $0) } ?? "—"
        row.frequency.setAccessibilityLabel("GPU average active frequency during sample")
    }

    // Horizontal reuses the existing detail-label/value pairs (PHY/SWP), with
    // the same baseline, reserved numeric width, emphasis, and tight pair gap.
    // Always include GHz here, independent of the saved Vertical bar mode.
    func horizontalReadings() -> [HUDHorizontalView.Reading] {
        let metric: HUDMetric = gpu ? .gpuCores : .cpuCores
        return rows.flatMap { row in
            let caption: String
            if gpu { caption = "C" }
            else {
                switch row.type.name {
                case "Super": caption = "S"
                case "Efficiency": caption = "E"
                case "Performance": caption = "P"
                default: caption = row.type.name
                }
            }
            return [("title", row.label), ("value", row.frequency)].map { role, field in
                HUDHorizontalView.Reading(id: "\(metric.rawValue).\(row.type.name).\(role)",
                    text: role == "title" ? caption : field.stringValue,
                    reference: role == "title" ? caption : HUDStyle.horizontalFrequencyReference,
                    font: field.font!, color: field.textColor!, help: row.frequency.accessibilityLabel(),
                    startsMetric: false, resourceGroup: gpu ? .gpu : .cpu, metric: metric,
                    tightLeading: role == "value", leftAligned: true)
            }
        }
    }

    override func layout() {
        super.layout()
        let factor = CGFloat(scale.rawValue)
        let height = HUDStyle.ramDetailHeight(scale: scale)
        var y: CGFloat = 0
        for row in rows {
            defer { y += rowHeight(row, scale: scale) }
            let h = row.label.intrinsicContentSize.height
            func place(_ field: NSTextField, x: CGFloat, width: CGFloat) {
                field.frame = field.frame(forAlignmentRect: NSRect(x: x, y: y + (height - h) / 2, width: width, height: h))
            }
            let right = bounds.width - row.frequency.alignmentRectInsets.right
            let column = frequencyColumn
            let gap = HUDStyle.metricColumnSpacing(scale: scale)
            let frequencyLeft = right - column.trailingInset - column.width
            let labelLeft = row.label.alignmentRectInsets.left
            place(row.label, x: labelLeft, width: max(0, frequencyLeft - gap - labelLeft))
            place(row.frequency, x: frequencyLeft, width: column.width)
            if let bars = row.bars {
                let graphWidth = 46 * factor // Eight 4 pt bars and seven 2 pt gaps.
                let graphLeft = right - graphWidth
                bars.frame = NSRect(x: graphLeft, y: y + (height - 10 * factor) / 2,
                    width: graphWidth, height: 10 * factor + rowHeight(row, scale: scale) - height)
            }
        }
    }
}

@MainActor
private final class HUDCPUCoreBarsView: NSView {
    var values: [Double?] = [] { didSet { needsDisplay = true } }
    var scale: CGFloat = 1
    var tint = NSColor.labelColor { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        guard !values.isEmpty else { return }
        let columns = min(8, values.count)
        let gap = 2 * scale
        let width = min(4 * scale, max(0, (bounds.width - gap * CGFloat(columns - 1)) / CGFloat(columns)))
        for (index, value) in values.enumerated() {
            // Each row ends at the reading edge and grows leftward, while
            // processor IDs keep their left-to-right order within that row.
            let countInRow = min(8, values.count - (index / 8) * 8)
            let rowWidth = CGFloat(countInRow) * width + CGFloat(countInRow - 1) * gap
            let rect = NSRect(x: bounds.width - rowWidth + CGFloat(index % 8) * (width + gap),
                              y: bounds.height - 10 * scale - CGFloat(index / 8) * 14 * scale,
                              width: width, height: 10 * scale)
            let path = NSBezierPath(roundedRect: rect, xRadius: scale, yRadius: scale)
            tint.withAlphaComponent(0.18).setFill(); path.fill()
            guard let value else { continue }
            NSGraphicsContext.saveGraphicsState(); path.addClip()
            tint.withAlphaComponent(0.85).setFill()
            NSRect(x: rect.minX, y: rect.minY, width: width, height: rect.height * CGFloat(min(100, max(0, value)) / 100)).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
