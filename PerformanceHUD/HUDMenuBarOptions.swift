import Foundation

/// Menu-bar visibility is independent of the overlay's category selections.
enum HUDMenuBarReading: String, CaseIterable, Codable {
    case fps
    case gpuPower, gpuTemperature, gpuUsage
    case cpuPower, cpuTemperature, cpuUsage
    case anePower, socPower
    case memoryPressure, memoryDetails, memoryUsage
    case fanUsage
    case batteryPower, batteryTemperature, batteryEnergy
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
