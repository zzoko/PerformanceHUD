import AppKit

/// Thirty seconds of actual readings; unavailable samples and sampling pauses
/// remain gaps. Time uses system uptime so clock changes cannot distort history.
nonisolated struct HUDMemoryPressureHistory {
    static let duration: TimeInterval = 30
    private(set) var samples: [MemoryPressureMonitor.Sample] = []

    mutating func append(_ sample: MemoryPressureMonitor.Sample) {
        guard sample.time.isFinite else { return }
        if let previous = samples.last, sample.time <= previous.time { return }
        samples.append(sample)
        let cutoff = sample.time - Self.duration
        if let firstVisible = samples.firstIndex(where: { $0.time >= cutoff }) {
            // Retain a real predecessor for interpolation at the exact left edge.
            // Without it, one second of empty space reappears as each point expires.
            let keepPrevious = firstVisible > 0 && samples[firstVisible].time > cutoff
                && Self.isValid(samples[firstVisible - 1]) && Self.isValid(samples[firstVisible])
                && samples[firstVisible].time - samples[firstVisible - 1].time <= 1.75
            let removeCount = firstVisible - (keepPrevious ? 1 : 0)
            if removeCount > 0 { samples.removeFirst(removeCount) }
        }
        if samples.count > 64 { samples.removeFirst(samples.count - 64) }
    }

    mutating func clear() { samples.removeAll() }

    static func isValid(_ sample: MemoryPressureMonitor.Sample) -> Bool {
        guard let value = sample.numericValue else { return false }
        return value.isFinite && (0...100).contains(value)
    }

    var runs: [[MemoryPressureMonitor.Sample]] {
        guard let latestTime = samples.last?.time else { return [] }
        var result: [[MemoryPressureMonitor.Sample]] = []
        var run: [MemoryPressureMonitor.Sample] = []
        for sample in samples {
            guard Self.isValid(sample) else {
                if !run.isEmpty { result.append(run); run = [] }
                continue
            }
            if let previous = run.last, sample.time - previous.time > 1.75 {
                result.append(run)
                run = []
            }
            run.append(sample)
        }
        if !run.isEmpty { result.append(run) }
        let cutoff = latestTime - Self.duration
        return result.compactMap { run in
            guard let firstVisible = run.firstIndex(where: { $0.time >= cutoff }) else { return nil }
            var visible = Array(run[firstVisible...])
            if firstVisible > 0, run[firstVisible].time > cutoff {
                let before = run[firstVisible - 1]
                let after = run[firstVisible]
                let fraction = (cutoff - before.time) / (after.time - before.time)
                visible.insert(.init(time: cutoff, level: fraction < 0.5 ? before.level : after.level,
                    numericValue: before.numericValue! + (after.numericValue! - before.numericValue!) * fraction), at: 0)
            }
            return visible
        }
    }
}

@MainActor
final class HUDMemoryPressureHistoryView: NSView {
    private(set) var history = HUDMemoryPressureHistory()
    private var colored = false
    private var scale: CGFloat = 1
    private var width: CGFloat = 72.6
    private var background: HUDBackground = .dark

