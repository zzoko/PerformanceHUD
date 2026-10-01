import Foundation

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
    // authoritative. Position, helper registration/setup, and other app data stay.
    static func resetOptions(in store: UserDefaults = .standard) {
        var keys = [hudEnabledKey, hudScaleKey, "hud.alignment", "hud.background", "hud.fps.dynamic",
                    "hud.package.power", "hud.package.highlighted",
                    "hud.battery.temperature", "hud.battery.charge", "hud.battery.temperatureHighlighted",
                    "hud.group.ram.details", "hud.fan.usage", "hud.fan.mode",
                    "hud.fan.average", "hud.fan.averageMode", "hud.fan.rpmHighlighted"]
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

    static var alignment: HUDAlignment {
        get { HUDAlignment(rawValue: defaults.string(forKey: "hud.alignment") ?? "") ?? .vertical }
        set { defaults.set(newValue.rawValue, forKey: "hud.alignment") }
    }

    // Opt-in experiment: horizontal always remains static without losing this choice.
    static var dynamicFPS: Bool {
        get { defaults.bool(forKey: "hud.fps.dynamic") }
        set { defaults.set(newValue, forKey: "hud.fps.dynamic") }
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
            // Uncomment to force a background-free HUD without adding Off to the menu.
            // return .off
            let saved = HUDBackground(rawValue: defaults.string(forKey: "hud.background") ?? "")
            // Follow macOS for fresh/reset settings and migrate the hidden Off choice.
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
                                   highlighted: defaults.object(forKey: "hud.package.highlighted") as? Bool ?? true)
        }
        set {
            defaults.set(newValue.enabled, forKey: "hud.package.power")
            defaults.set(newValue.highlighted, forKey: "hud.package.highlighted")
        }
    }

    // Only confirmed fanless hardware changes the initial category default.
    // Persist it to avoid showing the empty category again at the next launch,
    // but never overwrite a user's saved choice (including manually enabling it).
    @discardableResult
    static func applyFanDetectionDefault(_ sample: FanSample, in store: UserDefaults = .standard) -> Bool {
        let key = metricKey(.fans)
        guard sample.status == .noFans, store.object(forKey: key) == nil else { return false }
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
        HUDBatteryOptions(
            enabled: isMetricEnabled(.battery),
            temperature: defaults.object(forKey: "hud.battery.temperature") as? Bool ?? true,
            charge: defaults.object(forKey: "hud.battery.charge") as? Bool ?? true,
            temperatureHighlighted: defaults.bool(forKey: "hud.battery.temperatureHighlighted"))
    }

    static func setBatteryOptions(_ options: HUDBatteryOptions) {
        setMetricEnabled(.battery, enabled: options.enabled)
        defaults.set(options.temperature, forKey: "hud.battery.temperature")
        defaults.set(options.charge, forKey: "hud.battery.charge")
        defaults.set(options.temperatureHighlighted, forKey: "hud.battery.temperatureHighlighted")
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
        // Fresh installs emphasize usage only. An explicitly saved empty array
        // still means the user chose faint readings.
        let defaultHighlights: [HUDReadingKind] = group.supportsTotalUse ? [.totalUse, .focusedApp] : []
        let highlights = defaults.stringArray(forKey: "hud.group.\(group.rawValue).highlighted")
            .map { $0.compactMap(HUDReadingKind.init(rawValue:)) } ?? defaultHighlights
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
        }
    }
}
