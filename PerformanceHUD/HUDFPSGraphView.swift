import AppKit

// A rolling minute of per-interval readings from the selected Metal layer.
struct FPSHistory {
    struct Sample {
        let time: TimeInterval
        let fps: Double
        let startsSegment: Bool
        var timing: MetalFrameTiming? = nil
    }

    static let duration: TimeInterval = 60
    private(set) var samples: [Sample] = []
    private(set) var endTime: TimeInterval = 0
    private var interrupted = false

    var currentSample: Sample? { interrupted ? nil : samples.last }

    mutating func append(_ fps: Double, timing: MetalFrameTiming? = nil, at time: TimeInterval) {
        guard fps.isFinite, fps >= 0, time.isFinite else { return }
        if time < endTime { reset() }
        let startsSegment = interrupted || samples.last.map { time - $0.time > 3 } == true
        advance(to: time)
        samples.append(Sample(time: time, fps: fps, startsSegment: startsSegment, timing: timing))
        interrupted = false
        // Bound storage even if the underlying tool sends readings more frequently.
        if samples.count > 256 { samples.removeFirst(samples.count - 256) }
    }

    mutating func markUnavailable(at time: TimeInterval) {
        interrupted = true
        advance(to: time)
    }

    mutating func advance(to time: TimeInterval) {
        guard time.isFinite, time >= endTime else { return }
        endTime = time
        let cutoff = time - Self.duration
        guard let firstVisible = samples.firstIndex(where: { $0.time >= cutoff }) else {
            samples.removeAll(keepingCapacity: true)
            return
        }
        // Keep one predecessor so the curve reaches the exact window boundary
        // even when sample timing varies. Never bridge an unavailable interval.
        let needsPredecessor = firstVisible > 0 && samples[firstVisible].time > cutoff
            && !samples[firstVisible].startsSegment
        let removeCount = firstVisible - (needsPredecessor ? 1 : 0)
        if removeCount > 0 { samples.removeFirst(removeCount) }
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        endTime = 0
        interrupted = false
    }

    var visibleSegments: [[Sample]] {
        let cutoff = endTime - Self.duration
        var segments: [[Sample]] = []
        for (index, sample) in samples.enumerated() where sample.time >= cutoff {
            if segments.isEmpty || sample.startsSegment { segments.append([]) }
            if index > 0, segments[segments.count - 1].isEmpty,
               !sample.startsSegment, samples[index - 1].time < cutoff {
                let previous = samples[index - 1]
                let fraction = (cutoff - previous.time) / (sample.time - previous.time)
                var timing: MetalFrameTiming?
                if let a = previous.timing?.averageMS, let b = sample.timing?.averageMS {
                    timing = MetalFrameTiming(averageMS: a + (b - a) * fraction, worstMS: nil)
                }
                let boundary = Sample(time: cutoff,
                    fps: previous.fps + (sample.fps - previous.fps) * fraction, startsSegment: true, timing: timing)
                segments[segments.count - 1].append(boundary)
            }
            segments[segments.count - 1].append(sample)
        }
        return segments
    }

    func frameTimeUpperBound(holding previous: Double? = nil) -> Double {
        let minimumCeiling = 100.0
        let cutoff = endTime - Self.duration
        let averages = samples.filter { $0.time >= cutoff }.compactMap { $0.timing?.averageMS }.sorted()
        guard !averages.isEmpty else { return minimumCeiling }
        let current = max(previous ?? minimumCeiling, minimumCeiling)
        let middle = averages.count / 2
        let median = averages.count.isMultiple(of: 2) ? (averages[middle - 1] + averages[middle]) / 2 : averages[middle]
        let desired = 3 * median
        let step = 10.0
        // Give each step a 1 ms margin on both sides of the switching threshold.
        let margin = 1.0
        if desired > current + margin { return ceil((desired - margin) / step) * step }
        if desired <= current - step - margin { return max(minimumCeiling, ceil((desired + margin) / step) * step) }
        return current
    }

    var displayRange: ClosedRange<Double> {
        let visible = visibleSegments.flatMap { $0 }
        let minimum = visible.map(\.fps).min() ?? 0
        let maximum = visible.map(\.fps).max() ?? 0
        // A tighter range reveals trends without turning 1 FPS of jitter into
        // a full-height spike. Round outwards to reduce small scale changes.
        let padding = max(3, (maximum - minimum) * 0.15)
        let span = max(30, maximum * 0.5, maximum - minimum + 2 * padding)
        let lower = max(0, (minimum + maximum - span) / 2)
        return (floor(lower / 5) * 5)...(ceil((lower + span) / 5) * 5)
    }
}

