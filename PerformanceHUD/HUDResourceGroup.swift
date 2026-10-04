import Foundation

struct HUDPackagePowerOptions: Equatable {
    var enabled = true
    var highlighted = false
}

/// Sampling is needed for any visible power reading, including Package by itself.
enum HUDPowerDemand {
    static func isNeeded(hudEnabled: Bool,
                         resources: [HUDResourceGroup: HUDResourceOptions], package: HUDPackagePowerOptions) -> Bool {
        hudEnabled && (package.enabled || resources.contains { group, options in
            group.supportsPower && options.enabled && options.power
        })
    }
}

enum HUDUsageMode: String, CaseIterable {
    case total, app, both
}

enum HUDReadingKind: String, CaseIterable {
    case power, temperature, totalUse, focusedApp, details
}

struct HUDBatteryOptions: Equatable {
    var enabled: Bool
    var temperature: Bool
    var charge: Bool
    var temperatureHighlighted: Bool = false
}

enum HUDResourceGroup: String, CaseIterable {
    case gpu, cpu, ane, ram

    var title: String { self == .ram ? "MEM" : rawValue.uppercased() }
    var supportsTemperature: Bool { self == .cpu || self == .gpu }
    var supportsTotalUse: Bool { self != .ane }
    var supportsPower: Bool { self != .ram }
    var appMetric: HUDMetric? {
        switch self { case .gpu: return .gpu; case .cpu: return .cpu; case .ram: return .ram; case .ane: return nil }
    }
    var totalMetric: HUDMetric {
        switch self { case .gpu: return .gpuTotal; case .cpu: return .cpuTotal; case .ram: return .ramTotal; case .ane: return .aneTotal }
    }
}

struct HUDResourceOptions: Equatable {
    var enabled: Bool
    var temperature: Bool
    var totalUse: Bool
    var focusedApp: Bool
    var power: Bool = false
    var details: Bool = true
    var highlighted: Set<HUDReadingKind> = []
    var usageMode: HUDUsageMode?

    var usageVisible: Bool { totalUse || focusedApp }
    var detailsAvailable: Bool { enabled }
    var showsDetails: Bool { detailsAvailable && details }
    var usageHighlighted: Bool { !highlighted.isDisjoint(with: [.totalUse, .focusedApp]) }
    var selectedUsageMode: HUDUsageMode {
        usageMode ?? (totalUse && focusedApp ? .both : focusedApp ? .app : .total)
    }

    mutating func setUsagePresentation(visible: Bool, highlighted emphasis: Bool) {
        let mode = selectedUsageMode
        usageMode = mode
        totalUse = visible && mode != .app
        focusedApp = visible && mode != .total
        highlighted.subtract([.totalUse, .focusedApp])
        if emphasis { highlighted.formUnion([.totalUse, .focusedApp]) }
    }

    mutating func selectUsageMode(_ mode: HUDUsageMode) {
        let visible = usageVisible
        let emphasis = usageHighlighted
        usageMode = mode
        setUsagePresentation(visible: visible, highlighted: emphasis)
    }

    func visibleMetrics(for group: HUDResourceGroup) -> Set<HUDMetric> {
        guard enabled else { return [] }
        var metrics = Set<HUDMetric>()
        if group == .ram {
            guard usageVisible || showsDetails else { return [] }
            if selectedUsageMode != .app { metrics.insert(.ramTotal) }
            if selectedUsageMode != .total { metrics.insert(.ram) }
            return metrics
        }
        if focusedApp, let appMetric = group.appMetric { metrics.insert(appMetric) }
        if (group.supportsTotalUse && totalUse) || (group.supportsTemperature && temperature) || (group.supportsPower && power) {
            metrics.insert(group.totalMetric)
        }
        return metrics
    }
}
