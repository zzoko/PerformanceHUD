import Foundation

enum HUDAutoHideMode: String, CaseIterable {
    case fps, off, all
}

enum HUDPreferences {

    // MARK: - Storage

    private static let defaults =
        UserDefaults.standard

    // MARK: - Keys

    private static let hudEnabledKey =
        "hud.enabled"

    private static let hudScaleKey =
        "hud.scale"

    // Remove only display choices so the existing first-launch defaults stay
    // authoritative. The controller resets position separately; helper registration
    // and independent “Don’t show this again” choices stay.
    static func resetOptions(in store: UserDefaults = .standard) {
        var keys = [hudEnabledKey, hudScaleKey, "hud.alignment", "hud.background", "hud.fps.dynamic", "hud.fps.displayMode", "hud.fps.valueHighlighted", "hud.autoHide", "hud.autoHide.mode", "hud.autoHide.animated",
                    "hud.package.power", "hud.package.highlighted",
                    "hud.battery.temperature", "hud.battery.charge", "hud.battery.temperatureHighlighted",
                    "hud.battery.power", "hud.battery.powerHighlighted", "hud.battery.flowMode",
                    "hud.group.ram.details", "hud.fan.usage", "hud.fan.mode",
                    "hud.fan.average", "hud.fan.averageMode", "hud.fan.rpmHighlighted", "hud.misc.readings"]
        keys += HUDMetric.allCases.map { metricKey($0) }
        for group in HUDResourceGroup.allCases {
            keys += ["enabled", "temperature", "power", "highlighted", "usageMode"].map {
                "hud.group.\(group.rawValue).\($0)"
            }
        }
        for key in keys { store.removeObject(forKey: key) }
    }

    // MARK: - HUD Visibility

    static var hudEnabled: Bool {

        get {

            /*
             First launch:
             HUD defaults to enabled.
            */

            if defaults.object(
                forKey: hudEnabledKey
            ) == nil {

                return true
            }

            return defaults.bool(
                forKey: hudEnabledKey
            )
        }

        set {

            defaults.set(
                newValue,
                forKey: hudEnabledKey
            )
        }
    }

    static var autoHideMode: HUDAutoHideMode {
        get { autoHideMode(in: defaults) }
        set { setAutoHideMode(newValue, in: defaults) }
    }

    static func autoHideMode(in store: UserDefaults) -> HUDAutoHideMode {
        if let saved = store.string(forKey: "hud.autoHide.mode").flatMap(HUDAutoHideMode.init(rawValue:)) {
            return saved
        }
        // Preserve choices made with the previous FPS selector and Auto hide prototype.
        if store.bool(forKey: "hud.autoHide") { return .all }
        return (store.object(forKey: "hud.fps.dynamic") as? Bool ?? true) ? .fps : .off
    }

    static func setAutoHideMode(_ mode: HUDAutoHideMode, in store: UserDefaults) {
        store.set(mode.rawValue, forKey: "hud.autoHide.mode")
        store.removeObject(forKey: "hud.autoHide")
        store.removeObject(forKey: "hud.fps.dynamic")
    }

    static var autoHideAnimated: Bool {
        get { autoHideAnimated(in: defaults) }
        set { setAutoHideAnimated(newValue, in: defaults) }
    }

    static func autoHideAnimated(in store: UserDefaults) -> Bool {
        store.object(forKey: "hud.autoHide.animated") as? Bool ?? true
    }

    static func setAutoHideAnimated(_ animated: Bool, in store: UserDefaults) {
        store.set(animated, forKey: "hud.autoHide.animated")
    }

    // Dialog suppression choices are independent and survive display-option resets.
    // Each is saved only after its own dialog is confirmed.
    static var autoHideExplanationDismissed: Bool {
        get { defaults.bool(forKey: "hud.autoHide.explanationDismissed") }
        set { defaults.set(newValue, forKey: "hud.autoHide.explanationDismissed") }
    }

    static var resetOptionsConfirmationDismissed: Bool {
        get { defaults.bool(forKey: "hud.resetOptions.confirmationDismissed") }
        set { defaults.set(newValue, forKey: "hud.resetOptions.confirmationDismissed") }
    }

