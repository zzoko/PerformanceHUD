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
        precondition(HUDPreferences.deviceInfoOptions(in: store) == .init(enabled: false, chipMode: .full, os: true),
                     "Fresh settings select Full and OS with the category off")
        store.set(true, forKey: "hud.metric.deviceInfo")
        precondition(HUDPreferences.deviceInfoOptions(in: store) == .init(enabled: true), "Existing category switches are preserved")
        for enabled in [false, true] {
            for mode in HUDChipDisplayMode.allCases {
                for os in [false, true] {
                    let options = HUDDeviceInfoOptions(enabled: enabled, chipMode: mode, os: os)
                    HUDPreferences.setDeviceInfoOptions(options, in: store)
                    precondition(HUDPreferences.deviceInfoOptions(in: store) == options, "All independent selections persist")
                    let captured = HUDPresetConfiguration.capture(in: store)
                    let decoded = try JSONDecoder().decode(HUDPresetConfiguration.self, from: JSONEncoder().encode(captured))
                    precondition(decoded.deviceInfo == options, "Saved presets round-trip the complete category")
                    HUDPreferences.resetOptions(in: store)
                    decoded.apply(in: store)
                    precondition(HUDPreferences.deviceInfoOptions(in: store) == options, "Preset apply restores the complete category")
                }
            }
        }
        HUDPreferences.resetOptions(in: store)
        precondition(HUDPreferences.deviceInfoOptions(in: store) == .init(enabled: false, chipMode: .full, os: true),
                     "Reset restores Full and OS without enabling the category")

        let info = HUDDeviceInfo(chipName: "M5", macOSVersion: "macOS 27.2.1",
            efficiencyCores: 6, performanceCores: 4, cpuCores: 10, gpuCores: 10)
        precondition(info.cpuConfiguration == "(6 E-Cores + 4 P-Cores)" && info.gpuConfiguration == "(10 GPU-Cores)")
        let unknown = HUDDeviceInfo(chipName: "Mac", macOSVersion: "macOS 27", cpuCores: 8)
        precondition(unknown.cpuConfiguration == "(8 CPU-Cores)" && unknown.gpuConfiguration == "GPU cores unavailable",
                     "Unknown topology must not invent a split or GPU count")
        let detected = HUDDeviceInfo.current
        if let e = detected.efficiencyCores, let p = detected.performanceCores {
            precondition(e + p == detected.cpuCores, "Detected CPU split matches the installed physical core count")
        }
        print("LIVE: \(detected.chipName) \(detected.cpuConfiguration) \(detected.gpuConfiguration)")

        let menu = HUDDeviceInfoMenuView(options: .init(enabled: true), enabled: true)
        menu.layoutSubtreeIfNeeded()
        let master: NSButton = member(menu, "master")
        let selector: NSSegmentedControl = member(menu, "chipMode")
        let osControl: HUDReadingCheckbox = member(menu, "os")
        precondition(selector.selectedSegment == 1 && osControl.state == .on, "Menu defaults to Full and OS")
        precondition((0..<selector.segmentCount).map { selector.label(forSegment: $0)! } == ["Tier", "Full", "Off"])
        precondition(selector.frame.minX == HUDCategoryLayout.modeLeading && selector.frame.width == HUDCategoryLayout.modeWidth,
                     "Chip uses the same selector column as Charge and other modes")
        var selected = HUDDeviceInfoOptions(enabled: true)
        menu.onChange = { selected = $0 }
        selector.selectedSegment = 1
        selector.sendAction(selector.action, to: selector.target)
        precondition(selected.chipMode == .full && selected.os)
        osControl.performClick(nil)
        precondition(!selected.os && selected.chipMode == .full, "OS changes independently")
        master.performClick(nil)
        precondition(!selected.enabled && selected.chipMode == .full && !selected.os && !selector.isEnabled,
                     "Master-off remembers both choices")
        master.performClick(nil)
        precondition(selected.enabled && selector.selectedSegment == 1 && osControl.state == .off)
        menu.update(options: selected, enabled: false)
        precondition(!master.isEnabled && !selector.isEnabled && !osControl.isEnabled)
        menu.update(options: selected, enabled: true)
        precondition(master.state == .on && selector.selectedSegment == 1 && osControl.state == .off)

        let previous = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "off", "hud.alignment": "vertical"],
            forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        let hud = HUDWindowController()
        defer { hud.shutdown() }
        let panel: HUDPanel = member(hud, "panel")
        panel.alphaValue = 0
        hud.setHUDEnabled(true)
        hud.setAutoHideAnimated(false)
        hud.setAutoHideMode(.off)
        hud.setPackagePowerOptions(.init(enabled: false))
        for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: false) }
        let view: HUDDeviceInfoView = member(hud, "deviceInfoView")
        let chip: NSTextField = member(view, "chipLabel")
        let version: NSTextField = member(view, "versionLabel")
        let cpu: NSTextField = member(view, "cpuLabel")
        let gpu: NSTextField = member(view, "gpuLabel")
        func top(_ label: NSTextField) -> CGFloat { view.bounds.maxY - label.frame.maxY }
        for appearance in [HUDBackground.light, .dark] {
            hud.setBackground(appearance)
            for factor in [0.5, 0.75, 1, 1.25, 1.5, 2] {
                let scale = HUDScale(rawValue: factor)
                hud.setHUDScale(scale)
                hud.setDeviceInfoOptions(.init(enabled: true, chipMode: .tier))
                panel.contentView?.layoutSubtreeIfNeeded()
                let originalSize = panel.frame.size
                let chipTop = top(chip), versionTop = top(version)
                let chipLeft = chip.frame.minX, versionRight = version.frame.maxX
                hud.setDeviceInfoOptions(.init(enabled: true, chipMode: .full))
                panel.contentView?.layoutSubtreeIfNeeded()
                precondition(panel.frame.width == originalSize.width && abs(panel.frame.height - originalSize.height - 36 * factor) < 0.6,
                             "Full adds two rows while preserving HUD width")
                precondition(abs(top(chip) - chipTop) < 0.01 && abs(top(version) - versionTop) < 0.01
                    && chip.frame.minX == chipLeft && version.frame.maxX == versionRight,
                    "Full preserves the original chip/OS positions")
                for label in [chip, version, cpu, gpu] {
                    precondition(!label.isHidden && view.bounds.insetBy(dx: -2, dy: -1).contains(label.frame),
                                 "Every Full reading fits inside the footer at \(factor)×")
                    precondition(label.frame.width + 0.5 >= label.intrinsicContentSize.width, "No clipped core text")
                    precondition(label.font == HUDStyle.smallLabelFont(scale: scale)
                        && label.textColor == HUDStyle.TextStyle.label.color(background: appearance),
                        "All device information uses the shared Label style")
                }
                precondition(cpu.alignment == .left && gpu.alignment == .left
                    && cpu.frame.minX == chip.frame.minX && gpu.frame.minX == chip.frame.minX,
                    "Both core configurations align beneath the chip name")
                precondition(top(cpu) > top(version) && top(gpu) > top(cpu), "CPU and GPU details are added below the existing row")
                hud.setDeviceInfoOptions(.init(enabled: true, chipMode: .full, os: false))
                precondition(version.isHidden && !cpu.isHidden && !gpu.isHidden)
                hud.setDeviceInfoOptions(.init(enabled: true, chipMode: .off, os: true))
                panel.contentView?.layoutSubtreeIfNeeded()
                precondition(chip.isHidden && cpu.isHidden && gpu.isHidden && !version.isHidden,
                             "Chip Off leaves OS visible at its original position")
                precondition(abs(top(version) - versionTop) < 0.01 && version.frame.maxX == versionRight)
                hud.setDeviceInfoOptions(.init(enabled: true, chipMode: .off, os: false))
                let enabled: Set<HUDMetric> = member(hud, "enabledMetrics")
                precondition(!enabled.contains(.deviceInfo) && view.isHidden, "No empty footer or divider when both readings are off")
            }
        }
        var selection = HUDLogSelection(fps: false, resources: [:], package: .init(enabled: false),
            fans: .init(enabled: false), battery: .init(enabled: false, temperature: false, charge: false),
            deviceInfo: .init(enabled: true, chipMode: .full), alignment: .vertical)
        precondition(selection.columns(fanSample: .noFans) == [.chip, .cpuCores, .cpuEfficiencyCores, .cpuPerformanceCores, .gpuCores, .os])
        selection.deviceInfo.chipMode = .off
        precondition(selection.columns(fanSample: .noFans) == [.os])
        selection.deviceInfo.os = false
        precondition(selection.columns(fanSample: .noFans).isEmpty)
        selection.deviceInfo = .init(enabled: true, chipMode: .full)
        selection.alignment = .horizontal
        precondition(selection.columns(fanSample: .noFans).isEmpty, "Horizontal retains the existing category restriction")
        print("PASS: hardware counts/fallbacks, preferences/reset, preset round-trip, menu controls, Full layout, independent OS and CSV selections")
    }
}
