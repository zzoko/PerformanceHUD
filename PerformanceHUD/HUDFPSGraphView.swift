import AppKit

// A short history of the existing FPS readings, not a per-frame timing graph.
struct FPSHistory {
    struct Sample {
        let time: TimeInterval
        let fps: Double
        let startsSegment: Bool
    }

    static let duration: TimeInterval = 60
    private(set) var samples: [Sample] = []
    private(set) var endTime: TimeInterval = 0
    private var interrupted = false

    mutating func append(_ fps: Double, at time: TimeInterval) {
        guard fps.isFinite, fps >= 0, time.isFinite else { return }
        if time < endTime { reset() }
        let startsSegment = interrupted || samples.last.map { time - $0.time > 3 } == true
        advance(to: time)
        samples.append(Sample(time: time, fps: fps, startsSegment: startsSegment))
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
        samples.removeAll { $0.time < time - Self.duration }
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        endTime = 0
        interrupted = false
    }

    var upperBound: Double {
        max(60, ceil((samples.map(\.fps).max() ?? 0) / 30) * 30)
    }
}

@MainActor
final class HUDFPSGraphView: NSView {
    private var history = FPSHistory()
    private var lineColor = NSColor.secondaryLabelColor
    private var hudScale: CGFloat = 1
    private var unavailableTask: Task<Void, Never>?

    init() {
        super.init(frame: .zero)
        toolTip = "FPS history over the last 60 seconds, using approximately one reading per second. Not a frame-time graph."
        setAccessibilityElement(true)
        setAccessibilityLabel("FPS history, last 60 seconds")
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    deinit { unavailableTask?.cancel() }

    func applyStyle(scale: HUDScale, background: HUDBackground) {
        hudScale = CGFloat(scale.rawValue)
        lineColor = HUDStyle.titleColor(for: .gpuTotal, background: background)
        needsDisplay = true
    }

    func append(_ fps: Double) {
        unavailableTask?.cancel()
        unavailableTask = nil
        history.append(fps, at: ProcessInfo.processInfo.systemUptime)
        needsDisplay = true
    }

    func markUnavailable() {
        history.markUnavailable(at: ProcessInfo.processInfo.systemUptime)
        needsDisplay = true
        guard unavailableTask == nil, !history.samples.isEmpty else { return }
        // Age existing history out naturally while the FPS source is unavailable.
        unavailableTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                history.advance(to: ProcessInfo.processInfo.systemUptime)
                needsDisplay = true
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
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !history.samples.isEmpty, bounds.width > 0, bounds.height > 0 else { return }
        let lineWidth = hudScale
        let plot = bounds.insetBy(dx: lineWidth / 2, dy: 3 * hudScale)
        let upperBound = history.upperBound
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        let isolatedPoints = NSBezierPath()
        for (index, sample) in history.samples.enumerated() {
            let fraction = 1 - (history.endTime - sample.time) / FPSHistory.duration
            let point = NSPoint(x: plot.minX + CGFloat(fraction) * plot.width,
                                y: plot.minY + CGFloat(sample.fps / upperBound) * plot.height)
            if index == 0 || sample.startsSegment { path.move(to: point) }
            else { path.line(to: point) }
            let startsSegment = index == 0 || sample.startsSegment
            let endsSegment = index == history.samples.count - 1 || history.samples[index + 1].startsSegment
            if startsSegment && endsSegment {
                isolatedPoints.appendOval(in: NSRect(x: point.x - lineWidth / 2,
                                                     y: point.y - lineWidth / 2,
                                                     width: lineWidth, height: lineWidth))
            }
        }
        // No invented history or interpolation animation; the line grows as readings arrive.
        lineColor.setStroke()
        path.stroke()
        lineColor.setFill()
        isolatedPoints.fill()
    }
}
