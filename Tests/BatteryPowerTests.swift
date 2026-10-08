import AppKit

@main struct BatteryPowerTests {
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }

    @MainActor static func main() throws {
        _ = NSApplication.shared
        let scales = CommandLine.arguments.contains("--normal-size") ? [1.0] : [0.5, 1.0, 2.0]
        var failures = Set<String>()
        func check(_ value: Bool, _ reason: String) {
            if !value { failures.insert(reason) }
        }
        let voltage = NSNumber(value: 12_000)
        for current in [NSNumber(value: -2_000), NSNumber(value: UInt32(bitPattern: -2_000)),
                        NSNumber(value: UInt64(bitPattern: -2_000))] {
            check(BatteryPowerRate.watts(voltage: voltage, amperage: current) == -24, "Signed/unsigned discharge current")
        }
        check(BatteryPowerRate.watts(voltage: voltage, amperage: 2_000) == 24, "Charging is positive")
        check(BatteryPowerRate.watts(voltage: voltage, amperage: 0) == 0, "Real zero stays zero")
        func voltageReading(_ value: UInt16) -> (UInt32, [UInt8]) {
            (SMCTemperatureReader.fourCC("ui16"), [UInt8(truncatingIfNeeded: value), UInt8(value >> 8)])
        }
        func currentReading(_ value: Int16) -> (UInt32, [UInt8]) {
            let bits = UInt16(bitPattern: value)
            return (SMCTemperatureReader.fourCC("si16"), [UInt8(truncatingIfNeeded: bits), UInt8(bits >> 8)])
        }
        check(BatteryPowerRate.watts(smcVoltage: voltageReading(12_000), smcAmperage: currentReading(-2_000)) == -24, "SMC discharge is negative")
        check(BatteryPowerRate.watts(smcVoltage: voltageReading(12_000), smcAmperage: currentReading(2_000)) == 24, "SMC charging is positive")
        check(BatteryPowerRate.watts(smcVoltage: voltageReading(12_000), smcAmperage: currentReading(0)) == 0, "SMC zero is valid")
        check(BatteryPowerRate.watts(smcVoltage: voltageReading(0), smcAmperage: currentReading(2_000)) == nil, "Reject invalid voltage")
        check(BatteryPowerRate.watts(smcVoltage: voltageReading(60_000), smcAmperage: currentReading(32_000)) == nil, "Reject implausible watts")
        check(BatteryPowerRate.watts(smcVoltage: (SMCTemperatureReader.fourCC("ui16"), [0]), smcAmperage: currentReading(2_000)) == nil, "Reject truncated sensor bytes")
        check(BatteryPowerRate.watts(smcVoltage: voltageReading(12_000), smcAmperage: (0, [0, 0])) == nil, "Reject unsupported sensor format")
        check(BatteryPowerRate.watts(controller: ["Voltage": voltage, "InstantAmperage": -1_000, "Amperage": -2_000]) == -12,
              "Controller fallback prefers instantaneous current")
        check(BatteryPowerRate.watts(controller: ["Voltage": voltage, "InstantAmperage": true, "Amperage": -2_000]) == -24,
              "Invalid instantaneous current falls back to averaged current")
        check(BatteryPowerRate.watts(controller: ["Voltage": voltage, "InstantAmperage": 0, "Amperage": -2_000]) == 0,
              "Zero instantaneous current is not replaced with a stale average")
        for current: NSNumber? in [nil, NSNumber(value: Double.nan), NSNumber(value: Double.infinity),
                                   NSNumber(value: true), NSNumber(value: 1.5), NSNumber(value: 1_000_000)] {
            check(BatteryPowerRate.watts(voltage: voltage, amperage: current) == nil, "Invalid current stays unavailable")
        }
        for voltage: NSNumber? in [nil, 0, -12_000, NSNumber(value: Double.nan), 9_999_999] {
            check(BatteryPowerRate.watts(voltage: voltage, amperage: 1_000) == nil, "Invalid voltage stays unavailable")
        }
        check(BatteryPowerRate.text(24.34) == "24.3 W", "Positive HUD readings omit the plus sign")
        check(BatteryPowerRate.text(-24.34) == "-24.3 W", "Negative HUD sign")
        check(BatteryPowerRate.text(-0.01) == "0.0 W", "No signed zero")
        check(BatteryPowerRate.text(nil).isEmpty, "Missing power stays blank")
        check(BatterySample(percentage: 80, source: .powerAdapter, power: -.infinity).power == nil, "Reject invalid sample")

        for direction in [-1.0, 1.0] {
            var visibility = BatteryFlowVisibility()
            visibility.update(power: 0, now: 0)
            visibility.update(power: direction * 0.15, now: 1)
            check(!visibility.isVisible, "Idle noise does not reveal Auto")
            visibility.update(power: direction * 0.2, now: 2)
            check(visibility.isVisible, "Auto reveals either flow direction immediately")
            visibility.update(power: 0, now: 3)
            visibility.update(power: direction * 0.1, now: 5.99)
            check(visibility.isVisible, "Auto waits three seconds near zero")
            visibility.update(power: 0, now: 6)
            check(!visibility.isVisible, "Auto hides after sustained idle")
            visibility.update(power: direction * 12, now: 7)
            visibility.update(power: direction * -12, now: 8)
            check(visibility.isVisible, "Changing direction does not hide flow")
            visibility.update(power: 0, now: 9)
            visibility.update(power: direction * 0.15, now: 11)
            visibility.update(power: 0, now: 12)
            visibility.update(power: 0, now: 14)
            check(visibility.isVisible, "Recovery cancels the previous idle deadline")
            visibility.update(power: nil, now: 15)
            check(!visibility.isVisible, "Unavailable flow clears Auto state")
            visibility.update(power: .infinity, now: 16)
            check(!visibility.isVisible, "Invalid flow stays hidden")
        }

        let suite = "PerformanceHUD.BatteryPowerTests." + UUID().uuidString
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        var preferences = HUDPreferences.batteryOptions(in: store)
        check(preferences.flowMode == .auto && !preferences.powerHighlighted, "Flow defaults to Auto with regular Reading style")
        store.set(false, forKey: "hud.battery.power")
        check(HUDPreferences.batteryOptions(in: store).flowMode == .off, "Migrate a previously disabled power control")
        store.set("invalid", forKey: "hud.battery.flowMode")
        check(HUDPreferences.batteryOptions(in: store).flowMode == .off, "Invalid mode falls back to saved visibility")
        preferences.power = false; preferences.powerHighlighted = true
        HUDPreferences.setBatteryOptions(preferences, in: store)
        check(HUDPreferences.batteryOptions(in: store) == preferences, "Remember visibility and emphasis independently")
        preferences.flowMode = .auto
        HUDPreferences.setBatteryOptions(preferences, in: store)
        check(HUDPreferences.batteryOptions(in: store) == preferences && preferences.power, "Auto persists and keeps sampling enabled")
        HUDPreferences.resetOptions(in: store)
        check(HUDPreferences.batteryOptions(in: store).flowMode == .auto && !HUDPreferences.batteryOptions(in: store).powerHighlighted,
              "Reset restores both defaults")

        let battery = HUDResourceMenuView(batteryOptions: .init(enabled: true, temperature: true, charge: true))
        let gpu = HUDResourceMenuView(group: .gpu, options: .init(enabled: true, temperature: true, totalUse: true, focusedApp: false))
        battery.layoutSubtreeIfNeeded(); gpu.layoutSubtreeIfNeeded()
        let controls: [Int: NSButton] = member(battery, "controls")
        let gpuControls: [Int: NSButton] = member(gpu, "controls")
        let selector: NSSegmentedControl = member(battery, "flowControl") as NSSegmentedControl?
            ?? { fatalError("Missing charge selector") }()
        let highlight: NSButton = member(battery, "flowHighlight")
        let temperatureRect = controls[1]!.frame
        let energyRect = controls[6]!.frame
        check(temperatureRect.minX == gpuControls[1]!.frame.minX && energyRect.minX == temperatureRect.minX,
              "Battery checkboxes share the reading column")
        check(temperatureRect.maxY < energyRect.minY, "Temperature and Energy have separate rows")
        check(battery.frame.width == gpu.frame.width, "Category widths stay consistent")
        check(selector.frame.width >= selector.intrinsicContentSize.width - 1, "Charge segments fit without clipped labels")
        check(highlight.frame.minX > selector.frame.maxX && abs(highlight.frame.midY - selector.frame.midY) < 2,
              "Charge emphasis is independently clickable beside the selector")
        check(battery.bounds.contains(highlight.frame), "Charge emphasis stays inside the category")
        check((0..<3).map { selector.label(forSegment: $0) } == ["Always", "Auto", "Off"], "Flow uses three inline choices")
        check(selector.selectedSegment == 1 && (0..<3).allSatisfy { selector.isEnabled(forSegment: $0) },
              "Auto is selected and all flow choices are actionable")
        func selectFlow(_ mode: HUDBatteryFlowMode) {
            selector.selectedSegment = HUDBatteryFlowMode.allCases.firstIndex(of: mode)!
            selector.sendAction(selector.action, to: selector.target)
        }
        var changed = HUDBatteryOptions(enabled: true, temperature: true, charge: true)
        battery.onBatteryChange = { changed = $0 }
        highlight.performClick(nil)
        check(changed.powerHighlighted && !changed.temperatureHighlighted, "Flow emphasis is independent")
        selectFlow(.off)
        check(!changed.power && changed.powerHighlighted && changed.charge && !highlight.isEnabled, "Off preserves emphasis and Energy")
        selectFlow(.auto)
        check(changed.flowMode == .auto && changed.powerHighlighted && highlight.isEnabled, "Auto restores emphasis")
        controls[6]!.performClick(nil)
        check(!changed.charge && changed.flowMode == .auto && changed.temperature, "Energy changes preserve Auto")
        controls[1]!.performClick(nil)
        check(!changed.temperature && changed.flowMode == .auto, "Temperature changes preserve Auto")
        controls[0]!.performClick(nil)
        check(!selector.isEnabled && !highlight.isEnabled && changed.flowMode == .auto, "Category disabled retains flow mode")
        controls[0]!.performClick(nil)
        check(selector.isEnabled && changed.flowMode == .auto, "Category restores selected flow mode")
        selectFlow(.always)

        UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "off", "hud.alignment": "vertical"],
                                                forName: UserDefaults.argumentDomain)
        let hud = HUDWindowController()
        hud.setHUDEnabled(false)
        hud.setAutoHideMode(.off)
        hud.setPackagePowerOptions(.init(enabled: false))
        for metric in HUDMetric.allCases where metric != .battery { hud.setMetricEnabled(metric, enabled: false) }
        defer { hud.shutdown() }
        let panel: HUDPanel = member(hud, "panel")
        let verticalBattery: HUDBatteryIndicatorView = member(hud, "batteryIndicator")
        let view = HUDBatteryIndicatorView(frame: .zero)
        for horizontal in [false, true] {
            view.setHorizontal(horizontal)
            view.setOptions(.init(enabled: true, temperature: true, charge: true, flowMode: .auto))
            view.frame = NSRect(x: 0, y: 0, width: 232, height: horizontal ? 21 : 39)
            view.update(percentage: 80, source: .powerAdapter, temperature: 33, power: 12, now: 100)
            let reservedWidth = view.minimumRowWidth
            let temperatureRect = view.temperatureTextRect
            check(view.powerText == "12.0 W", "Auto displays real charging watts")
            view.update(percentage: 80, source: .powerAdapter, temperature: 33, power: 0, now: 101)
            check(!view.powerText.isEmpty, "Auto preserves the reading during the idle delay")
            view.update(percentage: 80, source: .powerAdapter, temperature: 33, power: 0, now: 104)
            check(view.powerText.isEmpty, "Auto hides idle text in both layouts")
            if horizontal {
                let reclaimed = reservedWidth - view.minimumRowWidth
                check(reclaimed > 0, "Horizontal Auto reclaims the hidden Charge slot")
                check(view.temperatureTextRect == temperatureRect,
                      "Horizontal temperature stays beside the icon when Charge hides")
            } else {
                check(view.minimumRowWidth == reservedWidth && view.temperatureTextRect == temperatureRect,
                      "Vertical Auto keeps its fixed columns")
            }
            check(!(view.accessibilityValue() as? String ?? "").contains("Battery charge rate:"), "Accessibility follows hidden Auto text")
            view.update(percentage: 80, source: .battery, temperature: 33, power: -8, now: 105)
            check(view.powerText == "-8.0 W", "Auto immediately resumes for discharge")
            if !horizontal { check(view.minimumRowWidth == reservedWidth, "Vertical Charge keeps its fixed width") }
            view.setOptions(.init(enabled: true, temperature: true, charge: true, flowMode: .off))
            view.update(percentage: 80, source: .battery, temperature: 33, power: -8, now: 106)
            check(view.powerText.isEmpty, "Off hides even active flow")
            view.setOptions(.init(enabled: true, temperature: true, charge: true, flowMode: .always))
            view.update(percentage: 80, source: .powerAdapter, temperature: 33, power: 0, now: 107)
            check(view.powerText == "0.0 W", "Always includes idle zeros")
        }

        // Exercise actual window resizing with only Battery enabled. No CPU/FPS
        // sample should be needed to apply an Auto transition to the HUD frame.
        for factor in scales {
            hud.setHUDScale(.init(rawValue: factor))
            hud.setAlignment(.horizontal)
            // Alignment reloads saved selections. Reapply this test's isolated
            // battery-only fixture, rather than leaving default FPS/CPU rows on.
            for metric in HUDMetric.allCases where metric != .battery { hud.setMetricEnabled(metric, enabled: false) }
            for temperature in [false, true] {
                for energy in [false, true] {
                    let auto = HUDBatteryOptions(enabled: true, temperature: temperature, charge: energy, flowMode: .auto)
                    hud.setBatteryOptions(auto)
                    hud.updateBattery(.init(percentage: 80, source: .powerAdapter, temperature: 33, power: nil), now: 200)
                    let compactWidth = panel.frame.width
                    hud.updateBattery(.init(percentage: 80, source: .powerAdapter, temperature: 33, power: 12), now: 201)
                    let expandedWidth = panel.frame.width
                    check(expandedWidth > compactWidth, "Horizontal window expands when Auto Charge appears at \(factor)×")
                    hud.updateBattery(.init(percentage: 80, source: .battery, temperature: 33, power: -24.3), now: 202)
                    check(panel.frame.width == expandedWidth, "Readings that fit the shared column keep the same width")
                    hud.updateBattery(.init(percentage: 80, source: .powerAdapter, temperature: 33, power: 0), now: 203)
                    check(panel.frame.width > compactWidth, "Horizontal window retains Charge through Auto's delay")
                    hud.updateBattery(.init(percentage: 80, source: .powerAdapter, temperature: 33, power: 0), now: 206)
                    check(panel.frame.width == compactWidth, "Horizontal window shrinks as soon as Auto Charge hides")
                    hud.setBatteryOptions(.init(enabled: true, temperature: temperature, charge: energy, flowMode: .off))
                    check(panel.frame.width == compactWidth, "Hidden Auto is as compact as Off with every remaining reading combination")
                    hud.setBatteryOptions(auto)
                    hud.updateBattery(.init(percentage: 80, source: .battery, temperature: 33, power: -8), now: 207)
                    check(panel.frame.width > compactWidth, "Returning Auto Charge restores its horizontal space")
                }
            }
            hud.setAlignment(.vertical)
            for metric in HUDMetric.allCases where metric != .battery { hud.setMetricEnabled(metric, enabled: false) }
            let fixedWidth = panel.frame.width
            hud.updateBattery(.init(percentage: 80, source: .powerAdapter, temperature: 33, power: 0), now: 208)
            hud.updateBattery(.init(percentage: 80, source: .powerAdapter, temperature: 33, power: 0), now: 211)
            check(panel.frame.width == fixedWidth, "Auto transitions preserve vertical HUD width at \(factor)×")
        }
        for horizontal in [false, true] {
            view.setHorizontal(horizontal)
            for factor in scales {
                let scale = HUDScale(rawValue: factor)
                view.applyStyle(scale: scale, background: .dark)
                for mask in 0..<8 {
                    for emphasized in [false, true] {
                        let options = HUDBatteryOptions(enabled: true, temperature: mask & 2 != 0,
                            charge: mask & 4 != 0, temperatureHighlighted: emphasized,
                            power: mask & 1 != 0, powerHighlighted: emphasized)
                        view.setOptions(options)
                        let referenceWidth = view.minimumRowWidth
                        var width: CGFloat
                        if horizontal {
                            width = referenceWidth
                        } else {
                            // Exercise actual HUD sizing, including the controller's
                            // spacing expansion, rather than using its sizing input
                            // as though that were the displayed battery-row width.
                            hud.setHUDScale(scale)
                            var powerOff = options
                            powerOff.power = false
                            hud.setBatteryOptions(powerOff)
                            panel.contentView?.layoutSubtreeIfNeeded()
                            let withoutWatts = panel.frame.width
                            hud.setBatteryOptions(options)
                            panel.contentView?.layoutSubtreeIfNeeded()
                            check(panel.frame.width == withoutWatts,
                                  "Aligned battery width: scale=\(factor), mask=\(mask), emphasized=\(emphasized), before=\(withoutWatts), after=\(panel.frame.width)")
                            width = verticalBattery.bounds.width
                        }
                        view.frame = NSRect(x: 0, y: 0, width: width,
                            height: horizontal ? 21 * factor : HUDStyle.rowHeight(for: .battery, scale: scale))
                        for reading: Double? in [-1000, -24.3, 0, 24.3, 1000, nil] {
                            view.update(percentage: 80, source: .powerAdapter, temperature: 99.9, power: reading)
                            if horizontal {
                                width = view.minimumRowWidth
                                view.setFrameSize(NSSize(width: width, height: view.frame.height))
                            } else {
                                check(abs(view.minimumRowWidth - referenceWidth) < 0.01, "Changing numbers never resize the vertical row")
                            }
                            if options.power && reading != nil {
                                let rect = view.powerTextRect
                                check(view.bounds.insetBy(dx: -0.1, dy: -0.1).contains(rect), "Power fits its row at every scale")
                                let label = horizontal ? "ADP" : "Adapter"
                                let font = HUDStyle.TextStyle.label.font(ofSize: 14 * factor)
                                let labelRight = 2 * factor + (label as NSString).size(withAttributes: [.font: font]).width
                                check(rect.minX >= labelRight + 7.9 * factor, "Power does not collide with its label: horizontal=\(horizontal), scale=\(factor), mask=\(mask), watts=\(String(describing: reading)), width=\(width), labelRight=\(labelRight), powerLeft=\(rect.minX)")
                            } else { check(view.powerText.isEmpty, "Hidden/unavailable power does not draw") }
                            if options.temperature {
                                let temperatureRect = view.temperatureTextRect
                                check(view.bounds.insetBy(dx: -0.1, dy: -0.1).contains(temperatureRect), "Temperature fits its row")
                                if options.power, reading != nil {
                                    check(view.powerTextRect.maxX + 7.9 * factor <= temperatureRect.minX,
                                          "Charge precedes Temperature in both layouts")
                                    check(abs(temperatureRect.minY - view.powerTextRect.minY) < 0.01,
                                          "Battery readings share one baseline")
                                }
                            } else { check(view.temperatureText.isEmpty, "Disabled temperature does not draw") }
                            if !horizontal {
                                if options.power, !options.temperature, !options.charge, reading != nil {
                                    check(abs(view.powerTextRect.maxX - (width - 2 * factor)) < 0.01,
                                          "Flow alone reaches the rightmost column")
                                }
                                if options.temperature, !options.charge {
                                    check(abs(view.temperatureTextRect.maxX - (width - 2 * factor)) < 0.01,
                                          "Temperature reaches the rightmost column when Energy is off")
                                }
                            }
                        }
                    }
                }
            }
        }
        // Compare Battery against the actual GPU/CPU horizontal layout, not
        // against a second set of battery-specific spacing constants.
        for emphasized in [false, true] {
            let comparison = HUDHorizontalView(frame: .zero)
            let readingFont = HUDStyle.readingFont(scale: .normal, highlighted: emphasized)
            let usageFont = HUDStyle.readingFont(scale: .normal, highlighted: false)
            let titleFont = HUDStyle.TextStyle.label.font(ofSize: 14)
            for watts in [0.0, -24.3, 100.0] {
                let power = BatteryPowerRate.text(watts)
                let fields = [("title", "ADP", "ADP", titleFont),
                    ("power", power, HUDStyle.horizontalPowerReference, readingFont),
                    ("temperature", "36°C", HUDStyle.horizontalTemperatureReference, readingFont),
                    ("use", "80%", HUDStyle.horizontalPercentageReference, usageFont)]
                let readings: [HUDHorizontalView.Reading] = fields.map { role, text, reference, font in
                    .init(id: role, text: text, reference: reference, font: font, color: .white,
                          help: nil, startsMetric: role == "title", resourceGroup: .gpu)
                }
                let size = comparison.configure(sections: [readings], showsBattery: false, scale: .normal, background: .dark)
                let labels: [String: NSTextField] = member(comparison, "labels")
                view.setHorizontal(true)
                view.applyStyle(scale: .normal, background: .dark)
                view.setOptions(.init(enabled: true, temperature: true, charge: true,
                    temperatureHighlighted: emphasized, power: true, powerHighlighted: emphasized))
                view.update(percentage: 80, source: .powerAdapter, temperature: 36, power: watts)
                view.frame = NSRect(x: 0, y: 0, width: view.minimumRowWidth, height: 21)
                check(abs(view.minimumRowWidth - size.width - 2) < 0.01, "Battery uses the GPU/CPU total column width")
                for (key, rect) in [("power", view.powerTextRect), ("temperature", view.temperatureTextRect)] {
                    let label = labels[key]!
                    let edge = label.alignmentRect(forFrame: label.frame).maxX
                    check(abs(rect.maxX - edge - 2) < 0.01, "Battery \(key) has the same column position as GPU/CPU")
                }
            }
        }
        for factor in scales {
            hud.setHUDScale(.init(rawValue: factor))
            let fixedWidth = panel.frame.width
            for group in HUDResourceGroup.allCases {
                for mask in 0..<16 {
                    hud.setResourceOptions(.init(enabled: mask != 0,
                        temperature: group.supportsTemperature && mask & 2 != 0,
                        totalUse: group.supportsTotalUse && mask & 4 != 0,
                        focusedApp: false, power: group.supportsPower && mask & 1 != 0,
                        details: mask & 8 != 0, highlighted: mask & 8 != 0 ? Set(HUDReadingKind.allCases) : []), for: group)
                    check(panel.frame.width == fixedWidth, "\(group) options must not resize the vertical HUD")
                }
            }
            for metric in HUDMetric.allCases where metric != .fps {
                hud.setMetricEnabled(metric, enabled: true)
                check(panel.frame.width == fixedWidth, "Enabling \(metric) must not resize the vertical HUD")
                hud.setMetricEnabled(metric, enabled: false)
                check(panel.frame.width == fixedWidth, "Disabling \(metric) must not resize the vertical HUD")
            }
            hud.setMetricEnabled(.fps, enabled: true)
            check(panel.frame.width < fixedWidth, "FPS Value alone retains its compact width")
            hud.setMetricEnabled(.fpsGraph, enabled: true)
            check(panel.frame.width == fixedWidth, "FPS history restores the regular width")
            hud.setMetricEnabled(.fps, enabled: false)
            hud.setMetricEnabled(.fpsGraph, enabled: false)
            for group in [HUDResourceGroup.gpu, .cpu] {
                hud.setResourceOptions(.init(enabled: true, temperature: true, totalUse: true,
                    focusedApp: false, power: true), for: group)
            }
            hud.setBatteryOptions(.init(enabled: true, temperature: true, charge: true))
            hud.updatePower(.init(cpu: 12.3, gpu: 24.5, package: 36.8, ane: 0))
            hud.updateTemperatures(.init(cpu: 65, gpu: 60))
            hud.updateBattery(.init(percentage: 80, source: .powerAdapter, temperature: 33, power: -24.3))
            panel.contentView?.layoutSubtreeIfNeeded()
            let powerLabels: [HUDMetric: NSTextField] = member(hud, "powerLabels")
            let temperatureLabels: [HUDMetric: NSTextField] = member(hud, "temperatureLabels")
            for metric in [HUDMetric.cpuTotal, .gpuTotal] {
                for (label, rect) in [(powerLabels[metric]!, verticalBattery.powerTextRect),
                                      (temperatureLabels[metric]!, verticalBattery.temperatureTextRect)] {
                    let expected = label.convert(label.bounds, to: verticalBattery).maxX - label.alignmentRectInsets.right
                    check(abs(expected - rect.maxX) <= 1 / panel.backingScaleFactor,
                          "Battery reading aligns with \(metric) at \(factor)×: \(rect.maxX) / \(expected)")
                }
            }
            let sharedMiddle = verticalBattery.temperatureTextRect.maxX
            let allReadingsFlowRight = verticalBattery.powerTextRect.maxX
            hud.setBatteryOptions(.init(enabled: true, temperature: false, charge: true))
            hud.updateBattery(.init(percentage: 80, source: .powerAdapter, temperature: 33, power: -24.3))
            check(abs(verticalBattery.powerTextRect.maxX - sharedMiddle) < 0.01,
                  "Disabling Temperature moves Flow into its previous shared column")
            check(verticalBattery.powerTextRect.maxX > allReadingsFlowRight, "Flow moves right when Temperature is off")
            hud.setBatteryOptions(.init(enabled: true, temperature: false, charge: false))
            hud.updateBattery(.init(percentage: 80, source: .powerAdapter, power: -24.3))
            check(abs(verticalBattery.powerTextRect.maxX - (verticalBattery.bounds.maxX - 2 * factor)) < 0.01,
                  "Disabling Temperature and Energy moves Flow two positions right")
            check(panel.frame.width == fixedWidth, "Repacking battery readings preserves fixed HUD width")
        }
        let monitor = BatteryMonitor()
        var deliveredAt: [TimeInterval] = []
        var sample: BatterySample?
        monitor.onBatteryUpdate = { sample = $0; deliveredAt.append(ProcessInfo.processInfo.systemUptime) }
        monitor.start(temperature: false, power: true)
        let deadline = Date().addingTimeInterval(4)
        while deliveredAt.count < 3 && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        monitor.stop()
        check(deliveredAt.count >= 3, "Battery monitor delivers three readings within four seconds")
        if deliveredAt.count >= 3 {
            let averageInterval = (deliveredAt[2] - deliveredAt[0]) / 2
            check((0.7...1.5).contains(averageInterval), "Battery sampling averages one second")
            print("LIVE: battery sampling interval=\(averageInterval) seconds")
        }
        print("LIVE: net battery power=\(BatteryPowerRate.text(sample?.power)), source=\(sample?.source?.rawValue ?? "unavailable")")
        for failure in failures.sorted() { print("FAIL: \(failure)") }
        if !failures.isEmpty { exit(1) }
        print("PASS: signed readings, Flow modes/idle transitions, persistence/migration/reset, independent emphasis, menu columns, fixed width and right-packed battery combinations at \(scales)× in both layouts")

        if CommandLine.arguments.contains("--preview") {
            let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 140))
            canvas.wantsLayer = true
            canvas.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
            let reference = HUDHorizontalView(frame: .zero)
            let readings: [HUDHorizontalView.Reading] = [
                ("title", "GPU", "GPU"), ("power", "0.0 W", HUDStyle.horizontalPowerReference),
                ("temperature", "36°C", HUDStyle.horizontalTemperatureReference),
                ("use", "80%", HUDStyle.horizontalPercentageReference)
            ].map { role, text, sizing in
                .init(id: role, text: text, reference: sizing,
                    font: role == "title" ? HUDStyle.TextStyle.label.font(ofSize: 14)
                        : HUDStyle.readingFont(scale: .normal, highlighted: false),
                    color: .white, help: nil, startsMetric: role == "title", resourceGroup: .gpu)
            }
            let size = reference.configure(sections: [readings], showsBattery: false, scale: .normal, background: .dark)
            reference.isHidden = false
            reference.frame = NSRect(origin: NSPoint(x: 22, y: 105), size: size)
            canvas.addSubview(reference)
            for (index, watts) in [0.0, -24.3].enumerated() {
                let preview = HUDBatteryIndicatorView(frame: .zero)
                preview.setHorizontal(true)
                preview.setOptions(.init(enabled: true, temperature: true, charge: true, power: true))
                preview.applyStyle(scale: .normal, background: .dark)
                preview.update(percentage: 80, source: .powerAdapter, temperature: 36, power: watts)
                preview.frame = NSRect(x: 20, y: CGFloat(75 - index * 30), width: ceil(preview.minimumRowWidth), height: 21)
                canvas.addSubview(preview)
            }
            for (index, level) in ["normal", "warning", "critical"].enumerated() {
                let meter = HUDMemoryPressureMeterView()
                meter.translatesAutoresizingMaskIntoConstraints = true
                meter.configure(mode: .colorMeter, scale: .normal, background: .dark)
                meter.update(level)
                meter.frame = NSRect(origin: NSPoint(x: CGFloat(20 + index * 100), y: 15), size: meter.intrinsicContentSize)
                canvas.addSubview(meter)
            }
            let window = NSWindow(contentRect: canvas.frame, styleMask: [], backing: .buffered, defer: false)
            window.contentView = canvas
            canvas.layoutSubtreeIfNeeded()
            let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/phud-battery-power-preview.png"))
        }
    }
}
