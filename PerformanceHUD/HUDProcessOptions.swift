import Foundation

enum HUDProcessReading: String, CaseIterable, Codable {
    case gpu, cpu, memory
    var title: String { self == .memory ? "Memory" : rawValue.uppercased() }
}

struct HUDProcessOptions: Codable, Equatable {
    var enabled = false
    var readings = Set(HUDProcessReading.allCases)
    var highlighted: Set<HUDProcessReading> = []

    static func migrating(resources: [HUDResourceGroup: HUDResourceOptions], misc: HUDMiscOptions) -> Self {
        var result = Self(enabled: misc.enabled && misc.readings.contains(.process), readings: [])
        for (group, reading) in [(HUDResourceGroup.gpu, HUDProcessReading.gpu), (.cpu, .cpu), (.ram, .memory)] {
            guard let old = resources[group], old.enabled, old.focusedApp else { continue }
            result.enabled = true; result.readings.insert(reading)
            if old.highlighted.contains(.focusedApp) || (group == .ram && old.highlighted.contains(.details)) {
                result.highlighted.insert(reading)
            }
        }
        if !result.enabled { result.readings = Set(HUDProcessReading.allCases) }
        return result
    }
}

enum HUDCoreDisplayMode: String, CaseIterable, Codable {
    case value, bars, both
    var title: String {
        switch self {
        case .value: return "GHz"
        case .bars: return "Load"
        case .both: return "Both"
        }
    }
    var showsValue: Bool { self != .bars }
    var showsBars: Bool { self != .value }
}

struct HUDCoreOptions: Codable, Equatable {
    var enabled = false
    var mode: HUDCoreDisplayMode = .both
    var highlighted = false

    static let cpuDefault = Self(enabled: true, mode: .bars)
    static let gpuDefault = Self(enabled: false, mode: .value)

    // GPU keeps the shared preference shape but no longer has a display mode.
    var gpuFrequencyOnly: Self { Self(enabled: enabled, mode: .value, highlighted: highlighted) }
}

extension HUDPreferences {
    static var processOptions: HUDProcessOptions {
        get { processOptions(in: .standard) }
        set { setProcessOptions(newValue, in: .standard) }
    }

    static func processOptions(in store: UserDefaults) -> HUDProcessOptions {
        guard let data = store.data(forKey: "hud.process.options"),
              let options = try? JSONDecoder().decode(HUDProcessOptions.self, from: data) else { return .init() }
        return options
    }

    static func setProcessOptions(_ options: HUDProcessOptions, in store: UserDefaults) {
        store.set(try? JSONEncoder().encode(options), forKey: "hud.process.options")
    }

    static var gpuCoreOptions: HUDCoreOptions {
        get { gpuCoreOptions(in: .standard) }
        set { setGPUCoreOptions(newValue, in: .standard) }
    }
    static func gpuCoreOptions(in store: UserDefaults) -> HUDCoreOptions {
        guard let data = store.data(forKey: "hud.gpu.cores"),
              let options = try? JSONDecoder().decode(HUDCoreOptions.self, from: data) else { return .gpuDefault }
        return options.gpuFrequencyOnly
    }
    static func setGPUCoreOptions(_ options: HUDCoreOptions, in store: UserDefaults) {
        store.set(try? JSONEncoder().encode(options.gpuFrequencyOnly), forKey: "hud.gpu.cores")
    }

    static var cpuCoreOptions: HUDCoreOptions {
        get { cpuCoreOptions(in: .standard) }
        set { setCPUCoreOptions(newValue, in: .standard) }
    }

    static func cpuCoreOptions(in store: UserDefaults) -> HUDCoreOptions {
        guard let data = store.data(forKey: "hud.cpu.cores"),
              let options = try? JSONDecoder().decode(HUDCoreOptions.self, from: data) else { return .cpuDefault }
        return options
    }

    static func setCPUCoreOptions(_ options: HUDCoreOptions, in store: UserDefaults) {
        store.set(try? JSONEncoder().encode(options), forKey: "hud.cpu.cores")
    }
}
