// Appended to the glass implementation so synthetic frames can exercise the
// real reveal callbacks without recording the screen or requesting permission.
@main struct GlassRevealTests {
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }
    @MainActor static func main() async {
        _ = NSApplication.shared
        UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "fps",
            "hud.background": "dark"], forName: UserDefaults.argumentDomain)

        let gate = HUDGlassRevealGate(timeout: .milliseconds(150))
        var waits = 0
        var completions = 0
        var cancellations = 0
        gate.onWait = { waits += 1 }
        gate.onFinish = { cancelled in
            if cancelled { cancellations += 1 } else { completions += 1 }
        }
        gate.begin(hasFrame: true, needsAttention: false)
        gate.begin(hasFrame: false, needsAttention: true)
        precondition(!gate.isWaiting && waits == 0, "Cached glass and permission/failure states must not wait")
        gate.begin(hasFrame: false, needsAttention: false)
        gate.begin(hasFrame: false, needsAttention: false)
        precondition(gate.isWaiting && waits == 1, "Repeated updates must not restart the wait")
        gate.update(hasFrame: true, needsAttention: false)
        precondition(!gate.isWaiting && completions == 1, "The first usable frame must release the reveal immediately")
        try? await Task.sleep(for: .milliseconds(220))
        precondition(completions == 1, "A completed wait must cancel its timeout")
        gate.begin(hasFrame: false, needsAttention: false)
        gate.update(hasFrame: false, needsAttention: true)
        precondition(!gate.isWaiting && completions == 2, "Capture failures must release the readable fallback")
        gate.begin(hasFrame: false, needsAttention: false)
        try? await Task.sleep(for: .milliseconds(220))
        precondition(!gate.isWaiting && completions == 3, "Slow capture must not leave the HUD invisible indefinitely")
        gate.begin(hasFrame: false, needsAttention: false)
        gate.finish(cancelled: true)
        try? await Task.sleep(for: .milliseconds(220))
        precondition(!gate.isWaiting && cancellations == 1 && completions == 3, "Disable must cancel the pending reveal")

        for alignment in [HUDAlignment.vertical, .horizontal] {
            let hud = HUDWindowController()
            hud.setAlignment(alignment)
            hud.setAutoHideMode(.all)
            let presentation: HUDAutoHidePresentation = member(hud, "autoHidePresentation")
            let waiting: HUDGlassRevealGate = member(hud, "glassRevealGate")
            let root: NSView = member(hud, "windowContentView")
            let glass: PerformanceHUDGlassBackground = member(hud, "backgroundView")
            let surface: HUDGlassSurfaceView = member(glass, "surface")
            let viewport: HUDGlassViewport = member(glass, "viewport")
            let panel: HUDPanel = member(hud, "panel")
            presentation.transition(visible: true, animated: true)
            waiting.begin(hasFrame: false, needsAttention: false)
            let frame = panel.frame
            let capture = glass.convert(glass.captureBounds, to: nil)
            precondition(root.layer?.opacity == 0 && glass.preparingForReveal)
            precondition(viewport.size(or: .zero) == glass.captureBounds.size,
                         "Prepare full-size glass, not a transparent zero-height/width frame")
            try? await Task.sleep(for: .milliseconds(120))
            precondition(presentation.progress == 0 && waiting.isWaiting,
                         "All options must wait before beginning its expansion")
            let size = glass.captureBounds.size
            let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 0.2, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            let image = context.makeImage()!
            surface.show(image: image, scale: 1, style: .dark)
            precondition(!waiting.isWaiting && root.layer?.opacity == 1 && !glass.preparingForReveal)
            precondition(!surface.isShowingFallback && presentation.progress == 0,
                         "Begin expansion after the real glass frame replaces fallback")
            try? await Task.sleep(for: .milliseconds(160))
            precondition(presentation.progress > 0 && presentation.progress < 1)
            precondition(panel.frame == frame && glass.convert(glass.captureBounds, to: nil) == capture,
                         "Waiting and revealing must not move or resize the capture")
            try? await Task.sleep(for: .milliseconds(350))
            precondition(presentation.progress == 1)

            // Keep the held glass and its matching foreground through a style switch.
            surface.holdLastFrame()
            hud.setBackground(.light)
            let heldText: HUDBackground = member(hud, "hudBackground")
            precondition(heldText == .light && glass.displayedStyle == .dark && !glass.isShowingFallback)
            surface.show(image: image, scale: 1, style: .light)
            precondition(glass.displayedStyle == .light && !glass.isShowingFallback)

            // Disabling during a fresh wait must not show the HUD on a late frame.
            presentation.transition(visible: false, animated: false)
            surface.showFallback()
            presentation.transition(visible: true, animated: true)
            waiting.begin(hasFrame: false, needsAttention: false)
            hud.setHUDEnabled(false)
            surface.show(image: image, scale: 1, style: .light)
            precondition(!waiting.isWaiting && !panel.isVisible)
            hud.shutdown()
        }
        print("PASS: first-frame readiness, cached-frame bypass, bounded wait, permission/failure fallback, cancellation, paused/resumed animation, full glass warm-up, fixed capture geometry, held appearance, and late-frame safety in both layouts")
    }
}
