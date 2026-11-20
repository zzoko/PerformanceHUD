import AppKit

nonisolated enum HUDCoreBarLayout {
    static let maximumColumns = 12
    static let barWidth: CGFloat = 4
    static let barHeight: CGFloat = 10
    static let columnGap: CGFloat = 2
    static let rowStride: CGFloat = 14
    static var width: CGFloat {
        CGFloat(maximumColumns) * barWidth + CGFloat(maximumColumns - 1) * columnGap
    }

    static func rowSizes(for count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let rows = (count - 1) / maximumColumns + 1
        let base = count / rows, extra = count % rows
        return (0..<rows).map { base + ($0 < extra ? 1 : 0) }
    }

    // Keep processor order, with longer rows first and every row ending at
    // the same reading edge. The same row calculation also sizes the HUD.
    static func rects(for count: Int, in bounds: NSRect, singleRow: Bool = false) -> [NSRect] {
        guard count > 0 else { return [] }
        let sizes = singleRow ? [count] : rowSizes(for: count)
        guard let columns = sizes.first else { return [] }
        let gap = columnGap
        let width = min(barWidth,
            max(0, (bounds.width - gap * CGFloat(columns - 1)) / CGFloat(columns)))
        return sizes.enumerated().flatMap { row, columns in
            let rowWidth = CGFloat(columns) * width + CGFloat(columns - 1) * gap
            return (0..<columns).map { column in
                NSRect(x: bounds.maxX - rowWidth + CGFloat(column) * (width + gap),
                    y: bounds.maxY - barHeight - CGFloat(row) * rowStride,
                    width: width, height: barHeight)
            }
        }
    }
}

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
    private let topology: CPUCoreTopology
    private var sample = CPUCoreSample.unavailable
    private var frequencies = CPUFrequencySample.unavailable
    private let gpu: Bool
    private var cpuPowerTrailingInset: CGFloat = 0
    private var matchingFrequencyColumn: FrequencyColumn?
    private var gpuFrequency: Double?
    override var isFlipped: Bool { true }

    init(frame: NSRect, gpu: Bool = false, types: [HUDCPUCoreType] = HUDDeviceInfo.current.coreTypes,
         topology: CPUCoreTopology = .current) {
        self.topology = topology
        self.gpu = gpu
        super.init(frame: frame)
        for type in gpu || types.isEmpty ? [.init(name: "Cores", count: 0)] : types {
            let label = HUDReadingLabel(labelWithString: type.name)
            let frequency = HUDReadingLabel(labelWithString: "")
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
    func height() -> CGFloat {
        HUDStyle.rowSpacing + rows.reduce(0) { $0 + rowHeight($1) }
    }
    private func rowHeight(_ row: Row) -> CGFloat {
        let lines = !gpu && options.mode.showsBars ? max(1, HUDCoreBarLayout.rowSizes(for: row.type.count).count) : 1
        return HUDStyle.ramDetailHeight()
            + CGFloat(lines - 1) * HUDCoreBarLayout.rowStride
    }

    // Both sections use the same column description when CPU GHz is visible.
    // GPU follows future CPU placement changes without duplicating its geometry.
    var frequencyColumn: FrequencyColumn {
        let rightAligned = FrequencyColumn(trailingInset: 0,
            width: 60, alignment: .right)
        if gpu {
            return matchingFrequencyColumn ?? rightAligned
        }
        if options.mode == .value { return rightAligned }
        return FrequencyColumn(trailingInset: cpuPowerTrailingInset,
            width: rightAligned.width, alignment: .right)
    }

    func configure(options: HUDCoreOptions, background: HUDBackground,
                   powerTrailingInset: CGFloat? = nil, matchingFrequencyColumn: FrequencyColumn? = nil) {
        self.options = options
        self.matchingFrequencyColumn = matchingFrequencyColumn
        let referenceFont = HUDStyle.readingFont(highlighted: false)
        cpuPowerTrailingInset = powerTrailingInset ?? HUDStyle.verticalPowerTrailingInset(temperature: referenceFont, usage: referenceFont)
        for row in rows {
            row.label.font = HUDStyle.smallLabelFont()
            row.label.textColor = HUDStyle.TextStyle.label.color(background: background)
            row.frequency.font = HUDStyle.readingFont(highlighted: options.highlighted)
            row.frequency.textColor = HUDStyle.readingColor(background: background)
            row.frequency.isHidden = !gpu && !options.mode.showsValue
            row.frequency.alignment = frequencyColumn.alignment
            row.bars?.isHidden = !options.mode.showsBars
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
            row.frequency.stringValue = ghz.map { String(format: "%.1f GHz", $0) } ?? ""
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
        row.frequency.stringValue = frequency.map { String(format: "%.1f GHz", $0) } ?? ""
        row.frequency.setAccessibilityLabel("GPU average active frequency during sample")
    }

    // Horizontal reuses the existing detail-label/value pairs (PHY/SWP), with
    // the same baseline, reserved numeric width, emphasis, and tight pair gap.
    // Bars and Both share a stack with one unwrapped row per core type.
    func horizontalReadings(background: HUDBackground) -> [HUDHorizontalView.Reading] {
        let coreRows = rows.map { row in
            HUDHorizontalView.CoreRow(name: row.type.name,
                frequency: gpu || options.mode.showsValue ? row.frequency.stringValue : nil,
                activity: row.bars?.values ?? [])
        }
        return Self.horizontalReadings(rows: coreRows, gpu: gpu, options: options, background: background)
    }

    static func horizontalReadings(rows: [HUDHorizontalView.CoreRow], gpu: Bool, options: HUDCoreOptions,
                                   background: HUDBackground) -> [HUDHorizontalView.Reading] {
        let metric: HUDMetric = gpu ? .gpuCores : .cpuCores
        let font = HUDStyle.readingFont(highlighted: options.highlighted)
        let color = HUDStyle.readingColor(background: background)
        if !gpu && options.mode.showsBars {
            return [.init(id: "cpu.coreBars", text: "", reference: "", font: font, color: color,
                help: nil, startsMetric: false, metric: metric, leftAligned: true, coreRows: rows)]
        }
        return rows.flatMap { row -> [HUDHorizontalView.Reading] in
            let caption = gpu ? "C" : row.caption
            let id = "\(metric.rawValue).\(row.name)"
            let help = gpu ? "GPU average active frequency during sample"
                : "\(row.name) active-time-weighted frequency during sample"
            return [.init(id: "\(id).title", text: caption, reference: caption, font: HUDStyle.smallLabelFont(),
                          color: HUDStyle.TextStyle.label.color(background: background), help: help,
                          startsMetric: false, metric: metric, leftAligned: true),
                    .init(id: "\(id).value", text: row.frequency ?? "", reference: HUDStyle.horizontalFrequencyReference,
                          font: font, color: color, help: help, startsMetric: false, metric: metric,
                          leadingGap: HUDStyle.memoryLabelValueSpacing, leftAligned: true)]
        }
    }

    override func layout() {
        super.layout()
        let height = HUDStyle.ramDetailHeight()
        var y: CGFloat = 0
        for row in rows {
            defer { y += rowHeight(row) }
            let h = row.label.intrinsicContentSize.height
            func place(_ field: NSTextField, x: CGFloat, width: CGFloat) {
                field.frame = field.frame(forAlignmentRect: NSRect(x: x, y: y, width: width, height: h))
            }
            let right = bounds.width - row.frequency.alignmentRectInsets.right
            let column = frequencyColumn
            let gap = HUDStyle.metricColumnSpacing
            let frequencyLeft = right - column.trailingInset - column.width
            let labelLeft = row.label.alignmentRectInsets.left
            place(row.label, x: labelLeft, width: max(0, frequencyLeft - gap - labelLeft))
            place(row.frequency, x: frequencyLeft, width: column.width)
            if let bars = row.bars {
                let graphWidth = HUDCoreBarLayout.width
                let graphLeft = right - graphWidth
                let barHeight = HUDCoreBarLayout.barHeight
                bars.frame = NSRect(x: graphLeft, y: y + (h - barHeight) / 2,
                    width: graphWidth, height: barHeight + rowHeight(row) - height)
            }
        }
    }
}

@MainActor
final class HUDCPUCoreBarsView: NSView {
    var singleRow = false
    var values: [Double?] = [] { didSet { needsDisplay = true } }
    var tint = NSColor.labelColor { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        guard !values.isEmpty else { return }
        for (rect, value) in zip(HUDCoreBarLayout.rects(for: values.count, in: bounds, singleRow: singleRow), values) {
            let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
            tint.withAlphaComponent(0.18).setFill(); path.fill()
            guard let value else { continue }
            NSGraphicsContext.saveGraphicsState(); path.addClip()
            tint.withAlphaComponent(0.85).setFill()
            NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * CGFloat(min(100, max(0, value)) / 100)).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
