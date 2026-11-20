import AppKit

@main struct MenuBarTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }

    static func disabledSelection() -> HUDLogSelection {
        HUDLogSelection(fps: false,
            resources: Dictionary(uniqueKeysWithValues: HUDResourceGroup.allCases.map {
                ($0, HUDResourceOptions(enabled: false, temperature: false, totalUse: false,
                    focusedApp: false, power: false, details: false, pressure: false))
            }), package: .init(enabled: false), fans: .init(enabled: false),
            battery: .init(enabled: false, temperature: false, charge: false, flowMode: .auto),
            alignment: .vertical)
    }

    static func persistence() {
        let suite = "PerformanceHUD.MenuBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fresh = HUDMenuBarOptions.load(in: defaults)
        check(fresh.readings.isEmpty && fresh.activeReadings.isEmpty,
              "Fresh installs and upgrades have no menu-bar readings selected")
        let selected = Set<HUDMenuBarReading>([.gpuTemperature, .memoryPressure, .fps, .gpuCores, .cpuCores])
        var options = HUDMenuBarOptions(readings: selected)
        options.save(in: defaults)
        check(HUDMenuBarOptions.load(in: UserDefaults(suiteName: suite)!) == options,
              "Menu-bar selections survive reopening the preference store")
        options.isCollapsed = true
        options.save(in: defaults)
        let restored = HUDMenuBarOptions.load(in: UserDefaults(suiteName: suite)!)
        check(restored.readings == selected && restored.activeReadings.isEmpty && restored.isCollapsed,
              "Collapse survives relaunch without discarding individual selections")
        options.isCollapsed = false
        check(options.activeReadings == selected, "Expanding restores all remembered readings")
        defaults.set(["gpuTemperature", "unknownFutureReading", "gpuTemperature"], forKey: HUDMenuBarOptions.readingsKey)
        check(HUDMenuBarOptions.load(in: defaults).readings == [.gpuTemperature],
              "Unknown or duplicate saved readings cannot enable unrelated readings")
        defaults.set("invalid", forKey: HUDMenuBarOptions.readingsKey)
        check(HUDMenuBarOptions.load(in: defaults).readings.isEmpty,
              "Malformed saved selections fall back to all off")
        options.isCollapsed = true
        options.save(in: defaults)
        HUDPresetConfiguration.builtIn(.fpsOnly).apply(in: defaults)
        check(HUDMenuBarOptions.load(in: defaults) == HUDMenuBarOptions(isCollapsed: true),
              "Built-in presets clear menu-bar selections while preserving global collapse")
        HUDPreferences.resetOptions(in: defaults)
        check(HUDMenuBarOptions.load(in: defaults) == HUDMenuBarOptions(),
              "Reset All restores all menu-bar selections to off")
        let withFan = HUDMenuBarOptions(readings: [.fanUsage, .gpuTemperature], isCollapsed: true)
        withFan.save(in: defaults)
        for sample in [FanSample.checking, .unavailable] {
            check(!HUDPreferences.applyFanAvailability(sample, in: defaults)
                  && HUDMenuBarOptions.load(in: defaults) == withFan,
                  "A temporary hardware read failure never removes a remembered fan pin")
        }
        check(HUDPreferences.applyFanAvailability(.noFans, in: defaults),
              "Confirmed fanless hardware clears an unavailable fan selection")
        let withoutFan = HUDMenuBarOptions.load(in: defaults)
        check(withoutFan.readings == [.gpuTemperature] && withoutFan.isCollapsed,
              "Removing a stale fan pin preserves other menu-bar selections and collapse state")
    }

    static func activeCollectors(_ demand: HUDMonitoringDemand) -> Set<String> {
        let choices: [(String, Bool)] = [
            ("fps", demand.fps), ("gpuUsage", demand.gpuUsage), ("gpuAppUsage", demand.gpuAppUsage),
            ("cpuCoreLoad", demand.cpuCores), ("cpuUsage", demand.cpuUsage), ("cpuAppUsage", demand.cpuAppUsage),
            ("totalMemory", demand.totalMemory), ("appMemory", demand.appMemory),
            ("pressure", demand.pressure), ("pressureHistory", demand.pressureHistory),
            ("power", demand.power), ("cpuTemperature", demand.cpuTemperature),
            ("gpuTemperature", demand.gpuTemperature), ("fans", demand.fans),
            ("battery", demand.battery), ("batteryTemperature", demand.batteryTemperature),
            ("batteryPower", demand.batteryPower)]
        return Set(choices.compactMap { $0.1 ? $0.0 : nil })
    }

    static func monitoring() {
        let disabled = disabledSelection()
        func demand(_ pins: Set<HUDMenuBarReading>, selection: HUDLogSelection = disabledSelection(),
                    enabled: Bool = false, visible: Bool = false, recording: Set<HUDLogColumn> = [],
                    collapsed: Bool = false, autoHide: HUDAutoHideMode = .off) -> HUDMonitoringDemand {
            HUDMonitoringDemand.make(hudEnabled: enabled, hudVisible: visible, recordingColumns: recording,
                autoHideMode: autoHide, selection: selection,
                menuBar: .init(readings: pins, isCollapsed: collapsed))
        }
        check(activeCollectors(demand([])).isEmpty, "A disabled overlay with no pins stops all collectors")
        let expected: [(HUDMenuBarReading, Set<String>)] = [
            (.fps, ["fps"]), (.gpuPower, ["power"]), (.gpuTemperature, ["gpuTemperature"]),
            (.gpuUsage, ["gpuUsage"]), (.cpuPower, ["power"]), (.cpuTemperature, ["cpuTemperature"]),
            (.cpuUsage, ["cpuUsage"]), (.cpuCores, ["cpuCoreLoad", "power"]), (.gpuCores, ["power"]),
            (.anePower, ["power"]), (.socPower, ["power"]),
            (.memoryPressure, ["pressure"]), (.memoryDetails, ["totalMemory"]),
            (.memoryUsage, ["totalMemory"]), (.fanUsage, ["fans"]),
            (.batteryPower, ["battery", "batteryPower"]),
            (.batteryTemperature, ["battery", "batteryTemperature"]), (.batteryEnergy, ["battery"])]
        check(Set(expected.map(\.0)) == Set(HUDMenuBarReading.allCases), "Every selectable pin has a collector expectation")
        for (pin, collectors) in expected {
            check(activeCollectors(demand([pin])) == collectors,
                  "Only necessary collectors run for a pinned \(pin.rawValue) with the HUD disabled")
            check(activeCollectors(demand([pin], enabled: true, visible: false)) == collectors,
                  "An automatically hidden overlay does not stop a pinned \(pin.rawValue)")
            check(activeCollectors(demand([pin], collapsed: true)).isEmpty,
                  "Collapsing a lone \(pin.rawValue) suspends sampling while retaining its selection")
        }
        var coreSelection = disabled
        coreSelection.cpuCores.mode = .bars
        check(activeCollectors(demand([.cpuCores], selection: coreSelection)) == ["cpuCoreLoad"],
              "Pinning CPU Load alone needs no power helper")
        coreSelection.cpuCores.mode = .value
        check(activeCollectors(demand([.cpuCores], selection: coreSelection)) == ["power"],
              "Pinning CPU GHz alone needs no per-core load sampler")
        for mode in HUDBatteryFlowMode.allCases {
            var batterySelection = disabled
            batterySelection.battery.flowMode = mode
            let collectors: Set<String> = mode == .off ? [] : ["battery", "batteryPower"]
            check(activeCollectors(demand([.batteryPower], selection: batterySelection)) == collectors,
                  "Pinned Charge in \(mode.rawValue) requests only the monitoring it needs; idle Auto can detect returning flow")
            if mode == .off {
                check(activeCollectors(demand([.batteryPower, .batteryTemperature], selection: batterySelection))
                      == ["battery", "batteryTemperature"],
                      "Charge Off never requests power while another pinned battery reading remains monitored")
                check(activeCollectors(demand([.batteryPower, .batteryEnergy], selection: batterySelection)) == ["battery"],
                      "Charge Off preserves Energy monitoring without adding power sampling")
                batterySelection.battery.enabled = true
                check(activeCollectors(demand([.batteryPower], selection: batterySelection, enabled: true, visible: true))
                      == ["battery"],
                      "An Off Charge pin does not stop battery monitoring still needed by the visible overlay")
            }
        }
        var selection = disabled
        selection.resources[.cpu]?.enabled = true
        selection.resources[.cpu]?.temperature = true
        check(activeCollectors(demand([.gpuTemperature], selection: selection, enabled: true, visible: true))
              == ["cpuTemperature", "gpuTemperature"], "Visible overlay and menu-bar collector demands form a union")
        check(activeCollectors(demand([.gpuTemperature], selection: selection, enabled: true, visible: true, collapsed: true))
              == ["cpuTemperature"], "Global collapse leaves visible overlay sampling active")
        check(activeCollectors(demand([], selection: selection, enabled: true, recording: [.cpuTemperature])) == ["cpuTemperature"],
              "Logging continues its overlay collector while the overlay is automatically hidden")
        check(activeCollectors(demand([.gpuUsage], selection: selection, recording: [.cpuTemperature]))
              == ["cpuTemperature", "gpuUsage"], "Disabling the HUD keeps only recorded and pinned readings active")
        check(activeCollectors(demand([], selection: selection, recording: [.memoryPressure], autoHide: .all))
              == ["pressure"], "CSV pressure needs its state only; a disabled HUD needs no wake-up detector")
        check(activeCollectors(demand([], selection: selection)).isEmpty, "Stopping recording releases its last collector")
        let miscLog = demand([], recording: [.resolutionWidth, .resolutionHeight, .thermal, .os])
        check(activeCollectors(miscLog) == ["fps"] && Set(miscLog.misc.visibleReadings) == [.resolution, .thermal],
              "Resolution uses the frame collector; static OS information starts no collectors")
        let coreAndFanLog = demand([], recording: [.gpuFrequency, .cpuTypeFrequency("Super"), .fanRPM(0), .cpuCores])
        check(activeCollectors(coreAndFanLog) == ["power", "fans"], "Frequency, fan RPM, and static core counts request only their sources")
        check(activeCollectors(demand([], enabled: true, autoHide: .all)) == ["fps"],
              "All auto hide retains the FPS detector needed to restore the overlay")
        check(activeCollectors(demand([], autoHide: .all)).isEmpty,
              "Disabling the overlay stops its auto-hide detector when no FPS pin needs it")
        for mode in HUDUsageMode.allCases {
            selection = disabled
            for group in [HUDResourceGroup.cpu, .gpu, .ram] { selection.resources[group]?.usageMode = mode }
            let totalOnly: Set<String> = ["gpuUsage", "cpuUsage", "totalMemory"]
            let expected = totalOnly
            check(activeCollectors(demand([.gpuUsage, .cpuUsage, .memoryUsage], selection: selection)) == expected,
                  "Pinned Use remains system-wide despite a legacy \(mode.rawValue) setting")
            check(activeCollectors(demand([.memoryPressure], selection: selection)) == ["pressure"],
                  "System pressure remains independently pinnable even when memory Use is App-only")
        }
        for mode in HUDMemoryPressureMode.allCases {
            selection = disabled
            selection.resources[.ram]?.enabled = true
            selection.resources[.ram]?.pressure = true
            selection.resources[.ram]?.pressureMode = mode
            let overlay = demand([], selection: selection, enabled: true, visible: true)
            check(overlay.pressure && overlay.pressureHistory == mode.isHistory,
                  "Visible vertical overlay alone requests pressure history for B styles")
            check(demand([.memoryPressure], selection: selection, enabled: true, visible: true).pressureHistory == mode.isHistory,
                  "Pinning pressure preserves the Vertical HUD's requested history")
            selection.alignment = .horizontal
            check(!demand([], selection: selection, enabled: true, visible: true).pressureHistory,
                  "The Horizontal HUD alone keeps using pressure meters")
            check(!demand([.memoryPressure], selection: selection, enabled: true, visible: true).pressureHistory,
                  "The meter pin only needs the current pressure state in Horizontal")
            check(activeCollectors(demand([.memoryPressure], selection: selection)) == ["pressure"],
                  "A pressure pin alone samples only the state")
            check(!demand([.memoryPressure], selection: selection, collapsed: true).pressureHistory,
                  "Collapsed pins do not request history when the HUD is off")
        }
        selection = disabled
        selection.misc = .init(enabled: true, readings: [.resolution])
        let resolution = demand([], selection: selection, enabled: true, visible: true)
        check(resolution.fps && resolution.misc.visibleReadings == [.resolution],
              "Vertical overlay resolution retains its existing FPS dependency")
        selection.alignment = .horizontal
        let horizontal = demand([], selection: selection, enabled: true, visible: true)
        check(!horizontal.fps && horizontal.misc.visibleReadings.isEmpty,
              "Horizontal-only output does not start unsupported Misc collectors")
    }

    @MainActor static func categoryControls() {
        let defaults = UserDefaults.standard
        let processDomain = ProcessInfo.processInfo.processName
        check(processDomain != "PerformanceHUD", "Native-control tests use their own defaults domain")
        let original = defaults.persistentDomain(forName: processDomain)
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer {
            if let original { defaults.setPersistentDomain(original, forName: processDomain) }
            else { defaults.removePersistentDomain(forName: processDomain) }
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        }
        defaults.removePersistentDomain(forName: processDomain)
        defaults.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
        HUDMenuBarOptions().save()
        let off = HUDResourceOptions(enabled: false, temperature: false, totalUse: false,
                                     focusedApp: false, power: false, details: false, pressure: false)
        let gpu = HUDResourceMenuView(group: .gpu, options: off)
        gpu.layoutSubtreeIfNeeded()
        let pins = gpu.subviews.compactMap { $0 as? HUDMenuBarButton }
        check(pins.count == 4 && pins.allSatisfy { $0.isEnabled && $0.state == .off },
              "GPU pins default off and are available with its entire overlay category disabled")
        let temperature = pins.first { $0.accessibilityLabel() == "Show GPU Temperature in menu bar" }!
        let controls: [Int: NSButton] = member(gpu, "controls")
        let checkbox = controls[1] as! HUDReadingCheckbox
        var overlayChanged = false
        var pinChanged = false
        gpu.onChange = { _ in overlayChanged = true }
        gpu.onMenuBarChange = { pinChanged = true }
        let savedBeforeRejection = HUDPreferences.menuBarOptions
        let presetBeforeRejection = HUDPresetConfiguration.capture()
        var checkedCandidates: [Set<HUDMenuBarReading>] = []
        gpu.shouldAllowMenuBarSelection = { candidate in
            checkedCandidates.append(candidate)
            return false
        }
        temperature.performClick(nil)
        check(checkedCandidates == [[.gpuTemperature]] && temperature.state == .off,
              "A rejected pin checks the complete proposed selection and restores its off button")
        check(!pinChanged && !overlayChanged && HUDPreferences.menuBarOptions == savedBeforeRejection
              && HUDPresetConfiguration.capture() == presetBeforeRejection,
              "Rejecting an oversized selection leaves saved readings, collapse, and preset state untouched")
        gpu.shouldAllowMenuBarSelection = { candidate in
            checkedCandidates.append(candidate)
            return true
        }
        temperature.performClick(nil)
        check(pinChanged && !overlayChanged && HUDPreferences.menuBarOptions.readings == [.gpuTemperature],
              "Pinning a temperature changes menu-bar selection without changing overlay options")
        check(controls[0]!.state == .off && checkbox.state == .off && !checkbox.isEnabled,
              "Pinning leaves the category and reading checkboxes off")
        check(checkbox.emphasisControl?.isEnabled == true,
              "A pinned temperature can use shared emphasis while its overlay reading stays hidden")
        var updated = off
        gpu.onChange = { updated = $0 }
        checkbox.emphasisControl!.performClick(nil)
        check(!updated.enabled && !updated.temperature && updated.highlighted.contains(.temperature),
              "Changing the B button for a pin never enables its hidden overlay reading")
        for pin in pins {
            check(pin.frame.minX == HUDCategoryLayout.menuBarLeading && pin.frame.size == NSSize(width: 22, height: 22),
                  "Menu-bar controls share one column and the B button's exact dimensions")
            for sibling in gpu.subviews where sibling !== pin {
                check(!pin.frame.intersects(sibling.frame), "Menu-bar control cannot overlap another setting")
            }
        }
        var collapsed = HUDPreferences.menuBarOptions
        collapsed.isCollapsed = true
        HUDPreferences.menuBarOptions = collapsed
        gpu.shouldAllowMenuBarSelection = { _ in
            preconditionFailure("Removing a pin must never be vetoed by a width check")
        }
        temperature.performClick(nil)
        check(HUDPreferences.menuBarOptions.readings.isEmpty && HUDPreferences.menuBarOptions.isCollapsed,
              "Toggling an individual pin preserves the global collapsed state")
        gpu.shouldAllowMenuBarSelection = { _ in false }
        let collapsedPreset = HUDPresetConfiguration.capture()
        temperature.performClick(nil)
        check(temperature.state == .off && HUDPreferences.menuBarOptions.isCollapsed
              && HUDPresetConfiguration.capture() == collapsedPreset,
              "A rejected pin remains off while collapsed and does not disturb the saved preset")

        let fps = HUDFPSMenuView(options: .init(enabled: false, mode: .history), alignment: .vertical)
        let fpsPin = fps.subviews.compactMap { $0 as? HUDMenuBarButton }.first!
        check(fpsPin.isEnabled && fpsPin.state == .off, "FPS pin remains available with overlay FPS off")
        fpsPin.performClick(nil)
        let fpsBold: HUDEmphasisButton = member(fps, "valueHighlight")
        check(fpsBold.isEnabled, "Menu-bar FPS value supports emphasis when overlay mode is history")
        let fpsOptions: HUDFPSOptions = member(fps, "options")
        check(!fpsOptions.enabled && fpsOptions.mode == .history,
              "A menu-bar FPS pin does not change the remembered overlay mode")

        let memory = HUDResourceMenuView(group: .ram, options: off)
        let detailsPin = memory.subviews.compactMap { $0 as? HUDMenuBarButton }
            .first { $0.accessibilityLabel() == "Show Memory Details in menu bar" }!
        let memoryControls: [Int: NSButton] = member(memory, "controls")
        let details = memoryControls[5] as! HUDReadingCheckbox
        detailsPin.performClick(nil)
        check(details.emphasisControl?.isEnabled == true, "Pinned system Details can be emphasized with the HUD off")
        detailsPin.performClick(nil)
        check(details.emphasisControl?.isEnabled == false, "Removing the pin restores inactive emphasis")
        memory.update(alignment: .horizontal)
        let pressurePin = memory.subviews.compactMap { $0 as? HUDMenuBarButton }
            .first { $0.accessibilityLabel() == "Show Memory Pressure in menu bar" }!
        let modes: NSSegmentedControl = member(memory, "pressureModeControl") as NSSegmentedControl?
            ?? { fatalError("Missing pressure selector") }()
        let color: HUDReadingCheckbox = member(memory, "pressureColorControl") as HUDReadingCheckbox?
            ?? { fatalError("Missing State color checkbox") }()
        check(!modes.isEnabled(forSegment: 2), "Unpinned Horizontal disables Graph")
        pressurePin.performClick(nil)
        check(modes.isEnabled && !modes.isEnabled(forSegment: 2) && modes.selectedSegment == 1 && color.isEnabled,
              "Pinned pressure uses Meter for a stored Graph in Horizontal")
        memory.update(alignment: .vertical)
        check(!modes.isEnabled(forSegment: 2) && modes.selectedSegment == 1,
              "When the pin is the only output, its controls reflect the meter")
        color.performClick(nil)
        let memoryOptions: HUDResourceOptions = member(memory, "options")
        check(memoryOptions.pressureMode == .history && !memoryOptions.enabled,
              "Changing a pinned graph's color preserves the hidden HUD category")
        check(memoryOptions.pressureMode.resolved(for: .horizontal) == .meter,
              "The Horizontal HUD retains its meter fallback")
        memory.update(alignment: .horizontal)
        pressurePin.performClick(nil)
        check(!modes.isEnabled(forSegment: 2) && modes.selectedSegment == 1 && !color.isEnabled,
              "Unpinning restores the Horizontal meter indication")

        for group in [HUDResourceGroup.gpu, .cpu] {
            let menu = HUDResourceMenuView(group: group, options: off)
            let pin = menu.subviews.compactMap { $0 as? HUDMenuBarButton }.first { $0.accessibilityLabel()?.contains("Cores") == true }!
            pin.performClick(nil)
            let controls: [Int: NSButton] = member(menu, "controls")
            let core = controls[9] as! HUDReadingCheckbox
            check(!core.isEnabled && HUDPreferences.menuBarOptions.readings.contains(group == .gpu ? .gpuCores : .cpuCores),
                  "A core pin works with its HUD category disabled")
            if group == .cpu {
                let selector: NSSegmentedControl = member(menu, "coreModeControl")
                check(selector.isEnabled, "A pinned CPU has access to its mode selector")
                selector.selectedSegment = 2
                selector.sendAction(selector.action, to: selector.target)
            }
            check(core.emphasisControl!.isEnabled, "A pinned frequency can use emphasis independently of the HUD")
            pin.performClick(nil)
        }

        let noFans = HUDFanMenuView(options: .init(enabled: true), sample: .noFans)
        check(noFans.subviews.compactMap { $0 as? HUDMenuBarButton }.allSatisfy { !$0.isEnabled },
              "A fanless Mac has no actionable fan pin")
        let ready = FanSample(status: .ready, fans: [.init(id: 0, rpm: 2200, maximumRPM: 5000)])
        let fan = HUDFanMenuView(options: .init(enabled: false, mode: .bar), sample: ready)
        let fanPin = fan.subviews.compactMap { $0 as? HUDMenuBarButton }.first!
        check(fanPin.isEnabled, "Detected fans can be pinned while the overlay fan category is off")
        fanPin.performClick(nil)
        let mode: NSSegmentedControl = member(fan, "mode")
        let rpmHighlight: NSButton = member(fan, "rpmHighlight")
        check(!mode.isEnabled && mode.selectedSegment == 0 && rpmHighlight.isEnabled,
              "Pinning enables RPM emphasis and preserves the disabled overlay's Bar selection")
        fan.update(sample: ready, options: .init(mode: .bar))
        check(mode.isEnabled && rpmHighlight.isEnabled, "An active Bar overlay can emphasize the pinned RPM")
        fanPin.performClick(nil)
        check(mode.isEnabled && !rpmHighlight.isEnabled, "Bar alone has no RPM to emphasize")
    }

    @MainActor static func presentation() {
        let configuration = HUDPresetConfiguration.builtIn(.balanced)
        var style = HUDMenuBarPresentation.Style(resources: configuration.resources,
            fpsHighlighted: true, packageHighlighted: false, fans: configuration.fans, battery: configuration.battery)
        var snapshot = HUDLogSnapshot()
        snapshot.set(.fps, 120)
        snapshot.set(.gpuPower, 9.9)
        snapshot.set(.gpuTemperature, 96)
        snapshot.set(.gpuUsage, 98)
        snapshot.setText(.memoryPressure, "warning")
        func sections(_ pins: Set<HUDMenuBarReading>, snapshot supplied: HUDLogSnapshot? = nil) -> [[HUDHorizontalView.Reading]] {
            HUDMenuBarPresentation.sections(snapshot: supplied ?? snapshot, fanSample: .noFans,
                readings: pins, style: style, background: .dark)
        }
        check(sections([]).isEmpty, "No pins produce no reading content")
        let fanSample = FanSample(status: .ready, fans: [
            FanReading(id: 0, rpm: 0, maximumRPM: 6000), FanReading(id: 1, rpm: 1000, maximumRPM: 6000)])
        for mode in HUDFanMode.allCases {
            var fanStyle = style
            for average in [false, true] {
                fanStyle.fans = .init(enabled: false, mode: mode, average: average)
                let sections = HUDMenuBarPresentation.sections(snapshot: snapshot, fanSample: fanSample,
                    readings: [.fanUsage], style: fanStyle, background: .dark)
                let items = sections.flatMap { $0 }
                check(items.compactMap(\.fanMarker) == (average ? ["A"] : ["1", "2"])
                      && items.compactMap(\.barWidth).isEmpty
                      && items.filter { $0.id.hasSuffix(".rpm") }.map(\.text) == (average ? ["500 RPM"] : ["0 RPM", "1000 RPM"]),
                      "Pinned fans always show the badge and RPM for individual or averaged readings")
                let strip = HUDHorizontalView(frame: .zero)
                _ = strip.configure(sections: sections, showsBattery: false, background: .dark, inMenuBar: true)
                let badges = strip.subviews.compactMap { $0 as? NSImageView }.map(\.frame)
                check(badges.count == (average ? 1 : 2) && Set(badges.map(\.midY)).count == 1
                      && Set(badges.map(\.minX)).count == badges.count, "Pinned fans occupy one horizontal line")
            }
        }
        for group in HUDResourceGroup.allCases { style.resources[group]?.enabled = false }
        snapshot.set(.memorySwap, 1.25)
        snapshot.set(.memoryPhysical, 16.75)
        snapshot.set(.memoryUsage, 68)
        check(sections([.memoryDetails]).flatMap { $0 }.map(\.text) == ["MEM", "SWP", "1.25 GB", "PHY", "16.75 GB"],
              "Pinned Memory details show Swap before Physical with the corresponding values")
        check(sections([.memoryDetails, .memoryUsage, .memoryPressure]).flatMap { $0 }.map(\.text)
              == ["MEM", "68%", "SWP", "1.25 GB", "PHY", "16.75 GB", "warning"],
              "Pinned Memory usage comes first, followed by Swap, Physical, and pressure")
        let types = [HUDCPUCoreType(name: "Super", count: 2), .init(name: "Performance", count: 1),
                     .init(name: "Efficiency", count: 1)]
        let topology = CPUCoreTopology(groups: [.init(name: "Super", ids: [2, 3]),
            .init(name: "Performance", ids: [1]), .init(name: "Efficiency", ids: [0])])
        var coreSnapshot = HUDLogSnapshot()
        coreSnapshot.set(.gpuFrequency, 0.9)
        coreSnapshot.set(.cpuTypeFrequency("Super"), 3.7)
        coreSnapshot.set(.cpuCoreUsage(3), 0)
        for mode in HUDCoreDisplayMode.allCases {
            style.cpuCores.mode = mode
            func coreSections(_ sample: HUDLogSnapshot) -> [[HUDHorizontalView.Reading]] {
                HUDMenuBarPresentation.sections(snapshot: sample, fanSample: .noFans,
                    readings: [.gpuCores, .cpuCores], style: style, background: .dark,
                    coreTypes: types, topology: topology)
            }
            let sections = coreSections(coreSnapshot)
            let readings = sections.flatMap { $0 }
            check(Array(readings.prefix(4)).map(\.text) == ["GPU", "C", "0.9 GHz", "CPU"],
                  "Core-only pins retain GPU and CPU headings in HUD order")
            if mode.showsBars {
                let rows = readings.last!.coreRows!
                check(rows.map(\.caption) == ["S", "P", "E"] && rows[0].activity == [nil, 0],
                      "Pinned CPU load respects physical core IDs and distinguishes zero from missing data")
                check(rows[0].frequency == (mode.showsValue ? "3.7 GHz" : nil), "Both adds the core frequency to Load")
            } else {
                check(readings.suffix(6).map(\.text) == ["S", "3.7 GHz", "P", "", "E", ""], "GHz-only pins use short captions and leave missing frequencies blank")
            }
            let view = HUDHorizontalView(frame: .zero)
            func size(_ sections: [[HUDHorizontalView.Reading]]) -> NSSize {
                view.configure(sections: sections, showsBattery: false, background: .dark, inMenuBar: true)
            }
            let pending = size(coreSections(.init()))
            let measured = size(sections)
            check(measured == pending, "Core pins reserve their full size before the first sample")
            let bars = view.subviews.compactMap { $0 as? HUDCPUCoreBarsView }
            check(bars.count == (mode.showsBars ? 3 : 0) && bars.allSatisfy { $0.frame.minY >= 0 && $0.frame.maxY <= measured.height }
                  && Set(bars.map { $0.frame.minX }).count == bars.count,
                  "Three core types fit at native height in separate menu-bar columns")
        }
        let pins: Set<HUDMenuBarReading> = [.fps, .gpuPower, .gpuTemperature, .gpuUsage]
        let readings = sections(pins).flatMap { $0 }
        check(readings.map(\.text) == ["FPS", "120", "GPU", "9.9 W", "96°C", "98%"],
              "Menu readings retain horizontal order, labels, precision, and units with all overlay categories off")
        check(readings.first { $0.text == "96°C" }?.color == NSColor.systemRed,
              "Pinned temperatures retain the enabled heat warning threshold")
        for (temperature, rendered, red) in [(94.49, "94°C", false), (94.5, "95°C", true)] {
            var precise = snapshot
            precise.set(.gpuTemperature, temperature)
            let reading = sections([.gpuTemperature], snapshot: precise).flatMap { $0 }.last!
            check(reading.text == rendered && (reading.color == .systemRed) == red,
                  "A temperature is rounded once from the raw sample, including the heat-warning boundary")
        }
        check(readings.filter { $0.metric == .fpsGraph }.isEmpty,
              "The FPS pin always produces a value, never a history graph")
        let view = HUDHorizontalView(frame: .zero)
        let nativeSize = view.configure(sections: sections(pins), showsBattery: false, background: .dark)
        style.fpsMeasure = .frameTime
        let frameTimeSize = view.configure(sections: sections(pins), showsBattery: false, background: .dark)
        check(frameTimeSize == nativeSize, "Switching between FPS and FT keeps neighboring pins in place")
        style.fpsMeasure = .frameRate
        _ = view.configure(sections: sections(pins), showsBattery: false, background: .dark)
        let labels: [String: NSTextField] = member(view, "labels")
        check(labels["fps.value"]?.font == HUDStyle.fpsValueFont(highlighted: true),
              "FPS keeps the original horizontal HUD emphasis and font size before the uniform transform")
        let gpuID = String(HUDMetric.gpuTotal.rawValue)
        for role in ["power", "temperature", "value"] {
            check(labels["\(gpuID).\(role)"]?.font == HUDStyle.readingFont(highlighted: false),
                  "GPU reading fonts remain unchanged before the single size transform")
        }
        for barHeight: CGFloat in [18, 22, 24, 32] {
            let scaled = HUDMenuBarPresentation.scaledSize(nativeSize, menuBarHeight: barHeight)
            let xScale = scaled.width / nativeSize.width
            let yScale = scaled.height / nativeSize.height
            check(abs(xScale - yScale) < 0.0001 && xScale > 0 && xScale <= 1,
                  "Menu-bar fitting scales width and height uniformly, preserving the complete horizontal proportions")
            check(scaled.height <= barHeight - 4, "Fitted readings leave room within the native menu-bar height")
        }
        for value in [9.0, 99.0, 100.0, 999.0] {
            var changed = snapshot
            changed.set(.fps, value)
            changed.set(.gpuPower, value / 10)
            let newSize = view.configure(sections: sections(pins, snapshot: changed), showsBattery: false,
                                         background: .dark)
            check(newSize == nativeSize, "Ordinary digit changes never move the status item's neighboring icons")
        }
        let missing = sections(pins, snapshot: HUDLogSnapshot()).flatMap { $0 }
        check(missing.filter { !$0.startsMetric }.allSatisfy { $0.text == "" },
              "Missing menu-bar readings keep an empty value slot")
        for mode in HUDMemoryPressureMode.allCases {
            style.resources[.ram]?.pressureMode = mode
            style.resources[.ram]?.usageMode = .app
            let pressure = sections([.memoryPressure]).flatMap { $0 }
            check(pressure.map(\.text) == ["MEM", "warning"],
                  "Pressure pin retains system context while the overlay's memory source is App")
            check(pressure.last?.pressureMode == mode.resolved(for: .horizontal),
                  "The menu-bar pressure pin uses the Horizontal display and selected color")
            if mode.display == .text {
                check(pressure.last?.color == (mode.usesStateColor ? HUDStyle.warningYellow : HUDStyle.readingColor(background: .dark)),
                      "Pinned text uses the selected state color")
            }
        }
        style.battery.enabled = false
        style.battery.temperature = false
        style.battery.charge = false
        style.battery.flowMode = .off
        let powerOnly = HUDMenuBarPresentation.batteryOptions(readings: [.batteryPower], style: style)
        check(!powerOnly.power && powerOnly.flowMode == .off && !powerOnly.temperature && !powerOnly.charge,
              "A pinned Charge reading respects Off without substituting Auto or adding other battery readings")
        style.battery.flowMode = .auto
        let autoPowerOnly = HUDMenuBarPresentation.batteryOptions(readings: [.batteryPower], style: style)
        check(autoPowerOnly.enabled && autoPowerOnly.power && !autoPowerOnly.temperature && !autoPowerOnly.charge,
              "A Charge pin in Auto works while the overlay battery category is disabled")
        let temperatureOnly = HUDMenuBarPresentation.batteryOptions(readings: [.batteryTemperature], style: style)
        check(temperatureOnly.enabled && temperatureOnly.temperature && !temperatureOnly.power && !temperatureOnly.charge,
              "A temperature-only battery pin preserves the horizontal reading selection")
        check(!HUDMenuBarPresentation.batteryOptions(readings: [], style: style).enabled,
              "Unpinned battery options never leak into the menu bar")
    }

    @MainActor static func nativeStatusControl() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let menu = NSMenu(title: "Menu-bar test")
        menu.addItem(withTitle: "Test", action: nil, keyEquivalent: "")
        item.menu = menu
        var collapsedClicks = 0
        let controller = HUDMenuBarController(statusItem: item, onToggleCollapsed: { collapsedClicks += 1 })
        let options = HUDMenuBarOptions(readings: [.gpuTemperature])
        controller.refresh(snapshot: HUDLogSnapshot(), fanSample: .noFans, batterySample: nil, options: options)
        let button = item.button!
        // Native status-item sizing normally happens on the AppKit run loop.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        let chevron = button.subviews.compactMap { $0 as? NSButton }.first!
        let bolt: NSImageView = member(controller, "bolt")
        let content: NSView = member(controller, "content")
        check(chevron.isHidden && bolt.isHidden && button.image == nil && !content.isHidden,
              "Expanded pins show just the selected readings")
        check(abs(item.length - content.frame.width - 2 * content.frame.minX) < 0.01,
              "The native item reserves only the reading width and its two existing margins")
        let insideReading = NSPoint(x: content.frame.midX, y: button.bounds.midY)
        check(button.hitTest(insideReading) === button && item.menu === menu,
              "Clicking a reading opens the settings menu")
        var collapsed = options
        collapsed.isCollapsed = true
        controller.refresh(snapshot: HUDLogSnapshot(), fanSample: .noFans, batterySample: nil, options: collapsed)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        check(item.length == 40 && content.isHidden && !bolt.isHidden && !chevron.isHidden
              && button.image == nil && chevron.accessibilityLabel() == "Show menu-bar readings",
              "Unchecking Show menu-bar readings keeps the expand arrow and bolt")
        check(button.hitTest(NSPoint(x: chevron.frame.midX, y: chevron.frame.midY)) === chevron
              && button.hitTest(NSPoint(x: bolt.frame.midX, y: bolt.frame.midY)) === button,
              "The left arrow expands while the bolt opens settings")
        chevron.performClick(nil)
        check(collapsedClicks == 1 && item.menu === menu, "The expand arrow invokes the global action")
        controller.refresh(snapshot: HUDLogSnapshot(), fanSample: .noFans, batterySample: nil, options: options)
        check(!content.isHidden && bolt.isHidden && chevron.isHidden && button.image == nil,
              "Expanding shows just the readings again")
        controller.refresh(snapshot: HUDLogSnapshot(), fanSample: .noFans, batterySample: nil, options: .init())
        check(item.length == NSStatusItem.squareLength && button.image != nil && item.menu === menu,
              "Removing the last pin restores the original bolt-only status item")
    }

    @MainActor static func widthSafety() {
        let defaults = UserDefaults.standard
        let processDomain = ProcessInfo.processInfo.processName
        let original = defaults.persistentDomain(forName: processDomain)
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer {
            if let original { defaults.setPersistentDomain(original, forName: processDomain) }
            else { defaults.removePersistentDomain(forName: processDomain) }
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        }
        defaults.removePersistentDomain(forName: processDomain)
        defaults.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
        HUDPresetConfiguration.builtIn(.balanced).apply()

        check(HUDMenuBarPresentation.widthLimit(availableWidth: 1440) == 360,
              "Large screens retain a conservative 360-point menu-bar width budget")
        check(HUDMenuBarPresentation.widthLimit(availableWidth: 601) == 300,
              "Smaller menu-bar regions reserve at least half their width for other items")
        check(HUDMenuBarPresentation.widthLimit(availableWidth: 70) == 40,
              "A very small region still has space for the collapse control and app icon")

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let menu = NSMenu(title: "Width safety test")
        item.menu = menu
        var widthBudget: CGFloat = 360
        var overflows = 0
        let controller = HUDMenuBarController(statusItem: item,
            widthLimitProvider: { widthBudget }, onToggleCollapsed: {})
        controller.onWidthOverflow = { overflows += 1 }
        let pins: Set<HUDMenuBarReading> = [.gpuTemperature]
        let options = HUDMenuBarOptions(readings: pins)
        var snapshot = HUDLogSnapshot()
        snapshot.set(.gpuTemperature, 72)
        func refresh(_ selected: HUDMenuBarOptions = options, battery: BatterySample? = nil) {
            controller.refresh(snapshot: snapshot, fanSample: .noFans, batterySample: battery, options: selected)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        func waitForOverflow(after count: Int) {
            // Overflow is reported asynchronously. Wait for that event rather
            // than assuming WindowServer/main-queue work always fits in 20 ms.
            let deadline = Date(timeIntervalSinceNow: 1)
            while overflows <= count && Date() < deadline {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
            }
        }
        refresh()
        let measured = controller.expandedWidth(for: pins)
        let content: NSView = member(controller, "content")
        let ordinaryFrame = content.frame
        let ordinaryBounds = content.bounds
        check(measured > 40 && measured < widthBudget && abs(item.length - measured) < 0.01,
              "Selection preflight measures the readings and their padding")
        for allowedWidth in [measured + 0.5, measured] {
            widthBudget = allowedWidth
            refresh()
            check(!content.isHidden && abs(item.length - measured) < 0.01 && overflows == 0,
                  "Readings below or exactly at the budget remain fully expanded")
            check(content.frame == ordinaryFrame && content.bounds == ordinaryBounds,
                  "The width safeguard never changes the existing horizontal proportions to make content fit")
        }
        widthBudget = measured - 0.5
        refresh()
        waitForOverflow(after: 0)
        let collapse = item.button!.subviews.compactMap { $0 as? NSButton }.first!
        check(item.length == 40 && content.isHidden && overflows > 0 && item.menu === menu,
              "An expanded reading that no longer fits collapses safely and reports overflow without losing settings access: length=\(item.length), hidden=\(content.isHidden), callbacks=\(overflows), menu=\(item.menu === menu)")
        check(collapse.accessibilityLabel() == "Show menu-bar readings",
              "Automatic overflow fallback shows the same accessible expand control as manual collapse")

        widthBudget = 360
        refresh()
        check(!content.isHidden && item.length == measured,
              "A fitting selection can expand again with its original proportions")
        let beforeOversizedPreset = overflows
        refresh(.init(readings: Set(HUDMenuBarReading.allCases)))
        waitForOverflow(after: beforeOversizedPreset)
        check(item.length == 40 && content.isHidden && overflows > beforeOversizedPreset,
              "Oversized selections loaded from a saved preset use the same safe collapsed fallback")
        let beforeManualCollapse = overflows
        refresh(.init(readings: Set(HUDMenuBarReading.allCases), isCollapsed: true))
        check(item.length == 40 && overflows == beforeManualCollapse,
              "An explicitly collapsed selection does not trigger an unnecessary overflow warning")

        var batteryOptions = HUDPreferences.batteryOptions
        batteryOptions.flowMode = .auto
        HUDPreferences.setBatteryOptions(batteryOptions)
        let batteryPins: Set<HUDMenuBarReading> = [.batteryPower, .batteryTemperature]
        let idleBattery = BatterySample(percentage: 80, source: .powerAdapter, temperature: 34, power: 0)
        let activeBattery = BatterySample(percentage: 80, source: .powerAdapter, temperature: 34, power: 12)
        refresh(.init(readings: batteryPins), battery: idleBattery)
        let autoReserved = controller.expandedWidth(for: batteryPins)
        let idleWidth = item.length
        batteryOptions.flowMode = .always
        HUDPreferences.setBatteryOptions(batteryOptions)
        let alwaysReserved = controller.expandedWidth(for: batteryPins)
        check(autoReserved == alwaysReserved && autoReserved >= idleWidth,
              "Preflight reserves the full Charge column even while Auto currently hides its idle reading")
        batteryOptions.flowMode = .auto
        HUDPreferences.setBatteryOptions(batteryOptions)
        widthBudget = autoReserved
        refresh(.init(readings: batteryPins), battery: activeBattery)
        check(!content.isHidden && item.length <= widthBudget,
              "Auto Charge becoming active stays within the width reserved when it was selected")
    }

    @MainActor static func fpsMenuAutoHide() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let controller = HUDMenuBarController(statusItem: item, widthLimitProvider: { 1000 }, onToggleCollapsed: {})
        let pins: Set<HUDMenuBarReading> = [.fps, .gpuPower, .gpuTemperature, .gpuUsage]
        let options = HUDMenuBarOptions(readings: pins)
        var snapshot = HUDLogSnapshot()
        snapshot.set(.fps, 120)
        snapshot.set(.gpuPower, 9.9)
        snapshot.set(.gpuTemperature, 72)
        snapshot.set(.gpuUsage, 98)
        func refresh(_ mode: HUDAutoHideMode, available: Bool, selected: HUDMenuBarOptions = options) {
            controller.refresh(snapshot: snapshot, fanSample: .noFans, batterySample: nil,
                options: selected, fpsExpanded: available, autoHideMode: mode)
        }
        refresh(.fps, available: true)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        // NSTextField resolves its native metrics after joining the status-item
        // window. Compare settled layouts, not that initial attachment pass.
        refresh(.fps, available: true)
        let fullWidth = item.length
        let fullPreflight = controller.expandedWidth(for: pins)
        let horizontal: HUDHorizontalView = member(controller, "horizontal")
        let content: NSView = member(controller, "content")
        let arrow: NSImageView = member(controller, "collapsedFPSIndicator")
        let labels: [String: NSTextField] = member(horizontal, "labels")
        let gpuID = String(HUDMetric.gpuTotal.rawValue)
        let gpuLabels = ["power", "temperature", "value"].map { labels["\(gpuID).\($0)"]! }
        let gpuFrames = gpuLabels.map(\.frame)
        let gpuFonts = gpuLabels.map(\.font)
        let fullScale = content.frame.width / content.bounds.width
        let fpsTitle = labels["\(HUDMetric.fps.rawValue).title"]!
        check(arrow.isHidden && fpsTitle.alphaValue == 1 && labels["fps.value"]!.alphaValue == 1,
              "Available FPS retains its ordinary horizontal label and value")
        refresh(.fps, available: false)
        check(item.length < fullWidth && !content.isHidden && !arrow.isHidden && arrow.image != nil,
              "FPS-only auto hide replaces unavailable menu-bar FPS with a compact arrow")
        check(fpsTitle.alphaValue == 0 && labels["fps.value"]!.alphaValue == 0,
              "Collapsed FPS leaves no title or value showing underneath its arrow")
        check(content.bounds.contains(arrow.frame) && arrow.frame.width == 12,
              "The FPS arrow fits its original horizontal HUD slot before uniform scaling")
        let pixel = horizontal.convertFromBacking(NSSize(width: 1, height: 1)).width
        for (label, expanded) in zip(gpuLabels, gpuFrames) {
            let frame = label.frame
            check(abs(frame.width - expanded.width) < 0.0001 && abs(frame.height - expanded.height) < 0.0001
                  && abs(frame.minX - expanded.minX) <= pixel && abs(frame.minY - expanded.minY) <= pixel,
                  "Collapsing FPS preserves column sizes and only shifts their local positions for pixel alignment")
            let pixels = horizontal.convertToBacking(frame)
            for edge in [pixels.minX, pixels.maxX, pixels.minY, pixels.maxY] {
                check(abs(edge.rounded() - edge) < 0.0001, "Pinned GPU text aligns to backing pixels")
            }
        }
        check(gpuLabels.map(\.font) == gpuFonts && gpuLabels.allSatisfy { !$0.isHidden && $0.alphaValue == 1 },
              "Collapsing FPS preserves neighboring fonts and visibility")
        check(abs(content.frame.width / content.bounds.width - fullScale) < 0.0001
              && abs(content.frame.height / content.bounds.height - fullScale) < 0.0001,
              "The compact FPS arrow changes only occupied width, never the menu-bar scaling")
        check(controller.expandedWidth(for: pins) == fullPreflight,
              "Width preflight continues reserving full FPS width while the arrow is shown")
        for mode in [HUDAutoHideMode.off, .all] {
            refresh(mode, available: false)
            check(item.length == fullWidth && arrow.isHidden && !content.isHidden
                  && fpsTitle.alphaValue == 1 && labels["fps.value"]!.alphaValue == 1,
                  "\(mode.rawValue) does not auto-hide menu-bar FPS or the other menu-bar readings")
        }
        refresh(.fps, available: false)
        refresh(.fps, available: true)
        check(item.length == fullWidth && arrow.isHidden && labels["fps.value"]!.alphaValue == 1,
              "A returning FPS sample restores the full category and hides its arrow")
        refresh(.fps, available: false, selected: .init(readings: [.fps]))
        check(item.length == NSStatusItem.squareLength && item.button?.image != nil && arrow.isHidden && content.isHidden,
              "FPS alone waits with the regular bolt and resumes automatically")
        let waiting: HUDMenuBarOptions = member(controller, "latestOptions")
        check(!waiting.isCollapsed && waiting.readings == [.fps],
              "Hiding the redundant FPS arrow keeps automatic return enabled and retains its selection")
        refresh(.fps, available: true, selected: .init(readings: [.fps]))
        check(item.length > 40 && arrow.isHidden && !content.isHidden,
              "FPS alone automatically returns at its original proportions when readings resume")
        refresh(.fps, available: false, selected: .init(readings: [.gpuTemperature]))
        check(arrow.isHidden && !content.isHidden,
              "FPS auto hide never adds an arrow when FPS is not selected for the menu bar")
    }

    @MainActor static func batteryChargeAutoHide() {
        let defaults = UserDefaults.standard
        let processDomain = ProcessInfo.processInfo.processName
        let original = defaults.persistentDomain(forName: processDomain)
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer {
            if let original { defaults.setPersistentDomain(original, forName: processDomain) }
            else { defaults.removePersistentDomain(forName: processDomain) }
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        }
        defaults.removePersistentDomain(forName: processDomain)
        defaults.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
        let savedOptions = HUDMenuBarOptions(readings: [.batteryPower])
        savedOptions.save()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let controller = HUDMenuBarController(statusItem: item, widthLimitProvider: { 1000 }, onToggleCollapsed: {})
        var snapshot = HUDLogSnapshot()
        snapshot.set(.gpuTemperature, 72)
        snapshot.set(.fps, 120)
        func refresh(_ pins: Set<HUDMenuBarReading>, mode: HUDBatteryFlowMode = .auto,
                     power: Double? = 0, samplePresent: Bool = true, fpsAvailable: Bool = true,
                     autoHide: HUDAutoHideMode = .off) {
            HUDPreferences.setBatteryOptions(.init(enabled: false, temperature: false, charge: false, flowMode: mode))
            let sample: BatterySample? = samplePresent
                ? .init(percentage: 80, source: .powerAdapter, temperature: 34, power: power) : nil
            controller.refresh(snapshot: snapshot, fanSample: .noFans, batterySample: sample,
                options: .init(readings: pins), fpsExpanded: fpsAvailable, autoHideMode: autoHide)
        }
        refresh([.gpuTemperature])
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        refresh([.gpuTemperature])
        let horizontal: HUDHorizontalView = member(controller, "horizontal")
        let content: NSView = member(controller, "content")
        let arrow: NSImageView = member(controller, "collapsedFPSIndicator")
        let labels: [String: NSTextField] = member(horizontal, "labels")
        let gpuLabel = labels["\(HUDMetric.gpuTotal.rawValue).temperature"]!
        let gpuFrame = gpuLabel.frame
        let gpuWidth = item.length
        let fullScale = content.frame.width / content.bounds.width
        func visibleDividerCount() -> Int {
            let dividers: [NSView] = member(horizontal, "dividers")
            return dividers.filter { !$0.isHidden }.count
        }
        let gpuDividers = visibleDividerCount()
        for mode in [HUDBatteryFlowMode.auto, .off] {
            refresh([.gpuTemperature, .batteryPower], mode: mode)
            check(item.length == gpuWidth && horizontal.battery.isHidden && visibleDividerCount() == gpuDividers,
                  "Idle or Off Charge leaves no battery source, divider, or space beside other menu readings")
            check(gpuLabel.frame == gpuFrame && !gpuLabel.isHidden
                  && abs(content.frame.width / content.bounds.width - fullScale) < 0.0001,
                  "Removing an empty Charge category preserves the neighboring GPU proportions (frame \(gpuLabel.frame), expected \(gpuFrame); hidden \(gpuLabel.isHidden); scale \(content.frame.width / content.bounds.width), expected \(fullScale))")
        }
        for mode in [HUDBatteryFlowMode.auto, .off] {
            refresh([.batteryPower], mode: mode)
            check(item.length == NSStatusItem.squareLength && item.button?.image != nil && content.isHidden && horizontal.battery.isHidden && arrow.isHidden,
                  "A lone idle or Off Charge selection leaves just the regular bolt")
            if mode == .off {
                check(controller.expandedWidth(for: [.batteryPower]) == NSStatusBar.system.thickness,
                      "Charge Off does not reserve unused reading padding")
            }
        }
        refresh([.batteryPower], power: nil, samplePresent: false)
        check(item.length == NSStatusItem.squareLength && item.button?.image != nil && content.isHidden && horizontal.battery.isHidden,
              "Auto Charge with no battery sample does not leave a source-only or placeholder category")
        let autoReservation = controller.expandedWidth(for: [.batteryPower])
        check(autoReservation > 40, "Auto Charge reserves its returning active width even while entirely hidden")
        refresh([.batteryPower], power: 0.19)
        check(content.isHidden, "Auto Charge below its activation threshold remains hidden")
        refresh([.batteryPower], power: 0.2)
        let activeWidth = item.length
        check(activeWidth > 40 && !content.isHidden && !horizontal.battery.isHidden,
              "Auto Charge returns with its source and value when flow reaches the visibility threshold")
        check(activeWidth <= autoReservation, "Returning Charge stays within its previously reserved width")
        refresh([.batteryPower], power: 0.1)
        check(item.length == activeWidth && !content.isHidden,
              "Low flow keeps Charge visible at its measured width throughout the grace period")
        horizontal.battery.update(percentage: 80, source: .powerAdapter, temperature: 34, power: 0.2)
        horizontal.battery.update(percentage: 80, source: .powerAdapter, temperature: 34, power: 0.1,
                                  now: ProcessInfo.processInfo.systemUptime - 3.1)
        refresh([.batteryPower], power: 0.1)
        check(item.length == NSStatusItem.squareLength && item.button?.image != nil && content.isHidden && horizontal.battery.isHidden,
              "Charge and its source disappear together after the existing idle grace period expires")
        refresh([.batteryPower], mode: .always)
        check(!content.isHidden && !horizontal.battery.isHidden && horizontal.battery.powerText == "0.0 W",
              "Always keeps a zero-watt Charge category visible")
        check(controller.expandedWidth(for: [.batteryPower]) == autoReservation,
              "Idle Auto reserves the same width as an Always Charge category")
        refresh([.batteryPower], mode: .off, power: 12)
        check(item.length == NSStatusItem.squareLength && item.button?.image != nil && content.isHidden && !horizontal.battery.hasVisiblePowerFlow,
              "Off remains hidden even when a cached battery sample contains active flow")
        for reading in [HUDMenuBarReading.batteryTemperature, .batteryEnergy] {
            refresh([reading], mode: .off)
            let otherReadingWidth = item.length
            refresh([.batteryPower, reading], mode: .off)
            check(!content.isHidden && !horizontal.battery.isHidden && item.length == otherReadingWidth,
                  "An Off Charge pin preserves \(reading.rawValue) with no unused power column")
            refresh([.batteryPower, reading])
            check(!content.isHidden && !horizontal.battery.isHidden,
                  "Idle Auto Charge never removes another selected battery reading")
        }
        for mode in [HUDBatteryFlowMode.auto, .off] {
            refresh([.fps, .batteryPower], mode: mode, fpsAvailable: false, autoHide: .fps)
            check(item.length == NSStatusItem.squareLength && item.button?.image != nil && content.isHidden && arrow.isHidden,
                  "Waiting FPS plus an empty Charge category leave just the regular bolt")
            let fullReservation = controller.expandedWidth(for: [.fps, .batteryPower])
            refresh([.fps, .batteryPower], mode: mode, power: 12, autoHide: .fps)
            check(!content.isHidden && item.length > 40
                  && controller.expandedWidth(for: [.fps, .batteryPower]) == fullReservation,
                  "Returning readings restore themselves within the full FPS and Charge width reservation")
        }
        check(HUDPreferences.menuBarOptions == savedOptions,
              "Automatic Charge visibility never changes pin selections or the saved collapse state")
    }

    @MainActor static func hiddenOverlayRendering() {
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "off",
                                   "hud.alignment": "horizontal"], forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain) }
        let hud = HUDWindowController()
        defer { hud.shutdown() }
        let panel: HUDPanel = member(hud, "panel")
        panel.alphaValue = 0
        hud.setPackagePowerOptions(.init(enabled: false))
        for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: false) }
        hud.setResourceOptions(.init(enabled: true, temperature: true, totalUse: false, focusedApp: false), for: .gpu)
        let horizontal: HUDHorizontalView = member(hud, "horizontalView")
        let labels: [String: NSTextField] = member(horizontal, "labels")
        let temperature = labels["\(HUDMetric.gpuTotal.rawValue).temperature"]!
        let before = temperature.stringValue
        let frame = panel.frame
        hud.updateTemperatures(.init(cpu: nil, gpu: 88))
        check(temperature.stringValue == before && panel.frame == frame,
              "Menu-only sampling does not rebuild or resize the hidden horizontal overlay")
        hud.setHUDEnabled(true)
        check(temperature.stringValue == "88°C" && panel.alphaValue == 0,
              "Re-enabling the overlay presents its latest cached sample; the test fixture stays invisible")
        hud.setHUDEnabled(false)
        hud.updateTemperatures(.init(cpu: nil, gpu: 89))
        check(temperature.stringValue == "88°C", "Disabling the HUD pauses its rendering again")
        hud.setHUDEnabled(true)
        check(temperature.stringValue == "89°C", "A second reveal flushes cached updates without restarting view state")
        hud.setHUDEnabled(false)
        var availabilityChanges: [Bool] = []
        hud.onFPSAvailabilityChange = { availabilityChanges.append(hud.hasRecentFPSReading) }
        check(!hud.hasRecentFPSReading, "The shared FPS availability starts unavailable")
        hud.updateFPS(120)
        check(hud.hasRecentFPSReading && availabilityChanges == [true],
              "Menu-bar FPS availability updates while the overlay remains disabled")
        hud.updateFPS(121)
        hud.markFPSUnavailable()
        hud.markFPSUnavailable()
        check(hud.hasRecentFPSReading && availabilityChanges == [true],
              "Repeated samples and unavailable reports retain the existing grace period without duplicate callbacks")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: HUDFPSAvailability.collapseDelay + 0.2))
        check(!hud.hasRecentFPSReading && availabilityChanges == [true, false],
              "The shared FPS grace period expires and notifies the menu bar even with the overlay disabled")
        hud.onFPSAvailabilityChange = nil
    }

    @MainActor static func pressureMeterPresentation() {
        let configuration = HUDPresetConfiguration.builtIn(.balanced)
        var style = HUDMenuBarPresentation.Style(resources: configuration.resources,
            fpsHighlighted: true, packageHighlighted: false, fans: configuration.fans, battery: configuration.battery)
        for background in [HUDBackground.light, .dark] {
            let view = HUDHorizontalView(frame: .zero)
            var meterSize: NSSize?
            for mode in [HUDMemoryPressureMode.meter, .colorMeter, .history, .colorHistory] {
                style.resources[.ram]?.pressureMode = mode
                for (state, segments) in [("normal", 1), ("warning", 2), ("critical", 3), ("", 0)] {
                    var snapshot = HUDLogSnapshot()
                    snapshot.setText(.memoryPressure, state)
                    let sections = HUDMenuBarPresentation.sections(snapshot: snapshot, fanSample: .noFans,
                        readings: [.memoryPressure], style: style, background: background)
                    let size = view.configure(sections: sections, showsBattery: false, background: background)
                    let meters: [String: HUDMemoryPressureMeterView] = member(view, "pressureMeters")
                    let meter = meters["ram.pressure"]!
                    let display: HUDMemoryPressureMode = member(meter, "mode")
                    check(display == (mode.usesStateColor ? .colorMeter : .meter) && !meter.isHidden,
                          "Pinned Meter and Graph render the same meter and respect State color")
                    check(meter.activeSegmentCount == segments, "Pinned meter follows the current pressure state")
                    if let meterSize { check(size == meterSize, "Meter width is stable across styles and states") }
                    meterSize = size
                }
            }
        }
    }

    @MainActor static func main() {
        _ = NSApplication.shared
        persistence()
        monitoring()
        categoryControls()
        presentation()
        pressureMeterPresentation()
        nativeStatusControl()
        widthSafety()
        fpsMenuAutoHide()
        batteryChargeAutoHide()
        hiddenOverlayRendering()
        print("Menu-bar preference, monitoring, native-control, and proportion checks passed")
    }
}
