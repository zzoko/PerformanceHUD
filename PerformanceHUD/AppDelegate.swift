import AppKit
import ServiceManagement

@MainActor
final class AppDelegate:
    NSObject,
    NSApplicationDelegate, NSMenuDelegate {

    // MARK: - HUD

    private var hudWindow:
        HUDWindowController?

    private var controlsGuide: HUDControlsGuide?
    private var hotkeyEditor: HUDHotkeyEditor?

    // MARK: - FPS

    private var fpsMonitor:
        MetalPerfTraceMonitor?

    // MARK: - GPU

    private var gpuUsageMonitor:
        GPUUsageMonitor?

    private var totalGPUUsageMonitor:
        TotalGPUUsageMonitor?

    // MARK: - CPU

    private var cpuUsageMonitor:
        CPUUsageMonitor?

    private var totalCPUUsageMonitor:
        TotalCPUUsageMonitor?

    // MARK: - RAM

    private var ramUsageMonitor:
        RAMUsageMonitor?

    private var totalRAMUsageMonitor:
        TotalRAMUsageMonitor?

    private var memoryPressureMonitor:
        MemoryPressureMonitor?

    // MARK: - Battery

    private var batteryMonitor:
        BatteryMonitor?

    // MARK: - Active Application

    private var currentPID:
        pid_t?
    private let miscMonitor = HUDMiscMonitor()

    // MARK: - Menu Bar

    private var statusItem:
        NSStatusItem?

    private let hotkeys = HUDHotkeyMonitor()

    private var hudVisibilityMenuItem:
        NSMenuItem?

    private var autoHideMenuView: HUDAutoHideMenuView?

    private var metricMenuItems:
        [HUDMetric: NSMenuItem] = [:]

    private var sizeMenuView:
        HUDSizeMenuView?

    private var fpsMenuView: HUDFPSMenuView?
    private var miscMenuView: HUDMiscMenuView?
    private var backgroundMenuView: HUDBackgroundMenuView?
    private var positionMenuView: HUDPositionMenuView?

    private var backgroundStatusItem: NSMenuItem?
    private var backgroundRetryItem: NSMenuItem?

    // MARK: - State

    private var hudEnabled =
        HUDPreferences.hudEnabled

    private var hudScale =
        HUDPreferences.hudScale

    private var hudBackground = HUDPreferences.background

    private var enabledMetrics = HUDPreferences.visibleMetrics
    private let temperatureMonitor = TemperatureMonitor()
    private let fanMonitor = FanMonitor()
    private var fanMenuView: HUDFanMenuView?
    private let powerMonitor = PowerMonitor()
    private var packagePowerMenuView: HUDPackagePowerMenuView?
    private var resourceMenuViews: [HUDResourceGroup: HUDResourceMenuView] = [:]
    private var powerHelperStatusItem: NSMenuItem?
    private var powerHelperSetupItem: NSMenuItem?
    private var powerHelperApprovalItem: NSMenuItem?
    private var powerHelperRemoveItem: NSMenuItem?

    private let csvLogger = HUDCSVLogger()
    private var logSnapshot = HUDLogSnapshot()
    private var loggingMenuItem: NSMenuItem?
    private var loggingActionPending = false

    // MARK: - Launch

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {

        // No Dock icon.
        NSApp.setActivationPolicy(
            .accessory
        )

        csvLogger.onFailure = { [weak self] error, recovery in
            self?.updateLoggingMenu()
            self?.reconcileMonitoring()
            self?.presentLoggingError(error, recovery: recovery)
        }
        setupHUD()

        // Selected app / FPS
        setupFPSMonitor()

        // GPU
        setupGPUUsageMonitor()
        setupTotalGPUUsageMonitor()

        // CPU
        setupCPUUsageMonitor()
        setupTotalCPUUsageMonitor()
        temperatureMonitor.onUpdate = { [weak self] sample in
            self?.logSnapshot.set(.cpuTemperature, sample.cpu)
            self?.logSnapshot.set(.gpuTemperature, sample.gpu)
            self?.hudWindow?.updateTemperatures(sample)
        }
        powerMonitor.onUpdate = { [weak self] sample in
            self?.logSnapshot.updatePower(sample)
            self?.hudWindow?.updatePower(sample)
        }

        // RAM
        setupRAMUsageMonitor()
        setupTotalRAMUsageMonitor()
        setupMemoryPressureMonitor()

        // Fans (read-only; independent of the power helper).
        fanMonitor.onUpdate = { [weak self] sample in
            guard let self else { return }
            logSnapshot.updateFans(sample)
            let defaultChanged = HUDPreferences.applyFanDetectionDefault(sample)
            let options = HUDPreferences.fanOptions
            if defaultChanged {
                enabledMetrics = HUDPreferences.visibleMetrics
                hudWindow?.setFanOptions(options)
            }
            hudWindow?.updateFans(sample)
            fanMenuView?.update(sample: sample, options: options)
            if defaultChanged { reconcileMonitoring() }
        }

        // Battery
        setupBatteryMonitor()
        miscMonitor.onUpdate = { [weak self] sample in
            self?.hudWindow?.updateMisc(sample)
            self?.logSnapshot.updateMisc(sample)
        }

        // Menu
        setupMenuBar()
        setupHUDShortcuts()

        // Active app detection
        setupApplicationMonitoring()

        powerMonitor.helper.onStateChange = { [weak self] in self?.powerHelperStateChanged() }
        powerMonitor.helper.onPowerSelectionChange = { [weak self] enabled in self?.setPowerSelections(enabled) }
        monitorFrontmostApplication()
        reconcileMonitoring()
        powerHelperStateChanged()
        // Let initial window setup finish before offering power setup.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.powerMonitor.helper.offerSetupOnFirstLaunch()
        }
    }

    // MARK: - HUD Setup

    private func setupHUD() {

        let hud =
            HUDWindowController()
        hud.setDragModifier(hotkeys.settings.dragModifier)
        for group in HUDResourceGroup.allCases {
            hud.setResourceOptions(HUDPreferences.resourceOptions(for: group), for: group)
        }
        hud.setBatteryOptions(HUDPreferences.batteryOptions)
        hud.setFanOptions(HUDPreferences.fanOptions)
        hud.setMiscOptions(HUDPreferences.miscOptions)

        // Restore metric visibility.
        for metric in HUDMetric.allCases {

            hud.setMetricEnabled(
                metric,
                enabled:
                    enabledMetrics
                        .contains(metric)
            )
        }

        // Restore size.
        hud.setHUDScale(
            hudScale
        )

        // Restore HUD visibility.
        hud.setHUDEnabled(
            hudEnabled
        )

        hud.show()

        self.hudWindow =
            hud
        hud.onAutoHideVisibilityChange = { [weak self] in
            // Let the reveal finish setting up before starting/stopping monitors.
            DispatchQueue.main.async { [weak self] in self?.reconcileMonitoring() }
        }
    }

    // MARK: - FPS Setup

    private func setupFPSMonitor() {

        let monitor =
            MetalPerfTraceMonitor()

        monitor.onMetricsUpdate = {
            [weak self] metrics in

            guard let self else {
                return
            }

            logSnapshot.set(.fps, metrics.fps)
            miscMonitor.updateResolution(metrics.resolution)
            if let fps =
                metrics.fps {

                self
                    .hudWindow?
                    .updateFPS(
                        fps
                    )
            } else {
                self.hudWindow?.markFPSUnavailable()
            }
        }

        self.fpsMonitor =
            monitor
    }

    // MARK: - Selected App GPU

    private func setupGPUUsageMonitor() {

        let monitor =
            GPUUsageMonitor()

        monitor.onGPUUsageUpdate = {
            [weak self] usage in

            guard let self else {
                return
            }

            logSnapshot.set(.gpuAppUsage, usage)

            guard let usage else {

                self
                    .hudWindow?
                    .updateMetric(
                        .gpu,
                        value: ""
                    )

                return
            }

            self
                .hudWindow?
                .updateMetric(
                    .gpu,
                    value:
                        "\(Int(usage.rounded()))%"
                )
        }

        self.gpuUsageMonitor =
            monitor
    }

    // MARK: - Total GPU

    private func setupTotalGPUUsageMonitor() {

        let monitor =
            TotalGPUUsageMonitor()

        monitor.onGPUUsageUpdate = {
            [weak self] usage in

            guard let self else {
                return
            }

            logSnapshot.set(.gpuUsage, usage)

            guard let usage else {

                self
                    .hudWindow?
                    .updateMetric(
                        .gpuTotal,
                        value: ""
                    )

                return
            }

            self
                .hudWindow?
                .updateMetric(
                    .gpuTotal,
                    value:
                        "\(Int(usage.rounded()))%"
                )
        }

        self.totalGPUUsageMonitor =
            monitor

    }

    // MARK: - Selected App CPU

    private func setupCPUUsageMonitor() {

        let monitor =
            CPUUsageMonitor()

        monitor.onCPUUsageUpdate = {
            [weak self] usage in

            guard let self else {
                return
            }

            logSnapshot.set(.cpuAppUsage, usage)

            guard let usage else {

                self
                    .hudWindow?
                    .updateMetric(
                        .cpu,
                        value: ""
                    )

                return
            }

            self
                .hudWindow?
                .updateMetric(
                    .cpu,
                    value:
                        "\(Int(usage.rounded()))%"
                )
        }

        self.cpuUsageMonitor =
            monitor
    }

    // MARK: - Total CPU

    private func setupTotalCPUUsageMonitor() {

        let monitor =
            TotalCPUUsageMonitor()

        monitor.onCPUUsageUpdate = {
            [weak self] usage in

            guard let self else {
                return
            }

            logSnapshot.set(.cpuUsage, usage)

            guard let usage else {

                self
                    .hudWindow?
                    .updateMetric(
                        .cpuTotal,
                        value: ""
                    )

                return
            }

            self
                .hudWindow?
                .updateMetric(
                    .cpuTotal,
                    value:
                        "\(Int(usage.rounded()))%"
                )
        }

        self.totalCPUUsageMonitor =
            monitor

    }

    // MARK: - Selected App RAM

    private func setupRAMUsageMonitor() {
        let monitor = RAMUsageMonitor()
        monitor.onRAMUsageUpdate = { [weak self] usage in
            self?.logSnapshot.updateMemory(usage, app: true)
            self?.hudWindow?.updateRAM(.ram, usage: usage)
        }
        self.ramUsageMonitor = monitor
    }

    // MARK: - Total RAM

    private func setupTotalRAMUsageMonitor() {
        let monitor = TotalRAMUsageMonitor()
        monitor.onRAMUsageUpdate = { [weak self] usage in
            self?.logSnapshot.updateMemory(usage, app: false)
            self?.hudWindow?.updateRAM(.ramTotal, usage: usage)
        }
        self.totalRAMUsageMonitor = monitor
    }

    // MARK: - RAM Pressure

    private func setupMemoryPressureMonitor() {

        let monitor =
            MemoryPressureMonitor()

        monitor.onPressureUpdate = {
            [weak self] level in

            self?.logSnapshot.setText(.memoryPressure, level?.displayText)
            self?.hudWindow?.updateMemoryPressure(level?.displayText ?? "")
        }

        self.memoryPressureMonitor =
            monitor

    }

    // MARK: - Battery

    private func setupBatteryMonitor() {

        let monitor =
            BatteryMonitor()

        monitor.onBatteryUpdate = { [weak self] sample in
            self?.logSnapshot.updateBattery(sample)
            self?.hudWindow?.updateBattery(sample)
        }

        self.batteryMonitor =
            monitor

    }

    // MARK: - Menu Bar

    private func setupMenuBar() {

        let statusItem = self.statusItem ??
            NSStatusBar.system.statusItem(
                withLength:
                    NSStatusItem.squareLength
            )

        if let button =
            statusItem.button {

            button.image =
                NSImage(
                    systemSymbolName:
                        "bolt.fill",
                    accessibilityDescription:
                        "Performance HUD"
                )
        }

        let menu =
            NSMenu()
        menu.autoenablesItems = false

        // MARK: Enable / Disable

        let hudVisibilityItem =
            NSMenuItem(
                title:
                    hudEnabled
                    ? "Disable"
                    : "Enable",
                action:
                    #selector(
                        toggleHUD(_:)
                    ),
                keyEquivalent: ""
            )

        hudVisibilityItem.target =
            self

        menu.addItem(
            hudVisibilityItem
        )

        self.hudVisibilityMenuItem =
            hudVisibilityItem
        let autoHideView = HUDAutoHideMenuView(selected: HUDPreferences.autoHideMode, animated: HUDPreferences.autoHideAnimated)
        autoHideView.onChange = { [weak self] mode in self?.selectAutoHideMode(mode) }
        autoHideView.onAnimatedChange = { [weak self] animated in
            HUDPreferences.autoHideAnimated = animated
            self?.hudWindow?.setAutoHideAnimated(animated)
        }
        let autoHideItem = NSMenuItem()
        autoHideItem.view = autoHideView
        menu.addItem(autoHideItem)
        autoHideMenuView = autoHideView

        // MARK: HUD Size

        let sizeView =
            HUDSizeMenuView(
                selectedScale:
                    hudScale
            )

        sizeView.onScaleSelected = {
            [weak self] newScale in

            self?
                .setHUDScale(
                    newScale
                )
        }

        let sizeItem =
            NSMenuItem()

        sizeItem.view =
            sizeView

        menu.addItem(
            sizeItem
        )

        self.sizeMenuView =
            sizeView

        // MARK: Reset

        let positionView = HUDPositionMenuView(dragModifier: hotkeys.settings.dragModifier)
        positionMenuView = positionView
        positionView.onReset = { [weak self] in
            self?.hudWindow?.resetPosition()
        }
        positionView.onResetSize = { [weak self] in self?.setHUDScale(.normal) }
        positionView.onResetOptions = { [weak self] in self?.confirmResetOptions() }
        let positionItem = NSMenuItem()
        positionItem.view = positionView
        menu.insertItem(positionItem, at: menu.index(of: sizeItem))

        let alignmentView = HUDAlignmentMenuView(selected: HUDPreferences.alignment)
        alignmentView.onAlignmentSelected = { [weak self] alignment in self?.setHUDAlignment(alignment) }
        let alignmentItem = NSMenuItem()
        alignmentItem.view = alignmentView
        menu.insertItem(alignmentItem, at: menu.index(of: sizeItem) + 1)

        // MARK: HUD Background

        let backgroundView = HUDBackgroundMenuView(selectedBackground: hudBackground)
        backgroundView.onBackgroundSelected = { [weak self] background in
            self?.setHUDBackground(background)
        }
        let backgroundItem = NSMenuItem()
        backgroundItem.view = backgroundView
        menu.addItem(backgroundItem)
        self.backgroundMenuView = backgroundView

        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let retry = NSMenuItem(title: "Retry Glass Compatibility", action: #selector(retryGlassSession), keyEquivalent: "")
        retry.target = self
        for item in [status, retry] { item.isHidden = true; menu.addItem(item) }
        backgroundStatusItem = status
        backgroundRetryItem = retry
        hudWindow?.onGlassSessionChange = { [weak self] in self?.updateGlassSessionStatus() }
        updateGlassSessionStatus()

        // Separator before metrics.

        menu.addItem(
            .separator()
        )

        // MARK: Metrics

        func addMetricPadding() {
            // Keep native menu checkmarks and keyboard handling while giving
            // 24pt standard items the same 34pt pitch as the resource rows.
            let padding = NSMenuItem()
            padding.isEnabled = false
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 5))
            view.setAccessibilityElement(false)
            padding.view = view
            menu.addItem(padding)
        }

        func addMetric(_ metric: HUDMetric) {
            addMetricPadding()
            let item = NSMenuItem(title: metric.menuTitle, action: #selector(toggleMetric(_:)), keyEquivalent: "")
            item.target = self
            item.tag = metric.rawValue
            HUDMenuLayout.reserveStateColumn(for: item)
            item.state = enabledMetrics.contains(metric) ? .on : .off
            item.isEnabled = HUDPreferences.alignment.allows(metric)
            menu.addItem(item)
            metricMenuItems[metric] = item
            addMetricPadding()
        }
        let fpsView = HUDFPSMenuView(options: HUDPreferences.fpsOptions, alignment: HUDPreferences.alignment)
        fpsView.onChange = { [weak self] options in
            guard let self else { return }
            let previousMetrics = HUDPreferences.fpsOptions.visibleMetrics(alignment: HUDPreferences.alignment)
            HUDPreferences.fpsOptions = options
            enabledMetrics = HUDPreferences.visibleMetrics
            hudWindow?.setFPSOptions(options)
            if previousMetrics != options.visibleMetrics(alignment: HUDPreferences.alignment) {
                reconcileMonitoring()
            }
        }
        fpsMenuView = fpsView
        let fpsItem = NSMenuItem()
        fpsItem.view = fpsView
        menu.addItem(fpsItem)
        var powerRows: [HUDResourceMenuView] = []
        for group in HUDResourceGroup.allCases {
            let view = HUDResourceMenuView(group: group, options: HUDPreferences.resourceOptions(for: group))
            view.onChange = { [weak self] options in
                guard let self else { return }
                HUDPreferences.setResourceOptions(options, for: group)
                enabledMetrics = HUDPreferences.visibleMetrics
                hudWindow?.setResourceOptions(options, for: group)
                updatePackagePowerMenu()
                reconcileMonitoring()
            }
            view.onPowerSetup = { [weak self] in
                self?.statusItem?.menu?.cancelTracking()
                Task { @MainActor [weak self] in self?.powerMonitor.helper.requestPowerAccess() }
            }
            resourceMenuViews[group] = view
            if group.supportsPower {
                powerRows.append(view)
                if group == .ane {
                    let package = HUDPackagePowerMenuView(options: HUDPreferences.packagePowerOptions)
                    package.onChange = { [weak self] options in
                        HUDPreferences.packagePowerOptions = options
                        self?.hudWindow?.setPackagePowerOptions(options)
                        self?.reconcileMonitoring()
                        self?.updatePackagePowerMenu()
                    }
                    package.onPowerSetup = { [weak self] in
                        self?.statusItem?.menu?.cancelTracking()
                        Task { @MainActor [weak self] in self?.powerMonitor.helper.requestPowerAccess() }
                    }
                    packagePowerMenuView = package
                    let item = NSMenuItem()
                    item.view = HUDPowerGroupMenuView(rows: powerRows, package: package)
                    menu.addItem(item)
                    updatePackagePowerMenu()
                }
            } else {
                let item = NSMenuItem()
                item.view = view
                menu.addItem(item)
            }
        }
        let fanView = HUDFanMenuView(options: HUDPreferences.fanOptions,
                                     sample: fanMonitor.sample)
        fanView.onChange = { [weak self] options in
            guard let self else { return }
            HUDPreferences.fanOptions = options
            enabledMetrics = HUDPreferences.visibleMetrics
            hudWindow?.setFanOptions(options)
            reconcileMonitoring()
        }
        fanMenuView = fanView
        let fanItem = NSMenuItem()
        fanItem.view = fanView
        menu.addItem(fanItem)
        let batteryView = HUDResourceMenuView(batteryOptions: HUDPreferences.batteryOptions)
        batteryView.onBatteryChange = { [weak self] options in
            guard let self else { return }
            HUDPreferences.setBatteryOptions(options)
            enabledMetrics = HUDPreferences.visibleMetrics
            hudWindow?.setBatteryOptions(options)
            reconcileMonitoring()
        }
        let batteryItem = NSMenuItem()
        batteryItem.view = batteryView
        menu.addItem(batteryItem)
        let miscView = HUDMiscMenuView(options: HUDPreferences.miscOptions, alignment: HUDPreferences.alignment)
        miscMenuView = miscView
        miscView.onChange = { [weak self] options in
            guard let self else { return }
            HUDPreferences.miscOptions = options
            enabledMetrics = HUDPreferences.visibleMetrics
            hudWindow?.setMiscOptions(options)
            reconcileMonitoring()
        }
        let miscItem = NSMenuItem()
        miscItem.view = miscView
        menu.addItem(miscItem)
        addMetric(.deviceInfo)

        // Separator before Close App.

        menu.addItem(
            .separator()
        )

        let loggingItem = NSMenuItem(title: "Start logging", action: #selector(toggleLogging), keyEquivalent: "")
        loggingItem.target = self
        loggingMenuItem = loggingItem
        menu.addItem(loggingItem)
        updateLoggingMenu()

        let helperMenu = NSMenu()
        helperMenu.autoenablesItems = false
        let helperItem = NSMenuItem(title: "Power Helper", action: nil, keyEquivalent: "")
        helperItem.submenu = helperMenu
        let helperStatus = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let helperSetup = NSMenuItem(title: "Set Up Power Readings…", action: #selector(setUpPowerHelper), keyEquivalent: "")
        let helperApproval = NSMenuItem(title: "Open Approval Settings…", action: #selector(openPowerHelperSettings), keyEquivalent: "")
        let helperRemove = NSMenuItem(title: "Remove Power Helper", action: #selector(removePowerHelper), keyEquivalent: "")
        for item in [helperStatus, helperSetup, helperApproval, helperRemove] {
            item.target = self
            helperMenu.addItem(item)
        }
        powerHelperStatusItem = helperStatus
        powerHelperSetupItem = helperSetup
        powerHelperApprovalItem = helperApproval
        powerHelperRemoveItem = helperRemove
        menu.addItem(helperItem)
        let hotkeysItem = NSMenuItem(title: "Edit hotkeys…", action: #selector(editHotkeys), keyEquivalent: "")
        hotkeysItem.target = self
        menu.addItem(hotkeysItem)
        let guideItem = NSMenuItem(title: "Controls Guide…", action: #selector(showControlsGuide), keyEquivalent: "")
        guideItem.target = self
        menu.addItem(guideItem)
        menu.addItem(.separator())
        menu.delegate = self
        helperMenu.delegate = self

        // MARK: Close App

        let closeItem =
            NSMenuItem(
                title:
                    "Quit",
                action:
                    #selector(
                        closeApplication(_:)
                    ),
                keyEquivalent:
                    "q"
            )

        closeItem.target =
            self

        menu.addItem(
            closeItem
        )

        statusItem.menu =
            menu

        self.statusItem =
            statusItem
        updateHotkeyHints()
    }

    @objc private func editHotkeys() {
        statusItem?.menu?.cancelTracking()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if hotkeyEditor == nil { hotkeyEditor = HUDHotkeyEditor(hotkeys: hotkeys) }
            hotkeyEditor?.present()
        }
    }

    @objc private func showControlsGuide() {
        statusItem?.menu?.cancelTracking()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if controlsGuide == nil { controlsGuide = HUDControlsGuide() }
            controlsGuide?.present()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateLoggingMenu()
        updateHotkeyHints()
        let fan = HUDPreferences.fanOptions
        fanMonitor.configure(readings: readingsActive && fan.enabled && fan.usage)
        powerMonitor.helper.refreshStatus()
        updatePowerHelperMenu()
    }

    private func setPowerSelections(_ enabled: Bool) {
        var changed = false
        for group in HUDResourceGroup.allCases where group.supportsPower {
            var options = HUDPreferences.resourceOptions(for: group)
            if options.power != enabled {
                options.power = enabled
                HUDPreferences.setResourceOptions(options, for: group)
                hudWindow?.setResourceOptions(options, for: group)
                changed = true
            }
        }
        var package = HUDPreferences.packagePowerOptions
        if package.enabled != enabled {
            package.enabled = enabled
            HUDPreferences.packagePowerOptions = package
            hudWindow?.setPackagePowerOptions(package)
            changed = true
        }
        if changed {
            enabledMetrics = HUDPreferences.visibleMetrics
            reconcileMonitoring()
        }
        updatePowerHelperMenu()
    }

    private func powerHelperStateChanged() {
        if powerMonitor.helper.shouldTurnPowerOff { setPowerSelections(false) }
        updatePowerHelperMenu()
    }

    private func updatePackagePowerMenu() {
        packagePowerMenuView?.setState(options: HUDPreferences.packagePowerOptions,
            helper: powerMonitor.helper.availability)
    }

    private func updatePowerHelperMenu() {
        updatePackagePowerMenu()
        let helper = powerMonitor.helper
        let text: String
        switch helper.availability {
        case .idle: text = "Power helper idle"
        case .ready: text = "Ready for power readings"
        case .starting: text = "Starting power readings…"
        case .approvalRequired: text = "Waiting for macOS approval"
        case .setupRequired: text = helper.needsUpdate ? "Helper update needed" : "Power readings need setup"
        case .updating: text = "Updating power helper…"
        case .failed: text = "Power readings unavailable — repair helper"
        }
        for group in HUDResourceGroup.allCases where group.supportsPower {
            resourceMenuViews[group]?.setPowerState(helper.availability,
                selected: HUDPreferences.resourceOptions(for: group).power)
        }
        powerHelperStatusItem?.title = text
        powerHelperStatusItem?.toolTip = helper.lastError
        powerHelperSetupItem?.title = helper.needsUpdate ? "Update Power Helper…" : (helper.status == .enabled ? "Repair Power Helper…" : "Set Up Power Readings…")
        powerHelperSetupItem?.isEnabled = !helper.busy
        powerHelperApprovalItem?.isHidden = helper.status != .requiresApproval
        powerHelperRemoveItem?.isEnabled = !helper.busy && (helper.status == .enabled || helper.status == .requiresApproval)
    }

    @objc private func setUpPowerHelper() { powerMonitor.helper.requestSetup() }
    @objc private func openPowerHelperSettings() { powerMonitor.helper.openApprovalSettings() }
    @objc private func removePowerHelper() { powerMonitor.helper.remove() }

    private func updateGlassSessionStatus() {
        let failure = hudWindow?.glassSessionFailure
        backgroundStatusItem?.isHidden = failure == nil
        backgroundRetryItem?.isHidden = failure == nil
        backgroundStatusItem?.title = "Glass compatibility workaround unavailable"
        backgroundStatusItem?.toolTip = failure.map {
            "Native glass still works, but some games may be limited to 60 FPS. \($0)"
        }
    }

    @objc private func retryGlassSession() { hudWindow?.retryGlassSession() }

    private func setupHUDShortcuts() {
        hotkeys.onPress = { [weak self] action in
            guard let self else { return }
            switch action {
            case .visibility: toggleHUD(nil)
            case .logging: toggleLogging()
            case .appearance: setHUDBackground(hudBackground.next)
            }
        }
        hotkeys.onChange = { [weak self] in self?.updateHotkeyHints() }
        hotkeys.start()
    }

    private func updateHotkeyHints() {
        hudWindow?.setDragModifier(hotkeys.settings.dragModifier)
        positionMenuView?.setDragModifier(hotkeys.settings.dragModifier)
        for (action, item) in [(HUDHotkeyAction.visibility, hudVisibilityMenuItem), (.logging, loggingMenuItem)] {
            let shortcut = hotkeys.isActive(action) ? hotkeys.settings[action] : nil
            item?.keyEquivalent = shortcut?.menuKey ?? ""
            item?.keyEquivalentModifierMask = shortcut?.menuModifiers ?? []
        }
        hudVisibilityMenuItem?.toolTip = hotkeys.errors[.visibility]
        backgroundMenuView?.toolTip = hotkeys.errors[.appearance]
            ?? hotkeys.settings[.appearance].map { "Cycle appearance: \($0.displayName)" }
    }

    private func setHUDBackground(_ background: HUDBackground) {
        hudBackground = background
        HUDPreferences.background = background
        hudWindow?.setBackground(background)
        backgroundMenuView?.select(background)
    }

    // MARK: - Enable / Disable HUD

    @objc
    private func toggleHUD(
        _ sender: NSMenuItem?
    ) {

        hudEnabled.toggle()
        if !hudEnabled { stopLogging() }
        updateLoggingMenu()

        // Save preference.
        HUDPreferences.hudEnabled =
            hudEnabled

        // Update HUD.
        hudWindow?
            .setHUDEnabled(
                hudEnabled
            )

        reconcileMonitoring()

        // Update menu text.
        hudVisibilityMenuItem?.title =
            hudEnabled
            ? "Disable"
            : "Enable"
    }

    private func selectAutoHideMode(_ mode: HUDAutoHideMode) {
        guard mode != HUDPreferences.autoHideMode else { return }
        guard mode == .all && !HUDPreferences.autoHideExplanationDismissed else {
            setAutoHideMode(mode)
            return
        }
        statusItem?.menu?.cancelTracking()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Automatically hide the HUD?"
            alert.informativeText = "The HUD will appear when FPS readings are available and hide after three seconds without them. Games or apps without detectable FPS readings will keep it hidden. Enable/Disable and your shortcut still control whether the HUD is enabled."
            alert.addButton(withTitle: "Use All options")
            alert.addButton(withTitle: "Cancel")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don’t show this again"
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            HUDPreferences.autoHideExplanationDismissed = alert.suppressionButton?.state == .on
            setAutoHideMode(.all)
        }
    }

    private func setAutoHideMode(_ mode: HUDAutoHideMode) {
        HUDPreferences.autoHideMode = mode
        autoHideMenuView?.select(mode)
        hudWindow?.setAutoHideMode(mode)
        reconcileMonitoring()
    }

    private func confirmResetOptions() {
        statusItem?.menu?.cancelTracking()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if HUDPreferences.resetOptionsConfirmationDismissed {
                resetHUDOptions()
                return
            }
            let alert = NSAlert()
            alert.messageText = "Reset all HUD options to defaults?"
            alert.informativeText = "This restores the default categories, readings, highlighting, usage modes, alignment, size, position, and appearance, and enables the HUD. Your permissions are kept."
            alert.addButton(withTitle: "Reset All Options")
            alert.addButton(withTitle: "Cancel")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don’t show this again"
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            HUDPreferences.resetOptionsConfirmationDismissed = alert.suppressionButton?.state == .on
            resetHUDOptions()
        }
    }

    private func resetHUDOptions() {
        HUDPreferences.resetOptions()
        HUDPreferences.applyFanDetectionDefault(fanMonitor.sample)
        // Restore display defaults without bypassing a denied or failed helper.
        if powerMonitor.helper.shouldTurnPowerOff {
            for group in HUDResourceGroup.allCases where group.supportsPower {
                var options = HUDPreferences.resourceOptions(for: group)
                options.power = false
                HUDPreferences.setResourceOptions(options, for: group)
            }
            var package = HUDPreferences.packagePowerOptions
            package.enabled = false
            HUDPreferences.packagePowerOptions = package
        }
        hudEnabled = HUDPreferences.hudEnabled
        hudScale = HUDPreferences.hudScale
        hudBackground = HUDPreferences.background
        enabledMetrics = HUDPreferences.visibleMetrics

        // Hide the HUD while applying all options, then restore its final layout.
        hudWindow?.setHUDEnabled(false)
        for group in HUDResourceGroup.allCases {
            hudWindow?.setResourceOptions(HUDPreferences.resourceOptions(for: group), for: group)
        }
        hudWindow?.setBatteryOptions(HUDPreferences.batteryOptions)
        hudWindow?.setFanOptions(HUDPreferences.fanOptions)
        hudWindow?.setMiscOptions(HUDPreferences.miscOptions)
        hudWindow?.setPackagePowerOptions(HUDPreferences.packagePowerOptions)
        hudWindow?.setAutoHideAnimated(HUDPreferences.autoHideAnimated)
        hudWindow?.setAutoHideMode(HUDPreferences.autoHideMode)
        hudWindow?.setAlignment(HUDPreferences.alignment)
        hudWindow?.setFPSOptions(HUDPreferences.fpsOptions)
        hudWindow?.setHUDScale(hudScale)
        hudWindow?.setBackground(hudBackground)
        hudWindow?.resetPosition()
        hudWindow?.setHUDEnabled(hudEnabled)
        reconcileMonitoring()

        // Display reset preserves the independently saved hotkeys.
        setupMenuBar()
        updatePowerHelperMenu()
    }

    // MARK: - HUD Scale

    private func setHUDAlignment(_ alignment: HUDAlignment) {
        HUDPreferences.alignment = alignment
        enabledMetrics = HUDPreferences.visibleMetrics
        hudWindow?.setAlignment(alignment)
        fpsMenuView?.update(options: HUDPreferences.fpsOptions, alignment: alignment)
        miscMenuView?.update(alignment: alignment)
        updatePackagePowerMenu()
        for metric in [HUDMetric.deviceInfo] {
            guard let item = metricMenuItems[metric] else { continue }
            item.isEnabled = alignment.allows(metric)
            item.state = enabledMetrics.contains(metric) ? .on : .off
        }
        reconcileMonitoring()
    }

    private func setHUDScale(
        _ newScale: HUDScale
    ) {

        hudScale =
            newScale

        // Save preference.
        HUDPreferences.hudScale =
            newScale
        sizeMenuView?.select(newScale)

        // Resize immediately.
        hudWindow?
            .setHUDScale(
                newScale
            )
    }

    // MARK: - Metric Toggle

    @objc
    private func toggleMetric(
        _ sender: NSMenuItem
    ) {

        guard
            let metric =
                HUDMetric(
                    rawValue:
                        sender.tag
                )
        else {
            return
        }

        guard HUDPreferences.alignment.allows(metric) else { return }

        let isEnabled =
            enabledMetrics
                .contains(
                    metric
                )

        let newState =
            !isEnabled

        if newState {

            enabledMetrics.insert(
                metric
            )

        } else {

            enabledMetrics.remove(
                metric
            )
        }

        // Save preference.
        HUDPreferences.setMetricEnabled(
            metric,
            enabled:
                newState
        )

        // Update menu checkmark.
        sender.state =
            newState
            ? .on
            : .off

        // Update HUD.
        hudWindow?
            .setMetricEnabled(
                metric,
                enabled:
                    newState
            )
        reconcileMonitoring()
    }

    // MARK: - Close

    @objc
    private func closeApplication(
        _ sender: NSMenuItem
    ) {

        NSApp.terminate(
            nil
        )
    }

    // MARK: - Application Monitoring

    private func setupApplicationMonitoring() {

        NSWorkspace.shared
            .notificationCenter
            .addObserver(
                self,
                selector:
                    #selector(
                        activeApplicationChanged(_:)
                    ),
                name:
                    NSWorkspace
                        .didActivateApplicationNotification,
                object:
                    nil
            )
    }

    @objc
    private func activeApplicationChanged(
        _ notification: Notification
    ) {

        monitorFrontmostApplication()
    }

    // MARK: - Frontmost Application

    private func monitorFrontmostApplication() {

        guard
            let app =
                NSWorkspace
                    .shared
                    .frontmostApplication
        else {
            return
        }

        let pid =
            app.processIdentifier

        // Never monitor PerformanceHUD itself.
        guard
            pid !=
            ProcessInfo
                .processInfo
                .processIdentifier
        else {
            return
        }

        // Avoid restarting all selected-app
        // monitors for the same PID.
        miscMonitor.setTarget(app)
        guard
            pid != currentPID
        else {
            return
        }

        currentPID =
            pid

        // Never attribute the previous app's readings to the newly focused app.
        logSnapshot.clear([.fps, .gpuAppUsage, .cpuAppUsage, .memoryAppUsage, .memoryAppPhysical])

        // MARK: Clear Previous Selected-App Data

        hudWindow?
            .resetFPS()

        hudWindow?
            .updateMetric(
                .gpu,
                value: ""
            )

        hudWindow?
            .updateMetric(
                .cpu,
                value: ""
            )

        hudWindow?.updateRAM(.ram, usage: nil)

        reconcileMonitoring()
    }

    // Collect selected metrics while visible or explicitly logging. Each monitor's
    // start is idempotent, so unrelated toggles do not reset its baselines.
    private var readingsActive: Bool {
        hudEnabled && (csvLogger.isLogging || !(hudWindow?.isAutomaticallyHidden ?? false))
    }

    private func reconcileMonitoring() {
        miscMonitor.configure(readingsActive && enabledMetrics.contains(.misc) ? HUDPreferences.miscOptions : HUDMiscOptions())
        var metrics = readingsActive ? enabledMetrics : []
        // CPU/GPU rows can stay visible without utilization. Memory sampling also
        // supplies Details, so it remains active for a Details-only row.
        for group in HUDResourceGroup.allCases where group != .ram && !HUDPreferences.resourceOptions(for: group).totalUse {
            metrics.remove(group.totalMetric)
        }
        let fan = HUDPreferences.fanOptions
        fanMonitor.configure(readings: readingsActive && fan.enabled && fan.usage)
        let cpu = HUDPreferences.resourceOptions(for: .cpu)
        let gpu = HUDPreferences.resourceOptions(for: .gpu)
        let resources = Dictionary(uniqueKeysWithValues: HUDResourceGroup.allCases.map {
            ($0, HUDPreferences.resourceOptions(for: $0))
        })
        let powerEnabled = HUDPowerDemand.isNeeded(hudEnabled: readingsActive,
            resources: resources, package: HUDPreferences.packagePowerOptions)
        powerMonitor.configure(enabled: powerEnabled)
        if !powerEnabled {
            logSnapshot.updatePower(.unavailable)
            hudWindow?.updatePower(.unavailable)
        }
        if !readingsActive || !cpu.enabled || !cpu.temperature { logSnapshot.set(.cpuTemperature, nil) }
        if !readingsActive || !gpu.enabled || !gpu.temperature { logSnapshot.set(.gpuTemperature, nil) }
        if !readingsActive || !fan.enabled || !fan.usage { logSnapshot.updateFans(.unavailable) }
        if !HUDPreferences.batteryOptions.temperature { logSnapshot.set(.batteryTemperature, nil) }
        if !HUDPreferences.batteryOptions.power { logSnapshot.set(.batteryPower, nil) }
        temperatureMonitor.configure(cpu: readingsActive && cpu.enabled && cpu.temperature,
                                     gpu: readingsActive && gpu.enabled && gpu.temperature)
        if metrics.contains(.gpuTotal) { totalGPUUsageMonitor?.start() }
        else { logSnapshot.set(.gpuUsage, nil); totalGPUUsageMonitor?.stop(); hudWindow?.updateMetric(.gpuTotal, value: "") }
        if metrics.contains(.cpuTotal) { totalCPUUsageMonitor?.start() }
        else { logSnapshot.set(.cpuUsage, nil); totalCPUUsageMonitor?.stop(); hudWindow?.updateMetric(.cpuTotal, value: "") }
        if metrics.contains(.ramTotal) { totalRAMUsageMonitor?.start() }
        else { logSnapshot.updateMemory(nil, app: false); totalRAMUsageMonitor?.stop(); hudWindow?.updateRAM(.ramTotal, usage: nil) }
        if metrics.contains(.ramTotal) { memoryPressureMonitor?.start() }
        else { logSnapshot.setText(.memoryPressure, nil); memoryPressureMonitor?.stop(); hudWindow?.updateMemoryPressure("") }
        if metrics.contains(.battery) {
            batteryMonitor?.start(temperature: HUDPreferences.batteryOptions.temperature, power: HUDPreferences.batteryOptions.power)
        }
        else { logSnapshot.updateBattery(nil); batteryMonitor?.stop(); hudWindow?.updateMetric(.battery, value: "") }

        if metrics.contains(.gpu), let pid = currentPID { gpuUsageMonitor?.start(pid: pid) }
        else { logSnapshot.set(.gpuAppUsage, nil); gpuUsageMonitor?.stop(); hudWindow?.updateMetric(.gpu, value: "") }
        if metrics.contains(.cpu), let pid = currentPID { cpuUsageMonitor?.start(pid: pid) }
        else { logSnapshot.set(.cpuAppUsage, nil); cpuUsageMonitor?.stop(); hudWindow?.updateMetric(.cpu, value: "") }
        if metrics.contains(.ram), let pid = currentPID { ramUsageMonitor?.start(pid: pid) }
        else { logSnapshot.updateMemory(nil, app: true); ramUsageMonitor?.stop(); hudWindow?.updateRAM(.ram, usage: nil) }
        // Auto hide must keep detecting FPS even with the FPS category unchecked
        // and all other readings paused, otherwise the HUD could never reappear.
        let needsResolution = readingsActive && enabledMetrics.contains(.misc)
            && HUDPreferences.miscOptions.visibleReadings.contains(.resolution)
        if hudEnabled && (HUDPreferences.autoHideMode == .all || metrics.contains(.fps) || metrics.contains(.fpsGraph) || needsResolution), let pid = currentPID {
            do { try fpsMonitor?.start(pid: pid) }
            catch { logSnapshot.set(.fps, nil); miscMonitor.updateResolution(nil); hudWindow?.markFPSUnavailable() }
        } else {
            fpsMonitor?.stop()
            logSnapshot.set(.fps, nil)
            miscMonitor.updateResolution(nil)
            hudWindow?.resetFPS()
        }
    }

    // MARK: - Logging

    private func updateLoggingMenu() {
        loggingMenuItem?.title = csvLogger.isLogging ? "Stop logging" : "Start logging"
        loggingMenuItem?.isEnabled = csvLogger.isLogging || hudEnabled
    }

    @objc private func toggleLogging() {
        guard !loggingActionPending else { return }
        loggingActionPending = true
        statusItem?.menu?.cancelTracking()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { loggingActionPending = false }
            if csvLogger.isLogging { stopLogging(); return }
            guard hudEnabled else { return }
            var dismissExplanation = HUDPreferences.loggingExplanationDismissed
            if !dismissExplanation {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = "Start logging HUD readings?"
                alert.informativeText = "Record selected readings once per second to a CSV for spreadsheets and graphs. Missing readings are left blank. Stop logging, disable the HUD, or quit to save the file to your Desktop. Auto hide does not stop logging.\n\nColumns are chosen when you start. Turning readings off leaves their cells blank; start a new log to include newly selected readings."
                alert.addButton(withTitle: "Start logging")
                alert.addButton(withTitle: "Cancel")
                alert.showsSuppressionButton = true
                alert.suppressionButton?.title = "Don’t show this again"
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                dismissExplanation = alert.suppressionButton?.state == .on
            }
            guard hudEnabled else { return }
            do {
                let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                    in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("PerformanceHUD/Logs", isDirectory: true)
                let columns = HUDLogSelection.current.columns(fanSample: fanMonitor.sample)
                try csvLogger.start(columns: columns, recoveryDirectory: directory) { [weak self] in
                    guard let self else { return (HUDLogSnapshot(), []) }
                    var snapshot = logSnapshot
                    snapshot.setText(.chip, HUDDeviceInfo.current.chipName)
                    snapshot.setText(.os, HUDDeviceInfo.current.macOSVersion)
                    // Match the Energy icon; macOS does not expose High Power here.
                    snapshot.set(.lowPowerMode, snapshot.values[.batteryCharge] == nil ? nil
                        : (ProcessInfo.processInfo.isLowPowerModeEnabled ? 1 : 0))
                    return (snapshot, Set(HUDLogSelection.current.columns(fanSample: fanMonitor.sample)))
                }
                HUDPreferences.loggingExplanationDismissed = dismissExplanation
                loggingMenuItem?.toolTip = nil
                updateLoggingMenu()
                reconcileMonitoring()
            } catch {
                presentLoggingError(error, recovery: csvLogger.recoveryURL, title: "Could not start logging")
            }
        }
    }

    private func stopLogging() {
        guard csvLogger.isLogging else { return }
        // Resolving this location does not create or request unrelated folders.
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        do {
            if let saved = try csvLogger.stop(savingTo: desktop) {
                loggingMenuItem?.toolTip = "Last log saved to \(saved.path)"
            }
        } catch {
            presentLoggingError(error, recovery: csvLogger.recoveryURL, title: "Could not save the log")
        }
        updateLoggingMenu()
        reconcileMonitoring()
    }

    private func presentLoggingError(_ error: Error, recovery: URL?, title: String = "Logging stopped") {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        if let recovery {
            alert.informativeText += "\n\nYour recorded data is kept at:\n" + recovery.path
            alert.addButton(withTitle: "Show Recovery File")
        }
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, let recovery {
            NSWorkspace.shared.activateFileViewerSelecting([recovery])
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        stopLogging()
        return .terminateNow
    }

    // MARK: - Shutdown

    func applicationWillTerminate(
        _ notification: Notification
    ) {

        stopLogging()
        temperatureMonitor.stop()
        miscMonitor.stop()
        fanMonitor.stop()
        powerMonitor.stop()
        hudWindow?.shutdown()
        hotkeys.stop()

        // FPS
        fpsMonitor?
            .stop()

        // GPU
        gpuUsageMonitor?
            .stop()

        totalGPUUsageMonitor?
            .stop()

        // CPU
        cpuUsageMonitor?
            .stop()

        totalCPUUsageMonitor?
            .stop()

        // RAM
        ramUsageMonitor?
            .stop()

        totalRAMUsageMonitor?
            .stop()

        memoryPressureMonitor?
            .stop()

        // Battery
        batteryMonitor?
            .stop()

        // Notifications
        NSWorkspace.shared
            .notificationCenter
            .removeObserver(
                self
            )
    }
}
