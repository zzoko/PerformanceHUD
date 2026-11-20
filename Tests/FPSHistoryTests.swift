import AppKit

@main struct FPSHistoryTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
    @MainActor static func testGraphBaseline() {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
        defaults.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "off", "hud.scale": 1.0,
            "hud.background": "dark", "hud.alignment": "vertical"], forName: UserDefaults.argumentDomain)
        let hud = HUDWindowController()
        defer { hud.shutdown() }
        hud.setPackagePowerOptions(.init(enabled: false))
        for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: false) }
        hud.setFPSOptions(.init(enabled: true, mode: .history))
        let members = Mirror(reflecting: hud).children
        let graph = members.first { $0.label == "fpsGraphView" }!.value as! HUDFPSGraphView
        let panel = members.first { $0.label == "panel" }!.value as! HUDPanel
        let dividers = members.first { $0.label == "groupDividers" }!.value as! [Int: NSView]
        graph.append(60) // One endpoint, leaving the center column free of any curve/fill.
        func centerColumnInk() -> CGFloat {
            panel.contentView?.layoutSubtreeIfNeeded()
            let bitmap = graph.bitmapImageRepForCachingDisplay(in: graph.bounds)!
            graph.cacheDisplay(in: graph.bounds, to: bitmap)
            return (0..<bitmap.pixelsHigh).reduce(CGFloat.zero) {
                $0 + bitmap.colorAt(x: bitmap.pixelsWide / 2, y: $1)!.alphaComponent
            } / (CGFloat(bitmap.pixelsWide) / graph.bounds.width)
        }
        let expectedInk = HUDStyle.separatorColor(background: .dark).alphaComponent * 0.5
        check(abs(centerColumnInk() - expectedInk) < 0.015,
              "Standalone FPS history draws a divider-weight bottom line")
        check(dividers.values.allSatisfy(\.isHidden), "The baseline does not create a category divider")
        let graphSize = graph.bounds.size
        hud.setMetricEnabled(.cpuTotal, enabled: true)
        check(centerColumnInk() == 0, "A following category supplies the baseline without a second graph stroke")
        check(graph.bounds.size == graphSize, "Adding a baseline cannot resize the graph")
        hud.setMetricEnabled(.cpuTotal, enabled: false)
        check(abs(centerColumnInk() - expectedInk) < 0.015, "Removing the following category restores the baseline")
        graph.reset()
        check(centerColumnInk() == 0, "Empty history does not leave a stray baseline")
    }

    @MainActor static func testFrameTiming() {
        func timing(_ average: Double, _ worst: Double) -> MetalFrameTiming {
            MetalFrameTiming(averageMS: average, worstMS: worst)!
        }
        // Keys and units from metalperftrace listen on a presenting Metal window.
        let record = #"{"PID":123,"Layers":[{"Configuration":{"Width (pixels)":640,"Height (pixels)":480},"Performance Stats":{"Presented Frame Stats":{"FPS":57.48},"Frame-On-Glass Interval Stats":{"Count":57,"Average (ms)":17.54,"Max (ms)":49.99}}},{"Configuration":{"Width (pixels)":20,"Height (pixels)":20},"Performance Stats":{"Presented Frame Stats":{"FPS":24},"Frame-On-Glass Interval Stats":{"Count":24,"Average (ms)":42,"Max (ms)":142}}}]}"#
        func parse(_ json: String) -> MetalPerfTraceMonitor.MetalMetrics {
            MetalMetricsParser(pid: 123).consume(Data(json.utf8)).first!
        }
        let report = parse(record)
        check(report.fps == 57.48 && report.frameTiming == timing(17.54, 49.99), "FPS and timing come from the same layer")
        check(parse(record.replacingOccurrences(of: "Frame-On-Glass Interval Stats", with: "On-GPU Walltime Stats")).frameTiming == nil,
              "Missing display intervals never fall back to GPU time or reciprocal FPS")
        check(parse(record.replacingOccurrences(of: #""Count":57"#, with: #""Count":0"#)).frameTiming == nil,
              "An empty reporting interval supplies no frame timing")
        check(timing(8, 24.9).hitch == nil && timing(10, 25).hitch == .warning, "Absolute threshold is inclusive")
        check(timing(20, 49.9).hitch == nil && timing(20, 50).hitch == .warning, "Relative threshold is inclusive")
        check(timing(16.8, 83).hitch == .warning && timing(16.8, 100).hitch == .severe
              && timing(50, 100).hitch == nil, "Severe hitches must also exceed relative pace")

        var history = FPSHistory()
        check(history.frameTimeUpperBound() == 100, "Frame time starts with a 100 ms ceiling")
        history.append(59, timing: timing(16, 83), at: 100)
        history.append(30, timing: timing(34, 142), at: 101)
        check(history.frameTimeUpperBound() == 100, "A 75 ms target stays at the minimum ceiling")
        history.append(60, timing: timing(16, 1200), at: 102)
        check(history.frameTimeUpperBound(holding: 130) == 100, "A single extreme worst frame cannot flatten the chart")
        history.append(60, at: 103)
        check(history.currentSample?.timing == nil, "Unavailable timings leave a gap")
        var ceiling = 100.0
        // Each step represents a full window at the specified frame pace.
        for (average, expected) in [(16.667, 100.0), (33.334, 100), (33.8, 110), (33.2, 110),
                                    (32.8, 100), (42.1, 130), (42.4, 130), (8.33, 100)] {
            var steady = FPSHistory()
            steady.append(1000 / average, timing: timing(average, average), at: 0)
            ceiling = steady.frameTimeUpperBound(holding: ceiling)
            check(ceiling == expected, "Frame-time ceiling at \(average) ms should be \(expected) ms")
        }
        var scale = FPSHistoryScale()
        scale.set(30...70, at: 1)
        scale.set(45...75, at: 2)
        check(scale.value(at: 2) == 30...70 && scale.value(at: 2.25) == 37.5...72.5
              && scale.value(at: 2.5) == 45...75, "FPS range eases over half a second")

        var style = HUDMenuBarPresentation.Style.current
        style.fpsMeasure = .frameTime
        var snapshot = HUDLogSnapshot()
        snapshot.setFPS(59, timing: timing(16.8, 142))
        func pinned() -> [String] {
            HUDMenuBarPresentation.sections(snapshot: snapshot, fanSample: .noFans, readings: [.fps],
                style: style, background: .dark).flatMap { $0.map(\.text) }
        }
        check(pinned() == ["FT", "16.8 ms"], "The pin uses the selected measure and average")
        check(snapshot.numbers[.frameTimeWorst] == 142, "CSV uses the measured, unclipped worst frame")
        snapshot.setFPS(59)
        check(pinned() == ["FT", ""] && snapshot.numbers[.frameTimeWorst] == nil, "Missing timing clears both readings")

        let name = "FPSOverhaul.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let options = HUDFPSOptions(enabled: true, mode: .both, valueSize: .enlarged, measure: .frameTime, hitchMarks: false)
        HUDPreferences.setFPSOptions(options, in: defaults)
        check(HUDPreferences.fpsOptions(in: defaults) == options, "Both display choices survive relaunch")
        check(try! JSONDecoder().decode(HUDFPSOptions.self, from: JSONEncoder().encode(options)) == options,
              "Custom presets round-trip the selected measure and warnings")
        HUDPreferences.resetOptions(in: defaults)
        check(HUDPreferences.fpsOptions(in: defaults).measure == .frameRate && HUDPreferences.fpsOptions(in: defaults).hitchMarks,
              "Reset restores frame rate and hitch marks")
    }

    @MainActor static func populateHistory(_ graph: HUDFPSGraphView) {
        graph.reset()
        let start = ProcessInfo.processInfo.systemUptime - 60
        for i in 0...60 {
            let avg = i == 12 ? 18.0 : i == 52 ? 19.0 : (35...42).contains(i) ? 25.0 : 16.8
            let worst = i == 12 ? 83.0 : i == 52 ? 142.0 : avg + 1
            graph.append(1000 / avg, timing: .init(averageMS: avg, worstMS: worst), at: start + Double(i))
        }
    }

    @MainActor static func testFrameTimeBarPlacement() {
        let graph = HUDFPSGraphView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 46),
                              styleMask: [], backing: .buffered, defer: false)
        window.contentView = graph
        graph.configure(measure: .frameTime, hitchMarks: true)
        for (second, worst) in [(0.0, 120.0), (10, 55), (20, 70), (30, 120), (40, 83), (60, 120)] {
            graph.append(60, timing: .init(averageMS: 16.67, worstMS: worst), at: second)
        }
        let bitmap = graph.bitmapImageRepForCachingDisplay(in: graph.bounds)!
        graph.cacheDisplay(in: graph.bounds, to: bitmap)
        let pixelsPerPoint = CGFloat(bitmap.pixelsWide) / graph.bounds.width
        // Halfway up, only the three severe-hitch bars have red ink.
        let redCenters = (0..<bitmap.pixelsWide).compactMap { x -> CGFloat? in
            guard let color = bitmap.colorAt(x: x, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB),
                  color.alphaComponent > 0.25, color.redComponent - color.greenComponent > 0.35 else { return nil }
            return (CGFloat(x) + 0.5) / pixelsPerPoint
        }
        let plot = graph.plotBounds
        // These three yellow bars all clipped at the former 50 ms ceiling.
        let yellowHeights = [10.0, 20, 40].map { second in
            let column = Int((plot.minX + plot.width * second / FPSHistory.duration) * pixelsPerPoint)
            return (0..<bitmap.pixelsHigh).filter { y in
                guard let color = bitmap.colorAt(x: column, y: y)?.usingColorSpace(.sRGB) else { return false }
                return color.alphaComponent > 0.3 && color.greenComponent - color.blueComponent > 0.3
            }.count
        }
        check(yellowHeights[0] > 0 && yellowHeights[0] < yellowHeights[1] && yellowHeights[1] < yellowHeights[2],
              "55, 70, and 83 ms yellow hitches have distinct, increasing bar heights at 60 FPS")
        let halfWidth = plot.width / CGFloat(FPSHistory.duration) * 0.30
        let pixel = 1 / pixelsPerPoint
        for center in [plot.minX, plot.midX, plot.maxX] {
            let columns = redCenters.filter { abs($0 - center) < 2 * halfWidth + pixel }
            guard let first = columns.first, let last = columns.last else { fatalError("Missing bar at \(center)") }
            check(abs(first - max(plot.minX, center - halfWidth)) <= pixel &&
                  abs(last - min(plot.maxX, center + halfWidth)) <= pixel,
                  "Each bar straddles its sample and clips at the plot edges")
        }
    }

    @MainActor static func testFPSHitchLine() {
        let graph = HUDFPSGraphView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 46),
                              styleMask: [], backing: .buffered, defer: false)
        window.contentView = graph
        graph.applyStyle(background: .dark)
        let hitches: Set<Int> = [20, 21, 26, 32]
        func render(worstMS: Double) -> NSBitmapImageRep {
            graph.reset()
            for second in 0...60 where !(27...31).contains(second) {
                graph.append(60, timing: .init(averageMS: 16.67, worstMS: hitches.contains(second) ? worstMS : 17),
                             at: Double(second))
            }
            let bitmap = graph.bitmapImageRepForCachingDisplay(in: graph.bounds)!
            graph.cacheDisplay(in: graph.bounds, to: bitmap)
            return bitmap
        }
        func markedRows(in bitmap: NSBitmapImageRep, at second: Double) -> Int {
            let x = graph.plotBounds.minX + graph.plotBounds.width * second / FPSHistory.duration
            let column = Int(x * CGFloat(bitmap.pixelsWide) / graph.bounds.width)
            return (0..<bitmap.pixelsHigh).filter { y in
                guard let color = bitmap.colorAt(x: column, y: y)?.usingColorSpace(.sRGB) else { return false }
                return color.alphaComponent > 0.2 && color.redComponent - color.blueComponent > 0.2
            }.count
        }
        let bitmap = render(worstMS: 120)
        check([19.87, 20.13, 20.87, 21.13].allSatisfy { markedRows(in: bitmap, at: $0) > 0 },
              "Each consecutive hitch tints the curve on both sides of its sample")
        check([19.65, 20.35, 20.5, 20.65, 21.35].allSatisfy { markedRows(in: bitmap, at: $0) == 0 },
              "Short hitch tints leave the intervening FPS curve neutral")
        check([26.03, 31.97].allSatisfy { markedRows(in: bitmap, at: $0) > 0 },
              "Hitches at either end of a segment tint the line cap")
        check(markedRows(in: bitmap, at: 22) == 0 && markedRows(in: bitmap, at: 29) == 0,
              "Hitch colour ends at normal readings and real gaps")
        let depths = [50.0, 85, 100, 150, 200].map { markedRows(in: render(worstMS: $0), at: 20) }
        check(depths[0] > 0 && zip(depths, depths.dropFirst()).allSatisfy { $0 < $1 },
              "Longer hitches draw deeper lines within and across both severity levels")
        check(markedRows(in: render(worstMS: 500), at: 20) == depths.last,
              "Hitches of 200 ms or more stop at the same baseline")
    }

    @MainActor static func testBothGraphs() {
        let graph = HUDFPSGraphView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 285, height: 46),
                              styleMask: [], backing: .buffered, defer: false)
        window.contentView = graph
        populateHistory(graph)
        for background in [HUDBackground.dark, .light] {
            graph.applyStyle(background: background)
            for measure in HUDFPSMeasure.allCases {
                for enabled in [true, false] {
                    graph.configure(measure: measure, hitchMarks: enabled)
                    let bitmap = graph.bitmapImageRepForCachingDisplay(in: graph.bounds)!
                    graph.cacheDisplay(in: graph.bounds, to: bitmap)
                    var yellow = 0, red = 0
                    for x in 0..<bitmap.pixelsWide {
                        for y in 0..<bitmap.pixelsHigh {
                            guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.3 else { continue }
                            // Allow for the fade and colour conversion, but reject the old dark amber.
                            if c.greenComponent > 0.70 && c.redComponent - c.blueComponent > 0.25 &&
                                c.greenComponent - c.blueComponent > 0.2 { yellow += 1 }
                            if c.redComponent - c.greenComponent > 0.35 && c.greenComponent - c.blueComponent < 0.12 { red += 1 }
                        }
                    }
                    check(enabled ? yellow > 2 && red > 2 : yellow == 0 && red == 0,
                          "Hitch marks use memory-pressure yellow and severe red in \(measure) / \(background)")
                    if enabled, let i = CommandLine.arguments.firstIndex(of: "--preview-dir") {
                        let directory = URL(fileURLWithPath: CommandLine.arguments[i + 1])
                        try! bitmap.representation(using: .png, properties: [:])!.write(to:
                            directory.appendingPathComponent("\(measure.rawValue)-\(background.rawValue).png"))
                    }
                }
            }
        }
    }

    @MainActor static func testMeasureSwitch() {
        _ = NSApplication.shared
        let hud = HUDWindowController()
        defer { hud.shutdown() }
        func member<T>(_ object: Any, _ name: String) -> T {
            Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
        }
        let panel: HUDPanel = member(hud, "panel")
        panel.alphaValue = 0
        hud.setAutoHideMode(.off)
        hud.setHUDEnabled(true)
        hud.setPackagePowerOptions(.init(enabled: false))
        let graph: HUDFPSGraphView = member(hud, "fpsGraphView")
        let titles: [HUDMetric: NSTextField] = member(hud, "titleLabels")
        let values: [HUDMetric: NSTextField] = member(hud, "valueLabels")
        let strip: HUDHorizontalView = member(hud, "horizontalView")
        for layout in HUDAlignment.allCases {
            hud.setAlignment(layout)
            for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: false) }
            for size in HUDFPSValueSize.allCases {
                for mode in HUDFPSDisplayMode.allCases {
                    var options = HUDFPSOptions(enabled: true, mode: mode, valueSize: size)
                    hud.setFPSOptions(options)
                    hud.updateFPS(59, timing: .init(averageMS: 16.8, worstMS: 142))
                    panel.contentView?.layoutSubtreeIfNeeded()
                    let original = panel.frame.size
                    let plot = graph.plotBounds
                    let before: FPSHistory = member(graph, "history")
                    options.measure = .frameTime
                    hud.setFPSOptions(options)
                    panel.contentView?.layoutSubtreeIfNeeded()
                    let after: FPSHistory = member(graph, "history")
                    check(panel.frame.height == original.height && graph.plotBounds == plot, "Measure switches preserve height and history geometry")
                    if size == .enlarged && (layout == .horizontal || mode == .value) {
                        check(panel.frame.width > original.width, "The compact 2× frame-time value reserves room for milliseconds")
                    } else {
                        check(panel.frame.width == original.width, "Standard readings and vertical history keep their width across measures")
                    }
                    check(before.samples.count == after.samples.count, "Switching measures retains collected history")
                    if !after.samples.isEmpty {
                        let axis: FPSHistoryScale = member(graph, "plotScale")
                        check(axis.target?.lowerBound == 0 && axis.value(at: 0) == axis.target,
                              "Switching to milliseconds starts directly on the frame-time scale")
                    }
                    if layout == .horizontal {
                        let fields: [String: NSTextField] = member(strip, "labels")
                        check(fields["0.title"]?.stringValue == "FT" && fields["0.value"]?.stringValue == "16.8 ms", "Horizontal label and number switch together")
                    } else {
                        check(titles[.fps]?.stringValue == "FT" && values[.fps]?.stringValue == "16.8 ms", "Vertical label and number switch together")
                        let heading: NSTextField = member(graph, "heading")
                        check(graph.showsHeading == (mode == .history) && heading.stringValue == "FT",
                              "History alone displays the abbreviated measure heading")
                    }
                    hud.updateFPS(59)
                    check(values[.fps]?.stringValue == "", "FPS-only telemetry cannot create displayed-frame timings")
                }
            }
        }

        let menu = HUDFPSMenuView(options: .init(enabled: true, mode: .both), alignment: .vertical)
        let win = NSWindow(contentRect: menu.frame, styleMask: [], backing: .buffered, defer: false)
        win.contentView = menu
        menu.layoutSubtreeIfNeeded()
        let display: NSSegmentedControl = member(menu, "control")
        let measure: NSSegmentedControl = member(menu, "measureControl")
        let size: NSSegmentedControl = member(menu, "valueSizeControl")
        let hitch: HUDReadingCheckbox = member(menu, "hitchControl")
        let selectorRects = [display, measure, size].map { $0.alignmentRect(forFrame: $0.frame) }
        let rowHeight = HUDCategoryLayout.rowHeight
        check(selectorRects.allSatisfy { $0.minX == HUDCategoryLayout.modeLeading && $0.size == selectorRects[0].size },
              "All three FPS selectors use the category mode column")
        check(selectorRects[1].midY == selectorRects[0].midY + rowHeight + HUDCategoryLayout.pinConnectionHeight &&
              selectorRects[2].midY == selectorRects[1].midY + rowHeight &&
              hitch.frame.midY == selectorRects[2].midY + rowHeight && hitch.frame.minX == HUDCategoryLayout.modeLeading,
              "Display, Measure, Number size, and Hitch marks sit on consecutive aligned rows")
        check(measure.label(forSegment: 0) == "Frame rate" && measure.label(forSegment: 1) == "Frame time",
              "Measure shows both choices directly")
        var selected: HUDFPSOptions?
        menu.onChange = { selected = $0 }
        measure.selectedSegment = 1
        _ = measure.sendAction(measure.action, to: measure.target)
        check(selected?.measure == .frameTime && selected?.hitchMarks == true, "Measure selection preserves warnings")
        hitch.performClick(nil)
        check(selected?.hitchMarks == false && selected?.measure == .frameTime, "Hitch marks toggle independently")
        menu.update(options: selected!, alignment: .horizontal)
        check(measure.isEnabled && measure.selectedSegment == 1 && !hitch.isEnabled,
              "Horizontal retains the measure selector for its numeric reading")
        if CommandLine.arguments.contains("--mouse-probe") {
            let nativeMenu = NSMenu()
            let item = NSMenuItem()
            item.view = HUDCategoryListView(categories: [menu])
            nativeMenu.addItem(item)
            var changes: [HUDFPSMeasure] = []
            menu.onChange = { changes.append($0.measure) }
            for layout in HUDAlignment.allCases {
                menu.update(options: .init(enabled: true, mode: .both, measure: .frameTime), alignment: layout)
                changes.removeAll()
                var click = 0
                let clickSegment: @MainActor (Timer) -> Void = { timer in
                    guard click < 2, let window = measure.window else {
                        timer.invalidate()
                        nativeMenu.cancelTracking()
                        return
                    }
                    let x = measure.bounds.width * (click == 0 ? 0.25 : 0.75)
                    let point = measure.convert(NSPoint(x: x, y: measure.bounds.midY), to: nil)
                    click += 1
                    for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                        let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                            context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                        NSApp.postEvent(event, atStart: false)
                    }
                }
                let timer = Timer(timeInterval: 0.1, repeats: true) { timer in
                    MainActor.assumeIsolated { clickSegment(timer) }
                }
                RunLoop.main.add(timer, forMode: .eventTracking)
                nativeMenu.popUp(positioning: nil, at: NSPoint(x: 100, y: 200), in: nil)
                timer.invalidate()
                check(changes == [.frameRate, .frameTime], "Mouse clicks switch both measures in the \(layout) menu")
            }
            win.contentView = menu
            menu.layoutSubtreeIfNeeded()
        }
        if let i = CommandLine.arguments.firstIndex(of: "--preview-dir") {
            let directory = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            hud.setAlignment(.vertical)
            hud.setHUDScale(.normal)
            for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: false) }
            hud.setFPSOptions(.init(enabled: true, mode: .both))
            hud.updateFPS(60, timing: .init(averageMS: 16.8, worstMS: 18))
            populateHistory(graph)
            let container: NSView = member(hud, "container")
            container.wantsLayer = true
            container.layer?.cornerRadius = 16
            for background in [HUDBackground.light, .dark] {
                hud.setBackground(background)
                container.layer?.backgroundColor = NSColor(white: background == .light ? 0.91 : 0.12, alpha: 1).cgColor
                for measure in HUDFPSMeasure.allCases {
                    hud.setFPSOptions(.init(enabled: true, mode: .both, measure: measure))
                    panel.contentView?.layoutSubtreeIfNeeded()
                    let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds)!
                    container.cacheDisplay(in: container.bounds, to: bitmap)
                    try! bitmap.representation(using: .png, properties: [:])!.write(to:
                        directory.appendingPathComponent("HUD-\(measure.rawValue)-\(background.rawValue).png"))
                }
            }
            menu.update(options: .init(enabled: true, mode: .both, measure: .frameTime), alignment: .vertical)
            menu.appearance = NSAppearance(named: .darkAqua)
            menu.wantsLayer = true
            menu.layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
            let bitmap = menu.bitmapImageRepForCachingDisplay(in: menu.bounds)!
            menu.cacheDisplay(in: menu.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("fps-menu.png"))
        }
    }

    @MainActor static func main() {
        testMeasureSwitch()
        testFrameTiming()
        testFrameTimeBarPlacement()
        testFPSHitchLine()
        testBothGraphs()
        var history = FPSHistory()
        var time = 100.0
        history.append(60, at: time)
        // Irregular arrivals reproduce the shifting oldest point after one minute.
        for index in 0..<1200 {
            time += [0.91, 1.04, 1.12, 0.98][index % 4]
            history.append(60 + sin(Double(index) / 10) * 10, at: time)
            let visible = history.visibleSegments
            check(visible.count == 1, "Continuous readings must remain connected")
            let first = visible[0][0]
            check(abs(first.time - max(100, time - 60)) < 0.000001,
                  "Filled history must reach the exact left boundary")
            check(visible[0].last!.time == time, "Newest sample must reach the right edge")
            check(visible[0].allSatisfy { $0.time >= time - 60 && $0.time <= time }, "No offscreen samples")
            check(history.samples.count <= 68, "Only one boundary predecessor is retained")
        }
        history.reset()
        history.append(0, at: 100)
        history.append(100, at: 102)
        history.advance(to: 161)
        check(history.visibleSegments[0][0].time == 101 && history.visibleSegments[0][0].fps == 50,
              "Boundary value interpolates between real samples")
        check(history.displayRange.lowerBound > 0, "Expired predecessor must not distort the visible range")
        history.advance(to: 163)
        check(history.samples.isEmpty && history.visibleSegments.isEmpty, "Unavailable history ages out completely")

        for explicit in [false, true] {
            history.reset()
            history.append(60, at: 100)
            if explicit { history.markUnavailable(at: 101) }
            history.append(75, at: explicit ? 102 : 105)
            history.advance(to: 161)
            check(history.visibleSegments.first?.first?.time == (explicit ? 102 : 105),
                  "Do not fill a real gap at the left edge")
        }
        history.reset()
        check(history.currentSample == nil, "Reset clears the current-reading marker")
        history.append(60, at: 100)
        history.append(61, at: 101)
        check(history.currentSample?.fps == 61, "The marker follows the latest reading")
        history.markUnavailable(at: 102)
        check(history.currentSample == nil && !history.visibleSegments.isEmpty,
              "Unavailable FPS hides the marker while retaining older history")
        history.append(65, at: 103)
        check(history.currentSample?.fps == 65, "The marker returns with resumed readings")
        check(history.visibleSegments.count == 2, "Internal interruptions remain separate")
        history.advance(to: 161)
        check(history.visibleSegments.count == 2 && history.visibleSegments[0][0].time == 101,
              "Exact boundary sample survives without extrapolation")
        history.append(70, at: 90)
        check(history.samples.count == 1 && history.samples[0].time == 90, "Backward clock resets history")
        history.append(.nan, at: 91)
        check(history.samples.count == 1, "Invalid FPS is ignored")
        for index in 0..<1000 { history.append(60, at: 100 + Double(index) / 100) }
        check(history.samples.count <= 256, "Storage remains bounded for bursts")
        testGraphBaseline()
        print("PASS: live-schema frame times, hitch rules, both graphs and appearances, measure switching, menu controls and legacy defaults")
        print("PASS: jittered 20-minute history, stable left edge, boundary interpolation, visible range, genuine gaps, expiry, clock reset, bounded storage")
        print("PASS: FPS graph baseline rendering, divider handoff, unchanged geometry, and empty history")
    }
}
