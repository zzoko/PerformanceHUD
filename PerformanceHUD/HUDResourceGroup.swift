import Foundation

struct HUDPackagePowerOptions: Codable, Equatable {
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

enum HUDUsageMode: String, CaseIterable, Codable {
    case total, app, both
}

nonisolated enum HUDMemoryPressureMode: String, CaseIterable, Sendable, Codable {
    case text, colorText, meter, colorMeter, history, colorHistory

    enum Display: Int, CaseIterable {
        case text, meter, graph

        var title: String {
            switch self {
            case .text: return "Text"
            case .meter: return "Meter"
            case .graph: return "Graph"
            }
        }

        func mode(stateColor: Bool) -> HUDMemoryPressureMode {
            switch self {
            case .text: return stateColor ? .colorText : .text
            case .meter: return stateColor ? .colorMeter : .meter
            case .graph: return stateColor ? .colorHistory : .history
            }
        }
    }

    var display: Display {
        switch self {
        case .text, .colorText: return .text
        case .meter, .colorMeter: return .meter
        case .history, .colorHistory: return .graph
        }
    }

    var usesStateColor: Bool { self == .colorText || self == .colorMeter || self == .colorHistory }
    var isHistory: Bool { display == .graph }

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
        case .colorText: return "Colored text"
        case .meter: return "Meter"
        case .colorMeter: return "Color meter"
        case .history: return "Graph"
        case .colorHistory: return "Colored graph"
        }
    }
}

enum HUDReadingKind: String, CaseIterable, Codable {
    case power, temperature, totalUse, focusedApp, details, pressure
}

enum HUDBatteryFlowMode: String, CaseIterable, Codable {
    case always, auto, off
    var title: String { rawValue.capitalized }
}

struct HUDHeatWarningOptions: Codable, Equatable {
    var enabled = true
    var thresholdCelsius = 95

    static let allowedThresholds = 1...149

    static func defaults(for group: HUDResourceGroup?) -> Self {
        Self(thresholdCelsius: group == nil ? 45 : 95)
    }

    static func parsedThreshold(_ text: String) -> Int? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(text), allowedThresholds.contains(value) else { return nil }
        return value
    }

    func isTriggered(by temperature: Double?) -> Bool {
        guard enabled, let temperature, temperature.isFinite,
              temperature > 0, temperature < 150 else { return false }
        // Match the whole-degree reading visible in the HUD.
        return temperature.rounded() >= Double(thresholdCelsius)
    }
}

struct HUDBatteryOptions: Codable, Equatable {
    var enabled: Bool
    var temperature: Bool
    var charge: Bool
    var temperatureHighlighted: Bool = false
    var flowMode: HUDBatteryFlowMode = .auto
    var powerHighlighted: Bool = false
    var heatWarning: HUDHeatWarningOptions

    // Sampling and logging remain enabled in Auto even while its HUD text is hidden.
    var power: Bool {
        get { flowMode != .off }
        set { flowMode = newValue ? .always : .off }
    }

    init(enabled: Bool, temperature: Bool, charge: Bool,
         temperatureHighlighted: Bool = false, power: Bool? = nil,
         powerHighlighted: Bool = false, flowMode: HUDBatteryFlowMode? = nil,
         heatWarning: HUDHeatWarningOptions = .defaults(for: nil)) {
        self.enabled = enabled
        self.temperature = temperature
        self.charge = charge
        self.temperatureHighlighted = temperatureHighlighted
        self.flowMode = flowMode ?? power.map { $0 ? .always : .off } ?? .auto
        self.powerHighlighted = powerHighlighted
        self.heatWarning = heatWarning
    }
}

enum HUDResourceGroup: String, CaseIterable, Codable {
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

struct HUDResourceOptions: Codable, Equatable {
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
    var heatWarning: HUDHeatWarningOptions = .init()

    var selectedPressureGraphStyle: HUDMemoryPressureMode {
        pressureMode.display != .text ? pressureMode : (pressureGraphStyle.display == .text ? .colorHistory : pressureGraphStyle)
    }

    mutating func selectPressureMode(_ mode: HUDMemoryPressureMode) {
        if pressureMode.display != .text { pressureGraphStyle = pressureMode }
        pressureMode = mode
        if mode.display != .text { pressureGraphStyle = mode }
    }

    var usageVisible: Bool { totalUse }
    var detailsAvailable: Bool { enabled }
    var showsDetails: Bool { detailsAvailable && details }
    var showsPressure: Bool { enabled && pressure }
    var usageHighlighted: Bool { highlighted.contains(.totalUse) }
    var selectedUsageMode: HUDUsageMode {
        usageMode ?? (totalUse && focusedApp ? .both : focusedApp ? .app : .total)
    }

    mutating func setUsagePresentation(visible: Bool, highlighted emphasis: Bool) {
        usageMode = .total
        totalUse = visible
        focusedApp = false
        highlighted.subtract([.totalUse, .focusedApp])
        if emphasis { highlighted.insert(.totalUse) }
    }

    mutating func selectUsageMode(_ mode: HUDUsageMode) {
        let visible = usageVisible
        let emphasis = usageHighlighted
        usageMode = mode
        setUsagePresentation(visible: visible, highlighted: emphasis)
    }

    /// Old app-mode fields remain decodable; current categories own system readings only.
    var systemOnly: Self {
        var result = self
        result.focusedApp = false
        result.usageMode = .total
        result.highlighted.remove(.focusedApp)
        return result
    }

    func visibleMetrics(for group: HUDResourceGroup) -> Set<HUDMetric> {
        guard enabled else { return [] }
        if group == .ram { return totalUse || details || pressure ? [.ramTotal] : [] }
        return (group.supportsTotalUse && totalUse) || (group.supportsTemperature && temperature)
            || (group.supportsPower && power) ? [group.totalMetric] : []
    }
}
