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
            ) ?? .normal
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
            // Migrate a previously saved Off choice while that option is hidden.
            guard let saved, HUDBackground.menuOptions.contains(saved) else { return .transparent }
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

    static func resourceOptions(for group: HUDResourceGroup) -> HUDResourceOptions {
        let total = isMetricEnabled(group.totalMetric)
        let app = isMetricEnabled(group.appMetric)
        let temperature = group.supportsTemperature
            && (defaults.object(forKey: "hud.group.\(group.rawValue).temperature") as? Bool ?? true)
        let enabled = defaults.object(forKey: "hud.group.\(group.rawValue).enabled") as? Bool
            ?? (total || app || temperature)
        return HUDResourceOptions(enabled: enabled, temperature: temperature, totalUse: total, focusedApp: app)
    }

    static func setResourceOptions(_ options: HUDResourceOptions, for group: HUDResourceGroup) {
        defaults.set(options.enabled, forKey: "hud.group.\(group.rawValue).enabled")
        defaults.set(options.temperature && group.supportsTemperature, forKey: "hud.group.\(group.rawValue).temperature")
        setMetricEnabled(group.totalMetric, enabled: options.totalUse)
        setMetricEnabled(group.appMetric, enabled: options.focusedApp)
    }

    static var visibleMetrics: Set<HUDMetric> {
        var metrics = Set(HUDMetric.allCases.filter { isMetricEnabled($0) })
        for group in HUDResourceGroup.allCases {
            metrics.remove(group.appMetric)
            metrics.remove(group.totalMetric)
            metrics.formUnion(resourceOptions(for: group).visibleMetrics(for: group))
        }
        return metrics
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

        case .ram:
            return "hud.metric.ram"

        case .ramTotal:
            return "hud.metric.ramTotal"

        case .battery:
            return "hud.metric.battery"

        case .deviceInfo:
            return "hud.metric.deviceInfo"
        }
    }
}