    static var loggingExplanationDismissed: Bool {
        get { defaults.bool(forKey: "hud.logging.explanationDismissed") }
        set { defaults.set(newValue, forKey: "hud.logging.explanationDismissed") }
    }

    static var alignment: HUDAlignment {
        get { HUDAlignment(rawValue: defaults.string(forKey: "hud.alignment") ?? "") ?? .vertical }
        set { defaults.set(newValue.rawValue, forKey: "hud.alignment") }
    }

    static var fpsOptions: HUDFPSOptions {
        get { fpsOptions(in: defaults) }
        set { setFPSOptions(newValue, in: defaults) }
    }

    static func fpsOptions(in store: UserDefaults) -> HUDFPSOptions {
        let value = store.object(forKey: metricKey(.fps)) as? Bool ?? HUDMetric.fps.defaultEnabled
        let history = store.object(forKey: metricKey(.fpsGraph)) as? Bool ?? HUDMetric.fpsGraph.defaultEnabled
        let mode: HUDFPSDisplayMode = value && history ? .both : value ? .value : history ? .history
            : store.string(forKey: "hud.fps.displayMode").flatMap(HUDFPSDisplayMode.init(rawValue:)) ?? .both
        return HUDFPSOptions(enabled: value || history, mode: mode,
                             valueHighlighted: store.object(forKey: "hud.fps.valueHighlighted") as? Bool ?? true)
    }

    static func setFPSOptions(_ options: HUDFPSOptions, in store: UserDefaults) {
        store.set(options.mode.rawValue, forKey: "hud.fps.displayMode")
        store.set(options.valueHighlighted, forKey: "hud.fps.valueHighlighted")
        let metrics = options.visibleMetrics(alignment: .vertical)
        store.set(metrics.contains(.fps), forKey: metricKey(.fps))
        store.set(metrics.contains(.fpsGraph), forKey: metricKey(.fpsGraph))
    }

    // MARK: - HUD Scale

    static var hudScale: HUDScale {

        get {

            /*
             First launch:
             HUD size defaults to 1x.
            */

            guard
                defaults.object(
                    forKey: hudScaleKey
                ) != nil
            else {
                return .normal
            }

            let value =
                defaults.double(
                    forKey: hudScaleKey
                )

            return HUDScale(
                rawValue: value
            )
        }

        set {

            defaults.set(
                newValue.rawValue,
                forKey: hudScaleKey
            )
        }
    }

    // MARK: - Background

    static var background: HUDBackground {
        get {
            let saved = HUDBackground(rawValue: defaults.string(forKey: "hud.background") ?? "")
            // Follow macOS for fresh/reset settings and migrate the retired Clear/Off choices.
            guard let saved, saved == .system || HUDBackground.menuOptions.contains(saved) else { return .system }
            return saved
        }
        set {
            defaults.set(newValue.rawValue, forKey: "hud.background")
        }
    }

    // MARK: - Position

    static var hudPosition: CGPoint? {
        get {
            guard let value = defaults.dictionary(forKey: "hud.position"),
                  let x = value["x"] as? Double,
                  let y = value["y"] as? Double,
                  x.isFinite, y.isFinite else { return nil }
            return CGPoint(x: x, y: y)
        }
        set {
            if let point = newValue {
                defaults.set(["x": Double(point.x), "y": Double(point.y)], forKey: "hud.position")
            } else {
                defaults.removeObject(forKey: "hud.position")
            }
        }
    }

    // MARK: - Metric Visibility

    static var miscOptions: HUDMiscOptions {
        get { miscOptions(in: defaults) }
        set { setMiscOptions(newValue, in: defaults) }
    }

    static func miscOptions(in store: UserDefaults) -> HUDMiscOptions {
        HUDMiscOptions(enabled: store.bool(forKey: metricKey(.misc)),
            readings: store.stringArray(forKey: "hud.misc.readings")
                .map { Set($0.compactMap(HUDMiscReading.init(rawValue:))) } ?? Set(HUDMiscReading.allCases))
    }

    static func setMiscOptions(_ options: HUDMiscOptions, in store: UserDefaults) {
        store.set(options.enabled, forKey: metricKey(.misc))
        store.set(options.readings.map(\.rawValue).sorted(), forKey: "hud.misc.readings")
    }

