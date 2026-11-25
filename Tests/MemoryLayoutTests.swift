import AppKit

@main struct MemoryLayoutTests {
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }
    @MainActor static func verticalDividerBoundaries() {
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "off",
            "hud.alignment": "vertical"], forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain) }
        let hud = HUDWindowController()
        defer { hud.shutdown() }
        hud.setPackagePowerOptions(.init(enabled: false))
        hud.setMiscOptions(.init(enabled: true, readings: [.chip, .os]))
        for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: false) }
        let dividers: [Int: NSView] = member(hud, "groupDividers")
        let groups: [[HUDMetric]] = member(hud, "verticalMetricGroups")
        let stack: NSView = member(hud, "stackView")
        let rows: [HUDMetric: NSView] = member(hud, "metricRows")
        precondition([HUDMetric.gpu, .cpu, .ram].allSatisfy { rows[$0] == nil }, "APP readings have no independent resource rows")
        for metric in [HUDMetric.ramTotal, .misc, .fans] {
            hud.setMetricEnabled(metric, enabled: true)
            precondition(dividers.values.allSatisfy(\.isHidden),
                         "A lone \(metric.hudTitle(for: .vertical)) category has no leading or trailing divider")
            precondition(stack.subviews.first(where: { !$0.isHidden }) === rows[metric],
                         "A lone \(metric.hudTitle(for: .vertical)) starts directly with its content")
            hud.setMetricEnabled(metric, enabled: false)
        }
        hud.setMetricEnabled(.ramTotal, enabled: true)
        hud.setMetricEnabled(.misc, enabled: true)
        let deviceGroup = groups.firstIndex { $0.contains(.misc) }!
        precondition(Set(dividers.filter { !$0.value.isHidden }.keys) == [deviceGroup],
                     "Memory and Misc have exactly one divider between them")
        hud.setMetricEnabled(.ramTotal, enabled: false)
        precondition(dividers.values.allSatisfy(\.isHidden),
                     "Removing the preceding category removes Misc's former boundary")
        hud.setMetricEnabled(.fans, enabled: true)
        precondition(Set(dividers.filter { !$0.value.isHidden }.keys) == [deviceGroup],
                     "Fans before Misc retains its separating boundary without a top divider")
        print("PASS: singleton Memory, Misc, and Fan divider boundaries")
    }
    @MainActor static func horizontalDividerSpacing() {
        let strip = HUDHorizontalView(frame: .zero)
        strip.battery.update(percentage: 50, source: .battery)
        let pins: Set<HUDMenuBarReading> = [.socPower, .batteryEnergy]
        let style = HUDMenuBarPresentation.Style.current
        let withMemory = HUDMenuBarPresentation.sections(snapshot: .init(), fanSample: .noFans,
            readings: pins.union([.memoryUsage]), style: style, background: .dark)
        let withoutMemory = HUDMenuBarPresentation.sections(snapshot: .init(), fanSample: .noFans,
            readings: pins, style: style, background: .dark)
        let withFPSAndFans = HUDMenuBarPresentation.sections(snapshot: .init(), fanSample: .noFans,
            readings: pins.union([.fps, .memoryUsage, .fanUsage]), style: style, background: .dark)
        for scale in [HUDScale.small, .normal, .large] {
            strip.setFrameSize(NSSize(width: 400 * scale.rawValue, height: 21 * scale.rawValue))
            strip.setBoundsSize(NSSize(width: 400, height: 21))
            _ = strip.configure(sections: withMemory, showsBattery: true, background: .dark)
            let labels: [String: NSTextField] = member(strip, "labels")
            let dividers: [NSView] = member(strip, "dividers")
            let soc = labels["package.title"]!, watts = labels["package.power"]!
            let memory = labels["\(HUDMetric.ramTotal.rawValue).title"]!
            let usage = labels["\(HUDMetric.ramTotal.rawValue).value"]!
            let memoryTextStart = memory.alignmentRect(forFrame: memory.frame).minX
            let socDivider = dividers[0].frame
            precondition(soc.frame.minX == 0)
            precondition(watts.alignmentRect(forFrame: watts.frame).minX - soc.alignmentRect(forFrame: soc.frame).maxX == 8)
            // 16.5 pt: a 1.5 pt divider then has a whole, equal number of pixels on each side.
            precondition(memory.frame.minX - watts.frame.maxX == 16.5)
            precondition(socDivider.midX == (watts.frame.maxX + memory.frame.minX) / 2)
            precondition(strip.battery.frame.minX - usage.frame.maxX == 16.5)
            precondition(dividers[1].frame.midX == (usage.frame.maxX + strip.battery.frame.minX) / 2)

            let size = strip.configure(sections: withoutMemory, showsBattery: true, background: .dark)
            precondition(dividers.filter { !$0.isHidden }.count == 1 && dividers[0].frame == socDivider,
                         "Hiding MEM must leave the divider after SOC in exactly the same position")
            precondition(strip.battery.frame.minX + strip.battery.sourceTextRect.minX == memoryTextStart,
                         "BAT must start where the MEM title was")
            precondition(strip.battery.frame.maxX == size.width)

            _ = strip.configure(sections: withFPSAndFans, showsBattery: true, background: .dark)
            let fields: [String: NSTextField] = member(strip, "labels")
            let fan = fields["fan.status"]!.frame
            let boundaries = [(fields["fps.value"]!.frame.maxX, soc.frame.minX),
                              (watts.frame.maxX, memory.frame.minX), (usage.frame.maxX, fan.minX),
                              (fan.maxX, strip.battery.frame.minX)]
            let lines: [NSView] = member(strip, "dividers")
            let visible = lines.filter { !$0.isHidden }
            precondition(visible.count == boundaries.count)
            for (line, (left, right)) in zip(visible, boundaries) {
                precondition(abs(right - left - 16.5) < 0.001)
                precondition(abs(line.frame.midX - (left + right) / 2) < 0.001)
            }
        }
    }
    @MainActor static func main() throws {
        _ = NSApplication.shared
        verticalDividerBoundaries()
        horizontalDividerSpacing()
        if CommandLine.arguments.contains("--dividers-only") { return }
        let scales: [HUDScale] = CommandLine.arguments.contains("--normal-size") ? [.normal] : [.small, .normal, .large]
        let suite = "PerformanceHUD.PressureTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        var saved = HUDPreferences.resourceOptions(for: .ram, in: store)
        precondition(saved.pressure && saved.pressureMode == .colorHistory, "Pressure B2 is enabled by default")
        for mode in HUDMemoryPressureMode.allCases {
            saved.selectPressureMode(mode)
            HUDPreferences.setResourceOptions(saved, for: .ram, in: store)
            precondition(HUDPreferences.resourceOptions(for: .ram, in: store) == saved, "Pressure preference round-trips")
        }
        HUDPreferences.resetOptions(in: store)
        precondition(HUDPreferences.resourceOptions(for: .ram, in: store).pressureMode == .colorHistory, "Reset restores B2")
        for (legacy, mode) in [("graph", HUDMemoryPressureMode.meter), ("colorGraph", .colorMeter)] {
            store.set(legacy, forKey: "hud.group.ram.pressureMode")
            precondition(HUDPreferences.resourceOptions(for: .ram, in: store).pressureMode == mode,
                         "The previous experiment keeps the user's neutral/coloured selection")
        }
        store.set("unknown", forKey: "hud.group.ram.pressureMode")
        precondition(HUDPreferences.resourceOptions(for: .ram, in: store).pressureMode == .colorHistory, "Unknown modes fall back to B2")
        UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "off",
            "hud.background": "dark", "hud.alignment": "vertical"], forName: UserDefaults.argumentDomain)
        let hud = HUDWindowController()
        let panel: HUDPanel = member(hud, "panel")
        panel.alphaValue = 0
        hud.setHUDEnabled(true)
        let container: NSView = member(hud, "container")
        let horizontal: HUDHorizontalView = member(hud, "horizontalView")
        let glass: NativeGlassHUDBackground = member(hud, "backgroundView")
        let surface: NSView = member(glass, "glass")
        surface.isHidden = true // Offscreen preview uses a plain surface.
        let titles: [HUDMetric: NSTextField] = member(hud, "titleLabels")
        let usage: [HUDMetric: NSTextField] = member(hud, "valueLabels")
        let physical: [HUDMetric: NSTextField] = member(hud, "ramDetailLabels")
        let captions: [HUDMetric: NSTextField] = member(hud, "ramDetailTitleLabels")
        let swapTitle: NSTextField = member(hud, "ramSwapTitleLabel")
        let swap: NSTextField = member(hud, "ramSwapValueLabel")
        let pressure: NSTextField = member(hud, "ramPressureValueLabel")
        let pressureTitle: NSTextField = member(hud, "ramPressureTitleLabel")
        var issues = Set<String>()
        var configurations = 0
        func check(_ condition: Bool, _ message: String) { if !condition { issues.insert(message) } }
        for alignment in HUDAlignment.allCases {
            hud.setAlignment(alignment)
            hud.setPackagePowerOptions(.init(enabled: false))
            for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: false) }
            for scale in scales {
                hud.setHUDScale(scale)
                for mode in [HUDUsageMode.total] {
                    for details in [false, true] {
                        for showsUsage in [false, true] where details || showsUsage {
                            for emphasized in [false, true] {
                                hud.setResourceOptions(.init(enabled: true, temperature: false,
                                    totalUse: showsUsage && mode != .app, focusedApp: showsUsage && mode != .total,
                                    details: details, pressure: details, highlighted: emphasized ? [.details, .totalUse, .focusedApp] : [], usageMode: mode,
                                    pressureMode: .text), for: .ram)
                                let size = panel.frame.size
                                configurations += 1
                                var memoryDetailFrames: [NSRect]?
                                var readings: [(Double?, Double?)] = [(0, 0), (13.71, 0.74), (13.88, 0.74),
                                                                      (13.88, 123.45), (999.99, 999.99)]
                                if alignment == .vertical {
                                    readings += [(nil, nil), (1024.25, nil), (8888.88, 8888.88), (13.71, 0.74)]
                                }
                                for state in ["normal", "warning", "critical", ""] {
                                    for (gb, swapGB) in readings {
                                        let sample = gb.map { RAMUsageSample(percentage: $0 == 0 ? 0 : 100,
                                            usedBytes: UInt64($0 * 1_073_741_824), swapUsedBytes: swapGB.map { UInt64($0 * 1_073_741_824) }) }
                                        hud.updateRAM(.ramTotal, usage: sample)
                                        hud.updateRAM(.ram, usage: sample)
                                        hud.updateMemoryPressure(state)
                                        panel.contentView?.layoutSubtreeIfNeeded()
                                        check(panel.frame.size == size, "Memory readings must not resize \(alignment), \(scale), \(mode)")
                                        let host: NSView = alignment == .vertical ? container : horizontal
                                        func inspect(_ view: NSView) {
                                            guard !view.isHidden else { return }
                                            if let label = view as? NSTextField, !label.stringValue.isEmpty {
                                                let context = "\(alignment) \(scale.rawValue) \(mode) \(details) \(showsUsage) \(emphasized) \(label.stringValue)"
                                                check(container.bounds.insetBy(dx: -1, dy: -1).contains(label.convert(label.bounds, to: container)), "Outside HUD: \(context)")
                                                check(label.frame.width + 1 >= label.intrinsicContentSize.width, "Clipped width: \(context)")
                                                check(label.frame.height + 1 >= label.intrinsicContentSize.height, "Clipped height: \(context)")
                                            }
                                            for child in view.subviews { inspect(child) }
                                        }
                                        inspect(host)
                                        if alignment == .horizontal && details {
                                            let labels: [String: NSTextField] = member(horizontal, "labels")
                                            let prefix = String(HUDMetric.ramTotal.rawValue)
                                            let heading = labels["\(prefix).title"]!
                                            let swapTitle = labels["\(prefix).SWP.title"]!
                                            let swapValue = labels["\(prefix).SWP.value"]!
                                            let physicalTitle = labels["\(prefix).PHY.title"]!
                                            let physicalValue = labels["\(prefix).PHY.value"]!
                                            check([heading, swapTitle, physicalTitle].map(\.stringValue) == ["MEM", "SWP", "PHY"],
                                                  "Horizontal memory uses abbreviated labels")
                                            check(swapValue.stringValue == swap.stringValue && physicalValue.stringValue == physical[.ramTotal]!.stringValue,
                                                  "Horizontal memory keeps each reading with its caption")
                                            for (caption, reading) in [(swapTitle, swapValue), (physicalTitle, physicalValue)] {
                                                let captionRect = caption.alignmentRect(forFrame: caption.frame)
                                                let readingRect = reading.alignmentRect(forFrame: reading.frame)
                                                let gap = readingRect.maxX - reading.intrinsicContentSize.width - captionRect.maxX
                                                check(abs(gap - HUDStyle.memoryLabelValueSpacing) <= 1,
                                                      "Horizontal \(caption.stringValue) uses the standard compact reading gap")
                                            }
                                            let pressureField = labels["ram.pressure"]!
                                            var ordered = [heading]
                                            if showsUsage { ordered.append(labels["\(prefix).value"]!) }
                                            ordered += [swapTitle, swapValue, physicalTitle, physicalValue, pressureField]
                                            let baseline = heading.frame.maxY - heading.firstBaselineOffsetFromTop
                                            for field in ordered {
                                                check(abs(field.frame.maxY - field.firstBaselineOffsetFromTop - baseline) <= 1,
                                                      "Horizontal memory readings share a baseline")
                                            }
                                            for (left, right) in zip(ordered, ordered.dropFirst()) {
                                                let leftRect = left.alignmentRect(forFrame: left.frame)
                                                let rightRect = right.alignmentRect(forFrame: right.frame)
                                                if right !== swapValue && right !== physicalValue {
                                                    check(leftRect.maxX <= rightRect.minX, "Horizontal memory order is MEM, use, SWP, PHY, pressure")
                                                }
                                            }
                                        }
                                        if alignment == .vertical && details && mode != .app {
                                            check(titles[.ramTotal]?.stringValue == "Memory", "Vertical HUD uses Memory")
                                            check(captions[.ramTotal]?.stringValue == "Physical" && swapTitle.stringValue == "Swap" && pressureTitle.stringValue == "Pressure", "Vertical uses full memory labels")
                                            func baseline(_ field: NSTextField) -> CGFloat {
                                                field.convert(field.bounds, to: field.superview).maxY - field.firstBaselineOffsetFromTop
                                            }
                                            let rowSpacing = HUDStyle.ramDetailHeight()
                                            let physicalTitle = captions[.ramTotal]!, physicalValue = physical[.ramTotal]!
                                            check(abs(baseline(physicalValue) - baseline(swap)) <= 0.5, "Swap and Physical share a row")
                                            check(abs(baseline(swap) - baseline(pressure) - rowSpacing) <= 0.5, "Pressure has its own row below Swap")
                                            func aligned(_ field: NSTextField) -> NSRect { field.alignmentRect(forFrame: field.frame) }
                                            let firstDetailSpacing = baseline(titles[.ramTotal]!) - baseline(captions[.ramTotal]!)
                                            check(abs(firstDetailSpacing - HUDStyle.headingToDetailSpacing(.tight)) <= 0.5, "Memory uses tight heading-to-detail spacing")
                                            for (caption, value) in [(physicalTitle, physicalValue), (swapTitle, swap), (pressureTitle, pressure)] {
                                                check(abs(baseline(caption) - baseline(value)) <= 0.5, "Memory caption/value baseline matches")
                                                check(value.alignment == .right && aligned(caption).maxX <= aligned(value).minX, "Memory reading fits after its label")
                                            }
                                            for field in [swapTitle, pressureTitle] {
                                                check(abs(aligned(field).minX - aligned(titles[.ramTotal]!).minX) <= 0.5, "Swap and Pressure align to Memory")
                                            }
                                            for field in [physicalValue, pressure] {
                                                check(abs(aligned(field).maxX - aligned(usage[.ramTotal]!).maxX) <= 0.5, "Physical and Pressure readings share the right edge")
                                            }
                                            let frames = [swapTitle, swap, physicalTitle, physicalValue].map(aligned)
                                            if let memoryDetailFrames {
                                                check(frames == memoryDetailFrames, "Vertical memory columns moved as readings changed at \(scale.rawValue)×")
                                            } else {
                                                memoryDetailFrames = frames
                                            }
                                            check(aligned(swap).maxX <= aligned(physicalTitle).minX, "Memory detail pairs fit side by side")
                                            check(HUDStyle.rowHeight(for: .ramTotal) == HUDStyle.headingToDetailSpacing(.tight) + 2 * rowSpacing, "Memory reserves one Details row and one Pressure row")
                                        }
                                        if alignment == .vertical {
                                            check(pressure.isHidden == !(details && mode != .app), "Pressure follows its own visibility and source")
                                            check(pressureTitle.isHidden == !(details && mode != .app), "Pressure caption follows pressure visibility")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        let meter: HUDMemoryPressureMeterView = member(hud, "ramPressureMeter")
        let history: HUDMemoryPressureHistoryView = member(hud, "ramPressureHistory")
        for scale in scales {
            hud.setHUDScale(scale)
            for appearance in [HUDBackground.light, .dark] {
                hud.setBackground(appearance)
                for alignment in HUDAlignment.allCases {
                    hud.setAlignment(alignment)
                    var options = HUDResourceOptions(enabled: true, temperature: false, totalUse: true,
                                                     focusedApp: false, pressureMode: .text)
                    hud.setResourceOptions(options, for: .ram)
                    let size = panel.frame.size
                    var compactMeterSize: NSSize?
                    hud.updateMemoryPressure("critical")
                    for mode in HUDMemoryPressureMode.allCases {
                        options.pressureMode = mode
                        hud.setResourceOptions(options, for: .ram)
                        panel.contentView?.layoutSubtreeIfNeeded()
                        if alignment == .horizontal && mode.display != .text {
                            check(panel.frame.width < size.width && panel.frame.height == size.height,
                                  "Horizontal meters reserve less width than pressure text")
                            if let compactMeterSize {
                                check(panel.frame.size == compactMeterSize, "Neutral and coloured meters reserve the same space")
                            } else { compactMeterSize = panel.frame.size }
                        } else if alignment == .vertical && mode.isHistory {
                            check(panel.frame.width == size.width
                                  && abs(panel.frame.height - size.height - 12.375 * CGFloat(scale.rawValue)) < 1,
                                  "Vertical history adds the taller plot's height only")
                        } else {
                            check(panel.frame.size == size, "Text and meters retain the compact size")
                        }
                        check(meter.isHidden == (alignment == .horizontal || mode.display == .text || mode.isHistory), "Only Vertical meters appear")
                        check(history.isHidden == (alignment == .horizontal || !mode.isHistory), "History is Vertical only")
                        check(pressure.isHidden == (mode.display != .text), "Text and meter are mutually exclusive")
                        check(pressure.stringValue == "critical", "Horizontal retains its pressure state in every display mode")
                        if !meter.isHidden {
                            let rect = meter.convert(meter.bounds, to: container)
                            let textRect = pressure.convert(pressure.alignmentRect(forFrame: pressure.frame), from: pressure.superview)
                            let right = pressure.convert(textRect, to: container).maxX
                            check(abs(rect.maxX - right) < 0.5, "Meter is right aligned with the pressure text")
                            check(abs(rect.width - 72.6 * CGFloat(scale.rawValue)) < 0.5
                                  && abs(rect.height - 12 * CGFloat(scale.rawValue)) < 0.5, "Meter scales without enlarging its row")
                            check(container.bounds.contains(rect), "Meter fits inside the HUD")
                        }
                        if !history.isHidden {
                            let rect = history.convert(history.bounds, to: container)
                            let plot = history.convert(history.plotBounds, to: container)
                            let caption = history.convert(pressureTitle.bounds, from: pressureTitle)
                            let captionBaseline = caption.maxY - pressureTitle.firstBaselineOffsetFromTop
                            let rowBaseline = history.convert(pressure.bounds, from: pressure).maxY - pressure.firstBaselineOffsetFromTop
                            check(abs(captionBaseline - rowBaseline) <= 0.5, "Pressure caption stays on the first graph row")
                            let physicalTitle = captions[.ramTotal]!
                            let captionX = physicalTitle.superview!.convert(physicalTitle.alignmentRect(forFrame: physicalTitle.frame), to: container).minX
                            check(abs(captionX - plot.minX) <= 0.5, "Physical starts at the left edge of the pressure graph")
                            check(abs(plot.maxX - (container.bounds.maxX - HUDStyle.horizontalPadding * scale.rawValue)) < 0.5,
                                  "History reaches the divider's right edge")
                            check(rect.width > 72.6 * CGFloat(scale.rawValue), "History extends beyond the meter towards the power column")
                            check(container.bounds.contains(rect), "History fade fits inside existing HUD bounds")
                        }
                    }
                    options.details = false
                    options.pressureMode = .colorMeter
                    let stripMeters: [String: HUDMemoryPressureMeterView] = member(horizontal, "pressureMeters")
                    let detailMeterY = stripMeters["ram.pressure"]?.frame.midY
                    hud.setResourceOptions(options, for: .ram)
                    if alignment == .horizontal {
                        let fields: [String: NSTextField] = member(horizontal, "labels")
                        let heading = fields["\(HUDMetric.ramTotal.rawValue).title"]!
                        check(heading.stringValue == "MEM", "Horizontal memory abbreviates the heading when Details is off")
                        if let detailMeterY, let meter = stripMeters["ram.pressure"] {
                            check(abs(meter.frame.midY - detailMeterY) <= 0.5,
                                  "Pressure meter stays centered when Details is toggled")
                        }
                    }
                    check(meter.isHidden == (alignment == .horizontal), "Details off retains the pressure meter")
                    options.pressure = false
                    hud.setResourceOptions(options, for: .ram)
                    check(meter.isHidden && pressure.isHidden && history.isHidden, "Pressure off hides every pressure display")
                }
            }
        }
        // Inspect the rendered segments: every state is distinguishable without colour.
        hud.setAlignment(.vertical)
        hud.setHUDScale(.normal)
        for background in [HUDBackground.light, .dark] {
            hud.setBackground(background)
            for mode in [HUDMemoryPressureMode.meter, .colorMeter] {
                hud.setResourceOptions(.init(enabled: true, temperature: false, totalUse: true,
                                            focusedApp: false, pressureMode: mode), for: .ram)
                panel.contentView?.layoutSubtreeIfNeeded()
                for (state, count) in [("normal", 1), ("warning", 2), ("critical", 3), ("normal", 1), ("", 0)] {
                    hud.updateMemoryPressure(state)
                    check(meter.activeSegmentCount == count, "Pressure changes immediately to the current level")
                    let bitmap = meter.bitmapImageRepForCachingDisplay(in: meter.bounds)!
                    meter.cacheDisplay(in: meter.bounds, to: bitmap)
                    let ratio = CGFloat(bitmap.pixelsWide) / meter.bounds.width
                    for index in 0..<3 {
                        let color = bitmap.colorAt(x: Int((CGFloat(11.1) + CGFloat(index) * 25.2) * ratio), y: bitmap.pixelsHigh / 2)!
                            .usingColorSpace(.deviceRGB)!
                        let active = index < count
                        check(active ? color.alphaComponent > 0.6 : color.alphaComponent < 0.3,
                              "Only the expected meter segments are filled")
                        if count > 0 && !active { check(color.alphaComponent > 0.05, "Inactive segments remain visible") }
                        if active && mode == .meter {
                            check(abs(color.redComponent - color.greenComponent) < 0.02
                                  && abs(color.greenComponent - color.blueComponent) < 0.02, "Neutral meter has no coloured tint")
                        }
                        if active && mode == .colorMeter {
                            check(count == 1 ? color.greenComponent > color.redComponent
                                : count == 2 ? min(color.redComponent, color.greenComponent) > color.blueComponent
                                : color.redComponent > color.greenComponent, "All filled segments share the current pressure state's colour")
                        }
                    }
                }
            }
        }
        check(meter.currentLevel == nil, "Unavailable pressure remains blank")
        let spacingPreview = HUDHorizontalView(frame: .zero)
        for scale in scales {
            let regularFont = HUDStyle.readingFont(highlighted: false)
            var normal = HUDHorizontalView.Reading(id: "pressure", text: "normal", reference: "normal",
                font: regularFont, color: .white, help: nil, startsMetric: false, pressureMode: .text)
            // The meter is spaced like the word "normal": right-aligned in its slot like every reading, with the
            // spare room that word has in the slot reserved for "warning".
            let insets = NSTextField(labelWithString: "").alignmentRectInsets
            let wordSlot = HUDStyle.horizontalColumnWidth(text: "normal", reference: "warning", font: regularFont,
                                                          sizingFont: HUDStyle.readingFont(highlighted: true))
            let wordInk = NSAttributedString(string: "normal", attributes: [.font: regularFont]).size().width
            for mode in [HUDMemoryPressureMode.meter, .colorMeter] {
                normal.pressureMode = mode
                let size = spacingPreview.configure(sections: [[normal]], showsBattery: false,
                                                    background: .dark)
                let meters: [String: HUDMemoryPressureMeterView] = member(spacingPreview, "pressureMeters")
                let rect = meters["pressure"]!.frame
                check(abs(rect.minX - (wordSlot - wordInk)) <= 0.5,
                      "A horizontal meter has the same spare room before it as the word normal")
                check(size.width == rect.maxX + insets.right && rect.maxX == rect.maxX.rounded(),
                      "A horizontal meter is right-aligned in a whole-point slot, with the text edge inset after it")
                for state in ["warning", "critical", ""] {
                    let reading = HUDHorizontalView.Reading(id: "pressure", text: state, reference: "warning",
                        font: HUDStyle.readingFont(highlighted: true), color: .white,
                        help: nil, startsMetric: false, pressureMode: mode)
                    let changed = spacingPreview.configure(sections: [[reading]], showsBattery: false,
                                                           background: .dark)
                    check(changed == size && meters["pressure"]!.frame == rect,
                          "State and text emphasis cannot move or resize a horizontal meter")
                }
            }
        }
        if CommandLine.arguments.contains("--preview") {
            hud.setAlignment(.vertical)
            hud.setHUDScale(.normal)
            hud.setFPSOptions(.init(enabled: true, mode: .both))
            hud.updateFPS(144)
            hud.setResourceOptions(.init(enabled: true, temperature: true, totalUse: true, focusedApp: false, power: true), for: .gpu)
            hud.setResourceOptions(.init(enabled: true, temperature: true, totalUse: true, focusedApp: false, power: true), for: .cpu)
            hud.updateMetric(.gpuTotal, value: "72%")
            hud.updateMetric(.cpuTotal, value: "26%")
            hud.updateTemperatures(.init(cpu: 46, gpu: 43))
            hud.updatePower(.init(cpu: 2.4, gpu: 1.8, package: 4.2, ane: 0))
            hud.setResourceOptions(.init(enabled: true, temperature: false, totalUse: true, focusedApp: false, details: true, highlighted: [.totalUse]), for: .ram)
            hud.updateRAM(.ramTotal, usage: .init(percentage: 57, usedBytes: UInt64(13.71 * 1_073_741_824), swapUsedBytes: 0))
            hud.updateMemoryPressure("normal")
            hud.setBatteryOptions(.init(enabled: true, temperature: true, charge: true))
            hud.updateBattery(.init(percentage: 80, source: .powerAdapter, temperature: 33))
            hud.setMiscOptions(.init(enabled: true, readings: [.chip, .os]))
            for appearance in [HUDBackground.light, .dark] {
                hud.setBackground(appearance)
                surface.isHidden = true
                glass.layer?.backgroundColor = NSColor(calibratedWhite: appearance == .light ? 0.91 : 0.12, alpha: 1).cgColor
                for mode in HUDMemoryPressureMode.allCases {
                    hud.setResourceOptions(.init(enabled: true, temperature: false, totalUse: true,
                        focusedApp: false, pressureMode: mode), for: .ram)
                    hud.updateMemoryPressure("warning")
                    if mode.isHistory {
                        hud.clearMemoryPressureHistory()
                        for second in 0...30 {
                            hud.updateMemoryPressureHistory(.init(time: Double(second), level: .medium,
                                numericValue: 54 + 5 * sin(Double(second) / 5)))
                        }
                    }
                    panel.contentView?.layoutSubtreeIfNeeded()
                    let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds)!
                    container.cacheDisplay(in: container.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/phud-memory-\(appearance.rawValue)-\(mode.rawValue).png"))
                }
            }
        }
        hud.shutdown()
        for issue in issues.sorted().prefix(30) { print(issue) }
        print("RESULT: \(issues.count) issues across \(configurations) memory configurations, pressure states and digit widths")
        if !issues.isEmpty { exit(1) }
    }
}
