import AppKit

@main struct HeatWarningTests {
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }

    @MainActor static func main() {
        _ = NSApplication.shared
        var failures = Set<String>()
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures.insert(message) }
        }

        let warning = HUDHeatWarningOptions(thresholdCelsius: 90)
        for (reading, expected) in [(89.0, false), (89.49, false), (89.5, true),
                                    (90.0, true), (90.49, true), (91.0, true)] {
            check(warning.isTriggered(by: reading) == expected,
                  "Warning boundary matches the visible whole-degree reading: \(reading)")
        }
        for reading: Double? in [nil, .nan, .infinity, -.infinity, 0, -1, 150] {
            check(!warning.isTriggered(by: reading), "Unavailable and invalid readings never warn")
        }
        check(!HUDHeatWarningOptions(enabled: false, thresholdCelsius: 90).isTriggered(by: 100),
              "Disabled warning ignores a hot reading")
        for (text, expected) in [("1", 1), ("90", 90), ("149", 149), (" 95\n", 95)] {
            check(HUDHeatWarningOptions.parsedThreshold(text) == expected, "Accept integer threshold: \(text)")
        }
        for text in ["", " ", "0", "150", "-1", "90.5", "1e2", "95°C", "NaN", "９０", "+90"] {
            check(HUDHeatWarningOptions.parsedThreshold(text) == nil, "Reject malformed threshold: \(text)")
        }

        let suite = "PerformanceHUD.HeatWarningTests." + UUID().uuidString
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        func checkDefaults(_ reason: String) {
            check(HUDPreferences.resourceOptions(for: .gpu, in: store).heatWarning == .init(thresholdCelsius: 95),
                  "GPU defaults enabled at 95°C: \(reason)")
            check(HUDPreferences.resourceOptions(for: .cpu, in: store).heatWarning == .init(thresholdCelsius: 95),
                  "CPU defaults enabled at 95°C: \(reason)")
            check(HUDPreferences.batteryOptions(in: store).heatWarning == .init(thresholdCelsius: 45),
                  "Battery defaults enabled at 45°C: \(reason)")
        }
        checkDefaults("new install")
        store.set(false, forKey: "hud.group.gpu.temperature")
        store.set(["temperature", "power"], forKey: "hud.group.cpu.highlighted")
        store.set(true, forKey: "hud.battery.temperatureHighlighted")
        checkDefaults("migration without new preference keys")
        check(!HUDPreferences.resourceOptions(for: .gpu, in: store).temperature,
              "Migration keeps an existing hidden temperature hidden")
        check(HUDPreferences.resourceOptions(for: .cpu, in: store).highlighted.contains(.temperature)
              && HUDPreferences.batteryOptions(in: store).temperatureHighlighted,
              "Migration preserves independent CPU and battery emphasis")
        var gpu = HUDPreferences.resourceOptions(for: .gpu, in: store)
        gpu.heatWarning = .init(enabled: false, thresholdCelsius: 87)
        HUDPreferences.setResourceOptions(gpu, for: .gpu, in: store)
        var cpu = HUDPreferences.resourceOptions(for: .cpu, in: store)
        cpu.heatWarning = .init(thresholdCelsius: 101)
        HUDPreferences.setResourceOptions(cpu, for: .cpu, in: store)
        var battery = HUDPreferences.batteryOptions(in: store)
        battery.heatWarning = .init(enabled: false, thresholdCelsius: 42)
        HUDPreferences.setBatteryOptions(battery, in: store)
        check(HUDPreferences.resourceOptions(for: .gpu, in: store) == gpu
              && HUDPreferences.resourceOptions(for: .cpu, in: store) == cpu
              && HUDPreferences.batteryOptions(in: store) == battery,
              "Thresholds, enablement, visibility and emphasis persist independently")
        gpu.heatWarning.enabled = true
        HUDPreferences.setResourceOptions(gpu, for: .gpu, in: store)
        check(HUDPreferences.resourceOptions(for: .gpu, in: store).heatWarning.thresholdCelsius == 87
              && HUDPreferences.resourceOptions(for: .cpu, in: store).heatWarning.thresholdCelsius == 101
              && HUDPreferences.batteryOptions(in: store).heatWarning == battery.heatWarning,
              "Toggling one warning retains its threshold and other categories")
        for invalid: Any in [0, 150, -1, 91.5, "invalid"] {
            store.set(invalid, forKey: "hud.group.cpu.heatWarning.threshold")
            check(HUDPreferences.resourceOptions(for: .cpu, in: store).heatWarning.thresholdCelsius == 95,
                  "Invalid stored threshold falls back to the category default")
        }
        HUDPreferences.resetOptions(in: store)
        checkDefaults("reset")

        let originalDomain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        UserDefaults.standard.setVolatileDomain([
            "hud.enabled": false, "hud.autoHide.mode": "off", "hud.alignment": "vertical",
            "hud.background": "dark", "hud.scale": 1.0
        ], forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(originalDomain, forName: UserDefaults.argumentDomain) }
        let hud = HUDWindowController()
        hud.setHUDEnabled(false)
        hud.setAutoHideMode(.off)
        hud.setHUDScale(.init(rawValue: 1))
        defer { hud.shutdown() }
        let labels: [HUDMetric: NSTextField] = member(hud, "temperatureLabels")
        let horizontal: HUDHorizontalView = member(hud, "horizontalView")
        let verticalBattery: HUDBatteryIndicatorView = member(hud, "batteryIndicator")
        let scale = HUDScale(rawValue: 1)

        for alignment in [HUDAlignment.vertical, .horizontal] {
            hud.setAlignment(alignment)
            for background in [HUDBackground.light, .dark] {
                hud.setBackground(background)
                for highlighted in [false, true] {
                    var options = HUDResourceOptions(enabled: true, temperature: true, totalUse: true,
                        focusedApp: false, power: true,
                        highlighted: highlighted ? [.temperature] : [],
                        heatWarning: .init(thresholdCelsius: 90))
                    hud.setResourceOptions(options, for: .gpu)
                    hud.setResourceOptions(options, for: .cpu)
                    hud.updateTemperatures(.init(cpu: 90, gpu: 100))
                    let expectedFont = HUDStyle.readingFont(scale: scale, highlighted: highlighted)
                    func verifyResource(_ metric: HUDMetric, warning expected: Bool, _ context: String) {
                        let expectedColor = expected ? NSColor.systemRed : HUDStyle.readingColor(background: background)
                        check(labels[metric]?.textColor == expectedColor, "Vertical temperature colour: \(context)")
                        check(labels[metric]?.font == expectedFont, "Temperature emphasis survives warning: \(context)")
                        if alignment == .horizontal {
                            let inlineLabels: [String: NSTextField] = member(horizontal, "labels")
                            let inline = inlineLabels["\(metric.rawValue).temperature"]
                            check(inline?.textColor == expectedColor && inline?.font == expectedFont,
                                  "Horizontal temperature matches colour and emphasis: \(context)")
                        }
                    }
                    verifyResource(.cpuTotal, warning: true, "at threshold")
                    verifyResource(.gpuTotal, warning: true, "above threshold")
                    let powerLabels: [HUDMetric: NSTextField] = member(hud, "powerLabels")
                    check(powerLabels[.gpuTotal]?.textColor == HUDStyle.readingColor(background: background),
                          "Warning does not recolour other GPU readings")

                    options.heatWarning.thresholdCelsius = 110
                    hud.setResourceOptions(options, for: .gpu)
                    verifyResource(.gpuTotal, warning: false, "raising threshold recolours the current reading immediately")
                    verifyResource(.cpuTotal, warning: true, "GPU threshold does not change CPU")
                    options.heatWarning.thresholdCelsius = 90
                    hud.setResourceOptions(options, for: .gpu)
                    verifyResource(.gpuTotal, warning: true, "lowering threshold recolours immediately")
                    options.heatWarning.enabled = false
                    hud.setResourceOptions(options, for: .gpu)
                    verifyResource(.gpuTotal, warning: false, "warning off restores ordinary colour immediately")
                    options.heatWarning.enabled = true
                    hud.setResourceOptions(options, for: .gpu)
                    hud.updateTemperatures(.init(cpu: 89.49, gpu: 89.5))
                    check(labels[.cpuTotal]?.stringValue == "89°C" && labels[.gpuTotal]?.stringValue == "90°C",
                          "Displayed threshold rounding matches warning logic")
                    verifyResource(.cpuTotal, warning: false, "below rounded threshold")
                    verifyResource(.gpuTotal, warning: true, "at rounded threshold")
                    hud.setBackground(background == .light ? .dark : .light)
                    hud.setBackground(background)
                    verifyResource(.gpuTotal, warning: true, "appearance refresh retains warning")
                    hud.updateTemperatures(.init(cpu: nil, gpu: .nan))
                    check(labels[.cpuTotal]?.stringValue == "" && labels[.gpuTotal]?.stringValue == "",
                          "Unavailable temperature remains blank")
                    verifyResource(.gpuTotal, warning: false, "invalid sample clears stale red colour")

                    var batteryOptions = HUDBatteryOptions(enabled: true, temperature: true, charge: true,
                        temperatureHighlighted: highlighted, heatWarning: .init(thresholdCelsius: 45))
                    hud.setBatteryOptions(batteryOptions)
                    hud.updateBattery(.init(percentage: 80, source: .battery, temperature: 45, power: -8))
                    func verifyBattery(warning expected: Bool, _ context: String) {
                        let expectedColor = expected ? NSColor.systemRed : HUDStyle.readingColor(background: background)
                        let activeBattery = alignment == .horizontal ? horizontal.battery : verticalBattery
                        for view in [activeBattery] {
                            check(view.temperatureColor == expectedColor, "Battery temperature colour: \(context)")
                            let saved: HUDBatteryOptions = member(view, "options")
                            check(saved.temperatureHighlighted == highlighted,
                                  "Battery warning preserves emphasis: \(context)")
                        }
                    }
                    verifyBattery(warning: true, "at threshold")
                    batteryOptions.heatWarning.thresholdCelsius = 50
                    hud.setBatteryOptions(batteryOptions)
                    verifyBattery(warning: false, "higher threshold recolours current reading")
                    batteryOptions.heatWarning.thresholdCelsius = 45
                    batteryOptions.heatWarning.enabled = false
                    hud.setBatteryOptions(batteryOptions)
                    verifyBattery(warning: false, "warning off")
                    batteryOptions.heatWarning.enabled = true
                    hud.setBatteryOptions(batteryOptions)
                    verifyBattery(warning: true, "warning restored without waiting for another sample")
                    hud.setBackground(background == .light ? .dark : .light)
                    hud.setBackground(background)
                    verifyBattery(warning: true, "appearance refresh retains warning")
                    hud.updateBattery(.init(percentage: 80, source: .battery, temperature: nil))
                    verifyBattery(warning: false, "missing reading clears warning")
                    check(verticalBattery.temperatureText.isEmpty && horizontal.battery.temperatureText.isEmpty,
                          "Missing battery temperature remains blank in both layouts")
                }
            }
        }
        if !failures.isEmpty {
            failures.sorted().forEach { print("FAIL: \($0)") }
            exit(1)
        }
        print("PASS: heat-warning defaults, migration, independent persistence/reset, validated thresholds, rounded boundaries, immediate recolouring, both layouts/appearances, emphasis preservation and missing readings")
    }
}