    static func isMetricEnabled(
        _ metric: HUDMetric
    ) -> Bool {

        let key =
            metricKey(
                metric
            )

        /*
         If this metric has never had a saved
         preference, use its defaultEnabled value.
        */

        if defaults.object(
            forKey: key
        ) == nil {

            return metric.defaultEnabled
        }

        return defaults.bool(
            forKey: key
        )
    }

    static func setMetricEnabled(
        _ metric: HUDMetric,
        enabled: Bool
    ) {

        defaults.set(
            enabled,
            forKey:
                metricKey(
                    metric
                )
        )
    }

    // MARK: - Metric Keys

    static var packagePowerOptions: HUDPackagePowerOptions {
        get {
            HUDPackagePowerOptions(enabled: defaults.object(forKey: "hud.package.power") as? Bool ?? true,
                                   highlighted: defaults.object(forKey: "hud.package.highlighted") as? Bool ?? false)
        }
        set {
            defaults.set(newValue.enabled, forKey: "hud.package.power")
            defaults.set(newValue.highlighted, forKey: "hud.package.highlighted")
        }
    }

    // Only confirmed fanless hardware forces the category off. Temporary read
    // failures preserve the user's selection and the known fan topology.
    @discardableResult
    static func applyFanAvailability(_ sample: FanSample, in store: UserDefaults = .standard) -> Bool {
        let key = metricKey(.fans)
        guard sample.status == .noFans, store.object(forKey: key) as? Bool != false else { return false }
        store.set(false, forKey: key)
        return true
    }

    static var fanOptions: HUDFanOptions {
        get { HUDFanOptions(enabled: isMetricEnabled(.fans),
            usage: defaults.object(forKey: "hud.fan.usage") as? Bool ?? true,
            mode: defaults.string(forKey: "hud.fan.mode").flatMap(HUDFanMode.init(rawValue:)) ?? .both,
            average: defaults.object(forKey: "hud.fan.average") as? Bool ?? true,
            averageMode: defaults.string(forKey: "hud.fan.averageMode").flatMap(HUDFanAverageMode.init(rawValue:)) ?? .horizontal,
            rpmHighlighted: defaults.bool(forKey: "hud.fan.rpmHighlighted")) }
        set {
            setMetricEnabled(.fans, enabled: newValue.enabled)
            defaults.set(newValue.usage, forKey: "hud.fan.usage")
            defaults.set(newValue.mode.rawValue, forKey: "hud.fan.mode")
            defaults.set(newValue.average, forKey: "hud.fan.average")
            defaults.set(newValue.averageMode.rawValue, forKey: "hud.fan.averageMode")
            defaults.set(newValue.rpmHighlighted, forKey: "hud.fan.rpmHighlighted")
        }
    }

    static var batteryOptions: HUDBatteryOptions {
        batteryOptions(in: defaults)
    }

    static func batteryOptions(in store: UserDefaults) -> HUDBatteryOptions {
        HUDBatteryOptions(
            enabled: store.object(forKey: metricKey(.battery)) as? Bool ?? HUDMetric.battery.defaultEnabled,
            temperature: store.object(forKey: "hud.battery.temperature") as? Bool ?? true,
            charge: store.object(forKey: "hud.battery.charge") as? Bool ?? true,
            temperatureHighlighted: store.bool(forKey: "hud.battery.temperatureHighlighted"),
            power: store.object(forKey: "hud.battery.power") as? Bool,
            powerHighlighted: store.bool(forKey: "hud.battery.powerHighlighted"),
            flowMode: store.string(forKey: "hud.battery.flowMode").flatMap(HUDBatteryFlowMode.init(rawValue:)))
    }

    static func setBatteryOptions(_ options: HUDBatteryOptions, in store: UserDefaults = .standard) {
        store.set(options.enabled, forKey: metricKey(.battery))
        store.set(options.temperature, forKey: "hud.battery.temperature")
        store.set(options.charge, forKey: "hud.battery.charge")
        store.set(options.temperatureHighlighted, forKey: "hud.battery.temperatureHighlighted")
        store.set(options.power, forKey: "hud.battery.power")
        store.set(options.powerHighlighted, forKey: "hud.battery.powerHighlighted")
        store.set(options.flowMode.rawValue, forKey: "hud.battery.flowMode")
    }

