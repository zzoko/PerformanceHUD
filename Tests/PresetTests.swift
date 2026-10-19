import AppKit

@main struct PresetTests {
    @MainActor static func main() throws {
        var failures = Set<String>()
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures.insert(message) }
        }
        func rejects(_ message: String, _ operation: () throws -> Void) {
            do { try operation(); failures.insert(message) } catch { }
        }
        let suite = "PerformanceHUD.PresetTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func clear() { defaults.removePersistentDomain(forName: suite) }

        let balanced = HUDPresetConfiguration.builtIn(.balanced)
        let fpsOnly = HUDPresetConfiguration.builtIn(.fpsOnly)
        let full = HUDPresetConfiguration.builtIn(.full)
        var presets = HUDPresetStore(in: defaults)
        check(HUDBuiltInPreset.allCases.map(\.title) == ["FPS", "Balanced", "Detailed"],
              "Built-ins keep the approved order and names")
        check(HUDPresetConfiguration.capture(in: defaults) == balanced,
              "Balanced exactly matches pre-preset fresh preferences")
        check(balanced.fps.enabled && balanced.fps.mode == .both && balanced.fps.valueHighlighted,
              "Balanced retains FPS Both and number emphasis")
        check(balanced.fans.mode == .bar && balanced.battery.flowMode == .auto
              && !balanced.misc.enabled && !balanced.deviceInfo,
              "Balanced retains fan, battery, Misc, and Chip & OS defaults")
        check(balanced.resources[.ram]?.pressureMode == .colorHistory,
              "Balanced retains colored memory history")
        check(presets.selection(for: balanced).title == "Balanced", "Fresh settings select Balanced")

        var expectedFPS = balanced
        expectedFPS.fps.mode = .value
        for group in HUDResourceGroup.allCases { expectedFPS.resources[group]?.enabled = false }
        expectedFPS.packagePower.enabled = false
        expectedFPS.fans.enabled = false
        expectedFPS.battery.enabled = false
        expectedFPS.misc.enabled = false
        expectedFPS.deviceInfo = false
        check(fpsOnly == expectedFPS, "FPS shows only the frame-rate value and retains other reading choices")
        check(fpsOnly.fps.visibleMetrics(alignment: .vertical) == [.fps],
              "FPS preset does not display the history graph in vertical mode")
        var expectedFull = balanced
        for group in [HUDResourceGroup.gpu, .cpu, .ram] {
            expectedFull.resources[group]?.selectUsageMode(.both)
        }
        expectedFull.misc.enabled = true
        expectedFull.deviceInfo = true
        check(full == expectedFull, "Detailed changes usage to Both and enables Misc and Chip & OS only")

        let designSettings: [String: Any] = [
            "hud.alignment": "horizontal", "hud.background": "dark", "hud.scale": 1.37,
            "hud.position": ["x": -890.5, "y": 431.25], "hud.autoHide.mode": "all",
            "hud.autoHide.animated": false, "hud.glass.mode": "strength", "hud.glass.strength": 0.38
        ]
        func retains(_ settings: [String: Any]) -> Bool {
            settings.allSatisfy { key, value in
                NSObject.isEqualValue(defaults.object(forKey: key), value)
            }
        }
        // Presets retain selected readings even when their category is hidden.
        // Seed a former release's preferences before constructing any preset store.
        clear()
        defaults.set(false, forKey: "hud.metric.fps")
        defaults.set(false, forKey: "hud.metric.fpsGraph")
        defaults.set("history", forKey: "hud.fps.displayMode")
        defaults.set(false, forKey: "hud.fps.valueHighlighted")
        for (key, value) in designSettings { defaults.set(value, forKey: key) }
        defaults.set(false, forKey: "hud.package.power")
        defaults.set(true, forKey: "hud.package.highlighted")
        defaults.set(false, forKey: "hud.metric.fans")
        defaults.set(false, forKey: "hud.fan.usage")
        defaults.set("both", forKey: "hud.fan.mode")
        defaults.set(false, forKey: "hud.fan.average")
        defaults.set("vertical", forKey: "hud.fan.averageMode")
        defaults.set(true, forKey: "hud.fan.rpmHighlighted")
        defaults.set(true, forKey: "hud.metric.deviceInfo")
        HUDPreferences.setMiscOptions(.init(enabled: false, readings: [.process, .thermal]), in: defaults)
        HUDPreferences.setBatteryOptions(.init(enabled: false, temperature: false, charge: false,
            temperatureHighlighted: true, powerHighlighted: true, flowMode: .off,
            heatWarning: .init(enabled: false, thresholdCelsius: 49)), in: defaults)
        for group in HUDResourceGroup.allCases {
            var options = HUDPreferences.resourceOptions(for: group, in: defaults)
            options.enabled = false
            options.temperature = false
            options.power = false
            options.selectUsageMode(.app)
            options.setUsagePresentation(visible: false, highlighted: true)
            options.highlighted.formUnion([.temperature, .power, .details, .pressure])
            options.details = false
            options.pressure = false
            options.selectPressureMode(.history)
            options.selectPressureMode(.text)
            options.heatWarning = .init(enabled: false, thresholdCelsius: group == .gpu ? 87 : 101)
            HUDPreferences.setResourceOptions(options, for: group, in: defaults)
        }
        let existing = defaults.persistentDomain(forName: suite)! as NSDictionary
        let customized = HUDPresetConfiguration.capture(in: defaults)
        presets = HUDPresetStore(in: defaults)
        check(presets.selection(for: customized).title == "Custom", "An existing customized install starts Custom")
        check(existing.isEqual(to: defaults.persistentDomain(forName: suite)!),
              "Opening the preset store and reading selection do not migrate or reset existing preferences")
        let encoded = try JSONEncoder().encode(customized)
        check(try JSONDecoder().decode(HUDPresetConfiguration.self, from: encoded) == customized,
              "Saved configuration encoding retains every selected and hidden category setting")
        let encodedObject = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        let independentFields = ["alignment", "background", "glass", "autoHideMode", "autoHideAnimated", "scale", "position"]
        check(independentFields.allSatisfy { encodedObject[$0] == nil },
              "New saved configurations exclude every independent design field")
        let globalBefore = defaults.persistentDomain(forName: UserDefaults.globalDomain) as NSDictionary?
        clear()
        for (key, value) in designSettings { defaults.set(value, forKey: key) }
        customized.apply(in: defaults)
        check(HUDPresetConfiguration.capture(in: defaults) == customized,
              "Applying restores hidden reading modes, emphasis, warnings, and categories")
        check(retains(designSettings), "Applying a saved configuration leaves all design settings untouched")
        check(globalBefore == defaults.persistentDomain(forName: UserDefaults.globalDomain) as NSDictionary?,
              "Applying a preset does not write macOS global preferences")

        let appSettings: [String: Any] = [
            "hud.enabled": false, "hud.hotkeys": Data("existing shortcuts".utf8),
            "SUEnableAutomaticChecks": true, "SUScheduledCheckInterval": 2_592_000,
            "hud.updates.firstLaunchCheckHandled": true, "SULastCheckTime": Date(timeIntervalSince1970: 42),
            "hud.logging.explanationDismissed": true, "hud.autoHide.explanationDismissed": true,
            "hud.resetOptions.confirmationDismissed": true,
            "powerHelperSetupOffered": true, "powerHelperInstalledRevision": "existing revision",
            "independent.login-setting": true, "independent.active-log": "existing CSV"
        ]
        for (key, value) in appSettings { defaults.set(value, forKey: key) }
        for configuration in [balanced, fpsOnly, full, customized] {
            configuration.apply(in: defaults)
            check(retains(appSettings), "Applying any preset preserves master visibility and independent application settings")
            check(retains(designSettings), "Applying any built-in or saved setup preserves layout, appearance, and auto-hide settings")
        }
        clear()
        for (key, value) in designSettings {
            defaults.set(value, forKey: key)
            check(HUDPresetConfiguration.capture(in: defaults) == balanced
                  && presets.selection(for: .capture(in: defaults)).title == "Balanced",
                  "Changing independent \(key) does not make Balanced Custom")
        }

        // Exercise real settings changes that should immediately clear the preset name.
        let changes: [(String, (inout HUDPresetConfiguration) -> Void)] = [
            ("FPS enable", { $0.fps.enabled.toggle() }),
            ("FPS mode", { $0.fps.mode = .value }),
            ("FPS emphasis", { $0.fps.valueHighlighted.toggle() }),
            ("GPU category", { $0.resources[.gpu]?.enabled.toggle() }),
            ("GPU temperature", { $0.resources[.gpu]?.temperature.toggle() }),
            ("CPU power", { $0.resources[.cpu]?.power.toggle() }),
            ("CPU usage", { $0.resources[.cpu]?.selectUsageMode(.both) }),
            ("Hidden usage", { $0.resources[.ram]?.setUsagePresentation(visible: false, highlighted: false) }),
            ("Memory details", { $0.resources[.ram]?.details.toggle() }),
            ("Memory pressure", { $0.resources[.ram]?.pressure.toggle() }),
            ("Memory graph", { $0.resources[.ram]?.selectPressureMode(.meter) }),
            ("Reading emphasis", { $0.resources[.gpu]?.highlighted.insert(.temperature) }),
            ("Heat threshold", { $0.resources[.cpu]?.heatWarning.thresholdCelsius = 96 }),
            ("Heat enable", { $0.resources[.gpu]?.heatWarning.enabled.toggle() }),
            ("SOC", { $0.packagePower.enabled.toggle() }),
            ("SOC emphasis", { $0.packagePower.highlighted.toggle() }),
            ("Fan mode", { $0.fans.mode = .both }),
            ("Fan average", { $0.fans.averageMode = .both }),
            ("Battery charge", { $0.battery.flowMode = .always }),
            ("Battery heat", { $0.battery.heatWarning.thresholdCelsius = 47 }),
            ("Misc", { $0.misc.enabled.toggle() }),
            ("Chip & OS", { $0.deviceInfo.toggle() })
        ]
        for (name, change) in changes {
            var changed = balanced
            change(&changed)
            check(presets.selection(for: changed).title == "Custom", "Custom after changing \(name)")
            changed.apply(in: defaults)
            check(presets.selection(for: .capture(in: defaults)).title == "Custom",
                  "Custom after persisting and rereading \(name)")
            balanced.apply(in: defaults)
            check(presets.selection(for: .capture(in: defaults)).title == "Balanced",
                  "Balanced recognized again after restoring \(name)")
        }
        for preset in HUDBuiltInPreset.allCases {
            let configuration = HUDPresetConfiguration.builtIn(preset)
            configuration.apply(in: defaults)
            check(presets.selection(for: .capture(in: defaults)).title == preset.title,
                  "All built-ins recognized after applying: \(preset.title)")
        }
        var unavailable = balanced
        unavailable.fans.enabled = false
        unavailable.packagePower.enabled = false
        for group in HUDResourceGroup.allCases { unavailable.resources[group]?.power = false }
        let noHardware = HUDPresetAvailability(fansAvailable: false, powerAvailable: false)
        check(unavailable.matches(balanced, availability: noHardware),
              "Forced fan/helper disablement does not make Balanced Custom")
        check(!unavailable.matches(balanced), "Actual display changes still count when hardware is available")
        unavailable.fans.mode = .both
        check(!unavailable.matches(balanced, availability: noHardware),
              "Remembered fan mode remains a choice even on a fanless Mac")
        clear()
        presets = HUDPresetStore(in: defaults)
        let first = try presets.add(name: "  Workload  ", configuration: customized)
        check(first.name == "Workload", "Saved names trim surrounding whitespace")
        check(HUDPresetStore(in: defaults).savedPresets.first?.configuration == customized,
              "Saved setups survive constructing a new store")
        let second = try presets.add(name: "Second setup", configuration: customized)
        presets.preferredSavedID = first.id
        check(presets.selection(for: customized).title == "Workload", "Preferred identical saved setup stays selected")
        presets.preferredSavedID = second.id
        check(presets.selection(for: customized).title == "Second setup", "Selecting an identical saved setup retains its name")
        customized.apply(in: defaults)
        for (key, value) in designSettings {
            defaults.set(value, forKey: key)
            check(presets.selection(for: .capture(in: defaults)).title == "Second setup",
                  "Changing independent \(key) does not clear the selected saved preset")
        }
        try presets.rename(id: second.id, name: "  Renamed  ")
        check(presets.selection(for: customized).title == "Renamed"
              && presets.savedPresets.first(where: { $0.id == second.id })?.configuration == customized,
              "Rename preserves ID/configuration and updates the selected name")
        let namesBeforeInvalid = presets.savedPresets.map(\.name)
        for name in ["", " \n ", "Balanced", " FPS ", "DETAILED", "custom", "WORKLOAD", String(repeating: "x", count: 61), "two\nlines"] {
            rejects("Reject invalid or duplicate saved name: \(name)") {
                _ = try presets.add(name: name, configuration: balanced)
            }
        }
        rejects("Rename cannot collide with another saved preset") { try presets.rename(id: second.id, name: "workload") }
        rejects("Rename rejects a missing preset") { try presets.rename(id: UUID(), name: "Missing") }
        check(presets.savedPresets.map(\.name) == namesBeforeInvalid, "Rejected operations do not alter saved presets")
        for (name, change) in [
            ("missing category", { (value: inout HUDPresetConfiguration) in value.resources[.cpu] = nil }),
            ("invalid temperature", { $0.battery.heatWarning.thresholdCelsius = 0 })
        ] {
            var invalid = balanced
            change(&invalid)
            rejects("Invalid \(name) cannot be saved") { _ = try presets.add(name: "Invalid", configuration: invalid) }
            let original = HUDPresetConfiguration.capture(in: defaults)
            invalid.apply(in: defaults)
            check(HUDPresetConfiguration.capture(in: defaults) == original,
                  "Invalid \(name) cannot partially apply settings")
        }
        let savedDefault = try presets.add(name: "My defaults", configuration: balanced)
        presets.preferredSavedID = savedDefault.id
        check(presets.selection(for: balanced).title == "My defaults", "Explicit saved selection wins when matching a built-in")
        presets.preferredSavedID = nil
        check(presets.selection(for: balanced).title == "Balanced", "Built-in selection returns when saved preference is cleared")
        presets.preferredSavedID = second.id
        presets.delete(id: second.id)
        check(!presets.savedPresets.contains { $0.id == second.id }
              && presets.selection(for: customized).title == "Workload",
              "Deleting selected setup falls back to another match")
        customized.apply(in: defaults)
        let savedBeforeReset = presets.savedPresets
        defaults.set(false, forKey: "hud.enabled")
        HUDPreferences.resetOptions(in: defaults)
        // Reset All's controller resets the separate position preference too.
        HUDPreferences.setHUDPosition(nil, in: defaults)
        check(HUDPresetStore(in: defaults).savedPresets == savedBeforeReset,
              "Reset All preserves every saved preset")
        check(HUDPresetConfiguration.capture(in: defaults) == balanced,
              "Reset All restores Balanced category defaults")
        check(defaults.object(forKey: "hud.enabled") == nil
              && HUDPreferences.hudScale(in: defaults) == .normal
              && HUDPreferences.hudPosition(in: defaults) == nil
              && HUDPreferences.alignment(in: defaults) == .vertical
              && HUDPreferences.background(in: defaults) == .system
              && HUDPreferences.glassOptions(in: defaults).mode == .system
              && HUDPreferences.autoHideMode(in: defaults) == .fps
              && HUDPreferences.autoHideAnimated(in: defaults),
              "Reset All keeps its full reset behavior for visibility, design, size, and position")

        // Broken on-disk data must not crash selection or reset the user's HUD.
        var records = defaults.array(forKey: "hud.presets.saved")!
        records.append(Data("corrupt preset data".utf8))
        records.append("malformed record")
        defaults.set(records, forKey: "hud.presets.saved")
        check(presets.savedPresets == savedBeforeReset, "Corrupt entries do not discard valid saved setups")
        try presets.rename(id: first.id, name: "Still valid")
        check(presets.savedPresets.contains { $0.id == first.id && $0.name == "Still valid" },
              "Valid presets remain editable beside damaged entries")
        defaults.set([Data("corrupt preset data".utf8)], forKey: "hud.presets.saved")
        let beforeCorruptRead = HUDPresetConfiguration.capture(in: defaults)
        let recovered = HUDPresetStore(in: defaults)
        check(recovered.savedPresets.isEmpty, "Corrupt preset collection fails safely")
        check(HUDPresetConfiguration.capture(in: defaults) == beforeCorruptRead,
              "Reading corrupt preset data never changes the active HUD")

        // Saved records may contain extra fields; only supported category
        // settings are decoded and applied.
        clear()
        var legacyConfiguration = encodedObject
        legacyConfiguration.merge([
            "alignment": "vertical", "background": "light", "scale": 1.72,
            "position": ["x": 420.0, "y": 690.0], "autoHideMode": "off",
            "autoHideAnimated": true, "glass": ["mode": "strength", "strength": 0.9]
        ]) { _, incoming in incoming }
        let legacyID = UUID()
        let legacyData = try JSONSerialization.data(withJSONObject: [
            "id": legacyID.uuidString, "name": "Legacy setup", "configuration": legacyConfiguration
        ])
        defaults.set([legacyData], forKey: "hud.presets.saved")
        let legacyStore = HUDPresetStore(in: defaults)
        let legacySaved = legacyStore.savedPresets.first
        check(legacySaved?.id == legacyID && legacySaved?.configuration == customized,
              "Saved full-configuration records decode their category settings and ignore old design fields")
        for (key, value) in designSettings { defaults.set(value, forKey: key) }
        legacySaved?.configuration.apply(in: defaults)
        check(HUDPresetConfiguration.capture(in: defaults) == customized && retains(designSettings),
              "Applying a legacy saved preset changes readings without restoring its former design settings")
        let unreservedName = try legacyStore.add(name: "Full", configuration: balanced)
        check(unreservedName.name == "Full", "Names other than current built-ins remain available for saved presets")

        if !failures.isEmpty {
            failures.sorted().forEach { print("FAIL: \($0)") }
            exit(1)
        }
        print("PASS: preset defaults/order, scoped built-ins, category round-trip, independent design/app settings, legacy migration, Custom detection, availability, saved selection, names/CRUD/reset and corrupt storage")
    }
}

private extension NSObject {
    static func isEqualValue(_ left: Any?, _ right: Any?) -> Bool {
        guard let left = left as? NSObject, let right = right as? NSObject else { return left == nil && right == nil }
        return left == right
    }
}
