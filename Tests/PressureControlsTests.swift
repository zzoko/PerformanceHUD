import AppKit

@main struct PressureControlsTests {
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }

    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "PerformanceHUD.PressureControls.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        let fresh = HUDPreferences.resourceOptions(for: .ram, in: store)
        precondition(fresh.pressure && fresh.pressureMode == .colorMeter, "Fresh settings enable Pressure with Color meter")
        store.set(false, forKey: "hud.group.ram.details")
        var saved = HUDPreferences.resourceOptions(for: .ram, in: store)
        precondition(!saved.pressure, "Existing hidden Details migrates to hidden Pressure")
        saved.pressure = true
        saved.highlighted = [.pressure]
        HUDPreferences.setResourceOptions(saved, for: .ram, in: store)
        precondition(HUDPreferences.resourceOptions(for: .ram, in: store).pressure, "Pressure persists separately")
        precondition(!HUDPreferences.resourceOptions(for: .ram, in: store).details, "Pressure does not enable Details")
        precondition(HUDPreferences.resourceOptions(for: .ram, in: store).highlighted == [.pressure],
                     "Pressure emphasis saves independently of Details")
        HUDPreferences.resetOptions(in: store)
        saved = HUDPreferences.resourceOptions(for: .ram, in: store)
        precondition(saved.details && saved.pressure, "Reset restores both defaults")
        precondition(saved.pressureMode == .colorMeter, "Reset restores Color meter")
        precondition(!saved.highlighted.contains(.pressure), "Pressure emphasis defaults off")

        var options = HUDResourceOptions(enabled: true, temperature: false, totalUse: true, focusedApp: false)
        let menu = HUDResourceMenuView(group: .ram, options: options)
        menu.onChange = { options = $0 }
        menu.layoutSubtreeIfNeeded()
        let controls: [Int: NSButton] = member(menu, "controls")
        let modes: NSSegmentedControl = member(menu, "pressureModeControl") as NSSegmentedControl?
            ?? { fatalError("Missing pressure modes") }()
        precondition(controls[8]!.frame.minY < controls[5]!.frame.minY, "Pressure precedes Details")
        precondition(abs(modes.frame.midY - controls[8]!.frame.midY) < 1, "Modes belong to Pressure")
        let bold = (controls[8] as! HUDReadingCheckbox).emphasisControl!
        precondition(modes.selectedSegment == 2 && !bold.isEnabled, "Pressure starts in Color meter with emphasis disabled")
        modes.selectedSegment = 0
        modes.sendAction(modes.action, to: modes.target)
        precondition(bold.isEnabled, "Text enables pressure emphasis")
        bold.performClick(nil)
        precondition(options.highlighted == [.pressure], "Pressure bold does not bold Details")
        for index in [1, 2] {
            modes.selectedSegment = index
            modes.sendAction(modes.action, to: modes.target)
            precondition(!bold.isEnabled && bold.state == .on, "Meters disable and remember text emphasis")
            bold.performClick(nil)
            precondition(options.highlighted == [.pressure], "Disabled emphasis cannot change the saved choice")
        }
        modes.selectedSegment = 0
        modes.sendAction(modes.action, to: modes.target)
        precondition(bold.isEnabled && bold.state == .on, "Returning to Text restores emphasis")
        controls[5]!.performClick(nil)
        precondition(!options.details && options.pressure && modes.isEnabled, "Details cannot hide Pressure")
        controls[8]!.performClick(nil)
        precondition(!options.pressure && !modes.isEnabled, "Pressure controls its selector")
        precondition(!bold.isEnabled, "Pressure off disables emphasis")
        controls[5]!.performClick(nil)
        precondition(options.details && !options.pressure, "Details cannot enable Pressure")

        UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "off",
            "hud.scale": 1.0, "hud.background": "dark", "hud.alignment": "vertical"], forName: UserDefaults.argumentDomain)
        let hud = HUDWindowController()
        hud.setHUDEnabled(false)
        hud.setHUDScale(.normal)
        let panel: HUDPanel = member(hud, "panel")
        let rows: [HUDMetric: NSView] = member(hud, "metricRows")
        let physical: [HUDMetric: NSTextField] = member(hud, "ramDetailLabels")
        let swap: NSTextField = member(hud, "ramSwapValueLabel")
        let pressure: NSTextField = member(hud, "ramPressureValueLabel")
        let title: NSTextField = member(hud, "ramPressureTitleLabel")
        let meter: HUDMemoryPressureMeterView = member(hud, "ramPressureMeter")
        let horizontal: HUDHorizontalView = member(hud, "horizontalView")
        for alignment in HUDAlignment.allCases {
            hud.setAlignment(alignment)
            for pressureBold in [false, true] {
                for detailsBold in [false, true] {
                    var emphasis = Set<HUDReadingKind>()
                    if pressureBold { emphasis.insert(.pressure) }
                    if detailsBold { emphasis.insert(.details) }
                    let option = HUDResourceOptions(enabled: true, temperature: false, totalUse: true,
                        focusedApp: false, highlighted: emphasis, pressureMode: .text)
                    hud.setResourceOptions(option, for: .ram)
                    hud.updateMemoryPressure("warning")
                    let expectedPressure = HUDStyle.readingFont(scale: .normal, highlighted: pressureBold)
                    let expectedDetails = HUDStyle.readingFont(scale: .normal, highlighted: detailsBold)
                    precondition(pressure.font == expectedPressure, "Pressure uses its own text emphasis")
                    precondition(physical[.ramTotal]!.font == expectedDetails && swap.font == expectedDetails,
                                 "Pressure emphasis leaves Physical and Swap independent")
                    if alignment == .horizontal {
                        let labels: [String: NSTextField] = member(horizontal, "labels")
                        precondition(labels["ram.pressure"]?.font == expectedPressure,
                                     "Horizontal pressure uses the saved text emphasis")
                    }
                }
            }
        }
        var combinations = 0
        for alignment in HUDAlignment.allCases {
            hud.setAlignment(alignment)
            hud.setPackagePowerOptions(.init(enabled: false))
            for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: false) }
            for source in HUDUsageMode.allCases {
                for details in [false, true] {
                    for enabled in [false, true] {
                        for use in [false, true] {
                            for mode in HUDMemoryPressureMode.allCases {
                                let option = HUDResourceOptions(enabled: true, temperature: false,
                                    totalUse: use && source != .app, focusedApp: use && source != .total,
                                    details: details, pressure: enabled, highlighted: [.details],
                                    usageMode: source, pressureMode: mode)
                                hud.setResourceOptions(option, for: .ram)
                                hud.updateRAM(.ramTotal, usage: .init(percentage: 51, usedBytes: 2_147_483_648, swapUsedBytes: 0))
                                hud.updateRAM(.ram, usage: .init(percentage: 20, usedBytes: 1_073_741_824))
                                hud.updateMemoryPressure("warning")
                                panel.contentView?.layoutSubtreeIfNeeded()
                                combinations += 1
                                let showsPressure = option.showsPressure
                                precondition(title.isHidden == !showsPressure, "Pressure caption follows its checkbox")
                                precondition(pressure.isHidden == (!showsPressure || mode != .text), "Pressure text is independent")
                                precondition(pressure.font == HUDStyle.readingFont(scale: .normal, highlighted: false), "Details cannot bold Pressure")
                                precondition(physical[.ramTotal]!.isHidden == !details && swap.isHidden == !details, "Details controls Physical and Swap")
                                let visible = option.visibleMetrics(for: .ram)
                                for metric in [HUDMetric.ram, .ramTotal] {
                                    precondition(rows[metric]!.isHidden == !visible.contains(metric), "Only requested memory sources appear")
                                }
                                if alignment == .vertical {
                                    precondition(meter.isHidden == (!showsPressure || mode == .text), "Pressure meter is independent")
                                    if visible.contains(.ramTotal) {
                                        let expected = 21 + (details ? 36 : 0) + (showsPressure ? 18 : 0)
                                        precondition(abs(rows[.ramTotal]!.frame.height - CGFloat(expected)) < 0.5, "Hidden rows reclaim their height")
                                        if showsPressure {
                                            let rect = pressure.convert(pressure.bounds, to: rows[.ramTotal]!)
                                            precondition(rows[.ramTotal]!.bounds.insetBy(dx: -2, dy: -2).contains(rect), "Pressure fits its row with Details on or off")
                                        }
                                    }
                                } else {
                                    let labels: [String: NSTextField] = member(horizontal, "labels")
                                    let meters: [String: HUDMemoryPressureMeterView] = member(horizontal, "pressureMeters")
                                    precondition((labels["ram.pressure"]?.isHidden == false) == (showsPressure && mode == .text), "Horizontal pressure text follows its checkbox")
                                    precondition((meters["ram.pressure"]?.isHidden == false) == (showsPressure && mode != .text), "Horizontal meter follows its checkbox")
                                }
                                let selection = HUDLogSelection(fps: false, resources: [.ram: option],
                                    package: .init(enabled: false), fans: .init(enabled: false),
                                    battery: .init(enabled: false, temperature: false, charge: false),
                                    deviceInfo: false, alignment: alignment)
                                let columns = selection.columns(fanSample: .noFans)
                                precondition(columns.contains(.memoryPressure) == showsPressure, "CSV pressure follows Pressure")
                                precondition(columns.contains(.memoryPhysical) == (details && source != .app), "CSV physical memory follows Details")
                                precondition(columns.contains(.memorySwap) == (details && source != .app), "CSV swap follows Details")
                                if showsPressure { precondition(columns.first == .memoryPressure, "CSV follows menu order") }
                            }
                        }
                    }
                }
            }
        }
        hud.shutdown()
        print("PASS: Pressure controls, preferences, text emphasis, CSV and \(combinations) normal-size layout combinations")
    }
}