    override var intrinsicContentSize: NSSize {
        NSSize(width: width, height: NSView.noIntrinsicMetric)
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
        setAccessibilityLabel("Memory pressure history")
        setAccessibilityHelp("Last 30 seconds on a fixed 0–100 scale. The dotted line marks 100; the endpoint dot marks the current reading. Style B2 uses colour to show macOS pressure state.")
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    func configure(mode: HUDMemoryPressureMode, scale: HUDScale, background: HUDBackground, width: CGFloat) {
        colored = mode == .colorHistory
        self.background = background
        if self.scale != CGFloat(scale.rawValue) || self.width != width {
            self.scale = CGFloat(scale.rawValue)
            self.width = width
            invalidateIntrinsicContentSize()
        }
        needsDisplay = true
    }

    func append(_ sample: MemoryPressureMonitor.Sample) {
        history.append(sample)
        guard let sample = history.samples.last else { return }
        if HUDMemoryPressureHistory.isValid(sample), let value = sample.numericValue {
            setAccessibilityValue("\(sample.level?.displayText ?? "Unknown status"), numeric level \(Int(value))")
        } else { setAccessibilityValue("Current numeric pressure unavailable") }
        needsDisplay = true
    }

    func clear() {
        history.clear()
        setAccessibilityValue("Waiting for pressure history")
        needsDisplay = true
    }

    // Zero is the bottom of the filled plot, with room for the endpoint halo
    // above and below. The fade changes opacity, never the numeric baseline.
    var plotBounds: NSRect {
        NSRect(x: 0.5 * scale, y: 3.5 * scale,
               width: max(0, bounds.width - 4 * scale),
               height: max(0, bounds.height - 7 * scale))
    }

    func point(for sample: MemoryPressureMonitor.Sample, latestTime: TimeInterval) -> NSPoint {
        let plot = plotBounds
        let x = plot.minX + plot.width * CGFloat(1 - (latestTime - sample.time) / HUDMemoryPressureHistory.duration)
        return NSPoint(x: x, y: plot.minY + plot.height * CGFloat((sample.numericValue ?? 0) / 100))
    }

    private func color(for level: MemoryPressureMonitor.Level?) -> NSColor {
        colored ? stateColor(for: level) : HUDStyle.readingColor(background: background)
    }

    private func stateColor(for level: MemoryPressureMonitor.Level?) -> NSColor {
        guard let level else { return HUDStyle.readingColor(background: background) }
        switch level {
        case .low: return NSColor(srgbRed: 0.29, green: 0.90, blue: 0.46, alpha: 1)
        case .medium: return HUDStyle.warningYellow
        case .high: return NSColor(srgbRed: 1, green: 0.39, blue: 0.36, alpha: 1)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let latestTime = history.samples.last?.time else { return }
        let runs = history.runs
        guard !runs.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
        drawGuides()
        // Fade only the history contour/fill. Guides and the current marker
        // remain separate so the reference scale and latest reading stay clear.
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        for run in runs where run.count >= 2 {
            let points = run.map { point(for: $0, latestTime: latestTime) }
            let outline = NSBezierPath()
            outline.move(to: points[0])
            for point in points.dropFirst() { outline.line(to: point) }
            outline.lineWidth = scale
            outline.lineJoinStyle = .round
            outline.lineCapStyle = .butt
            let area = outline.copy() as! NSBezierPath
            area.line(to: NSPoint(x: points.last!.x, y: plotBounds.minY))
            area.line(to: NSPoint(x: points[0].x, y: plotBounds.minY))
            area.close()

            // Clip one continuous contour into color regions. Drawing many short
            // rounded strokes independently would turn steady readings into dots.
            var start = 0
            while start < run.count {
                var end = start
                while end + 1 < run.count && (!colored || run[end + 1].level == run[start].level) { end += 1 }
                let left = start == 0 ? points[0].x : (points[start - 1].x + points[start].x) / 2
                let right = end == run.count - 1 ? points[end].x : (points[end].x + points[end + 1].x) / 2
                let tint = color(for: run[start].level)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: NSRect(x: left, y: 0, width: max(0, right - left), height: bounds.height)).addClip()
                NSGraphicsContext.saveGraphicsState()
                area.addClip()
                // Retain a little more tint near the divider, then taper to
                // transparent at zero without changing the plotted values.
                NSGradient(colors: [tint.withAlphaComponent(0), tint.withAlphaComponent(0.06),
                                    tint.withAlphaComponent(0.13), tint.withAlphaComponent(0.24)],
                           atLocations: [0, 0.1, 0.35, 1], colorSpace: .deviceRGB)?
                    .draw(in: plotBounds, angle: 90)
                NSGraphicsContext.restoreGraphicsState()
                tint.withAlphaComponent(0.9).setStroke()
                outline.stroke()
                NSGraphicsContext.restoreGraphicsState()
                start = end + 1
            }
        }
        if let oldest = runs.first?.first,
           let mask = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                 colorComponents: [1, 1, 1, 0, 1, 1, 1, 1],
                                 locations: [0, 1], count: 2) {
            let left = point(for: oldest, latestTime: latestTime).x
            context.saveGState()
            context.setBlendMode(.destinationIn)
            context.drawLinearGradient(mask, start: CGPoint(x: left, y: 0),
                                       end: CGPoint(x: left + 6 * scale, y: 0),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            context.restoreGState()
        }
        context.endTransparencyLayer()
        context.restoreGState()
        if let current = history.samples.last, HUDMemoryPressureHistory.isValid(current) {
            let center = point(for: current, latestTime: latestTime)
            let tint = color(for: current.level)
            func circle(radius: CGFloat) -> NSBezierPath {
                NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2))
            }
            tint.withAlphaComponent(0.22).setFill()
            circle(radius: 3 * scale).fill()
            tint.setFill()
            circle(radius: 1.6 * scale).fill()
        }
    }

    private func drawGuides() {
        let plot = plotBounds
        let tint = HUDStyle.readingColor(background: background)
        let ends = NSBezierPath()
        for x in [plot.minX, plot.maxX] {
            ends.move(to: NSPoint(x: x, y: plot.minY))
            ends.line(to: NSPoint(x: x, y: plot.maxY))
        }
        ends.lineWidth = 0.5 * scale
        tint.withAlphaComponent(0.16).setStroke()
        ends.stroke()

        let maximum = NSBezierPath()
        maximum.move(to: NSPoint(x: plot.minX, y: plot.maxY))
        maximum.line(to: NSPoint(x: plot.maxX, y: plot.maxY))
        maximum.lineWidth = 0.6 * scale
        maximum.setLineDash([1 * scale, 1.7 * scale], count: 2, phase: 0)
        tint.withAlphaComponent(0.35).setStroke()
        maximum.stroke()
    }
}
