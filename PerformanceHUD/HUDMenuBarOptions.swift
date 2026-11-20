import Foundation

/// Menu-bar visibility is independent of the overlay's category selections.
enum HUDMenuBarReading: String, CaseIterable, Codable {
    case fps
    case gpuPower, gpuTemperature, gpuUsage, gpuCores
    case cpuPower, cpuTemperature, cpuUsage, cpuCores
    case anePower, socPower
    case memoryPressure, memoryDetails, memoryUsage
    case fanUsage
    case batteryPower, batteryTemperature, batteryEnergy

    static let fanMode = HUDFanMode.rpm

    static func pressureMode(_ mode: HUDMemoryPressureMode) -> HUDMemoryPressureMode {
        mode.resolved(for: .horizontal)
    }

    /// Maps a HUD selector segment to the format its pin actually displays.
    func outputSegment(for segment: Int) -> Int? {
        guard segment >= 0 else { return nil }
        switch self {
        case .fps:
            return HUDFPSDisplayMode.allCases.firstIndex(of: .value)
        case .fanUsage:
            return HUDFanMode.allCases.firstIndex(of: Self.fanMode)
        case .memoryPressure:
            guard let display = HUDMemoryPressureMode.Display(rawValue: segment) else { return nil }
            return Self.pressureMode(display.mode(stateColor: false)).display.rawValue
        case .cpuCores:
            return segment
        case .batteryPower:
            guard HUDBatteryFlowMode.allCases.indices.contains(segment),
                  HUDBatteryFlowMode.allCases[segment] != .off else { return nil }
            return segment
        default:
            return nil
        }
    }
}

struct HUDMenuBarOptions: Equatable {
    var readings: Set<HUDMenuBarReading> = []
    var isCollapsed = false

    static let readingsKey = "hud.menuBar.readings"
    static let collapsedKey = "hud.menuBar.collapsed"

    // Collapsing retains the selection, but hidden readings do not need sampling.
    var activeReadings: Set<HUDMenuBarReading> { isCollapsed ? [] : readings }

    static func load(in store: UserDefaults = .standard) -> Self {
        Self(readings: Set((store.stringArray(forKey: readingsKey) ?? []).compactMap(HUDMenuBarReading.init(rawValue:))),
             isCollapsed: store.bool(forKey: collapsedKey))
    }

    func save(in store: UserDefaults = .standard) {
        store.set(readings.map(\.rawValue).sorted(), forKey: Self.readingsKey)
        store.set(isCollapsed, forKey: Self.collapsedKey)
    }
}

extension HUDPreferences {
    static var menuBarOptions: HUDMenuBarOptions {
        get { HUDMenuBarOptions.load() }
        set { newValue.save() }
    }
}
