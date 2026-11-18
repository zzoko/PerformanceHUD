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
    static func rects(for count: Int, in bounds: NSRect, scale: CGFloat, singleRow: Bool = false) -> [NSRect] {
        guard count > 0 else { return [] }
        let sizes = singleRow ? [count] : rowSizes(for: count)
        guard let columns = sizes.first else { return [] }
        let gap = columnGap * scale
        let width = min(barWidth * scale,
            max(0, (bounds.width - gap * CGFloat(columns - 1)) / CGFloat(columns)))
        return sizes.enumerated().flatMap { row, columns in
            let rowWidth = CGFloat(columns) * width + CGFloat(columns - 1) * gap
            return (0..<columns).map { column in
                NSRect(x: bounds.maxX - rowWidth + CGFloat(column) * (width + gap),
                    y: bounds.maxY - barHeight * scale - CGFloat(row) * rowStride * scale,
                    width: width, height: barHeight * scale)
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
    private var scale = HUDScale.normal
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
        let lines = !gpu && options.mode.showsBars ? max(1, HUDCoreBarLayout.rowSizes(for: row.type.count).count) : 1
        return HUDStyle.ramDetailHeight(scale: scale)
            + CGFloat(lines - 1) * HUDCoreBarLayout.rowStride * CGFloat(scale.rawValue)
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
        return FrequencyColumn(trailingInset: cpuPowerTrailingInset,
            width: rightAligned.width, alignment: .right)
    }

    func configure(options: HUDCoreOptions, scale: HUDScale, background: HUDBackground,
                   powerTrailingInset: CGFloat? = nil, matchingFrequencyColumn: FrequencyColumn? = nil) {
        self.options = options; self.scale = scale
        self.matchingFrequencyColumn = matchingFrequencyColumn
        let referenceFont = HUDStyle.readingFont(scale: scale, highlighted: false)
        cpuPowerTrailingInset = powerTrailingInset ?? HUDStyle.verticalPowerTrailingInset(scale: scale,
            temperature: referenceFont, usage: referenceFont)
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
    // Bars and Both share a stack with one unwrapped row per core type.
    func horizontalReadings() -> [HUDHorizontalView.Reading] {
        let metric: HUDMetric = gpu ? .gpuCores : .cpuCores
        func caption(_ row: Row) -> String {
            if gpu { return "C" }
            switch row.type.name {
            case "Super": return "S"
            case "Efficiency": return "E"
            case "Performance": return "P"
            default: return row.type.name
            }
        }
        if !gpu && options.mode.showsBars, let first = rows.first {
            let stack = rows.map { row in
                HUDHorizontalView.CoreRow(name: row.type.name, caption: caption(row),
                    frequency: options.mode.showsValue ? row.frequency.stringValue : nil,
                    activity: row.bars?.values ?? [])
            }
            return [.init(id: "cpu.coreBars", text: "", reference: "", font: first.frequency.font!,
                color: first.frequency.textColor!, help: nil, startsMetric: false,
                metric: metric, leftAligned: true, coreRows: stack)]
        }
        return rows.flatMap { row in
            let caption = caption(row)
            return [("title", row.label), ("value", row.frequency)].map { role, field in
                HUDHorizontalView.Reading(id: "\(metric.rawValue).\(row.type.name).\(role)",
                    text: role == "title" ? caption : field.stringValue,
                    reference: role == "title" ? caption : HUDStyle.horizontalFrequencyReference,
                    font: field.font!, color: field.textColor!, help: row.frequency.accessibilityLabel(),
                    startsMetric: false, metric: metric,
                    leadingGap: role == "value" ? HUDStyle.memoryLabelValueSpacing : nil, leftAligned: true)
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
                let graphWidth = HUDCoreBarLayout.width * factor
                let graphLeft = right - graphWidth
                let barHeight = HUDCoreBarLayout.barHeight * factor
                bars.frame = NSRect(x: graphLeft, y: y + (height - barHeight) / 2,
                    width: graphWidth, height: barHeight + rowHeight(row, scale: scale) - height)
            }
        }
    }
}

@MainActor
final class HUDCPUCoreBarsView: NSView {
    var singleRow = false
    var values: [Double?] = [] { didSet { needsDisplay = true } }
    var scale: CGFloat = 1
    var tint = NSColor.labelColor { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        guard !values.isEmpty else { return }
        for (rect, value) in zip(HUDCoreBarLayout.rects(for: values.count, in: bounds, scale: scale, singleRow: singleRow), values) {
            let path = NSBezierPath(roundedRect: rect, xRadius: scale, yRadius: scale)
            tint.withAlphaComponent(0.18).setFill(); path.fill()
            guard let value else { continue }
            NSGraphicsContext.saveGraphicsState(); path.addClip()
            tint.withAlphaComponent(0.85).setFill()
            NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * CGFloat(min(100, max(0, value)) / 100)).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
