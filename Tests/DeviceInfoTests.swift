import AppKit

@main struct DeviceInfoTests {
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }

    @MainActor static func main() throws {
        _ = NSApplication.shared
        let suite = "PerformanceHUD-device-info-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        precondition(HUDPreferences.miscOptions(in: store) == .init(), "Fresh Misc is off with Full and OS selected")

        // Migrate both former master switches without unexpectedly revealing
        // readings from the category that was off, including Chip Off/OS-only.
        for miscEnabled in [false, true] {
            for macEnabled in [false, true] {
                for mode in HUDChipDisplayMode.allCases {
                    for os in [false, true] {
                        store.removePersistentDomain(forName: suite)
                        store.set(miscEnabled, forKey: "hud.metric.misc")
                        store.set(["resolution"], forKey: "hud.misc.readings")
                        store.set(macEnabled, forKey: "hud.metric.deviceInfo")
                        store.set(mode.rawValue, forKey: "hud.deviceInfo.chipMode")
                        store.set(os, forKey: "hud.deviceInfo.os")
                        let migrated = HUDPreferences.miscOptions(in: store)
                        var expected: Set<HUDMiscReading> = miscEnabled ? [.resolution] : []
                        if macEnabled && mode != .off { expected.insert(.chip) }
                        if macEnabled && os { expected.insert(.os) }
                        precondition(Set(migrated.visibleReadings) == expected, "Migration preserves visible readings")
                        precondition(migrated.enabled == (miscEnabled || macEnabled))
                        precondition(migrated.chipMode == (mode == .tier ? .tier : .full))
                        HUDPreferences.setMiscOptions(migrated, in: store)
                        store.set(!macEnabled, forKey: "hud.metric.deviceInfo")
                        precondition(HUDPreferences.miscOptions(in: store) == migrated, "Old settings cannot override a saved v3.2 choice")
                        let captured = HUDPresetConfiguration.capture(in: store)
                        let data = try JSONEncoder().encode(captured)
                        let encoded = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                        precondition(encoded["deviceInfo"] == nil, "New presets contain only the merged category")
                        let decoded = try JSONDecoder().decode(HUDPresetConfiguration.self, from: data)
                        HUDPreferences.resetOptions(in: store)
                        decoded.apply(in: store)
                        precondition(HUDPreferences.miscOptions(in: store) == migrated, "Preset apply restores all merged choices")
                    }
                }
            }
        }
        HUDPreferences.resetOptions(in: store)
        precondition(HUDPreferences.miscOptions(in: store) == .init(), "Reset clears legacy switches and restores new defaults")
        precondition(HUDPresetConfiguration.builtIn(.full).misc == .init(enabled: true), "Detailed enables all Misc readings")

        // A v3.1 object preset retains the same Chip/OS selections after loading.
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(HUDPresetConfiguration.builtIn(.balanced))) as! [String: Any]
        legacy["misc"] = ["enabled": false, "readings": ["process", "thermal"]]
        legacy["deviceInfo"] = ["enabled": true, "chipMode": "full", "os": false] as [String: Any]
        let migratedPreset = try JSONDecoder().decode(HUDPresetConfiguration.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(migratedPreset.misc == .init(enabled: true, readings: [.chip]), "Old Full preset moves into Misc without revealing other readings")

        let info = HUDDeviceInfo(chipName: "M5", macOSVersion: "macOS 27.2.1",
            efficiencyCores: 6, cpuCores: 10, gpuCores: 10, superCores: 4)
        precondition(info.cpuConfiguration == "4 Super + 6 Efficiency" && info.gpuConfiguration == "10")
        let unknown = HUDDeviceInfo(chipName: "Mac", macOSVersion: "macOS 27", cpuCores: 8)
        precondition(unknown.cpuConfiguration == "8" && unknown.gpuConfiguration == "Not available")
        let detected = HUDDeviceInfo.current
        if !detected.coreTypes.isEmpty {
            precondition(detected.coreTypes.reduce(0) { $0 + $1.count } == detected.cpuCores, "CPU split matches installed physical cores")
        }

        let menu = HUDMiscMenuView(options: .init(enabled: true))
        let chip: NSButton = member(menu, "chip")
        let os: NSButton = member(menu, "os")
        let modes: [NSButton] = member(menu, "chipModes")
        menu.layoutSubtreeIfNeeded()
        let choices: [NSButton] = member(menu, "choices")
        precondition(type(of: chip) == type(of: choices[0]) && type(of: os) == type(of: choices[0]),
                     "OS and Chip reuse the existing Misc pill style")
        precondition(os.frame.height == choices[0].frame.height && chip.frame.height == choices[0].frame.height)
        let chipGroup = chip.superview!
        precondition(os.superview === chipGroup.superview && modes.allSatisfy { $0.superview === chipGroup },
                     "Chip and both modes share one capsule after OS")
        precondition(os.frame.maxX < chipGroup.frame.minX && chip.frame.maxX < modes[0].frame.minX)
        precondition(modes[0].frame.maxX == modes[1].frame.minX && modes.allSatisfy { chipGroup.bounds.contains($0.frame) })
        precondition(chipGroup.frame.height == os.frame.height && modes.allSatisfy { abs($0.frame.midY - chip.frame.midY) < 0.1 })
        var selected = HUDMiscOptions(enabled: true)
        menu.onChange = { selected = $0 }
        precondition(modes.map(\.title) == ["Tier", "Full"])
        chip.performClick(nil)
        precondition(!selected.readings.contains(.chip) && modes.allSatisfy { !$0.isEnabled } && selected.readings.contains(.os))
        chip.performClick(nil)
        modes[0].performClick(nil)
        precondition(selected.chipMode == .tier && modes[0].state == .on && modes[1].state == .off)
        modes[0].performClick(nil)
        precondition(selected.chipMode == .tier && modes[0].state == .on, "Clicking the selected mode keeps one selected")
        os.performClick(nil)
        precondition(!selected.readings.contains(.os) && selected.readings.contains(.chip))
        menu.update(alignment: .horizontal)
        precondition(!chip.isEnabled && !os.isEnabled && modes.allSatisfy { !$0.isEnabled })
        menu.update(alignment: .vertical)
        precondition(chip.isEnabled && chip.state == .on && os.state == .off && modes[0].state == .on && modes[1].state == .off)

        UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "off",
            "hud.alignment": "vertical", "hud.metric.misc": false, "hud.misc.chipMode": "full"],
            forName: UserDefaults.argumentDomain)
        let hud = HUDWindowController()
        defer { hud.shutdown() }
        hud.setHUDEnabled(false)
        hud.setPackagePowerOptions(.init(enabled: false))
        for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: false) }
        let panel: HUDPanel = member(hud, "panel")
        let view: HUDMiscView = member(hud, "miscView")
        let fields: [HUDMiscReading: (NSTextField, NSTextField)] = member(view, "fields")
        let cores: [(NSTextField, NSTextField)] = member(view, "coreFields")
        for appearance in [HUDBackground.light, .dark] {
            hud.setBackground(appearance)
            for factor in [0.5, 0.75, 1, 1.25, 1.5, 2] {
                let scale = HUDScale(rawValue: factor)
                hud.setHUDScale(scale)
                hud.setMiscOptions(.init(enabled: true, readings: [.chip, .os], chipMode: .tier))
                panel.contentView?.layoutSubtreeIfNeeded()
                let tierSize = panel.frame.size
                let chipTop = fields[.chip]!.0.frame.minY
                let osTop = fields[.os]!.0.frame.minY
                hud.setMiscOptions(.init(enabled: true, readings: [.chip, .os]))
                panel.contentView?.layoutSubtreeIfNeeded()
                precondition(panel.frame.width == tierSize.width && abs(panel.frame.height - tierSize.height - 36 * factor) < 0.6,
                             "Full adds two rows without changing HUD width")
                precondition(fields[.chip]!.0.frame.minY == chipTop)
                let rows = [fields[.os]!, fields[.chip]!] + cores
                for (title, value) in rows {
                    precondition(!title.isHidden && !value.isHidden)
                    precondition((title.alignment == .left || title.alignment == .natural) && value.alignment == .right, "All rows follow Misc layout")
                    precondition(title.font == HUDStyle.smallLabelFont(scale: scale)
                        && title.textColor == HUDStyle.TextStyle.label.color(background: appearance))
                    precondition(value.font == HUDStyle.readingFont(scale: scale, highlighted: false)
                        && value.textColor == HUDStyle.TextStyle.reading.color(background: appearance))
                    precondition(value.alignmentRect(forFrame: value.frame).minX > title.alignmentRect(forFrame: title.frame).maxX, "Label and reading have a gap")
                    precondition(value.frame.width + 0.5 >= value.intrinsicContentSize.width, "Core values fit at \(factor)×")
                    precondition(view.bounds.insetBy(dx: -2, dy: -1).contains(value.frame))
                    precondition(abs(value.frame.maxX - rows[0].1.frame.maxX) < 0.1, "Values share a trailing column")
                }
                precondition(rows.map { $0.0.frame.minY } == rows.map { $0.0.frame.minY }.sorted(), "OS, Chip, CPU, GPU order")
                hud.setMiscOptions(.init(enabled: true, readings: [.os]))
                panel.contentView?.layoutSubtreeIfNeeded()
                precondition(fields[.chip]!.0.isHidden && cores.allSatisfy { $0.0.isHidden } && !fields[.os]!.0.isHidden)
                precondition(fields[.os]!.0.frame.minY == osTop, "OS-only has no empty rows before it")
                hud.setMiscOptions(.init(enabled: true, readings: []))
                precondition(view.isHidden, "Empty Misc has no content or trailing divider")
            }
        }
        var selection = HUDLogSelection(fps: false, resources: [:], package: .init(enabled: false),
            fans: .init(enabled: false), battery: .init(enabled: false, temperature: false, charge: false),
            alignment: .vertical, misc: .init(enabled: true, readings: [.chip, .os]))
        precondition(selection.columns(fanSample: .noFans) == [.os, .chip, .cpuCores, .cpuEfficiencyCores, .cpuPerformanceCores, .cpuSuperCores, .gpuCores])
        selection.misc.chipMode = .tier
        precondition(selection.columns(fanSample: .noFans) == [.os, .chip])
        selection.misc.readings.remove(.chip)
        precondition(selection.columns(fanSample: .noFans) == [.os])
        selection.misc.enabled = false
        precondition(selection.columns(fanSample: .noFans).isEmpty)
        selection.misc.enabled = true
        selection.alignment = .horizontal
        precondition(selection.columns(fanSample: .noFans).isEmpty)
        print("PASS: Mac-to-Misc settings/preset migration, reset, independent Chip/OS controls, core layout, typography, and CSV selections")
    }
}
