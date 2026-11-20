import AppKit

@main struct DynamicFPSTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }
    @MainActor static func activeHUD() -> HUDWindowController {
        let hud = HUDWindowController()
        let panel: HUDPanel = member(hud, "panel")
        panel.alphaValue = 0
        hud.setAutoHideAnimated(false)
        // Disabled overlays intentionally stop live rendering. Keep the fixture
        // active but invisible; geometry checks use instant transitions.
        hud.setHUDEnabled(true)
        return hud
    }
    @MainActor static func valueSizing() {
        let suiteName = "FPSValueSize.tests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suiteName)!
        defer { store.removePersistentDomain(forName: suiteName) }
        check(HUDPreferences.fpsOptions(in: store).valueSize == .standard, "New and existing settings default to 1×")
        let legacy = Data(#"{"enabled":true,"mode":"both","valueHighlighted":false}"#.utf8)
        let decoded = try! JSONDecoder().decode(HUDFPSOptions.self, from: legacy)
        check(decoded.valueSize == .standard && !decoded.valueHighlighted, "Old presets keep their emphasis and default to 1×")
        let enlarged = HUDFPSOptions(enabled: false, mode: .history, valueHighlighted: false, valueSize: .enlarged)
        HUDPreferences.setFPSOptions(enlarged, in: store)
        check(HUDPreferences.fpsOptions(in: store) == enlarged, "Hidden FPS remembers its size and emphasis")
        check(try! JSONDecoder().decode(HUDFPSOptions.self, from: JSONEncoder().encode(enlarged)) == enlarged,
              "Saved presets preserve FPS size")
        HUDPreferences.resetOptions(in: store)
        check(HUDPreferences.fpsOptions(in: store).valueSize == .standard, "Reset restores 1×")

        let menu = HUDFPSMenuView(options: .init(enabled: true, mode: .both), alignment: .vertical)
        let selector: NSSegmentedControl = member(menu, "valueSizeControl")
        let mode: NSSegmentedControl = member(menu, "control")
        menu.layoutSubtreeIfNeeded()
        let sizeRect = selector.alignmentRect(forFrame: selector.frame)
        let modeRect = mode.alignmentRect(forFrame: mode.frame)
        check(sizeRect.minX == modeRect.minX && sizeRect.size == modeRect.size && sizeRect.minY > modeRect.maxY,
              "The size selector uses the shared bezel height and column below Frame rate")
        var changed: HUDFPSOptions?
        menu.onChange = { changed = $0 }
        selector.selectedSegment = 1
        _ = selector.sendAction(selector.action, to: selector.target)
        check(changed?.valueSize == .enlarged && changed?.mode == .both && changed?.valueHighlighted == true,
              "2× changes only the number size")
        menu.update(options: enlarged, alignment: .horizontal)
        check(!selector.isEnabled && selector.selectedSegment == 1, "Hidden category retains the size without enabling it")
        menu.update(options: .init(enabled: true, mode: .history, valueSize: .enlarged), alignment: .vertical)
        check(!selector.isEnabled && selector.selectedSegment == 1, "History-only disables the size control")
        menu.update(options: .init(enabled: true, mode: .history, valueSize: .enlarged), alignment: .horizontal)
        check(selector.isEnabled && selector.selectedSegment == 1, "Horizontal Value still permits 2×")

        let hud = activeHUD()
        defer { hud.shutdown() }
        hud.setAutoHideMode(.off)
        hud.setHUDScale(.normal)
        hud.setPackagePowerOptions(.init(enabled: false))
        hud.setCPUCoreOptions(.init(enabled: false))
        hud.setGPUCoreOptions(.init(enabled: false))
        for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: false) }
        hud.setResourceOptions(.init(enabled: true, temperature: true, totalUse: true,
            focusedApp: false, power: true), for: .gpu)
        hud.updateMetric(.gpuTotal, value: "42%")
        hud.updateTemperatures(.init(cpu: 50, gpu: 48))
        hud.updatePower(.init(cpu: 1, gpu: 3.5, package: 4.5))
        let panel: HUDPanel = member(hud, "panel")
        let container: NSView = member(hud, "container")
        let values: [HUDMetric: NSTextField] = member(hud, "valueLabels")
        let titles: [HUDMetric: NSTextField] = member(hud, "titleLabels")
        let graph: HUDFPSGraphView = member(hud, "fpsGraphView")
        let horizontal: HUDHorizontalView = member(hud, "horizontalView")
        for alignment in HUDAlignment.allCases {
            hud.setAlignment(alignment)
            hud.setFPSOptions(.init(enabled: true, mode: .both))
            hud.updateFPS(144)
            panel.contentView?.layoutSubtreeIfNeeded()
            let normal = container.bounds.size
            let graphSize = graph.bounds.size
            let before: FPSHistory = member(graph, "history")
            hud.setFPSOptions(.init(enabled: true, mode: .both, valueSize: .enlarged))
            panel.contentView?.layoutSubtreeIfNeeded()
            check(values[.fps]!.font!.pointSize == 24 && values[.gpuTotal]!.font!.pointSize == 12
                  && titles[.fps]!.font!.pointSize == 12, "Only the FPS number doubles")
            let after: FPSHistory = member(graph, "history")
            check(before.samples.count == after.samples.count, "Resizing FPS preserves history")
            if alignment == .vertical {
                check(container.bounds.width == normal.width && container.bounds.height > normal.height,
                      "Vertical reserves height for the number without widening the HUD")
                check(graph.bounds.size == graphSize, "FPS history keeps its existing size")
            }
            let enlargedFrame = container.bounds.size
            for highlighted in [false, true] {
                hud.setFPSOptions(.init(enabled: true, mode: .both, valueHighlighted: highlighted, valueSize: .enlarged))
                for reading: Double? in [9, 144, 9999, nil] {
                    if let reading { hud.updateFPS(reading) }
                    else { hud.markFPSUnavailable() }
                    panel.contentView?.layoutSubtreeIfNeeded()
                    let field: NSTextField
                    if alignment == .horizontal {
                        let fields: [String: NSTextField] = member(horizontal, "labels")
                        field = fields["\(HUDMetric.fps.rawValue).value"]!
                        check(fields["\(HUDMetric.gpuTotal.rawValue).value"]!.font!.pointSize == 12,
                              "Horizontal keeps other readings at their normal font size")
                    } else { field = values[.fps]! }
                    let rect = field.alignmentRect(forFrame: field.frame)
                    check(field.font!.pointSize == 24 && rect.height >= field.intrinsicContentSize.height,
                          "Both emphasis weights retain the full 2× number")
                    check(container.bounds.contains(field.convert(field.bounds, to: container)),
                          "Enlarged FPS fits inside the visible HUD")
                    check(container.bounds.size == enlargedFrame, "Digits, missing readings and B cannot resize enlarged FPS")
                }
            }
            if CommandLine.arguments.contains("--preview") {
                hud.updateFPS(144)
                let glass: NativeGlassHUDBackground = member(hud, "backgroundView")
                let surface: NSView = member(glass, "glass")
                surface.isHidden = true
                container.wantsLayer = true
                container.layer?.backgroundColor = NSColor(white: 0.14, alpha: 1).cgColor
                panel.contentView?.layoutSubtreeIfNeeded()
                let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds)!
                container.cacheDisplay(in: container.bounds, to: bitmap)
                try! bitmap.representation(using: .png, properties: [:])!.write(to:
                    URL(fileURLWithPath: "/tmp/phud-fps-2x-\(alignment.rawValue).png"))
            }
            hud.setFPSOptions(.init(enabled: true, mode: .both))
            panel.contentView?.layoutSubtreeIfNeeded()
            check(container.bounds.size == normal, "1× restores the original layout exactly")

            for scale in [HUDScale.small, HUDScale(rawValue: 0.75), .normal, HUDScale(rawValue: 1.25), .large] {
                hud.setHUDScale(scale)
                hud.setFPSOptions(.init(enabled: true, mode: .both))
                let standardHeight = container.bounds.height
                for measure in HUDFPSMeasure.allCases {
                    for emphasis in [false, true] {
                        hud.setFPSOptions(.init(enabled: true, mode: .both, valueHighlighted: emphasis,
                                                valueSize: .enlarged, measure: measure))
                        hud.updateFPS(144, timing: .init(averageMS: 6.94, worstMS: 7))
                        panel.contentView?.layoutSubtreeIfNeeded()
                        if alignment == .horizontal {
                            let fields: [String: NSTextField] = member(horizontal, "labels")
                            let value = fields["0.value"]!
                            check(container.bounds.height == standardHeight, "2× keeps the 1× horizontal strip height")
                            check(container.bounds.contains(value.convert(value.bounds, to: container)),
                                  "The 2× reading fits within the horizontal padding")
                        } else {
                            func capTop(_ field: NSTextField) -> CGFloat {
                                field.convert(field.bounds, to: container).maxY - (field.firstBaselineOffsetFromTop - field.font!.capHeight) * scale.rawValue
                            }
                            let titleTop = capTop(titles[.fps]!)
                            let valueTop = capTop(values[.fps]!)
                            check(abs(titleTop - valueTop) <= 1 / panel.backingScaleFactor + 0.01,
                                  "Vertical 2× cap tops at \(scale.rawValue)×: caption \(titleTop), reading \(valueTop)")
                        }
                    }
                }
            }
            hud.setHUDScale(.normal)
        }

        hud.setAlignment(.horizontal)
        hud.setResourceOptions(.init(enabled: true, temperature: true, totalUse: true, focusedApp: false), for: .gpu)
        for size in HUDFPSValueSize.allCases {
            for measure in HUDFPSMeasure.allCases {
                var dividerX: CGFloat?
                var valueRight: CGFloat?
                hud.setFPSOptions(.init(enabled: true, mode: .value, valueSize: size, measure: measure))
                for fps in [9.0, 60, 144, 9999] {
                    hud.updateFPS(fps, timing: .init(averageMS: 1000 / fps, worstMS: 1000 / fps))
                    panel.contentView?.layoutSubtreeIfNeeded()
                    let fields: [String: NSTextField] = member(horizontal, "labels")
                    let caption = fields["0.title"]!
                    let value = fields["0.value"]!
                    let column = value.alignmentRect(forFrame: value.frame)
                    let gap = column.minX - caption.alignmentRect(forFrame: caption.frame).maxX
                    let expectedGap: CGFloat = size == .enlarged ? 30.5 : 19
                    check(value.alignment == .right && abs(gap - expectedGap) <= 0.5,
                          "Horizontal FPS keeps the wider label gap and the reading’s right alignment")
                    check(abs(column.maxX - (valueRight ?? column.maxX)) <= 0.5, "Changing digits keeps the reading’s right edge")
                    valueRight = column.maxX
                    let dividers: [NSView] = member(horizontal, "dividers")
                    let x = dividers.first { !$0.isHidden }!.frame.midX
                    check(abs(x - (dividerX ?? x)) <= 0.5, "The following divider stays put as digits change")
                    dividerX = x
                }
            }
        }
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var doubled = original; doubled["hud.fps.valueSize"] = 2
        defaults.setVolatileDomain(doubled, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
        let pinned = HUDMenuBarPresentation.sections(snapshot: .init(), fanSample: .noFans,
            readings: [.fps], style: .current, background: .dark)
        let menuBar = HUDHorizontalView(frame: .zero)
        let size = menuBar.configure(sections: pinned, showsBattery: false, background: .dark)
        let pinnedFields: [String: NSTextField] = member(menuBar, "labels")
        check(pinnedFields["fps.value"]!.font!.pointSize == 12 && size.height == HUDStyle.rowHeight,
              "Pinned menu-bar FPS retains 1× even when the HUD preference is 2×")
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
        valueSizing()
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
        check(abs(fpsSelector.alignmentRect(forFrame: fpsSelector.frame).minX - HUDCategoryLayout.modeLeading) < 1,
              "FPS uses the shared mode column")
        check(fpsSelector.frame.maxX <= fpsMenu.bounds.maxX, "FPS selector fits its row")
        var selected: HUDFPSOptions?
        fpsMenu.onChange = { selected = $0 }
        check(fpsHighlight.isEnabled && fpsHighlight.state == .on, "FPS emphasis starts available and on")
        let hitPoint = fpsMenu.convert(NSPoint(x: fpsHighlight.frame.midX, y: fpsHighlight.frame.midY), to: fpsMenu.superview)
        check(fpsMenu.hitTest(hitPoint) === fpsHighlight,
              "FPS emphasis receives its own click instead of toggling the category")
        check(fpsHighlight.frame.minX > fpsSelector.frame.maxX && fpsMenu.bounds.contains(fpsHighlight.frame),
              "FPS emphasis has its own column clear of all mode buttons")
        fpsHighlight.performClick(nil)
        check(selected?.valueHighlighted == false && selected?.enabled == true && selected?.mode == .both,
              "Emphasis turns emphasis off independently of visibility and mode")
        fpsHighlight.performClick(nil)
        check(selected?.valueHighlighted == true, "Emphasis turns emphasis back on")
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

        let styledHUD = activeHUD()
        styledHUD.setAutoHideMode(.off)
        let styledPanel: HUDPanel = member(styledHUD, "panel")
        let styledGlass: NativeGlassHUDBackground = member(styledHUD, "backgroundView")
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
                let frame = styledPanel.frame
                let bodyFrame = styledGlass.bodyFrame
                let values: [HUDMetric: NSTextField] = member(styledHUD, "valueLabels")
                let titles: [HUDMetric: NSTextField] = member(styledHUD, "titleLabels")
                for highlighted in [false, true, false] {
                    let storedHistory: FPSHistory = member(styledGraph, "history")
                    styledHUD.setFPSOptions(.init(enabled: true, mode: .both, valueHighlighted: highlighted))
                    let history: FPSHistory = member(styledGraph, "history")
                    check(history.samples.count == storedHistory.samples.count, "Emphasis must retain FPS history")
                    for value in [0.0, 8, 120, 9999] {
                        styledHUD.updateFPS(value)
                        let horizontalLabels: [String: NSTextField] = member(styledHorizontal, "labels")
                        let valueLabel = alignment == .horizontal ? horizontalLabels["0.value"]! : values[.fps]!
                        let expected = highlighted ? HUDStyle.TextStyle.emphasizedReading : .reading
                        check(valueLabel.font == expected.font(ofSize: 12), "FPS uses the selected style at its label size")
                        check(valueLabel.textColor == expected.color(background: .dark), "FPS color follows Reading or Emphasized Reading")
                        styledPanel.contentView?.layoutSubtreeIfNeeded()
                        let fpsTitle = alignment == .horizontal ? horizontalLabels["0.title"]! : titles[.fps]!
                        for (role, field) in [("title", fpsTitle), ("value", valueLabel)] {
                            let box = field.convert(field.bounds, to: styledContainer)
                            let topToBaseline = styledContainer.bounds.maxY - box.maxY + field.firstBaselineOffsetFromTop * scale.rawValue
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
                        check(styledPanel.frame == frame && styledGlass.bodyFrame == bodyFrame,
                              "FPS emphasis and changing digits must not resize the window or glass")
                    }
                    check(titles[.fps]?.font == HUDStyle.titleFont(for: .fps), "Emphasis affects only the FPS number")
                }
                if alignment == .vertical {
                    let dividers: [Int: NSView] = member(styledHUD, "groupDividers")
                    let line = dividers[2]!.subviews.first!
                    let dividerRight = line.convert(line.bounds, to: styledContainer).maxX
                    let plotRight = styledGraph.convert(styledGraph.plotBounds, to: styledContainer).maxX
                    check(abs(plotRight - dividerRight) <= 0.5,
                          "FPS history reaches the divider's right edge at \(scale.rawValue)×")
                    let graphRight = styledGraph.convert(styledGraph.bounds, to: styledContainer).maxX
                    check(abs(graphRight - plotRight - 3 * CGFloat(scale.rawValue)) <= 0.01,
                          "The endpoint halo retains its full space beyond the aligned plot")
                    check(graphRight <= styledContainer.bounds.maxX,
                          "The halo fits inside the HUD without changing its width")
                }
            }
        }
        styledHUD.shutdown()

        // Changing hidden FPS content must not resize the HUD or move its arrow
        // and first divider. Compare modes on the same live layout.
        let collapsedBodies: [(Set<HUDMetric>, Bool)] = [([], false), ([], true), ([.cpuTotal], false),
            ([.ramTotal], false), ([.fans], false), ([.battery], false), ([.misc], false),
            ([.cpuTotal, .ramTotal, .battery], false)]
        for scale in [HUDScale.small, HUDScale(rawValue: 0.51), HUDScale(rawValue: 0.75), .normal,
                      HUDScale(rawValue: 1.01), HUDScale(rawValue: 1.25), .large] {
            for (body, packageEnabled) in collapsedBodies {
                let compactHUD = HUDWindowController()
                compactHUD.setHUDEnabled(false)
                compactHUD.setMiscOptions(.init(enabled: true, readings: [.chip, .os]))
                compactHUD.setPackagePowerOptions(.init(enabled: packageEnabled))
                for metric in HUDMetric.allCases { compactHUD.setMetricEnabled(metric, enabled: body.contains(metric)) }
                compactHUD.setHUDScale(scale)
                compactHUD.setAutoHideMode(.fps)
                let panel: HUDPanel = member(compactHUD, "panel")
                let host: NSView = member(compactHUD, "container")
                let arrow: NSImageView = member(compactHUD, "collapsedFPSIndicator")
                let dividers: [Int: NSView] = member(compactHUD, "groupDividers")
                var reference: [CGFloat]?
                for mode in [HUDFPSDisplayMode.value, .history, .both, .value, .both] {
                    compactHUD.setFPSOptions(.init(enabled: true, mode: mode))
                    panel.contentView?.layoutSubtreeIfNeeded()
                    let visibleLines = dividers.sorted { $0.key < $1.key }.compactMap { _, divider -> CGFloat? in
                        guard !divider.isHidden, let line = divider.subviews.first else { return nil }
                        return host.bounds.maxY - line.convert(line.bounds, to: host).maxY
                    }
                    let geometry = [host.bounds.height, panel.frame.maxY, host.bounds.maxY - arrow.convert(arrow.bounds, to: host).maxY]
                        + Array(visibleLines.prefix(1))
                    if let reference {
                        check(reference.count == geometry.count && zip(reference, geometry).allSatisfy { abs($0 - $1) < 0.01 },
                              "Collapsed mode geometry changed: scale=\(scale.rawValue), body=\(body), package=\(packageEnabled), mode=\(mode), expected=\(reference), actual=\(geometry)")
                    } else { reference = geometry }
                }
                compactHUD.shutdown()
            }
        }
        if CommandLine.arguments.contains("--controls-only") {
            print("PASS: FPS mode preferences, emphasis save/reset, independent emphasis button clicks, History/Horizontal states, matching FPS baselines in both layouts at six scales from 0.5× to 2×, preserved history and stable surface geometry")
            return
        }

        for scale in [HUDScale.small, HUDScale(rawValue: 0.51), HUDScale(rawValue: 0.75), .normal,
                      HUDScale(rawValue: 1.01), HUDScale(rawValue: 1.25), HUDScale.large] {
            for fpsMetrics: Set<HUDMetric> in [[.fps], [.fpsGraph], [.fps, .fpsGraph]] {
                for body: Set<HUDMetric> in [[], [.cpuTotal], [.ramTotal], [.fans], [.battery], [.misc], [.cpuTotal, .ramTotal, .battery]] {
                    let hud = activeHUD()
                    hud.setMiscOptions(.init(enabled: true, readings: [.chip, .os]))
                    hud.setPackagePowerOptions(.init(enabled: false))
                    for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: fpsMetrics.union(body).contains(metric)) }
                    hud.setHUDScale(scale)
                    let panel: HUDPanel = member(hud, "panel")
                    let container: NSView = member(hud, "container")
                    let glass: NativeGlassHUDBackground = member(hud, "backgroundView")
                    let expandedSize = container.frame.size
                    let expandedFrame = panel.frame
                    func windowAnchor() -> NSPoint { NSPoint(x: panel.frame.minX, y: panel.frame.maxY) }
                    let originalRect = windowAnchor()
                    hud.setAutoHideMode(.fps)
                    check(container.frame.height < expandedSize.height, "Unavailable FPS collapses")
                    check(panel.frame.height < expandedFrame.height && panel.frame.width == expandedFrame.width, "Collapse shrinks the native window height")
                    check(windowAnchor() == originalRect, "Anchor mismatch scale=\(scale) fps=\(fpsMetrics) body=\(body), old=\(originalRect) new=\(windowAnchor()), container=\(container.frame), glass=\(glass.frame)")
                    let header: NSImageView = member(hud, "collapsedFPSIndicator")
                    check(!header.isHidden && header.alphaValue == 1 && header.image != nil,
                          "Collapsed FPS keeps a visible reminder, including History-only")
                    let headerFrame = header.convert(header.bounds, to: container)
                    check(abs(headerFrame.midX - container.bounds.midX) <= 0.5 / panel.backingScaleFactor,
                          "Rolled-up arrow is centered")
                    let dividers: [Int: NSView] = member(hud, "groupDividers")
                    for divider in dividers.values where !divider.isHidden {
                        check(divider.alphaValue == 1, "Section dividers remain visible while rolled up")
                    }
                    check(headerFrame.minY >= 0 && headerFrame.maxY <= container.bounds.height,
                          "Reminder stays inside the compact panel")
                    if body.isEmpty {
                        check(container.alphaValue == 1 && container.frame.height > 0, "FPS-only retains the compact header")
                    } else {
                        check(container.alphaValue == 1 && container.frame.height > 0, "Other metrics remain visible")
                        let rows: [HUDMetric: NSView] = member(hud, "metricRows")
                        let host = container
                        for metric in body {
                            let row = rows[metric]!
                            let rect = row.convert(row.bounds, to: host)
                            check(rect.minY >= -0.1 && rect.maxY <= host.bounds.height + 0.1, "Body rows must stay inside the visible crop: \(metric)")
                            check(rect.maxY <= headerFrame.minY, "Compact header must not overlap other metrics")
                        }
                    }
                    if CommandLine.arguments.contains("--preview"), scale == .normal,
                       fpsMetrics == [.fps, .fpsGraph], body == [.cpuTotal, .ramTotal, .battery] {
                        // Render the real native layout over a neutral backing over a neutral backing.
                        let surface: NSView = member(glass, "glass")
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
                    check(panel.frame == expandedFrame && windowAnchor() == originalRect, "Samples do not move the HUD")
                    hud.markFPSUnavailable()
                    check(container.frame.size == expandedSize, "A single missing reading must not collapse")
                    hud.setAutoHideMode(.off)
                    check(header.isHidden, "Static does not show the compact reminder")
                    check(container.frame.size == expandedSize && glass.bodyFrame.size == expandedSize, "Static restores original geometry")
                    hud.setAlignment(.horizontal)
                    hud.setAutoHideMode(.fps)
                    check(glass.bodyFrame.size == container.frame.size && header.isHidden, "Horizontal glass fits valid expanded FPS")
                    hud.shutdown()
                }
            }
        }

        for scale in [HUDScale.small, HUDScale(rawValue: 0.51), HUDScale(rawValue: 0.75), .normal,
                      HUDScale(rawValue: 1.01), HUDScale(rawValue: 1.25), HUDScale.large] {
            for background in [HUDBackground.dark, .light] {
                for body: Set<HUDMetric> in [[], [.cpuTotal], [.ramTotal, .battery], [.fans]] {
                    let hud = activeHUD()
                    hud.setMiscOptions(.init(enabled: true, readings: [.chip, .os]))
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
                    let glass: NativeGlassHUDBackground = member(hud, "backgroundView")
                    let expandedSize = container.frame.size
                    let expandedFrame = panel.frame
                    func windowAnchor() -> NSPoint { NSPoint(x: panel.frame.minX, y: panel.frame.maxY) }
                    let originalAnchor = windowAnchor()
                    hud.setAutoHideMode(.fps)
                    let collapsedSize = container.frame.size
                    check(collapsedSize.width < expandedSize.width && collapsedSize.height == expandedSize.height,
                          "Horizontal collapses width only")
                    check(!arrow.isHidden && arrow.alphaValue == 1 && container.bounds.contains(arrow.convert(arrow.bounds, to: container)),
                          "Sideways reminder fits inside the compact HUD")
                    check(panel.frame.width < expandedFrame.width && windowAnchor() == originalAnchor, "Horizontal native window shrinks at its existing anchor")
                    hud.updateMetric(.cpuTotal, value: "24%")
                    check(container.frame.size == collapsedSize && windowAnchor() == originalAnchor,
                          "Regular sampling cannot reset a collapsed width or move the HUD anchor")
                    if CommandLine.arguments.contains("--preview"), scale == .normal,
                       background == .dark, body == [.cpuTotal] {
                        let surface: NSView = member(glass, "glass")
                        surface.isHidden = true
                        glass.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor
                        let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds)!
                        container.cacheDisplay(in: container.bounds, to: bitmap)
                        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/phud-horizontal-collapsed.png"))
                        surface.isHidden = false
                    }
                    hud.updateFPS(60)
                    check(container.frame.size == expandedSize && arrow.isHidden, "Horizontal FPS recovery restores full width")
                    check(horizontal.frame.minX == HUDStyle.horizontalPadding, "Expanded FPS keeps its original alignment")
                    check(panel.frame == expandedFrame && windowAnchor() == originalAnchor, "Recovery restores full geometry")
                    hud.setAutoHideMode(.off)
                    check(glass.bodyFrame.size == expandedSize && container.frame.size == expandedSize, "Static restores horizontal geometry")
                    hud.shutdown()
                }
            }
        }

        // Exercise real asynchronous collapse/recovery, including a cancelled deadline.
        let hud = activeHUD()
        hud.setAutoHideMode(.fps)
        let container: NSView = member(hud, "container")
        let panel: HUDPanel = member(hud, "panel")
        let glass: NativeGlassHUDBackground = member(hud, "backgroundView")
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
        check(container.frame.height == compact && panel.frame.maxY == reserved.maxY && panel.frame.minX == reserved.minX, "Delayed collapse: height=\(container.frame.height) expected=\(compact), frame=\(panel.frame) expectedFrame=\(reserved), progress=\(member(hud, "fpsProgress") as CGFloat), availability=\(member(hud, "fpsAvailability") as HUDFPSAvailability)")
        hud.updateFPS(.nan)
        check(container.frame.height == compact, "Invalid readings do not reopen FPS")
        hud.updateFPS(50)
        check(container.frame.height == expanded, "Next valid reading reopens")
        hud.setAutoHideMode(.off)
        let staticSize = container.frame.size
        hud.markFPSUnavailable()
        try? await Task.sleep(for: .seconds(3.1))
        check(container.frame.size == staticSize && glass.bodyFrame.size == staticSize, "Static ignores the collapse deadline")
        // Animate a visible native window and verify its anchor through reversal.
        hud.setBackground(.dark)
        hud.setAutoHideMode(.fps)
        hud.setAutoHideAnimated(true)
        hud.setHUDEnabled(true)
        let animationStart = container.frame.height
        let animationWindow = panel.frame
        hud.updateFPS(60)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            try? await Task.sleep(for: .milliseconds(180))
            check(container.frame.height > animationStart && container.frame.height < staticSize.height,
                  "Visible native window should pass through an intermediate expansion height")
            check(panel.frame.maxY == animationWindow.maxY && panel.frame.minX == animationWindow.minX, "Animation preserves the window anchor")
            // Another sample during expansion must not restart its easing curve.
            hud.updateFPS(55)
        }
        try? await Task.sleep(for: .milliseconds(600))
        let finalExpanded = container.frame.height
        check(finalExpanded > animationStart && panel.frame.maxY == animationWindow.maxY, "Animation completes at expanded size")
        hud.resetFPS()
        try? await Task.sleep(for: .seconds(3.2))
        hud.updateFPS(48) // Reverse a collapse that has already started.
        try? await Task.sleep(for: .milliseconds(700))
        check(container.frame.height == finalExpanded, "Returning readings reverse an in-flight collapse")
        hud.setHUDEnabled(false)
        hud.shutdown()
        let sideways = activeHUD()
        sideways.setAlignment(.horizontal)
        sideways.setBackground(.dark)
        sideways.setAutoHideMode(.fps)
        sideways.setAutoHideAnimated(true)
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
        check(fullWidth > initialWidth && sidewaysPanel.frame.minX == fixedFrame.minX && sidewaysPanel.frame.maxY == fixedFrame.maxY, "Sideways expansion preserves the top-left anchor")
        sideways.resetFPS()
        try? await Task.sleep(for: .seconds(3.2))
        sideways.updateFPS(48)
        try? await Task.sleep(for: .milliseconds(700))
        check(sidewaysContainer.frame.width == fullWidth && sidewaysPanel.frame.minX == fixedFrame.minX && sidewaysPanel.frame.maxY == fixedFrame.maxY,
              "Horizontal recovery reverses an in-flight collapse")
        sideways.setHUDEnabled(false)
        sideways.shutdown()
        print("PASS: FPS availability, shared mode/reset, all scales/row selections, stable text geometry and native window resizing, FPS-only, horizontal, cancelled deadlines, recovery, native animation and reversal")
    }
}
