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

nonisolated enum HUDMemoryPressureMode: String, CaseIterable, Sendable {
    case text, meter, colorMeter, history, colorHistory

    static let graphStyles: [Self] = [.meter, .colorMeter, .history, .colorHistory]
    var isHistory: Bool { self == .history || self == .colorHistory }

    func resolved(for alignment: HUDAlignment) -> Self {
        guard alignment == .horizontal else { return self }
        switch self {
        case .history: return .meter
        case .colorHistory: return .colorMeter
        default: return self
        }
    }

    init?(storedValue: String) {
        switch storedValue {
        case "graph": self = .meter
        case "colorGraph": self = .colorMeter
        default:
            guard let mode = Self(rawValue: storedValue) else { return nil }
            self = mode
        }
    }

    var title: String {
        switch self {
        case .text: return "Text"
        case .meter: return "Meter"
        case .colorMeter: return "Color meter"
        case .history: return "Graph"
        case .colorHistory: return "Colored graph"
        }
    }
}

enum HUDReadingKind: String, CaseIterable {
    case power, temperature, totalUse, focusedApp, details, pressure
}

enum HUDBatteryFlowMode: String, CaseIterable {
    case always, auto, off
    var title: String { rawValue.capitalized }
}

struct HUDBatteryOptions: Equatable {
    var enabled: Bool
    var temperature: Bool
    var charge: Bool
    var temperatureHighlighted: Bool = false
    var flowMode: HUDBatteryFlowMode = .auto
    var powerHighlighted: Bool = false

    // Sampling and logging remain enabled in Auto even while its HUD text is hidden.
    var power: Bool {
        get { flowMode != .off }
        set { flowMode = newValue ? .always : .off }
    }

    init(enabled: Bool, temperature: Bool, charge: Bool,
         temperatureHighlighted: Bool = false, power: Bool? = nil,
         powerHighlighted: Bool = false, flowMode: HUDBatteryFlowMode? = nil) {
        self.enabled = enabled
        self.temperature = temperature
        self.charge = charge
        self.temperatureHighlighted = temperatureHighlighted
        self.flowMode = flowMode ?? power.map { $0 ? .always : .off } ?? .auto
        self.powerHighlighted = powerHighlighted
    }
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
    var pressure: Bool = true
    var highlighted: Set<HUDReadingKind> = []
    var usageMode: HUDUsageMode?
    var pressureMode: HUDMemoryPressureMode = .colorHistory
    var pressureGraphStyle: HUDMemoryPressureMode = .colorHistory

    var selectedPressureGraphStyle: HUDMemoryPressureMode {
        pressureMode != .text ? pressureMode : (pressureGraphStyle == .text ? .colorHistory : pressureGraphStyle)
    }

    mutating func selectPressureMode(_ mode: HUDMemoryPressureMode) {
        if pressureMode != .text { pressureGraphStyle = pressureMode }
        pressureMode = mode
        if mode != .text { pressureGraphStyle = mode }
    }

    var usageVisible: Bool { totalUse || focusedApp }
    var detailsAvailable: Bool { enabled }
    var showsDetails: Bool { detailsAvailable && details }
    var showsPressure: Bool { enabled && pressure && selectedUsageMode != .app }
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
            if selectedUsageMode != .app && (usageVisible || showsDetails || showsPressure) { metrics.insert(.ramTotal) }
            if selectedUsageMode != .total && (usageVisible || showsDetails) { metrics.insert(.ram) }
            return metrics
        }
        if focusedApp, let appMetric = group.appMetric { metrics.insert(appMetric) }
        if (group.supportsTotalUse && totalUse) || (group.supportsTemperature && temperature) || (group.supportsPower && power) {
            metrics.insert(group.totalMetric)
        }
        return metrics
    }
}
