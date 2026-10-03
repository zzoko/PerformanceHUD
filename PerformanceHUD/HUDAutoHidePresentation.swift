import AppKit

// Drives the All options reveal. The host changes only its rounded visible
// surface, leaving the window and capture footprint fixed.
@MainActor final class HUDAutoHidePresentation {
    private(set) var enabled: Bool
    private(set) var progress: CGFloat
    private var target: CGFloat
    private var timer: Timer?
    private var revealSuspended = false
    private var revealAnimated = false
    var onChange: (() -> Void)?
    var isHidden: Bool { enabled && progress <= 0 && target == 0 }

    init(enabled: Bool) {
        self.enabled = enabled
        progress = enabled ? 0 : 1
        target = progress
    }

    func setEnabled(_ enabled: Bool, visible: Bool, animated: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        if enabled { transition(visible: visible, animated: animated) }
        else {
            stop()
            progress = 1; target = 1
            onChange?()
        }
    }

    func transition(visible: Bool, animated: Bool) {
        guard enabled else { return }
        let next: CGFloat = visible ? 1 : 0
        if animated && target == next && (timer != nil || (visible && revealSuspended)) { return }
        stop()
        target = next
        if visible { revealAnimated = animated }
        // Announce an expansion before its first frame so the hidden panel and
        // its capture can start again while the reveal is still at zero.
        onChange?()
        // Ordering the window in can start a first-frame wait synchronously.
        // Hold the animation at its starting point until the glass is usable.
        if visible && revealSuspended { return }
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

    func setRevealSuspended(_ suspended: Bool, resume: Bool = true) {
        guard revealSuspended != suspended else { return }
        revealSuspended = suspended
        if suspended && target == 1 { stop() }
        else if !suspended && resume && enabled && target == 1 {
            transition(visible: true, animated: revealAnimated)
        }
    }

    func stop() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }
}
