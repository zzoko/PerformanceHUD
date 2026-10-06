import AppKit

@main struct AutoHideAnimationTests {
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }
    @MainActor static func fixture(_ alignment: HUDAlignment, scale: HUDScale = .normal,
                                   animated: Bool) -> HUDWindowController {
        let hud = HUDWindowController()
        hud.setHUDEnabled(false)
        hud.setAutoHideAnimated(animated)
        hud.setAlignment(alignment)
        hud.setHUDScale(scale)
        hud.setPackagePowerOptions(.init(enabled: false))
        for metric in HUDMetric.allCases {
            hud.setMetricEnabled(metric, enabled: [.fps, .fpsGraph, .gpuTotal].contains(metric) && alignment.allows(metric))
        }
        hud.setAutoHideMode(.fps)
        hud.updateMetric(.gpuTotal, value: "42%")
        hud.setHUDEnabled(true)
        return hud
    }
    @MainActor static func main() async {
        _ = NSApplication.shared
        let suiteName = "AutoHideAnimation.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        precondition(HUDPreferences.autoHideAnimated(in: suite), "Animation defaults on for fresh and existing settings")
        HUDPreferences.setAutoHideAnimated(false, in: suite)
        for mode in HUDAutoHideMode.allCases {
            HUDPreferences.setAutoHideMode(mode, in: suite)
            precondition(!HUDPreferences.autoHideAnimated(in: UserDefaults(suiteName: suiteName)!))
        }
        HUDPreferences.resetOptions(in: suite)
        precondition(HUDPreferences.autoHideAnimated(in: suite) && HUDPreferences.autoHideMode(in: suite) == .fps)

        UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "fps",
            "hud.autoHide.animated": true, "hud.alignment": "vertical", "hud.background": "dark"],
            forName: UserDefaults.argumentDomain)
        let menu = HUDAutoHideMenuView(selected: .fps, animated: true)
        let control: NSSegmentedControl = member(menu, "control")
        let checkbox: NSButton = member(menu, "animatedControl")
        let menuWindow = NSWindow(contentRect: menu.frame, styleMask: [], backing: .buffered, defer: false)
        menuWindow.contentView = menu
        menu.layoutSubtreeIfNeeded()
        precondition(checkbox.title == "Animated" && checkbox.state == .on)
        let selectorRect = control.alignmentRect(forFrame: control.frame)
        let checkboxRect = checkbox.alignmentRect(forFrame: checkbox.frame)
        precondition(checkboxRect.minX >= selectorRect.maxX + 8 && abs(checkboxRect.midY - selectorRect.midY) < 0.1)
        precondition(menu.bounds.contains(checkbox.frame) && menu.bounds.contains(control.frame))
        var selectedMode: HUDAutoHideMode?
        var selectedAnimation: Bool?
        menu.onChange = { selectedMode = $0 }
        menu.onAnimatedChange = { selectedAnimation = $0 }
        checkbox.performClick(nil)
        precondition(selectedAnimation == false && selectedMode == nil && control.selectedSegment == 1)
        menu.select(.off)
        precondition(checkbox.isEnabled && checkbox.state == .off, "Off preserves the independent animation choice")
        menu.select(.all)
        precondition(checkbox.state == .off)
        if CommandLine.arguments.contains("--preview") {
            menu.appearance = NSAppearance(named: .darkAqua)
            menu.wantsLayer = true
            menu.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
            menu.select(.fps)
            checkbox.state = .on
            let bitmap = menu.bitmapImageRepForCachingDisplay(in: menu.bounds)!
            menu.cacheDisplay(in: menu.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/phud-animated-checkbox.png"))
        }

        for alignment in HUDAlignment.allCases {
            let hud = fixture(alignment, animated: false)
            let panel: HUDPanel = member(hud, "panel")
            let body: NSView = member(hud, "container")
            let arrow: NSImageView = member(hud, "collapsedFPSIndicator")
            let whole: HUDAutoHidePresentation = member(hud, "autoHidePresentation")
            let compact = body.frame.size
            precondition(!arrow.isHidden && panel.isVisible)
            hud.updateFPS(60)
            let expanded = body.frame.size
            let timer: Timer? = member(hud, "fpsAnimationTimer")
            precondition(expanded != compact && arrow.isHidden && timer == nil, "Unchecked Animated expands FPS instantly")
            hud.markFPSUnavailable()
            try? await Task.sleep(for: .milliseconds(250))
            precondition(body.frame.size == expanded, "Instant transitions still honor the three-second grace")
            try? await Task.sleep(for: .milliseconds(2900))
            precondition(body.frame.size == compact && !arrow.isHidden && panel.isVisible)
            hud.setAutoHideMode(.all)
            precondition(!panel.isVisible && whole.progress == 0, "Unchecked All options hides immediately")
            hud.setFPSOptions(.init(enabled: false, mode: .both))
            hud.updateFPS(60)
            precondition(panel.isVisible && whole.progress == 1, "Unchecked All options appears instantly even without its FPS category")
            let wholeTimer: Timer? = member(whole, "timer")
            precondition(wholeTimer == nil)
            hud.markFPSUnavailable()
            try? await Task.sleep(for: .milliseconds(3150))
            precondition(!panel.isVisible && hud.isAutomaticallyHidden)
            hud.setFPSOptions(.init(enabled: true, mode: .both))
            hud.setAutoHideMode(.off)
            let staticSize = body.frame.size
            precondition(panel.isVisible && !hud.isAutomaticallyHidden)
            hud.updateFPS(60)
            hud.markFPSUnavailable()
            try? await Task.sleep(for: .milliseconds(3150))
            precondition(body.frame.size == staticSize && panel.isVisible && arrow.isHidden, "Off never hides with Animated unchecked")
            hud.setAutoHideAnimated(true)
            precondition(body.frame.size == staticSize && panel.isVisible && arrow.isHidden, "Checking Animated does not change Off behavior")
            hud.shutdown()
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for alignment in HUDAlignment.allCases {
            for scale in [HUDScale.small, .normal, .large] {
                let hud = fixture(alignment, scale: scale, animated: true)
                let panel: HUDPanel = member(hud, "panel")
                let body: NSView = member(hud, "container")
                let arrow: NSImageView = member(hud, "collapsedFPSIndicator")
                let top: NSLayoutConstraint? = member(hud, "stackTopConstraint")
                let horizontal: HUDHorizontalView = member(hud, "horizontalView")
                let before = panel.frame
                let offset = alignment == .horizontal ? horizontal.frame.minX : top!.constant
                let rows: [HUDMetric: NSView] = member(hud, "metricRows")
                precondition(!arrow.isHidden)
                hud.setAutoHideMode(.all)
                if !reduceMotion {
                    precondition(panel.frame == before && !arrow.isHidden && rows[.fps]!.alphaValue == 0,
                                 "Collapsed FPS must not flash open when switching to All options")
                    precondition((alignment == .horizontal ? horizontal.frame.minX : top!.constant) == offset,
                                 "Existing content must retain its compact offset")
                    var previous = alignment == .horizontal ? body.frame.width : body.frame.height
                    for _ in 0..<25 where panel.isVisible {
                        try? await Task.sleep(for: .milliseconds(20))
                        let current = alignment == .horizontal ? body.frame.width : body.frame.height
                        precondition(current <= previous, "Handoff must only shrink; never expand FPS first")
                        precondition(panel.frame.minX == before.minX && panel.frame.maxY == before.maxY)
                        if panel.isVisible {
                            precondition(!arrow.isHidden && rows[.fps]!.alphaValue == 0)
                            precondition((alignment == .horizontal ? horizontal.frame.minX : top!.constant) == offset)
                        }
                        previous = current
                    }
                }
                precondition(hud.isAutomaticallyHidden && !panel.isVisible)
                hud.updateFPS(60)
                if !reduceMotion {
                    try? await Task.sleep(for: .milliseconds(80))
                    let whole: HUDAutoHidePresentation = member(hud, "autoHidePresentation")
                    precondition(whole.progress > 0 && whole.progress < 1)
                }
                hud.setAutoHideAnimated(false)
                let whole: HUDAutoHidePresentation = member(hud, "autoHidePresentation")
                let timer: Timer? = member(whole, "timer")
                precondition(panel.isVisible && whole.progress == 1 && timer == nil && arrow.isHidden,
                             "Unchecking Animated finishes a whole-HUD reveal immediately")
                hud.shutdown()
            }
            // Reverse the compact handoff when readings return before the HUD is gone.
            let reversing = fixture(alignment, animated: true)
            let body: NSView = member(reversing, "container")
            reversing.setAutoHideMode(.all)
            try? await Task.sleep(for: .milliseconds(60))
            let before = body.frame.size
            reversing.updateFPS(60)
            if !reduceMotion { precondition(body.frame.size == before, "Reversal starts at the current visible size") }
            try? await Task.sleep(for: .milliseconds(550))
            let full: NSSize = member(reversing, "expandedHUDSize")
            precondition(body.frame.size == full && !reversing.isAutomaticallyHidden)
            reversing.shutdown()

            let fps = fixture(alignment, animated: true)
            fps.updateFPS(60)
            try? await Task.sleep(for: .milliseconds(80))
            let progress: CGFloat = member(fps, "fpsProgress")
            if !reduceMotion { precondition(progress > 0 && progress < 1) }
            fps.setAutoHideAnimated(false)
            let finished: CGFloat = member(fps, "fpsProgress")
            let timer: Timer? = member(fps, "fpsAnimationTimer")
            precondition(finished == 1 && timer == nil, "Unchecking Animated finishes an FPS reveal immediately")
            fps.shutdown()
        }
        print("PASS: independent Animated defaults/persistence/reset and menu geometry; instant FPS/All options; unchanged delay; static Off; compact handoff at 0.5×/1×/2×, reversal and mid-animation disable in both layouts")
    }
}
