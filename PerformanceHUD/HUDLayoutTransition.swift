import Foundation

/// Window-independent timing in the HUD's normal, unscaled layout points.
struct HUDLayoutTransition {
    let start: CGSize
    let end: CGSize
    let duration: TimeInterval
    let handoff: TimeInterval
    private let widthStart, heightStart: TimeInterval
    private let widthDuration, heightDuration: TimeInterval
    private static let halfFade: TimeInterval = 0.05

    init(from start: CGSize, to end: CGSize) {
        self.start = start
        self.end = end
        func travel(_ a: CGFloat, _ b: CGFloat) -> TimeInterval {
            let extent = max(a, b)
            return extent > 0 ? HUDFPSAvailability.animationDuration * Double(abs(b - a) / extent) : 0
        }
        var w = travel(start.width, end.width), h = travel(start.height, end.height)
        var wx = 0.0, hy = 0.0
        let middle: TimeInterval
        let dw = end.width - start.width, dh = end.height - start.height
        if dw * dh < 0 {
            let overlap = min(0.04, w, h)
            if dw < 0 { hy = w - overlap } else { wx = h - overlap }
            middle = max(wx, hy) + overlap / 2
        } else {
            // A short strip can change both dimensions in the same direction.
            // Move them together, including the single-axis and equal-size cases.
            w = max(w, h)
            h = w
            middle = w / 2
        }
        // Even a tiny (or zero) change in size has time for the content handoff.
        let lead = max(0, Self.halfFade - middle)
        widthStart = lead + wx
        heightStart = lead + hy
        widthDuration = w
        heightDuration = h
        handoff = lead + middle
        duration = max(widthStart + w, heightStart + h, handoff + Self.halfFade)
    }

    func frame(at elapsed: TimeInterval) -> (size: CGSize, outgoing: CGFloat, incoming: CGFloat) {
        func ease(from begin: TimeInterval, over span: TimeInterval) -> CGFloat {
            guard span > 0 else { return elapsed >= begin ? 1 : 0 }
            let t = min(1, max(0, (elapsed - begin) / span))
            return CGFloat(t * t * (3 - 2 * t))
        }
        return (CGSize(width: start.width + (end.width - start.width) * ease(from: widthStart, over: widthDuration),
                       height: start.height + (end.height - start.height) * ease(from: heightStart, over: heightDuration)),
                1 - ease(from: handoff - Self.halfFade, over: Self.halfFade),
                ease(from: handoff, over: Self.halfFade))
    }
}