    static func resourceOptions(for group: HUDResourceGroup) -> HUDResourceOptions {
        let total = group.supportsTotalUse && isMetricEnabled(group.totalMetric)
        let app = group.appMetric.map { isMetricEnabled($0) } ?? false
        let temperature = group.supportsTemperature
            && (defaults.object(forKey: "hud.group.\(group.rawValue).temperature") as? Bool ?? true)
        let power = group.supportsPower
            && (defaults.object(forKey: "hud.group.\(group.rawValue).power") as? Bool ?? true)
        let enabled = defaults.object(forKey: "hud.group.\(group.rawValue).enabled") as? Bool
            ?? (total || app || temperature || (group == .ane && power))
        // Fresh installs and All options reset use regular readings. Preserve
        // individually saved emphasis choices when updating the app.
        let highlights = defaults.stringArray(forKey: "hud.group.\(group.rawValue).highlighted")
            .map { $0.compactMap(HUDReadingKind.init(rawValue:)) } ?? []
        var options = HUDResourceOptions(enabled: enabled, temperature: temperature, totalUse: total, focusedApp: app, power: power,
            details: defaults.object(forKey: "hud.group.ram.details") as? Bool ?? true,
            highlighted: Set(highlights),
            usageMode: defaults.string(forKey: "hud.group.\(group.rawValue).usageMode").flatMap(HUDUsageMode.init(rawValue:)))
        options.setUsagePresentation(visible: options.usageVisible, highlighted: options.usageHighlighted)
        return options
    }

    static func setResourceOptions(_ options: HUDResourceOptions, for group: HUDResourceGroup) {
        defaults.set(options.enabled, forKey: "hud.group.\(group.rawValue).enabled")
        defaults.set(options.selectedUsageMode.rawValue, forKey: "hud.group.\(group.rawValue).usageMode")
        defaults.set(options.highlighted.map(\.rawValue).sorted(), forKey: "hud.group.\(group.rawValue).highlighted")
        defaults.set(options.temperature && group.supportsTemperature, forKey: "hud.group.\(group.rawValue).temperature")
        defaults.set(options.power && group.supportsPower, forKey: "hud.group.\(group.rawValue).power")
        if group == .ram { defaults.set(options.details, forKey: "hud.group.ram.details") }
        setMetricEnabled(group.totalMetric, enabled: group.supportsTotalUse && options.totalUse)
        if let appMetric = group.appMetric { setMetricEnabled(appMetric, enabled: options.focusedApp) }
    }

    static var visibleMetrics: Set<HUDMetric> {
        var metrics = Set(HUDMetric.allCases.filter { isMetricEnabled($0) })
        metrics.subtract([.fps, .fpsGraph])
        metrics.formUnion(fpsOptions.visibleMetrics(alignment: alignment))
        if miscOptions.visibleReadings.isEmpty { metrics.remove(.misc) }
        for group in HUDResourceGroup.allCases {
            if let appMetric = group.appMetric { metrics.remove(appMetric) }
            metrics.remove(group.totalMetric)
            metrics.formUnion(resourceOptions(for: group).visibleMetrics(for: group))
        }
        return Set(metrics.filter { alignment.allows($0) })
    }

    private static func metricKey(
        _ metric: HUDMetric
    ) -> String {

        switch metric {

        case .fps:
            return "hud.metric.fps"

        case .fpsGraph:
            return "hud.metric.fpsGraph"

        case .gpu:
            return "hud.metric.gpu"

        case .gpuTotal:
            return "hud.metric.gpuTotal"

        case .cpu:
            return "hud.metric.cpu"

        case .cpuTotal:
            return "hud.metric.cpuTotal"

        case .aneTotal:
            return "hud.metric.aneTotal"

        case .ram:
            return "hud.metric.ram"

        case .ramTotal:
            return "hud.metric.ramTotal"

        case .fans:
            return "hud.metric.fans"

        case .battery:
            return "hud.metric.battery"

        case .deviceInfo:
            return "hud.metric.deviceInfo"
        case .misc:
            return "hud.metric.misc"
        }
    }
}