// Shape-preserving cubic curves: smoothing cannot invent peaks or dips between
// readings. Each unavailable interval is drawn as a separate, unconnected path.
enum FPSHistoryCurve {
    static func path(through points: [NSPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }
        let slopes = zip(points, points.dropFirst()).map { a, b -> CGFloat in
            b.x > a.x ? (b.y - a.y) / (b.x - a.x) : 0
        }
        var tangents = [slopes[0]]
        for index in 1..<slopes.count {
            let before = slopes[index - 1]
            let after = slopes[index]
            tangents.append(before * after > 0 ? 2 * before * after / (before + after) : 0)
        }
        tangents.append(slopes[slopes.count - 1])
        for index in 1..<points.count {
            let a = points[index - 1]
            let b = points[index]
            let third = (b.x - a.x) / 3
            path.curve(to: b,
                       controlPoint1: NSPoint(x: a.x + third, y: a.y + tangents[index - 1] * third),
                       controlPoint2: NSPoint(x: b.x - third, y: b.y - tangents[index] * third))
        }
        return path
    }
}

/// The target can move again before the previous half-second transition completes.
struct FPSHistoryScale {
    private var origin: ClosedRange<Double>?
    private(set) var target: ClosedRange<Double>?
    private var started: TimeInterval = 0
    static let duration: TimeInterval = 0.5

    mutating func set(_ range: ClosedRange<Double>, at time: TimeInterval) {
        guard range != target else { return }
        origin = value(at: time) ?? range
        target = range
        started = time
    }

    func value(at time: TimeInterval) -> ClosedRange<Double>? {
        guard let origin, let target else { return nil }
        let t = min(1, max(0, (time - started) / Self.duration))
        let mix = t * t * (3 - 2 * t)
        let lower = origin.lowerBound + (target.lowerBound - origin.lowerBound) * mix
        let upper = origin.upperBound + (target.upperBound - origin.upperBound) * mix
        return lower...upper
    }
}

@MainActor
final class HUDFPSGraphView: NSView {
    private static let fullHitchDepthMS = 200.0
    private var history = FPSHistory()
    private var lineColor = NSColor.secondaryLabelColor
    private var baselineColor = HUDStyle.separatorColor(background: .dark)
    private var hudScale: CGFloat = 1
    private var measure = HUDFPSMeasure.frameRate
    private var hitchMarks = true
    private var plotScale = FPSHistoryScale()
    private var scaleTask: Task<Void, Never>?
    private let heading = NSTextField(labelWithString: "")
    var showsHeading = false {
        didSet { heading.isHidden = !showsHeading; needsLayout = true; needsDisplay = true }
    }

    private var unavailableTask: Task<Void, Never>?

    // A following category supplies this line when its divider is visible.
    var showsBaseline = true {
        didSet { if showsBaseline != oldValue { needsDisplay = true } }
    }

    private var dotHaloRadius: CGFloat { 3 * hudScale }

