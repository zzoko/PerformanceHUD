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
        availability.advance(to: 12.9)
        check(availability.expanded, "Brief gaps keep the FPS area open")
        availability.advance(to: 13)
        check(!availability.expanded, "Repeated unavailability must not extend the deadline")
        availability.receivedReading()
        availability.unavailable(at: 20)
        availability.receivedReading()
        availability.advance(to: 30)
        check(availability.expanded, "A recovered sample cancels collapse")

        let domain: [String: Any] = ["hud.enabled": false, "hud.autoHide.mode": "off", "hud.background": "dark", "hud.alignment": "vertical",
            "hud.fps.dynamic": false]
        UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
        check(HUDPreferences.autoHideMode == .off, "Off preserves static FPS")
        let suiteName = "DynamicFPS.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.set(true, forKey: "hud.fps.dynamic")
        HUDPreferences.resetOptions(in: suite)
        check(suite.persistentDomain(forName: suiteName)?["hud.fps.dynamic"] == nil, "Reset removes the experimental setting")

        // Migrate all legacy combinations and remember the selected mode while off.
        for value in [false, true] {
            for history in [false, true] {
                suite.removePersistentDomain(forName: suiteName)
                suite.set(value, forKey: "hud.metric.fps")
                suite.set(history, forKey: "hud.metric.fpsGraph")
                let options = HUDPreferences.fpsOptions(in: suite)
                check(options.enabled == (value || history), "Existing FPS visibility is preserved")
                let expected: Set<HUDMetric> = Set([value ? HUDMetric.fps : nil, history ? HUDMetric.fpsGraph : nil].compactMap { $0 })
                check(options.visibleMetrics(alignment: .vertical) == expected, "Existing value/history selection migrates")
            }
        }
        for mode in HUDFPSDisplayMode.allCases {
            HUDPreferences.setFPSOptions(.init(enabled: false, mode: mode), in: suite)
            let saved = HUDPreferences.fpsOptions(in: suite)
            check(!saved.enabled && saved.mode == mode, "Disabled FPS remembers its selected mode")
            HUDPreferences.setFPSOptions(.init(enabled: true, mode: saved.mode), in: suite)
            check(HUDPreferences.fpsOptions(in: suite).mode == mode, "Re-enabling restores the mode")
            check(HUDPreferences.fpsOptions(in: suite).visibleMetrics(alignment: .horizontal) == [.fps], "Horizontal uses Value")
        }
        check(HUDPreferences.fpsOptions(in: suite).valueHighlighted, "FPS emphasis defaults on")
        for enabled in [false, true] {
            for mode in HUDFPSDisplayMode.allCases {
                HUDPreferences.setFPSOptions(.init(enabled: enabled, mode: mode, valueHighlighted: true), in: suite)
                let saved = HUDPreferences.fpsOptions(in: suite)
                check(saved.enabled == enabled && saved.mode == mode && saved.valueHighlighted,
                      "FPS emphasis survives saving, History-only mode and category disabling")
            }
        }
        HUDPreferences.setFPSOptions(.init(enabled: true, mode: .both, valueHighlighted: false), in: suite)
        check(!HUDPreferences.fpsOptions(in: suite).valueHighlighted, "An explicit off preference survives the enabled default")
        HUDPreferences.resetOptions(in: suite)
        check(HUDPreferences.fpsOptions(in: suite).valueHighlighted, "All options restores enabled FPS emphasis")
        check(HUDPreferences.fpsOptions(in: suite).enabled && HUDPreferences.fpsOptions(in: suite).mode == .both,
              "Reset restores FPS with Both")
        suite.removePersistentDomain(forName: suiteName)

        let fpsMenu = HUDFPSMenuView(options: .init(enabled: true, mode: .both), alignment: .vertical)
        let fpsSelector: NSSegmentedControl = member(fpsMenu, "control")
        let fpsMaster: NSButton = member(fpsMenu, "master")
        let fpsHighlight: NSButton = member(fpsMenu, "valueHighlight")
        let fpsWindow = NSWindow(contentRect: fpsMenu.frame, styleMask: [], backing: .buffered, defer: false)
        fpsWindow.contentView = fpsMenu
        fpsMenu.layoutSubtreeIfNeeded()
        check(fpsSelector.frame.minX == 8 + HUDResourceMenuView.masterWidth + 8,
              "FPS selector starts at the GPU options column")
        check(fpsSelector.frame.maxX <= fpsMenu.bounds.maxX, "FPS selector fits its row")
        var selected: HUDFPSOptions?
        fpsMenu.onChange = { selected = $0 }
        check(fpsHighlight.isEnabled && fpsHighlight.state == .on, "FPS underline starts available and on")
        check(fpsMenu.hitTest(NSPoint(x: fpsHighlight.frame.midX, y: fpsHighlight.frame.midY)) === fpsHighlight,
              "FPS underline receives its own click instead of toggling the category")
        check(fpsHighlight.frame.maxY < fpsSelector.frame.midY && fpsHighlight.frame.minY >= 0,
              "FPS underline fits beneath the Value selector inside the existing row")
        check(fpsHighlight.frame.minX > fpsSelector.frame.minX
              && fpsHighlight.frame.maxX <= fpsSelector.frame.minX + fpsSelector.frame.width / 3
              && fpsHighlight.frame.width > fpsSelector.frame.width / 4
              && fpsHighlight.frame.minX > fpsMaster.frame.maxX,
              "FPS underline spans Value, clear of the category checkmark and History/Both buttons")
        fpsHighlight.performClick(nil)
        check(selected?.valueHighlighted == false && selected?.enabled == true && selected?.mode == .both,
              "Underline turns emphasis off independently of visibility and mode")
        fpsHighlight.performClick(nil)
        check(selected?.valueHighlighted == true, "Underline turns emphasis back on")
        fpsSelector.selectedSegment = 1
        _ = fpsSelector.sendAction(fpsSelector.action, to: fpsSelector.target)
        check(selected?.mode == .history, "History button updates options")
        check(!fpsHighlight.isEnabled && fpsHighlight.state == .on, "History disables emphasis while remembering it")
        fpsMaster.performClick(nil)
        check(!fpsHighlight.isEnabled && selected?.valueHighlighted == true, "Disabled category preserves emphasis")
        check(selected?.enabled == false && selected?.mode == .history && !fpsSelector.isEnabled,
              "Master hides FPS and remembers History")
        fpsMaster.performClick(nil)
        check(selected?.enabled == true && fpsSelector.selectedSegment == 1, "Master restores History")
        fpsMenu.update(options: .init(enabled: true, mode: .both), alignment: .horizontal)
        check(fpsSelector.selectedSegment == 0 && !fpsSelector.isEnabled(forSegment: 1)
              && !fpsSelector.isEnabled(forSegment: 2), "Horizontal disables History and Both")
        fpsMenu.update(options: .init(enabled: true, mode: .both), alignment: .vertical)
        check(fpsSelector.selectedSegment == 2 && fpsSelector.isEnabled(forSegment: 1), "Vertical restores Both")
        fpsMenu.update(options: .init(enabled: true, mode: .history, valueHighlighted: true), alignment: .horizontal)
        check(fpsHighlight.isEnabled && fpsHighlight.state == .on, "Horizontal allows emphasis despite saved History mode")
        fpsHighlight.performClick(nil)
        check(selected?.valueHighlighted == false && selected?.mode == .history, "Turning emphasis off preserves the saved vertical mode")
        fpsMenu.update(options: .init(enabled: true, mode: .both), alignment: .vertical)
        if CommandLine.arguments.contains("--preview") {
            fpsMenu.appearance = NSAppearance(named: .darkAqua)
            fpsMenu.wantsLayer = true
            fpsMenu.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
            let bitmap = fpsMenu.bitmapImageRepForCachingDisplay(in: fpsMenu.bounds)!
            fpsMenu.cacheDisplay(in: fpsMenu.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/phud-fps-selector-preview.png"))
        }

        let styledHUD = HUDWindowController()
        styledHUD.setHUDEnabled(false)
        styledHUD.setAutoHideMode(.off)
        let styledPanel: HUDPanel = member(styledHUD, "panel")
        let styledGlass: PerformanceHUDGlassBackground = member(styledHUD, "backgroundView")
        let styledHorizontal: HUDHorizontalView = member(styledHUD, "horizontalView")
        let styledGraph: HUDFPSGraphView = member(styledHUD, "fpsGraphView")
        let styledContainer: NSView = member(styledHUD, "container")
        var verticalFPSBaselines: [String: CGFloat] = [:]
        for alignment in HUDAlignment.allCases {
            styledHUD.setAlignment(alignment)
            styledHUD.setResourceOptions(.init(enabled: true, temperature: false, totalUse: true, focusedApp: false), for: .gpu)
            styledHUD.updateMetric(.gpuTotal, value: "97%")
            styledHUD.setFPSOptions(.init(enabled: true, mode: .both))
            for scale in [HUDScale.small, HUDScale(rawValue: 0.75), HUDScale(rawValue: 0.9), .normal,
                          HUDScale(rawValue: 1.25), .large] {
                styledHUD.setHUDScale(scale)
                styledHUD.updateFPS(60)
                styledGraph.append(60)
                let storedHistory: FPSHistory = member(styledGraph, "history")
                let frame = styledPanel.frame
                let capture = styledGlass.captureBounds
                let values: [HUDMetric: NSTextField] = member(styledHUD, "valueLabels")
                let titles: [HUDMetric: NSTextField] = member(styledHUD, "titleLabels")
                for highlighted in [false, true, false] {
                    styledHUD.setFPSOptions(.init(enabled: true, mode: .both, valueHighlighted: highlighted))
                    for value in [0.0, 8, 120, 9999] {
                        styledHUD.updateFPS(value)
                        let horizontalLabels: [String: NSTextField] = member(styledHorizontal, "labels")
                        let valueLabel = alignment == .horizontal ? horizontalLabels["0.value"]! : values[.fps]!
                        let expected = highlighted ? HUDStyle.TextStyle.emphasizedReading : .reading
                        check(valueLabel.font == expected.font(ofSize: 14 * CGFloat(scale.rawValue)), "FPS uses the selected style at its label size")
                        check(valueLabel.textColor == expected.color(background: .dark), "FPS color follows Reading or Emphasized Reading")
                        styledPanel.contentView?.layoutSubtreeIfNeeded()
                        let fpsTitle = alignment == .horizontal ? horizontalLabels["0.title"]! : titles[.fps]!
                        for (role, field) in [("title", fpsTitle), ("value", valueLabel)] {
                            let box = field.convert(field.bounds, to: styledContainer)
                            let topToBaseline = styledContainer.bounds.maxY - box.maxY + field.firstBaselineOffsetFromTop
                            let key = "\(scale.rawValue).\(highlighted).\(role)"
                            if alignment == .vertical { verticalFPSBaselines[key] = topToBaseline }
                            else {
                                check(abs(topToBaseline - verticalFPSBaselines[key]!) < 0.01,
                                      "Switching layout must not shift the FPS \(role) vertically at \(scale.rawValue)×")
                            }
                        }
                        let valueRect = valueLabel.alignmentRect(forFrame: valueLabel.frame)
                        check(valueRect.height + 0.5 >= valueLabel.intrinsicContentSize.height,
                              "The FPS value must retain its full text height")
                        check(valueRect.minY >= -0.5 && valueRect.maxY <= valueLabel.superview!.bounds.height + 0.5,
                              "The FPS value must fit its row in both layouts")
                        check(valueLabel.font?.pointSize == titles[.fps]?.font?.pointSize,
                              "FPS number matches its label size")
                        check(titles[.fps]?.font?.pointSize == titles[.gpuTotal]?.font?.pointSize,
                              "FPS and GPU labels keep equal sizes")
                        if alignment == .vertical {
                            styledPanel.contentView?.layoutSubtreeIfNeeded()
                            let gpu = values[.gpuTotal]!
                            let fpsRight = valueLabel.convert(valueLabel.bounds, to: nil).maxX
                            let gpuRight = gpu.convert(gpu.bounds, to: nil).maxX
                            check(abs(fpsRight - gpuRight) <= 0.5, "FPS number aligns with the GPU percentage's right edge")
                        }
                        check(styledPanel.frame == frame && styledGlass.captureBounds == capture,
                              "FPS emphasis and changing digits must not resize the window or capture")
                    }
                    let history: FPSHistory = member(styledGraph, "history")
                    check(history.samples.count == storedHistory.samples.count, "Emphasis must retain FPS history")
                    check(titles[.fps]?.font == HUDStyle.titleFont(for: .fps, scale: scale), "Emphasis affects only the FPS number")
                }
            }
        }
        styledHUD.shutdown()
        if CommandLine.arguments.contains("--controls-only") {
            print("PASS: FPS mode preferences, emphasis save/reset, independent underline clicks, History/Horizontal states, matching FPS baselines in both layouts at six scales from 0.5× to 2×, preserved history and stable capture geometry")
            return
        }

        for scale in [HUDScale.small, HUDScale(rawValue: 0.51), HUDScale(rawValue: 0.75), .normal,
                      HUDScale(rawValue: 1.01), HUDScale(rawValue: 1.25), HUDScale.large] {
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
                    hud.setAutoHideMode(.fps)
                    check(container.frame.height < expandedSize.height, "Unavailable FPS collapses")
                    check(panel.frame == expandedFrame, "Collapse must not resize or move the capture window")
                    check(captureRect() == originalRect, "Capture mismatch scale=\(scale) fps=\(fpsMetrics) body=\(body), old=\(originalRect) new=\(captureRect()), container=\(container.frame), glass=\(glass.frame)")
                    let header: NSImageView = member(hud, "collapsedFPSIndicator")
                    check(!header.isHidden && header.alphaValue == 1 && header.image != nil,
                          "Collapsed FPS keeps a visible reminder, including History-only")
                    check(abs(header.frame.midX - container.bounds.midX) < 0.1,
                          "Rolled-up arrow is centered")
                    let dividers: [Int: NSView] = member(hud, "groupDividers")
                    for divider in dividers.values where !divider.isHidden {
                        check(divider.alphaValue == 1, "Section dividers remain visible while rolled up")
                    }
                    check(header.frame.minY >= 0 && header.frame.maxY <= container.frame.height,
                          "Reminder stays inside the compact panel")
                    if body.isEmpty {
                        check(container.alphaValue == 1 && container.frame.height > 0, "FPS-only retains the compact header")
                    } else {
                        check(container.alphaValue == 1 && container.frame.height > 0, "Other metrics remain visible")
                        let rows: [HUDMetric: NSView] = member(hud, "metricRows")
                        let host: NSView = member(hud, "backgroundContentView")
                        for metric in body {
                            let row = rows[metric]!
                            let rect = row.convert(row.bounds, to: host)
                            check(rect.minY >= -0.1 && rect.maxY <= host.bounds.height + 0.1, "Body rows must stay inside the visible crop: \(metric)")
                            check(rect.maxY <= header.frame.minY, "Compact header must not overlap other metrics")
                        }
                    }
                    if CommandLine.arguments.contains("--preview"), scale == .normal,
                       fpsMetrics == [.fps, .fpsGraph], body == [.cpuTotal, .ramTotal, .battery] {
                        // Render the real native layout over a neutral backing without capture.
                        let surface: NSView = member(glass, "surface")
                        surface.isHidden = true
                        glass.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor
                        hud.updateMetric(.cpuTotal, value: "24%")
                        hud.updateRAM(.ramTotal, usage: .init(percentage: 65, usedBytes: 15_580_000_000, swapUsedBytes: 0))
                        hud.updateMemoryPressure("normal")
                        let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds)!
                        container.cacheDisplay(in: container.bounds, to: bitmap)
                        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/phud-rolled-header-preview.png"))
                        surface.isHidden = false
                        glass.layer?.backgroundColor = NSColor.clear.cgColor
                    }
                    hud.updateFPS(0)
                    check(header.isHidden, "Expanded FPS must not show a duplicate small header")
                    check(container.frame.size == expandedSize, "Zero FPS is a valid reading and expands the panel")
                    hud.updateFPS(60)
                    check(panel.frame == expandedFrame && captureRect() == originalRect, "Samples do not move capture")
                    hud.markFPSUnavailable()
                    check(container.frame.size == expandedSize, "A single missing reading must not collapse")
                    hud.setAutoHideMode(.off)
                    check(header.isHidden, "Static does not show the compact reminder")
                    check(container.frame.size == expandedSize && glass.reservedCaptureSize == nil, "Static restores original geometry")
                    hud.setAlignment(.horizontal)
                    hud.setAutoHideMode(.fps)
                    check(glass.reservedCaptureSize != nil && header.isHidden, "Horizontal reserves capture while valid FPS remains expanded")
                    hud.shutdown()
                }
            }
        }

        for scale in [HUDScale.small, HUDScale(rawValue: 0.51), HUDScale(rawValue: 0.75), .normal,
                      HUDScale(rawValue: 1.01), HUDScale(rawValue: 1.25), HUDScale.large] {
            for background in [HUDBackground.dark, .light, .transparent, .off] {
                for body: Set<HUDMetric> in [[], [.cpuTotal], [.ramTotal, .battery], [.fans]] {
                    let hud = HUDWindowController()
                    hud.setAutoHideMode(.off)
                    hud.setAlignment(.horizontal)
                    hud.setBackground(background)
                    hud.setPackagePowerOptions(.init(enabled: false))
                    for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: body.union([.fps]).contains(metric)) }
                    hud.setHUDScale(scale)
                    let panel: HUDPanel = member(hud, "panel")
                    let container: NSView = member(hud, "container")
                    let horizontal: HUDHorizontalView = member(hud, "horizontalView")
                    let arrow: NSImageView = member(hud, "collapsedFPSIndicator")
                    let glass: PerformanceHUDGlassBackground = member(hud, "backgroundView")
                    let expandedSize = container.frame.size
                    let expandedFrame = panel.frame
                    func captureRect() -> NSRect { panel.convertToScreen(glass.convert(glass.captureBounds, to: nil)) }
                    let originalCapture = captureRect()
                    hud.setAutoHideMode(.fps)
                    let collapsedSize = container.frame.size
                    check(collapsedSize.width < expandedSize.width && collapsedSize.height == expandedSize.height,
                          "Horizontal collapses width only")
                    check(!arrow.isHidden && arrow.alphaValue == 1 && container.bounds.contains(arrow.frame),
                          "Sideways reminder fits inside the compact HUD")
                    check(panel.frame == expandedFrame && captureRect() == originalCapture, "Horizontal capture stays fixed")
                    hud.updateMetric(.cpuTotal, value: "24%")
                    check(container.frame.size == collapsedSize && captureRect() == originalCapture,
                          "Regular sampling cannot reset a collapsed width or resize capture")
                    if CommandLine.arguments.contains("--preview"), scale == .normal,
                       background == .dark, body == [.cpuTotal] {
                        let surface: NSView = member(glass, "surface")
                        surface.isHidden = true
                        glass.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor
                        let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds)!
                        container.cacheDisplay(in: container.bounds, to: bitmap)
                        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/phud-horizontal-collapsed.png"))
                        surface.isHidden = false
                    }
                    hud.updateFPS(60)
                    check(container.frame.size == expandedSize && arrow.isHidden, "Horizontal FPS recovery restores full width")
                    check(horizontal.frame.minX == HUDStyle.horizontalPadding(scale: scale), "Expanded FPS keeps its original alignment")
                    check(panel.frame == expandedFrame && captureRect() == originalCapture, "Recovery keeps capture fixed")
                    hud.setAutoHideMode(.off)
                    check(glass.reservedCaptureSize == nil && container.frame.size == expandedSize, "Static clears horizontal reservation")
                    hud.shutdown()
                }
            }
        }

        // Exercise real asynchronous collapse/recovery, including a cancelled deadline.
        let hud = HUDWindowController()
        hud.setAutoHideMode(.fps)
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
        try? await Task.sleep(for: .seconds(3.1))
        check(container.frame.height == expanded, "Cancelled deadline cannot hide recovered FPS")
        hud.markFPSUnavailable()
        try? await Task.sleep(for: .seconds(3.1))
        // A busy system may deliver the main-actor deadline after this task resumes.
        for _ in 0..<100 where container.frame.height != compact {
            try? await Task.sleep(for: .milliseconds(20))
        }
        check(container.frame.height == compact && panel.frame == reserved, "Delayed collapse: height=\(container.frame.height) expected=\(compact), frame=\(panel.frame) expectedFrame=\(reserved), progress=\(member(hud, "fpsProgress") as CGFloat), availability=\(member(hud, "fpsAvailability") as HUDFPSAvailability)")
        hud.updateFPS(.nan)
        check(container.frame.height == compact, "Invalid readings do not reopen FPS")
        hud.updateFPS(50)
        check(container.frame.height == expanded, "Next valid reading reopens")
        hud.setAutoHideMode(.off)
        let staticSize = container.frame.size
        hud.markFPSUnavailable()
        try? await Task.sleep(for: .seconds(3.1))
        check(container.frame.size == staticSize && glass.reservedCaptureSize == nil, "Static ignores the collapse deadline")
        // Animate a visible native window with capture deliberately off. This
        // exercises the real timer without prompting for screen-recording access.
        hud.setBackground(.off)
        hud.setAutoHideMode(.fps)
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
        try? await Task.sleep(for: .seconds(3.2))
        hud.updateFPS(48) // Reverse a collapse that has already started.
        try? await Task.sleep(for: .milliseconds(700))
        check(container.frame.height == finalExpanded, "Returning readings reverse an in-flight collapse")
        hud.setHUDEnabled(false)
        hud.shutdown()
        let sideways = HUDWindowController()
        sideways.setAlignment(.horizontal)
        sideways.setBackground(.off)
        sideways.setAutoHideMode(.fps)
        sideways.setHUDEnabled(true)
        let sidewaysContainer: NSView = member(sideways, "container")
        let sidewaysPanel: HUDPanel = member(sideways, "panel")
        let initialWidth = sidewaysContainer.frame.width
        let fixedFrame = sidewaysPanel.frame
        sideways.updateFPS(60)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            try? await Task.sleep(for: .milliseconds(180))
            check(sidewaysContainer.frame.width > initialWidth, "Horizontal animation advances through intermediate widths")
            let midway = sidewaysContainer.frame.width
            sideways.updateMetric(.cpuTotal, value: "35%")
            check(abs(sidewaysContainer.frame.width - midway) < 1, "Mid-animation sampling does not jump to an endpoint")
        }
        try? await Task.sleep(for: .milliseconds(650))
        let fullWidth = sidewaysContainer.frame.width
        check(fullWidth > initialWidth && sidewaysPanel.frame == fixedFrame, "Sideways expansion leaves window fixed")
        sideways.resetFPS()
        try? await Task.sleep(for: .seconds(3.2))
        sideways.updateFPS(48)
        try? await Task.sleep(for: .milliseconds(700))
        check(sidewaysContainer.frame.width == fullWidth && sidewaysPanel.frame == fixedFrame,
              "Horizontal recovery reverses an in-flight collapse")
        sideways.setHUDEnabled(false)
        sideways.shutdown()
        print("PASS: FPS availability, shared mode/reset, all scales/row selections, fixed capture geometry, FPS-only, horizontal, cancelled deadlines, recovery, native animation and reversal")
    }
}
