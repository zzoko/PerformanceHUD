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
    static func layoutTiming() {
        let tall = CGSize(width: 285, height: 398.5)
        let wide = CGSize(width: 1435.5, height: 49)
        let reveal = HUDFPSAvailability.animationDuration
        let taller = CGSize(width: tall.width, height: tall.height + 21)
        let narrower = CGSize(width: wide.width - 40, height: wide.height)
        let short = CGSize(width: tall.width, height: 49)
        // A preset resize moves at the auto-hide pace: the reveal time scaled by how much of the larger size
        // changes, on both axes together, and never shorter than the minimum.
        for (start, end, expected) in [(tall, taller, HUDLayoutTransition.minimumPresetDuration),
                                       (wide, narrower, HUDLayoutTransition.minimumPresetDuration),
                                       (short, tall, reveal * (398.5 - 49) / 398.5),
                                       (tall, short, reveal * (398.5 - 49) / 398.5),
                                       (tall, tall, 0)] {
            let preset = HUDLayoutTransition(from: start, to: end, kind: .preset)
            precondition(abs(preset.duration - expected) < 0.000001)
            precondition(preset.duration <= reveal, "Never slower than a full auto-hide reveal")
            let size = preset.frame(at: preset.duration / 4).size
            // Auto-hide's smoothstep covers 15.625% of the distance at one quarter of its duration.
            precondition(abs(size.width - (start.width + (end.width - start.width) * 0.15625)) < 0.000001)
            precondition(abs(size.height - (start.height + (end.height - start.height) * 0.15625)) < 0.000001)
            // No fades: growing shows the new readings from the first frame, shrinking keeps the old to the last.
            guard preset.duration > 0 else { continue }
            let grows = end.width * end.height > start.width * start.height
            for time in [0, preset.duration / 2, preset.duration * 0.99] {
                let frame = preset.frame(at: time)
                precondition(frame.outgoing == (grows ? 0 : 1) && frame.incoming == (grows ? 1 : 0))
            }
            precondition(preset.frame(at: preset.duration).incoming == 1 && preset.frame(at: preset.duration).outgoing == 0)
        }
        // A size that changes mid-flight carries on as one movement: no second ease-in, no minimum, and only
        // the time its remaining distance needs.
        let late = HUDLayoutTransition(from: tall, to: taller, kind: .preset, continuing: true)
        precondition(abs(late.duration - reveal * 21 / (398.5 + 21)) < 0.000001 && late.duration < HUDLayoutTransition.minimumPresetDuration)
        let lateQuarter = late.frame(at: late.duration / 4).size.height
        precondition(abs(lateQuarter - (tall.height + 21 * 0.4375)) < 0.000001, "Ease-out: already moving at the start")
        precondition(late.frame(at: late.duration).size == taller)
        for (start, end) in [(tall, wide), (wide, tall)] {
            let path = HUDLayoutTransition(from: start, to: end)
            precondition(abs(path.duration - 0.632) < 0.002)
            let early = path.frame(at: 0.12)
            if start == tall {
                precondition(early.size.width == start.width && early.size.height < start.height)
            } else {
                precondition(early.size.width < start.width && early.size.height == start.height)
            }
            let crossover = path.frame(at: path.handoff)
            precondition(crossover.size.width > tall.width && crossover.size.height > wide.height,
                         "Both edges are moving during the overlap")
            // No fades: the old readings show until the edges cross, then the new ones.
            precondition(crossover.outgoing == 0 && crossover.incoming == 1)
            for time in stride(from: 0, through: path.duration, by: path.duration / 40) {
                let frame = path.frame(at: time)
                precondition(frame.outgoing == (time < path.handoff ? 1 : 0) && frame.incoming == 1 - frame.outgoing,
                             "Exactly one set of readings is fully visible at every moment")
            }
        }
        for end in [tall, CGSize(width: 200, height: 80), CGSize(width: 700, height: 480),
                    CGSize(width: 285, height: 49), CGSize(width: 285.5, height: 398.5)] {
            let path = HUDLayoutTransition(from: tall, to: end)
            let middle = path.frame(at: path.handoff)
            precondition(abs(middle.size.width - (tall.width + end.width) / 2) < 0.001)
            precondition(abs(middle.size.height - (tall.height + end.height) / 2) < 0.001)
            precondition(path.frame(at: 0).size == tall && (path.duration == 0 || path.frame(at: 0).outgoing == 1))
            precondition(path.frame(at: path.duration).size == end && path.frame(at: path.duration).incoming == 1)
        }
    }

    @MainActor static func layoutSwitches() async {
        let hud = HUDWindowController()
        defer { hud.shutdown() }
        hud.setAutoHideMode(.off)
        hud.setAutoHideAnimated(false)
        hud.setHUDEnabled(true)
        let panel: HUDPanel = member(hud, "panel")
        let body: NSView = member(hud, "container")
        let live: NSView = member(hud, "scaledContentView")
        let glass: NativeGlassHUDBackground = member(hud, "backgroundView")
        let defaults = UserDefaults.standard
        let saved = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(saved, forName: UserDefaults.argumentDomain) }
        func select(_ layout: HUDAlignment) {
            var domain = saved
            domain["hud.alignment"] = layout.rawValue
            defaults.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
            hud.setAlignment(layout, animated: true)
        }
        func topLeft() -> CGPoint {
            panel.convertPoint(toScreen: body.convert(NSPoint(x: 0, y: body.bounds.maxY), to: nil))
        }
        select(.horizontal)
        let horizontal = body.frame.size
        select(.vertical)
        let vertical = body.frame.size
        precondition(vertical != horizontal && body.subviews.count == 1)
        hud.setAutoHideAnimated(true)
        for (layout, from, to) in [(HUDAlignment.horizontal, vertical, horizontal), (.vertical, horizontal, vertical)] {
            let anchor = topLeft()
            select(layout)
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                precondition(body.frame.size == to && body.subviews.count == 1)
                continue
            }
            precondition(body.frame.size == from && glass.clipsContent && live.alphaValue == 0)
            let snapshot = body.subviews.last as! NSImageView
            let bitmap = snapshot.image!.representations.first as! NSBitmapImageRep
            // The snapshot contains the readings and empty pixels around them, without glass.
            var ink = false, clear = false
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
                    let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                    ink = ink || alpha > 0.3
                    clear = clear || alpha == 0
                    if ink && clear { break }
                }
                if ink && clear { break }
            }
            precondition(ink && clear, "Outgoing content is a transparent snapshot with visible readings")
            let deadline = ProcessInfo.processInfo.systemUptime + 1.5
            var sawIntermediate = false
            while snapshot.superview != nil && ProcessInfo.processInfo.systemUptime < deadline {
                precondition(topLeft() == anchor && snapshot.frame.maxY == body.bounds.maxY)
                precondition(snapshot.alphaValue == 0 || live.alphaValue == 0)
                sawIntermediate = sawIntermediate || (body.frame.size != from && body.frame.size != to)
                try? await Task.sleep(for: .milliseconds(12))
            }
            precondition(sawIntermediate && topLeft() == anchor && body.frame.size == to)
            precondition(live.alphaValue == 1 && snapshot.superview == nil && !glass.clipsContent)
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        select(.horizontal)
        try? await Task.sleep(for: .milliseconds(100))
        let interrupted = body.frame
        select(.vertical)
        precondition(body.frame == interrupted && body.subviews.count == 2, "Reverse from the current viewport")
        hud.setAutoHideAnimated(false)
        precondition(body.frame.size == vertical && body.subviews.count == 1 && live.alphaValue == 1)
        hud.setAutoHideMode(.fps)
        let arrow: NSImageView = member(hud, "collapsedFPSIndicator")
        precondition(!arrow.isHidden)
        hud.setAutoHideAnimated(true)
        select(.horizontal)
        hud.updateFPS(60)
        try? await Task.sleep(for: .seconds(1.2))
        precondition(body.frame.size == horizontal && body.subviews.count == 1 && arrow.isHidden,
                     "FPS arriving during a layout switch reveals the live destination")
        select(.vertical)
        hud.setHUDEnabled(false)
        precondition(!panel.isVisible && body.subviews.count == 1)
        hud.setHUDEnabled(true)
        hud.setAutoHideAnimated(false)
        hud.setAutoHideMode(.off)
        hud.markFPSUnavailable()
        try? await Task.sleep(for: .seconds(3.1))
        hud.setAutoHideAnimated(true)
        hud.setAutoHideMode(.all)
        try? await Task.sleep(for: .milliseconds(500))
        select(.horizontal)
        precondition(hud.isAutomaticallyHidden && !panel.isVisible && body.subviews.count == 1)
    }

    @MainActor static func presetSwitches(_ alignment: HUDAlignment) async {
        let hud = fixture(alignment, animated: false)
        defer { hud.shutdown() }
        hud.setAutoHideMode(.off)
        let panel: HUDPanel = member(hud, "panel")
        let body: NSView = member(hud, "container")
        let glass: NativeGlassHUDBackground = member(hud, "backgroundView")
        let compact = HUDPresetConfiguration.builtIn(.fpsOnly)
        let detailed = HUDPresetConfiguration.builtIn(.full)
        hud.applyPreset(detailed)
        let large = body.frame.size
        hud.applyPreset(compact)
        let small = body.frame.size
        precondition(large != small && !glass.clipsContent)

        // Switching from SOC alone to FPS alone removes the last old category
        // before the FPS setter runs. Keep the native glass session alive.
        let session: NativeGlassSession = member(hud, "glassSession")
        var stopped = false
        hud.onGlassSessionChange = { stopped = stopped || session.status == "Stopped" }
        var socOnly = compact
        socOnly.fps.enabled = false
        socOnly.packagePower.enabled = true
        hud.applyPreset(socOnly)
        hud.applyPreset(compact)
        precondition(!stopped && panel.isVisible && body.frame.size == small)
        hud.onGlassSessionChange = nil

        hud.setAutoHideAnimated(true)
        for (preset, start, end) in [(detailed, small, large), (compact, large, small)] {
            let anchor = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
            hud.applyPreset(preset)
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                precondition(body.frame.size == end && !glass.clipsContent)
                continue
            }
            precondition(panel.isVisible && glass.clipsContent && body.frame.size == start)
            var sawIntermediate = false
            let deadline = ProcessInfo.processInfo.systemUptime + 1
            while glass.clipsContent && ProcessInfo.processInfo.systemUptime < deadline {
                precondition(panel.isVisible && glass.alphaValue == 1)
                precondition(panel.frame.minX == anchor.x && panel.frame.maxY == anchor.y)
                sawIntermediate = sawIntermediate || (body.frame.size != start && body.frame.size != end)
                try? await Task.sleep(for: .milliseconds(12))
            }
            precondition(sawIntermediate && body.frame.size == end && body.subviews.count == 1)
        }

        var custom = compact
        custom.fps.valueHighlighted.toggle()
        hud.applyPreset(custom)
        precondition(body.frame.size == small && !glass.clipsContent, "Same-size presets apply immediately")
        hud.applyPreset(detailed)
        try? await Task.sleep(for: .milliseconds(80))
        let interrupted = body.frame.size
        hud.applyPreset(compact)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            precondition(body.frame.size == interrupted, "Reverse from the visible size")
        }
        hud.setAutoHideAnimated(false)
        precondition(body.frame.size == small && !glass.clipsContent)
        hud.setAutoHideAnimated(true)
        hud.applyPreset(detailed)
        hud.setPackagePowerOptions(.init(enabled: false))
        precondition(panel.isVisible && !glass.clipsContent && body.frame.size != small, "Individual toggles are immediate")
        hud.applyPreset(compact)
        hud.setHUDEnabled(false)
        precondition(!panel.isVisible && body.subviews.count == 1)
        hud.applyPreset(detailed)
        precondition(!panel.isVisible, "A preset cannot enable the HUD")
        hud.setHUDEnabled(true)
        precondition(panel.isVisible && body.frame.size == large && !glass.clipsContent)
        hud.setAutoHideAnimated(false)
        hud.setAutoHideMode(.all)
        hud.setAutoHideAnimated(true)
        hud.applyPreset(compact)
        precondition(hud.isAutomaticallyHidden && !panel.isVisible)
        print("PASS: in-place preset growth, shrink, interruption and instant visibility in \(alignment)")
    }

    @MainActor static func main() async {
        _ = NSApplication.shared
        let suiteName = "AutoHideAnimation.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        precondition(!HUDAccessibility.reduceMotion(in: suite))
        suite.set(false, forKey: "hud.autoHide.animated")
        for mode in HUDAutoHideMode.allCases {
            HUDPreferences.setAutoHideMode(mode, in: suite)
            precondition(HUDAccessibility.reduceMotion(in: UserDefaults(suiteName: suiteName)!))
        }
        HUDPreferences.resetOptions(in: suite)
        precondition(HUDAccessibility.reduceMotion(in: suite) && HUDPreferences.autoHideMode(in: suite) == .fps)

        UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "fps",
            "hud.autoHide.animated": true, "hud.alignment": "vertical", "hud.background": "dark"],
            forName: UserDefaults.argumentDomain)
        layoutTiming()
        await layoutSwitches()
        for alignment in HUDAlignment.allCases { await presetSwitches(alignment) }
        let menu = HUDAutoHideMenuView(selected: .fps)
        let control: NSSegmentedControl = member(menu, "control")
        let status: NSTextField = member(menu, "status")
        let menuWindow = NSWindow(contentRect: menu.frame, styleMask: [], backing: .buffered, defer: false)
        menuWindow.contentView = menu
        menu.layoutSubtreeIfNeeded()
        precondition(status.isHidden && status.stringValue == "Hidden · Waiting for FPS readings")
        for mode in HUDAutoHideMode.allCases {
            menu.select(mode)
            for enabled in [false, true] {
                for hidden in [false, true] {
                    menu.updateStatus(hudEnabled: enabled, automaticallyHidden: hidden)
                    precondition(status.isHidden == !(mode == .all && enabled && hidden))
                }
            }
        }
        menu.select(.all)
        menu.updateStatus(hudEnabled: true, automaticallyHidden: true)
        menu.layoutSubtreeIfNeeded()
        let selectorRect = control.alignmentRect(forFrame: control.frame)
        let statusRect = status.alignmentRect(forFrame: status.frame)
        precondition(statusRect.minX >= selectorRect.maxX + 8 && abs(statusRect.midY - selectorRect.midY) < 0.1)
        precondition(menu.bounds.contains(status.frame) && menu.bounds.contains(control.frame))
        if CommandLine.arguments.contains("--preview") {
            menu.appearance = NSAppearance(named: .darkAqua)
            menu.wantsLayer = true
            menu.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
            let bitmap = menu.bitmapImageRepForCachingDisplay(in: menu.bounds)!
            menu.cacheDisplay(in: menu.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/phud-auto-hide-status.png"))
        }
        menu.select(.fps)
        precondition(status.isHidden)

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
        // Every mode pair must start at the current surface and move directly
        // to its destination. In particular All -> FPS must never expose the
        // expanded FPS rows when readings are unavailable.
        for alignment in HUDAlignment.allCases {
            for animated in [false, true] {
                for source in HUDAutoHideMode.allCases {
                    for destination in HUDAutoHideMode.allCases where source != destination {
                        let hud = fixture(alignment, animated: false)
                        let body: NSView = member(hud, "container")
                        let panel: HUDPanel = member(hud, "panel")
                        let arrow: NSImageView = member(hud, "collapsedFPSIndicator")
                        let rows: [HUDMetric: NSView] = member(hud, "metricRows")
                        hud.setAutoHideMode(destination)
                        let expected = body.frame.size
                        hud.setAutoHideMode(source)
                        let start = body.frame.size
                        let anchor = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
                        hud.setAutoHideAnimated(animated)
                        hud.setAutoHideMode(destination)
                        let description = "\(alignment): \(source) -> \(destination), animation=\(animated)"
                        func extent(_ size: NSSize) -> CGFloat {
                            alignment == .horizontal ? size.width : size.height
                        }
                        if animated && !reduceMotion {
                            precondition(body.frame.size == start, "Mode switch must not snap: \(description)")
                            var previous = extent(start)
                            var sawIntermediate = false
                            for _ in 0..<25 {
                                try? await Task.sleep(for: .milliseconds(20))
                                let current = extent(body.frame.size)
                                let end = extent(expected)
                                precondition(current >= min(extent(start), end) && current <= max(extent(start), end),
                                             "Mode switch overshot its destination: \(description)")
                                precondition(end > extent(start) ? current >= previous : current <= previous,
                                             "Mode switch reversed unexpectedly: \(description)")
                                if current != extent(start) && current != end { sawIntermediate = true }
                                if source == .all && destination == .fps {
                                    precondition(!arrow.isHidden && rows[.fps]!.alphaValue == 0,
                                                 "All -> FPS must reveal only the arrow: \(description)")
                                }
                                precondition(panel.frame.minX == anchor.x && panel.frame.maxY == anchor.y,
                                             "Mode switch moved its anchor: \(description)")
                                previous = current
                            }
                            precondition(sawIntermediate, "Missing animation: \(description)")
                        } else {
                            let timer: Timer? = member(hud, "modeAnimationTimer")
                            precondition(timer == nil, "Instant mode switch must not leave an animation timer")
                        }
                        precondition(body.frame.size == expected, "Wrong final size: \(description)")
                        precondition(hud.isAutomaticallyHidden == (destination == .all))
                        precondition(panel.isVisible == (destination != .all))
                        hud.shutdown()
                    }
                }
            }

            let interrupting = fixture(alignment, animated: false)
            let body: NSView = member(interrupting, "container")
            let compact = body.frame.size
            interrupting.setAutoHideMode(.all)
            interrupting.setAutoHideAnimated(true)
            interrupting.setAutoHideMode(.off)
            try? await Task.sleep(for: .milliseconds(100))
            let partial = body.frame.size
            interrupting.setAutoHideMode(.fps)
            if !reduceMotion { precondition(body.frame.size == partial, "Rapid mode changes continue from the current frame") }
            interrupting.setAutoHideAnimated(false)
            precondition(body.frame.size == compact, "Disabling Animation finishes at the compact FPS arrow")
            let timer: Timer? = member(interrupting, "modeAnimationTimer")
            precondition(timer == nil)
            interrupting.shutdown()
        }
        for alignment in HUDAlignment.allCases {
            for scale in [HUDScale.small, .normal, .large] {
                let hud = fixture(alignment, scale: scale, animated: true)
                let panel: HUDPanel = member(hud, "panel")
                let body: NSView = member(hud, "container")
                let arrow: NSImageView = member(hud, "collapsedFPSIndicator")
                let stack: NSView = member(hud, "stackView")
                let horizontal: HUDHorizontalView = member(hud, "horizontalView")
                let before = panel.frame
                let offset = alignment == .horizontal ? horizontal.frame.minX : stack.frame.minY
                let rows: [HUDMetric: NSView] = member(hud, "metricRows")
                precondition(!arrow.isHidden)
                hud.setAutoHideMode(.all)
                if !reduceMotion {
                    precondition(panel.frame == before && !arrow.isHidden && rows[.fps]!.alphaValue == 0,
                                 "Collapsed FPS must not flash open when switching to All options")
                    precondition((alignment == .horizontal ? horizontal.frame.minX : stack.frame.minY) == offset,
                                 "Existing content must retain its compact offset")
                    var previous = alignment == .horizontal ? body.frame.width : body.frame.height
                    for _ in 0..<25 where panel.isVisible {
                        try? await Task.sleep(for: .milliseconds(20))
                        let current = alignment == .horizontal ? body.frame.width : body.frame.height
                        precondition(current <= previous, "Handoff must only shrink; never expand FPS first")
                        precondition(panel.frame.minX == before.minX && panel.frame.maxY == before.maxY)
                        if panel.isVisible {
                            precondition(!arrow.isHidden && rows[.fps]!.alphaValue == 0)
                            precondition((alignment == .horizontal ? horizontal.frame.minX : stack.frame.minY) == offset)
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
        print("PASS: auto-hide waiting status and saved Reduce motion preference; every Off/FPS/All transition animated or instant; stable arrow reveal, rapid switching, unchanged delay, compact handoff at 0.5×/1×/2×, FPS recovery and mid-animation disable in both layouts")
    }
}
