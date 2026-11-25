import Foundation

/// Window-independent timing in the HUD's normal, unscaled layout points.
struct HUDLayoutTransition {
    enum Kind { case alignment, preset }
    private let kind: Kind
    private let continuing: Bool
    let start: CGSize
    let end: CGSize
    let duration: TimeInterval
    let handoff: TimeInterval
    private let widthStart, heightStart: TimeInterval
    private let widthDuration, heightDuration: TimeInterval
    /// Even a one-row preset change stays visible as a movement.
    static let minimumPresetDuration: TimeInterval = 0.2

    /// `continuing` is for a size that changed mid-flight (a reading arrived
    /// late): the glass is already moving, so it eases out without a new ease-in
    /// and takes only the time its remaining distance needs.
    init(from start: CGSize, to end: CGSize, kind: Kind = .alignment, continuing: Bool = false) {
        self.kind = kind
        self.continuing = continuing
        self.start = start
        self.end = end
        // Every HUD resize moves at the auto-hide pace: the full reveal time,
        // scaled by how much of the larger size actually changes.
        func travel(_ a: CGFloat, _ b: CGFloat) -> TimeInterval {
            guard a != b else { return 0 }
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
            if kind == .preset && !continuing && w > 0 { w = max(w, Self.minimumPresetDuration) }
            h = w
            middle = w / 2
        }
        widthStart = wx
        heightStart = hy
        widthDuration = w
        heightDuration = h
        handoff = middle
        duration = max(widthStart + w, heightStart + h)
    }

    func frame(at elapsed: TimeInterval) -> (size: CGSize, outgoing: CGFloat, incoming: CGFloat) {
        func ease(from begin: TimeInterval, over span: TimeInterval) -> CGFloat {
            guard span > 0 else { return elapsed >= begin ? 1 : 0 }
            let t = min(1, max(0, (elapsed - begin) / span))
            return CGFloat(continuing ? t * (2 - t) : t * t * (3 - 2 * t))
        }
        let size = CGSize(width: start.width + (end.width - start.width) * ease(from: widthStart, over: widthDuration),
                          height: start.height + (end.height - start.height) * ease(from: heightStart, over: heightDuration))
        // The readings never fade: one set is shown, then the other.
        let showOld: Bool
        if kind == .preset {
            // Reveal the new readings on growth. On shrink, clip the old readings
            // up to the last frame so the closing glass never trails empty space.
            showOld = end.width * end.height < start.width * start.height && elapsed < duration
        } else {
            // An orientation change swaps them as the two moving edges cross.
            showOld = elapsed < handoff
        }
        return (size, showOld ? 1 : 0, showOld ? 0 : 1)
    }
}
