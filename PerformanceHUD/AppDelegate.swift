import AppKit

@MainActor
final class AppDelegate:
    NSObject,
    NSApplicationDelegate {

    // MARK: - HUD

    private var hudWindow:
        HUDWindowController?

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

    // MARK: - Menu Bar

    private var statusItem:
        NSStatusItem?

    private let toggleShortcut = HUDToggleShortcut()

    private var hudVisibilityMenuItem:
        NSMenuItem?

    private var metricMenuItems:
        [HUDMetric: NSMenuItem] = [:]

    private var sizeMenuView:
        HUDSizeMenuView?

    private var backgroundMenuView: HUDBackgroundMenuView?

    private var backgroundStatusItem: NSMenuItem?
    private var backgroundSettingsItem: NSMenuItem?
    private var backgroundRetryItem: NSMenuItem?

    // MARK: - State

    private var hudEnabled =
        HUDPreferences.hudEnabled

    private var hudScale =
        HUDPreferences.hudScale

    private var hudBackground = HUDPreferences.background

    private var enabledMetrics = HUDPreferences.visibleMetrics
    private let temperatureMonitor = TemperatureMonitor()

    // MARK: - Launch

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {

        // No Dock icon.
        NSApp.setActivationPolicy(
            .accessory
        )

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
            self?.hudWindow?.updateTemperatures(sample)
        }

        // RAM
        setupRAMUsageMonitor()
        setupTotalRAMUsageMonitor()
        setupMemoryPressureMonitor()

        // Battery
        setupBatteryMonitor()

        // Menu
        setupMenuBar()
        setupHUDShortcut()

        // Active app detection
        setupApplicationMonitoring()

        monitorFrontmostApplication()
        reconcileMonitoring()
    }

    // MARK: - HUD Setup

    private func setupHUD() {

        let hud =
            HUDWindowController()
        for group in HUDResourceGroup.allCases {
            hud.setResourceOptions(HUDPreferences.resourceOptions(for: group), for: group)
        }

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
            self?.hudWindow?.updateRAM(.ram, usage: usage)
        }
        self.ramUsageMonitor = monitor
    }

    // MARK: - Total RAM

    private func setupTotalRAMUsageMonitor() {
        let monitor = TotalRAMUsageMonitor()
        monitor.onRAMUsageUpdate = { [weak self] usage in
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
            self?.hudWindow?.updateBattery(sample)
        }

        self.batteryMonitor =
            monitor

    }

    // MARK: - Menu Bar

    private func setupMenuBar() {

        let statusItem =
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

        // MARK: HUD Position

        let positionView = HUDPositionMenuView()
        positionView.onReset = { [weak self] in
            self?.hudWindow?.resetPosition()
        }
        let positionItem = NSMenuItem()
        positionItem.view = positionView
        menu.addItem(positionItem)

        // MARK: HUD Background

        let backgroundView = HUDBackgroundMenuView(selectedBackground: hudBackground)
        backgroundView.onBackgroundSelected = { [weak self] background in
            self?.hudBackground = background
            HUDPreferences.background = background
            self?.hudWindow?.setBackground(background)
        }
        let backgroundItem = NSMenuItem()
        backgroundItem.view = backgroundView
        menu.addItem(backgroundItem)
        self.backgroundMenuView = backgroundView

        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let settings = NSMenuItem(title: "Screen Recording Settings…", action: #selector(openScreenRecordingSettings), keyEquivalent: "")
        let retry = NSMenuItem(title: "Retry Background", action: #selector(retryBackground), keyEquivalent: "")
        settings.target = self
        retry.target = self
        for item in [status, settings, retry] { item.isHidden = true; menu.addItem(item) }
        backgroundStatusItem = status
        backgroundSettingsItem = settings
        backgroundRetryItem = retry
        hudWindow?.onCaptureStateChange = { [weak self] state in self?.updateCaptureStatus(state) }
        if let state = hudWindow?.captureState { updateCaptureStatus(state) }

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
            item.state = enabledMetrics.contains(metric) ? .on : .off
            if metric == .fpsGraph {
                item.toolTip = "Shows FPS trends over the last 60 seconds, using approximately one reading per second."
            }
            menu.addItem(item)
            metricMenuItems[metric] = item
            addMetricPadding()
        }
        addMetric(.fps)
        addMetric(.fpsGraph)
        for group in HUDResourceGroup.allCases {
            let view = HUDResourceMenuView(group: group, options: HUDPreferences.resourceOptions(for: group))
            view.onChange = { [weak self] options in
                guard let self else { return }
                HUDPreferences.setResourceOptions(options, for: group)
                enabledMetrics = HUDPreferences.visibleMetrics
                hudWindow?.setResourceOptions(options, for: group)
                reconcileMonitoring()
            }
            let item = NSMenuItem()
            item.view = view
            menu.addItem(item)
        }
        addMetric(.battery)
        addMetric(.deviceInfo)

        // Separator before Close App.

        menu.addItem(
            .separator()
        )

        // MARK: Close App

        let closeItem =
            NSMenuItem(
                title:
                    "Close App",
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

        menu.addItem(.separator())

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let versionItem = NSMenuItem(title: "App version \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        statusItem.menu =
            menu

        self.statusItem =
            statusItem
    }

    private func updateCaptureStatus(_ state: HUDGlassCaptureState) {
        backgroundStatusItem?.isHidden = !state.needsAttention
        backgroundSettingsItem?.isHidden = !state.needsAttention
        backgroundRetryItem?.isHidden = !state.needsAttention
        switch state {
        case .permissionRequired:
            backgroundStatusItem?.title = "Screen Recording permission needed"
            backgroundStatusItem?.toolTip = "Allow PerformanceHUD in System Settings, then choose Retry Background. Metrics still work with a plain background."
        case .failed(let message):
            backgroundStatusItem?.title = "Glass background unavailable"
            backgroundStatusItem?.toolTip = message
        default:
            backgroundStatusItem?.toolTip = nil
        }
    }

    @objc private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func retryBackground() { hudWindow?.retryBackground() }

    private func setupHUDShortcut() {
        toggleShortcut.onToggle = { [weak self] in
            self?.toggleHUD(nil)
        }
        let status = toggleShortcut.start()
        if status == 0 {
            // AppKit draws the right-aligned, subdued shortcut glyphs.
            hudVisibilityMenuItem?.keyEquivalent = HUDToggleShortcut.menuKey
            hudVisibilityMenuItem?.keyEquivalentModifierMask = HUDToggleShortcut.menuModifiers
        } else {
            hudVisibilityMenuItem?.toolTip = "Control + Option + Command + H could not be registered. Another app may be using it."
            NSLog("PerformanceHUD: toggle shortcut registration failed (%d)", status)
        }
    }

    // MARK: - Enable / Disable HUD

    @objc
    private func toggleHUD(
        _ sender: NSMenuItem?
    ) {

        hudEnabled.toggle()

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

    // MARK: - HUD Scale

    private func setHUDScale(
        _ newScale: HUDScale
    ) {

        hudScale =
            newScale

        // Save preference.
        HUDPreferences.hudScale =
            newScale

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
        guard
            pid != currentPID
        else {
            return
        }

        currentPID =
            pid

        let appName =
            app.localizedName
            ?? "Unknown"

        print(
            "Active application:",
            appName,
            "PID:",
            pid
        )

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

    // Collect only visible metrics. Each monitor's start is idempotent for its
    // current session, so changing an unrelated toggle does not reset baselines.
    private func reconcileMonitoring() {
        var metrics = hudEnabled ? enabledMetrics : []
        // A temperature-only row is visible without collecting its utilization counter.
        for group in HUDResourceGroup.allCases where !HUDPreferences.resourceOptions(for: group).totalUse {
            metrics.remove(group.totalMetric)
        }
        let cpu = HUDPreferences.resourceOptions(for: .cpu)
        let gpu = HUDPreferences.resourceOptions(for: .gpu)
        temperatureMonitor.configure(cpu: hudEnabled && cpu.enabled && cpu.temperature,
                                     gpu: hudEnabled && gpu.enabled && gpu.temperature)
        if metrics.contains(.gpuTotal) { totalGPUUsageMonitor?.start() }
        else { totalGPUUsageMonitor?.stop(); hudWindow?.updateMetric(.gpuTotal, value: "") }
        if metrics.contains(.cpuTotal) { totalCPUUsageMonitor?.start() }
        else { totalCPUUsageMonitor?.stop(); hudWindow?.updateMetric(.cpuTotal, value: "") }
        if metrics.contains(.ramTotal) { totalRAMUsageMonitor?.start() }
        else { totalRAMUsageMonitor?.stop(); hudWindow?.updateRAM(.ramTotal, usage: nil) }
        if metrics.contains(.ramTotal) { memoryPressureMonitor?.start() }
        else { memoryPressureMonitor?.stop(); hudWindow?.updateMemoryPressure("") }
        if metrics.contains(.battery) { batteryMonitor?.start() }
        else { batteryMonitor?.stop(); hudWindow?.updateMetric(.battery, value: "") }

        if metrics.contains(.gpu), let pid = currentPID { gpuUsageMonitor?.start(pid: pid) }
        else { gpuUsageMonitor?.stop(); hudWindow?.updateMetric(.gpu, value: "") }
        if metrics.contains(.cpu), let pid = currentPID { cpuUsageMonitor?.start(pid: pid) }
        else { cpuUsageMonitor?.stop(); hudWindow?.updateMetric(.cpu, value: "") }
        if metrics.contains(.ram), let pid = currentPID { ramUsageMonitor?.start(pid: pid) }
        else { ramUsageMonitor?.stop(); hudWindow?.updateRAM(.ram, usage: nil) }
        if (metrics.contains(.fps) || metrics.contains(.fpsGraph)), let pid = currentPID {
            do { try fpsMonitor?.start(pid: pid) }
            catch { hudWindow?.markFPSUnavailable() }
        } else {
            fpsMonitor?.stop()
            hudWindow?.resetFPS()
        }
    }

    // MARK: - Shutdown

    func applicationWillTerminate(
        _ notification: Notification
    ) {

        temperatureMonitor.stop()
        hudWindow?.shutdown()
        toggleShortcut.stop()

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
