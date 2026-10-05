import AppKit

// Drives the All options reveal. The host changes only its rounded visible
// surface and resizes the native glass and window together.
@MainActor final class HUDAutoHidePresentation {
    private(set) var enabled: Bool
    private(set) var progress: CGFloat
    private var target: CGFloat
    private var timer: Timer?
    var onChange: (() -> Void)?
    var targetsVisible: Bool { target == 1 }
    var isHidden: Bool { enabled && progress <= 0 && target == 0 }

    init(enabled: Bool) {
        self.enabled = enabled
        progress = enabled ? 0 : 1
        target = progress
    }

    func setEnabled(_ enabled: Bool, visible: Bool, animated: Bool, initialProgress: CGFloat? = nil) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        if enabled {
            if let initialProgress { progress = min(1, max(0, initialProgress)) }
            transition(visible: visible, animated: animated)
        }
        else {
            stop()
            progress = 1; target = 1
            onChange?()
        }
    }

    func transition(visible: Bool, animated: Bool) {
        guard enabled else { return }
        let next: CGFloat = visible ? 1 : 0
        if animated && target == next && timer != nil { return }
        stop()
        target = next
        // Order the hidden panel in before the first frame of expansion.
        onChange?()
        guard animated, progress != target else {
            progress = target
            onChange?()
            return
        }
        let start = progress
        let started = ProcessInfo.processInfo.systemUptime
        let duration = HUDFPSAvailability.animationDuration * Double(abs(next - start))
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let t = min(1, (ProcessInfo.processInfo.systemUptime - started) / duration)
                let eased = t * t * (3 - 2 * t)
                self.progress = start + (next - start) * CGFloat(eased)
                if t >= 1 { timer.invalidate(); self.timer = nil }
                self.onChange?()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }
}