    // Align the plot with the other rows, reserving the halo in the HUD's
    // outer padding instead of shortening the line and fill before the divider.
    override var alignmentRectInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: dotHaloRadius)
    }

    var plotBounds: NSRect {
        let halfLineWidth = 1.35 * hudScale / 2
        let fadeExtension = HUDStyle.fpsHistoryFadeExtension * hudScale
        return NSRect(x: bounds.minX + halfLineWidth, y: bounds.minY + 9 * hudScale + fadeExtension,
                      width: max(0, bounds.width - halfLineWidth - dotHaloRadius),
                      height: max(0, bounds.height - (showsHeading ? 21 * hudScale : 0) - 12 * hudScale - fadeExtension))
    }

    init() {
        super.init(frame: .zero)
        setAccessibilityElement(true)
        heading.isHidden = true
        addSubview(heading)
        configure(measure: .frameRate, hitchMarks: true)
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    deinit { unavailableTask?.cancel(); scaleTask?.cancel() }

    override func layout() {
        super.layout()
        let h = heading.intrinsicContentSize.height
        heading.frame = NSRect(x: 0, y: bounds.maxY - 10.5 * hudScale - h / 2, width: bounds.width, height: h)
    }

    func configure(measure: HUDFPSMeasure, hitchMarks: Bool) {
        let measureChanged = self.measure != measure
        self.measure = measure
        self.hitchMarks = hitchMarks
        if measureChanged {
            // Start directly in the new unit using the same collected samples.
            plotScale = FPSHistoryScale()
            updateScale()
        }
        heading.stringValue = measure.caption
        setAccessibilityLabel("\(measure.caption) history, last 60 seconds")
        let warning = hitchMarks ? " Yellow marks a hitch. Red marks a severe hitch." : ""
        let depth = hitchMarks && measure == .frameRate ? " Longer hitches extend farther down." : ""
        let series = measure == .frameRate ? "The curve shows FPS." :
            "Each bar shows the worst displayed frame interval in one second. The line shows the average in milliseconds."
        setAccessibilityHelp(series + " The endpoint dot marks the current reading." + warning + depth)
        needsDisplay = true
    }

    func applyStyle(scale: HUDScale, background: HUDBackground) {
        if hudScale != CGFloat(scale.rawValue) {
            hudScale = CGFloat(scale.rawValue)
            invalidateIntrinsicContentSize()
        }
        heading.font = HUDStyle.titleFont(for: .fps, scale: scale)
        heading.textColor = HUDStyle.primaryTitleColor(for: .fps, background: background)
        needsLayout = true
        lineColor = HUDStyle.titleColor(for: .gpuTotal, background: background)
        baselineColor = HUDStyle.separatorColor(background: background)
        needsDisplay = true
    }

    func append(_ fps: Double, timing: MetalFrameTiming? = nil, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        unavailableTask?.cancel()
        unavailableTask = nil
        history.append(fps, timing: timing, at: time)
        updateScale()
    }

    func markUnavailable() {
        history.markUnavailable(at: ProcessInfo.processInfo.systemUptime)
        updateScale()
        guard unavailableTask == nil, !history.samples.isEmpty else { return }
        // Age existing history out naturally while the FPS source is unavailable.
        unavailableTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                history.advance(to: ProcessInfo.processInfo.systemUptime)
                updateScale()
                if history.samples.isEmpty {
                    unavailableTask = nil
                    return
                }
            }
        }
    }

    func reset() {
        unavailableTask?.cancel()
        unavailableTask = nil
        history.reset()
        updateScale()
    }

    private func updateScale() {
        needsDisplay = true
        guard !history.samples.isEmpty else {
            scaleTask?.cancel()
            scaleTask = nil
            plotScale = FPSHistoryScale()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let range = measure == .frameRate ? history.displayRange
            : 0...history.frameTimeUpperBound(holding: plotScale.target?.upperBound)
        guard range != plotScale.target else { return }
        let hasPrevious = plotScale.target != nil
        plotScale.set(range, at: now)
        scaleTask?.cancel()
        guard hasPrevious, window != nil, !isHiddenOrHasHiddenAncestor else { return }
        scaleTask = Task { [weak self] in
            repeat {
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                guard let self else { return }
                needsDisplay = true
            } while ProcessInfo.processInfo.systemUptime - now < FPSHistoryScale.duration
        }
    }

    private func hitchColor(_ timing: MetalFrameTiming?) -> NSColor? {
        guard hitchMarks, let hitch = timing?.hitch else { return nil }
        switch hitch {
        case .warning: return HUDStyle.warningYellow
        case .severe: return HUDStyle.pressureRed
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !history.samples.isEmpty else { return }
        let lineWidth = 1.35 * hudScale
        var plot = plotBounds
        let fillBaseline = bounds.minY
        let isRate = measure == .frameRate
        if !isRate {
            let top = plot.maxY
            plot.origin.y = fillBaseline + lineWidth / 2
            plot.size.height = top - plot.minY
        }
        guard plot.width > 0, plot.height > 0 else { return }
        guard let range = plotScale.value(at: ProcessInfo.processInfo.systemUptime) else { return }
        func x(_ sample: FPSHistory.Sample) -> CGFloat {
            plot.maxX - CGFloat((history.endTime - sample.time) / FPSHistory.duration) * plot.width
        }
        func y(_ value: Double) -> CGFloat {
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            return plot.minY + CGFloat(min(1, max(0, fraction))) * plot.height
        }
        func point(_ sample: FPSHistory.Sample) -> NSPoint? {
            let value = isRate ? sample.fps : sample.timing?.averageMS
            return value.map { NSPoint(x: x(sample), y: y($0)) }
        }
        let segments = history.visibleSegments
        let gradient = HUDStyle.historyFillGradient(tint: lineColor)
        var marks: [(index: Int, color: NSColor, worstMS: Double)] = []
        func stroke(_ points: [NSPoint]) {
            guard let first = points.first, let last = points.last else { return }
            let path = FPSHistoryCurve.path(through: points)
            if isRate && points.count > 1 {
                let fill = path.copy() as! NSBezierPath
                fill.line(to: NSPoint(x: last.x, y: fillBaseline))
                fill.line(to: NSPoint(x: first.x, y: fillBaseline))
                fill.close()
                NSGraphicsContext.saveGraphicsState()
                fill.addClip()
                gradient?.draw(from: NSPoint(x: plot.midX, y: fillBaseline),
                               to: NSPoint(x: plot.midX, y: points.map(\.y).max() ?? plot.maxY), options: [])
                NSGraphicsContext.restoreGraphicsState()
            }
            if isRate {
                for mark in marks {
                    let center = points[mark.index]
                    let depth = (center.y - fillBaseline) * min(mark.worstMS / Self.fullHitchDepthMS, 1)
                    let rect = NSRect(x: center.x - 0.55 * hudScale, y: center.y - depth,
                                      width: 1.1 * hudScale, height: depth)
                    NSGradient(starting: mark.color.withAlphaComponent(0), ending: mark.color)?.draw(in: rect, angle: 90)
                }
            }
            if points.count == 1 {
                // An isolated hitch already has a vertical mark at its sample.
                if marks.isEmpty {
                    lineColor.setFill()
                    NSBezierPath(ovalIn: NSRect(x: first.x - lineWidth / 2, y: first.y - lineWidth / 2,
                                               width: lineWidth, height: lineWidth)).fill()
                }
                return
            }
            lineColor.setStroke()
            path.lineWidth = lineWidth
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()
            guard !marks.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
            // Tint the existing curve halfway to each neighbouring sample.
            let outline = path.cgPath.copy(strokingWithWidth: lineWidth, lineCap: .round,
                                           lineJoin: .round, miterLimit: path.miterLimit)
            context.saveGState()
            context.addPath(outline)
            context.clip()
            for (index, color, _) in marks {
                let x = points[index].x
                let left = index == 0 ? first.x - lineWidth / 2 : (points[index - 1].x + x) / 2
                let right = index == points.count - 1 ? last.x + lineWidth / 2 : (x + points[index + 1].x) / 2
                color.setFill()
                NSRect(x: left, y: bounds.minY, width: right - left, height: bounds.height).fill()
            }
            context.restoreGState()
        }
        let barWidth = max(hudScale, plot.width / CGFloat(FPSHistory.duration) * 0.60)
        for segment in segments {
            var points: [NSPoint] = []
            marks.removeAll(keepingCapacity: true)
            for sample in segment {
                guard let p = point(sample) else {
                    stroke(points)
                    points.removeAll(keepingCapacity: true)
                    continue
                }
                points.append(p)
                let color = hitchColor(sample.timing)
                if isRate {
                    if let color, let worst = sample.timing?.worstMS { marks.append((points.count - 1, color, worst)) }
                } else if let worst = sample.timing?.worstMS {
                    (color ?? lineColor.withAlphaComponent(0.28)).setFill()
                    let left = max(plot.minX, p.x - barWidth / 2)
                    let right = min(plot.maxX, p.x + barWidth / 2)
                    NSRect(x: left, y: fillBaseline, width: right - left, height: y(worst) - fillBaseline).fill()
                }
            }
            stroke(points)
        }
        if let current = history.currentSample, let center = point(current) {
            // Match the memory pressure graph's current-reading dot and halo.
            func circle(radius: CGFloat) -> NSBezierPath {
                NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2))
            }
            lineColor.withAlphaComponent(0.22).setFill()
            circle(radius: dotHaloRadius).fill()
            lineColor.setFill()
            circle(radius: 1.6 * hudScale).fill()
        }
        if showsBaseline {
            baselineColor.setFill()
            NSRect(x: bounds.minX, y: fillBaseline, width: plot.maxX - bounds.minX,
                   height: 0.5 * hudScale).fill()
        }
    }
}
