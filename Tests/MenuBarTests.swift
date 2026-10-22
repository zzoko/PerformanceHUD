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
            deviceInfo: false, alignment: .vertical)
    }

    static func persistence() {
        let suite = "PerformanceHUD.MenuBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fresh = HUDMenuBarOptions.load(in: defaults)
        check(fresh.readings.isEmpty && fresh.activeReadings.isEmpty,
              "Fresh installs and upgrades have no menu-bar readings selected")
        let selected = Set<HUDMenuBarReading>([.gpuTemperature, .memoryPressure, .fps])
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
            ("cpuUsage", demand.cpuUsage), ("cpuAppUsage", demand.cpuAppUsage),
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
                    enabled: Bool = false, visible: Bool = false, logging: Bool = false,
                    collapsed: Bool = false, autoHide: HUDAutoHideMode = .off) -> HUDMonitoringDemand {
            HUDMonitoringDemand.make(hudEnabled: enabled, hudVisible: visible, isLogging: logging,
                autoHideMode: autoHide, selection: selection,
                menuBar: .init(readings: pins, isCollapsed: collapsed))
        }
        check(activeCollectors(demand([])).isEmpty, "A disabled overlay with no pins stops all collectors")
        let expected: [(HUDMenuBarReading, Set<String>)] = [
            (.fps, ["fps"]), (.gpuPower, ["power"]), (.gpuTemperature, ["gpuTemperature"]),
            (.gpuUsage, ["gpuUsage"]), (.cpuPower, ["power"]), (.cpuTemperature, ["cpuTemperature"]),
            (.cpuUsage, ["cpuUsage"]), (.anePower, ["power"]), (.socPower, ["power"]),
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
        check(activeCollectors(demand([], selection: selection, enabled: true, logging: true)) == ["cpuTemperature"],
              "Logging continues its overlay collector while the overlay is automatically hidden")
        check(activeCollectors(demand([], selection: selection, logging: true)).isEmpty,
              "A disabled overlay cannot retain stale logging demand")
        check(activeCollectors(demand([], enabled: true, autoHide: .all)) == ["fps"],
              "All auto hide retains the FPS detector needed to restore the overlay")
        check(activeCollectors(demand([], autoHide: .all)).isEmpty,
              "Disabling the overlay stops its auto-hide detector when no FPS pin needs it")
        for mode in HUDUsageMode.allCases {
            selection = disabled
            for group in [HUDResourceGroup.cpu, .gpu, .ram] { selection.resources[group]?.usageMode = mode }
            let appOnly: Set<String> = ["gpuAppUsage", "cpuAppUsage", "appMemory"]
            let totalOnly: Set<String> = ["gpuUsage", "cpuUsage", "totalMemory"]
            let expected = mode == .app ? appOnly : mode == .total ? totalOnly : appOnly.union(totalOnly)
            check(activeCollectors(demand([.gpuUsage, .cpuUsage, .memoryUsage], selection: selection)) == expected,
                  "Pinned use follows shared \(mode.rawValue) source without enabling hidden overlay readings")
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
            selection.alignment = .horizontal
            check(!demand([.memoryPressure], selection: selection, enabled: true, visible: true).pressureHistory,
                  "Horizontal presentations never request history even when B is remembered")
            check(!demand([.memoryPressure], selection: selection).pressureHistory,
                  "Menu-bar pressure never requests B-style history data")
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
        check(pins.count == 3 && pins.allSatisfy { $0.isEnabled && $0.state == .off },
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
        let memoryMode: NSSegmentedControl = member(memory, "usageModeControl")
        let detailsPin = memory.subviews.compactMap { $0 as? HUDMenuBarButton }
            .first { $0.accessibilityLabel() == "Show MEM Details in menu bar" }!
        var memoryOptions = off
        memory.onChange = { memoryOptions = $0 }
        detailsPin.performClick(nil)
        check(memoryMode.isEnabled, "Pinned memory Details can change source while HUD memory and Use are off")
        memoryMode.selectedSegment = 1
        NSApp.sendAction(memoryMode.action!, to: memoryMode.target, from: memoryMode)
        check(memoryOptions.selectedUsageMode == .app && !memoryOptions.enabled && !memoryOptions.usageVisible,
              "Changing the source for pinned Details leaves HUD memory and Use off")
        detailsPin.performClick(nil)
        check(!memoryMode.isEnabled, "Removing the only memory pin restores the inactive mode control")

        let noFans = HUDFanMenuView(options: .init(enabled: true), sample: .noFans)
        check(noFans.subviews.compactMap { $0 as? HUDMenuBarButton }.allSatisfy { !$0.isEnabled },
              "A fanless Mac has no actionable fan pin")
        let ready = FanSample(status: .ready, fans: [.init(id: 0, rpm: 2200, maximumRPM: 5000)])
        let fan = HUDFanMenuView(options: .init(enabled: false), sample: ready)
        let fanPin = fan.subviews.compactMap { $0 as? HUDMenuBarButton }.first!
        check(fanPin.isEnabled, "Detected fans can be pinned while the overlay fan category is off")
        fanPin.performClick(nil)
        let mode: NSSegmentedControl = member(fan, "mode")
        check(mode.isEnabled, "Pinned fans retain access to the shared Bar/RPM/Both choice")
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
        for group in HUDResourceGroup.allCases { style.resources[group]?.enabled = false }
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
        let nativeSize = view.configure(sections: sections(pins), showsBattery: false, scale: .normal, background: .dark)
        let labels: [String: NSTextField] = member(view, "labels")
        check(labels["fps.value"]?.font == HUDStyle.fpsValueFont(scale: .normal, highlighted: true),
              "FPS keeps the original horizontal HUD emphasis and font size before the uniform transform")
        let gpuID = String(HUDMetric.gpuTotal.rawValue)
        for role in ["power", "temperature", "value"] {
            check(labels["\(gpuID).\(role)"]?.font == HUDStyle.readingFont(scale: .normal, highlighted: false),
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
                                         scale: .normal, background: .dark)
            check(newSize == nativeSize, "Ordinary digit changes never move the status item's neighboring icons")
        }
        let missing = sections(pins, snapshot: HUDLogSnapshot()).flatMap { $0 }
        check(missing.filter { !$0.startsMetric }.allSatisfy { $0.text == "—" },
              "Unavailable readings clear to a dash instead of reusing a previous value")
        for mode in HUDMemoryPressureMode.allCases {
            style.resources[.ram]?.pressureMode = mode
            style.resources[.ram]?.usageMode = .app
            let pressure = sections([.memoryPressure]).flatMap { $0 }
            check(pressure.map(\.text) == ["MEM", "warning"],
                  "Pressure pin retains system context while the overlay's memory source is App")
            check(pressure.last?.pressureMode == mode.resolved(for: .horizontal),
                  "B1 and B2 pressure styles resolve to their horizontal A1 and A2 equivalents")
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
        check(chevron.frame.width > 0 && !chevron.isHidden && item.menu === menu,
              "Expanded readings retain the existing settings menu and a separate collapse control")
        let insideChevron = NSPoint(x: chevron.frame.midX, y: chevron.frame.midY)
        check(button.hitTest(insideChevron) === chevron,
              "The collapse control receives its own mouse clicks instead of opening the settings menu")
        let insideBolt = NSPoint(x: item.length - 11, y: button.bounds.midY)
        check(button.hitTest(insideBolt) === button,
              "The app icon keeps native menu-opening behavior: hit \(String(describing: button.hitTest(insideBolt))) button \(button.frame) bounds \(button.bounds)")
        let insideReading = NSPoint(x: chevron.frame.minX / 2, y: button.bounds.midY)
        check(button.hitTest(insideReading) === button,
              "Readings leave the native status-button click target available for settings")
        chevron.performClick(nil)
        check(collapsedClicks == 1 && item.menu === menu,
              "Clicking the chevron invokes only the global collapse action and retains the settings menu")
        var collapsed = options
        collapsed.isCollapsed = true
        controller.refresh(snapshot: HUDLogSnapshot(), fanSample: .noFans, batterySample: nil, options: collapsed)
        check(item.length == 40 && item.menu === menu && chevron.accessibilityLabel() == "Show menu-bar readings",
              "Collapsed state keeps the bolt and an accessible expand action without readings")
        check(chevron.frame.minX == item.length - 40,
              "The collapse control remains fixed beside the app icon at the status item's anchored right edge")
        controller.refresh(snapshot: HUDLogSnapshot(), fanSample: .noFans, batterySample: nil, options: options)
        check(item.length > 40 && chevron.accessibilityLabel() == "Hide menu-bar readings",
              "Expanding restores the selected reading without recreating its menu")
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
        refresh()
        let measured = controller.expandedWidth(for: pins)
        let content: NSView = member(controller, "content")
        let ordinaryFrame = content.frame
        let ordinaryBounds = content.bounds
        check(measured > 40 && measured < widthBudget && abs(item.length - measured) < 0.01,
              "Selection preflight measures the actual horizontal rendering plus its native controls and padding")
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
        let collapse = item.button!.subviews.compactMap { $0 as? NSButton }.first!
        check(item.length == 40 && content.isHidden && overflows > 0 && item.menu === menu,
              "An expanded reading that no longer fits collapses safely and reports overflow without losing settings access")
        check(collapse.accessibilityLabel() == "Show menu-bar readings",
              "Automatic overflow fallback shows the same accessible expand control as manual collapse")

        widthBudget = 360
        refresh()
        check(!content.isHidden && item.length == measured,
              "A fitting selection can expand again with its original proportions")
        let beforeOversizedPreset = overflows
        refresh(.init(readings: Set(HUDMenuBarReading.allCases)))
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
        check(gpuLabels.map(\.frame) == gpuFrames && gpuLabels.map(\.font) == gpuFonts
              && gpuLabels.allSatisfy { !$0.isHidden && $0.alphaValue == 1 },
              "Collapsing FPS leaves other readings' internal spacing, fonts, and visibility unchanged (frames \(gpuLabels.map(\.frame)), expected \(gpuFrames); fonts equal \(gpuLabels.map(\.font) == gpuFonts))")
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
        check(item.length == 40 && arrow.isHidden && content.isHidden,
              "FPS alone waits with just the existing controls, without a second arrow or unused spacing")
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
            check(item.length == 40 && content.isHidden && horizontal.battery.isHidden && arrow.isHidden,
                  "A lone idle or Off Charge selection leaves only the existing controls, without source or an extra arrow")
            if mode == .off {
                check(controller.expandedWidth(for: [.batteryPower]) == 40,
                      "Charge Off does not reserve unused reading padding")
            }
        }
        refresh([.batteryPower], power: nil, samplePresent: false)
        check(item.length == 40 && content.isHidden && horizontal.battery.isHidden,
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
              "Low flow retains the established three-second grace period instead of immediately removing Charge")
        horizontal.battery.update(percentage: 80, source: .powerAdapter, temperature: 34, power: 0.2)
        horizontal.battery.update(percentage: 80, source: .powerAdapter, temperature: 34, power: 0.1,
                                  now: ProcessInfo.processInfo.systemUptime - 3.1)
        refresh([.batteryPower], power: 0.1)
        check(item.length == 40 && content.isHidden && horizontal.battery.isHidden,
              "Charge and its source disappear together after the existing idle grace period expires")
        refresh([.batteryPower], mode: .always)
        check(!content.isHidden && !horizontal.battery.isHidden && horizontal.battery.powerText == "0.0 W",
              "Always keeps a zero-watt Charge category visible")
        check(controller.expandedWidth(for: [.batteryPower]) == autoReservation,
              "Idle Auto reserves the same width as an Always Charge category")
        refresh([.batteryPower], mode: .off, power: 12)
        check(item.length == 40 && content.isHidden && !horizontal.battery.hasVisiblePowerFlow,
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
            check(item.length == 40 && content.isHidden && arrow.isHidden,
                  "Waiting FPS plus an empty Charge category share only the existing controls")
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

    @MainActor static func main() {
        _ = NSApplication.shared
        persistence()
        monitoring()
        categoryControls()
        presentation()
        nativeStatusControl()
        widthSafety()
        fpsMenuAutoHide()
        batteryChargeAutoHide()
        hiddenOverlayRendering()
        print("Menu-bar preference, monitoring, native-control, and proportion checks passed")
    }
}
