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

    var displayRange: ClosedRange<Double> {
        let minimum = samples.map(\.fps).min() ?? 0
        let maximum = samples.map(\.fps).max() ?? 0
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
        let lineWidth = 1.35 * hudScale
        // Reserve the extra bottom area for the fade without moving or scaling the stroke.
        let fadeExtension = HUDStyle.fpsHistoryFadeExtension * hudScale
        let plot = NSRect(x: bounds.minX + lineWidth / 2, y: bounds.minY + 9 * hudScale + fadeExtension,
                          width: bounds.width - lineWidth,
                          height: bounds.height - 12 * hudScale - fadeExtension)
        let fillBaseline = bounds.minY
        guard plot.width > 0, plot.height > 0 else { return }
        let range = history.displayRange
        var segments: [[NSPoint]] = []
        for (index, sample) in history.samples.enumerated() {
            let fraction = 1 - (history.endTime - sample.time) / FPSHistory.duration
            let point = NSPoint(x: plot.minX + CGFloat(fraction) * plot.width,
                                y: plot.minY + CGFloat((sample.fps - range.lowerBound)
                                    / (range.upperBound - range.lowerBound)) * plot.height)
            if index == 0 || sample.startsSegment { segments.append([]) }
            segments[segments.count - 1].append(point)
        }
        // A long, gentle tail avoids a bright shelf followed by a rapid falloff.
        // Retain a faint tint at the divider so the fill stays visibly connected.
        let locations = (0...32).map { CGFloat($0) / 32 }
        let colors = locations.map { position in
            return lineColor.withAlphaComponent(0.045 + 0.295 * pow(position, 1.35))
        }
        let gradient = NSGradient(colors: colors, atLocations: locations, colorSpace: .deviceRGB)
        for points in segments {
            guard let first = points.first, let last = points.last else { continue }
            if points.count == 1 {
                lineColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: first.x - lineWidth / 2, y: first.y - lineWidth / 2,
                                           width: lineWidth, height: lineWidth)).fill()
                continue
            }
            let path = FPSHistoryCurve.path(through: points)
            let fill = path.copy() as! NSBezierPath
            fill.line(to: NSPoint(x: last.x, y: fillBaseline))
            fill.line(to: NSPoint(x: first.x, y: fillBaseline))
            fill.close()
            NSGraphicsContext.saveGraphicsState()
            fill.addClip()
            gradient?.draw(from: NSPoint(x: plot.midX, y: fillBaseline),
                           to: NSPoint(x: plot.midX, y: points.map(\.y).max() ?? plot.maxY), options: [])
            NSGraphicsContext.restoreGraphicsState()
            path.lineWidth = lineWidth
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            lineColor.setStroke()
            path.stroke()
        }
    }
}
