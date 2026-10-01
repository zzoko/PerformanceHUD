import AppKit

@main struct DynamicFPSTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }
    @MainActor static func main() async {
        _ = NSApplication.shared
        var availability = HUDFPSAvailability()
        check(!availability.expanded, "No startup dead space in Dynamic")
        availability.receivedReading()
        availability.unavailable(at: 10)
        availability.unavailable(at: 12)
        availability.advance(to: 13.9)
        check(availability.expanded, "Brief gaps keep the FPS area open")
        availability.advance(to: 14)
        check(!availability.expanded, "Repeated unavailability must not extend the deadline")
        availability.receivedReading()
        availability.unavailable(at: 20)
        availability.receivedReading()
        availability.advance(to: 30)
        check(availability.expanded, "A recovered sample cancels collapse")

        let domain: [String: Any] = ["hud.enabled": false, "hud.background": "dark", "hud.alignment": "vertical",
            "hud.fps.dynamic": false]
        UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
        check(!HUDPreferences.dynamicFPS, "Static remains the default")
        let menu = HUDFPSModeMenuView(dynamic: true, alignment: .vertical)
        let control: NSSegmentedControl = member(menu, "control")
        check(control.selectedSegment == 1 && control.isEnabled, "Dynamic is selectable vertically")
        menu.update(dynamic: true, alignment: .horizontal)
        check(control.selectedSegment == 0 && !control.isEnabled, "Horizontal forces Static")
        menu.update(dynamic: true, alignment: .vertical)
        check(control.selectedSegment == 1 && control.isEnabled, "Vertical restores saved choice")
        let menuWindow = NSWindow(contentRect: menu.frame, styleMask: [], backing: .buffered, defer: false)
        menuWindow.contentView = menu
        menu.layoutSubtreeIfNeeded()
        check(control.frame.maxX <= menu.bounds.width && control.frame.minX > 100,
              "Shared FPS mode control fits without crowding its label")
        if CommandLine.arguments.contains("--preview") {
            menu.appearance = NSAppearance(named: .darkAqua)
            menu.wantsLayer = true
            menu.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
            let bitmap = menu.bitmapImageRepForCachingDisplay(in: menu.bounds)!
            menu.cacheDisplay(in: menu.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/phud-dynamic-fps-menu.png"))
        }
        let suiteName = "DynamicFPS.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.set(true, forKey: "hud.fps.dynamic")
        HUDPreferences.resetOptions(in: suite)
        check(suite.persistentDomain(forName: suiteName)?["hud.fps.dynamic"] == nil, "Reset removes the experimental setting")

        for scale in [HUDScale(rawValue: 0.75), .normal, HUDScale(rawValue: 1.25)] {
            for fpsMetrics: Set<HUDMetric> in [[.fps], [.fpsGraph], [.fps, .fpsGraph]] {
                for body: Set<HUDMetric> in [[], [.cpuTotal], [.ramTotal], [.fans], [.battery], [.deviceInfo], [.cpuTotal, .ramTotal, .battery]] {
                    let hud = HUDWindowController()
                    hud.setPackagePowerOptions(.init(enabled: false))
                    for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: fpsMetrics.union(body).contains(metric)) }
                    hud.setHUDScale(scale)
                    let panel: HUDPanel = member(hud, "panel")
                    let container: NSView = member(hud, "container")
                    let glass: PerformanceHUDGlassBackground = member(hud, "backgroundView")
                    let expandedSize = container.frame.size
                    let expandedFrame = panel.frame
                    func captureRect() -> NSRect { panel.convertToScreen(glass.convert(glass.captureBounds, to: nil)) }
                    let originalRect = captureRect()
                    hud.setDynamicFPS(true)
                    check(container.frame.height < expandedSize.height, "Unavailable FPS collapses")
                    check(panel.frame == expandedFrame, "Collapse must not resize or move the capture window")
                    check(captureRect() == originalRect, "Capture mismatch scale=\(scale) fps=\(fpsMetrics) body=\(body), old=\(originalRect) new=\(captureRect()), container=\(container.frame), glass=\(glass.frame)")
                    if body.isEmpty {
                        check(container.alphaValue == 0 && container.frame.height == 0, "FPS-only leaves no empty panel")
                    } else {
                        check(container.alphaValue == 1 && container.frame.height > 0, "Other metrics remain visible")
                        let rows: [HUDMetric: NSView] = member(hud, "metricRows")
                        let host: NSView = member(hud, "backgroundContentView")
                        for metric in body {
                            let row = rows[metric]!
                            let rect = row.convert(row.bounds, to: host)
                            check(rect.minY >= -0.1 && rect.maxY <= host.bounds.height + 0.1, "Body rows must stay inside the visible crop: \(metric)")
                        }
                    }
                    hud.updateFPS(0)
                    check(container.frame.size == expandedSize, "Zero FPS is a valid reading and expands the panel")
                    hud.updateFPS(60)
                    check(panel.frame == expandedFrame && captureRect() == originalRect, "Samples do not move capture")
                    hud.markFPSUnavailable()
                    check(container.frame.size == expandedSize, "A single missing reading must not collapse")
                    hud.setDynamicFPS(false)
                    check(container.frame.size == expandedSize && glass.reservedCaptureSize == nil, "Static restores original geometry")
                    hud.setAlignment(.horizontal)
                    hud.setDynamicFPS(true)
                    check(glass.reservedCaptureSize == nil, "Horizontal never reserves Dynamic geometry")
                    hud.shutdown()
                }
            }
        }

        // Exercise real asynchronous collapse/recovery, including a cancelled deadline.
        let hud = HUDWindowController()
        hud.setDynamicFPS(true)
        let container: NSView = member(hud, "container")
        let panel: HUDPanel = member(hud, "panel")
        let glass: PerformanceHUDGlassBackground = member(hud, "backgroundView")
        let compact = container.frame.height
        hud.updateFPS(60)
        let expanded = container.frame.height
        let reserved = panel.frame
        check(expanded > compact, "Real sample expands")
        hud.resetFPS()
        try? await Task.sleep(for: .milliseconds(100))
        hud.updateFPS(45)
        try? await Task.sleep(for: .seconds(4.1))
        check(container.frame.height == expanded, "Cancelled deadline cannot hide recovered FPS")
        hud.markFPSUnavailable()
        try? await Task.sleep(for: .seconds(4.1))
        // A busy system may deliver the main-actor deadline after this task resumes.
        for _ in 0..<100 where container.frame.height != compact {
            try? await Task.sleep(for: .milliseconds(20))
        }
        check(container.frame.height == compact && panel.frame == reserved, "Delayed collapse: height=\(container.frame.height) expected=\(compact), frame=\(panel.frame) expectedFrame=\(reserved), progress=\(member(hud, "fpsProgress") as CGFloat), availability=\(member(hud, "fpsAvailability") as HUDFPSAvailability)")
        hud.updateFPS(.nan)
        check(container.frame.height == compact, "Invalid readings do not reopen FPS")
        hud.updateFPS(50)
        check(container.frame.height == expanded, "Next valid reading reopens")
        hud.setDynamicFPS(false)
        let staticSize = container.frame.size
        hud.markFPSUnavailable()
        try? await Task.sleep(for: .seconds(4.1))
        check(container.frame.size == staticSize && glass.reservedCaptureSize == nil, "Static ignores the collapse deadline")
        // Animate a visible native window with capture deliberately off. This
        // exercises the real timer without prompting for screen-recording access.
        hud.setBackground(.off)
        hud.setDynamicFPS(true)
        hud.setHUDEnabled(true)
        let animationStart = container.frame.height
        let animationWindow = panel.frame
        hud.updateFPS(60)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            try? await Task.sleep(for: .milliseconds(180))
            check(container.frame.height > animationStart && container.frame.height < staticSize.height,
                  "Visible native window should pass through an intermediate expansion height")
            check(panel.frame == animationWindow, "Animation must not resize the window")
            // Another sample during expansion must not restart its easing curve.
            hud.updateFPS(55)
        }
        try? await Task.sleep(for: .milliseconds(600))
        let finalExpanded = container.frame.height
        check(finalExpanded > animationStart && panel.frame == animationWindow, "Animation completes at expanded size")
        hud.resetFPS()
        try? await Task.sleep(for: .seconds(4.2))
        hud.updateFPS(48) // Reverse a collapse that has already started.
        try? await Task.sleep(for: .milliseconds(700))
        check(container.frame.height == finalExpanded, "Returning readings reverse an in-flight collapse")
        hud.setHUDEnabled(false)
        hud.shutdown()
        print("PASS: FPS availability, shared mode/reset, all scales/row selections, fixed capture geometry, FPS-only, horizontal, cancelled deadlines, recovery, native animation and reversal")
    }
}
