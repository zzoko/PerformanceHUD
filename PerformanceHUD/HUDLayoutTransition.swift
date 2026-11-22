import Foundation

/// Window-independent timing in the HUD's normal, unscaled layout points.
struct HUDLayoutTransition {
    enum Kind { case alignment, preset }
    private let kind: Kind
    let start: CGSize
    let end: CGSize
    let duration: TimeInterval
    let handoff: TimeInterval
    private let widthStart, heightStart: TimeInterval
    private let widthDuration, heightDuration: TimeInterval
    private static let halfFade: TimeInterval = 0.05

    init(from start: CGSize, to end: CGSize, kind: Kind = .alignment) {
        self.kind = kind
        self.start = start
        self.end = end
        func travel(_ a: CGFloat, _ b: CGFloat) -> TimeInterval {
            guard a != b else { return 0 }
            // Give even a one-row preset change the full auto-hide reveal time.
            if kind == .preset { return HUDFPSAvailability.animationDuration }
            let extent = max(a, b)
            return extent > 0 ? HUDFPSAvailability.animationDuration * Double(abs(b - a) / extent) : 0
        }
        var w = travel(start.width, end.width), h = travel(start.height, end.height)
        var wx = 0.0, hy = 0.0
        let middle: TimeInterval
        let dw = end.width - start.width, dh = end.height - start.height
        if kind == .alignment && dw * dh < 0 {
            let overlap = min(0.04, w, h)
            if dw < 0 { hy = w - overlap } else { wx = h - overlap }
            middle = max(wx, hy) + overlap / 2
        } else {
            // Presets resize both axes together. So do orientation changes
            // where neither axis needs to make room for the other.
            w = max(w, h)
            h = w
            middle = w / 2
        }
        // Only an orientation change needs time for the content fade.
        let halfFade = kind == .alignment ? Self.halfFade : 0
        let lead = max(0, halfFade - middle)
        widthStart = lead + wx
        heightStart = lead + hy
        widthDuration = w
        heightDuration = h
        handoff = lead + middle
        duration = max(widthStart + w, heightStart + h, handoff + halfFade)
    }

    func frame(at elapsed: TimeInterval) -> (size: CGSize, outgoing: CGFloat, incoming: CGFloat) {
        func ease(from begin: TimeInterval, over span: TimeInterval) -> CGFloat {
            guard span > 0 else { return elapsed >= begin ? 1 : 0 }
            let t = min(1, max(0, (elapsed - begin) / span))
            return CGFloat(t * t * (3 - 2 * t))
        }
        let size = CGSize(width: start.width + (end.width - start.width) * ease(from: widthStart, over: widthDuration),
                          height: start.height + (end.height - start.height) * ease(from: heightStart, over: heightDuration))
        if kind == .preset {
            // Reveal the new readings on growth. On shrink, clip the old readings
            // up to the last frame so the closing glass never trails empty space.
            let showOld = end.width * end.height < start.width * start.height && elapsed < duration
            return (size, showOld ? 1 : 0, showOld ? 0 : 1)
        }
        return (size, 1 - ease(from: handoff - Self.halfFade, over: Self.halfFade),
                ease(from: handoff, over: Self.halfFade))
    }
}
