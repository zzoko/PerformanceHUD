import Foundation

enum HUDMiscReading: String, CaseIterable, Codable {
    case process, resolution, refreshRate, gameMode, thermal, os, chip

    // Process is retained for decoding older settings only.
    static let allCases: [Self] = [.resolution, .refreshRate, .gameMode, .thermal, .os, .chip]
    static let liveReadings: [Self] = [ .resolution, .refreshRate, .gameMode, .thermal]

    var title: String {
        switch self {
        case .process: return "Process"
        case .resolution: return "Resolution"
        case .refreshRate: return "Refresh rate"
        case .gameMode: return "Game Mode"
        case .thermal: return "Thermal"
        case .os: return "OS"
        case .chip: return "Chip"
        }
    }
}

struct HUDMiscOptions: Codable, Equatable {
    var enabled = false
    var readings = Set(HUDMiscReading.allCases)
    var chipMode: HUDChipDisplayMode = .full
    var highlighted = false
    var visibleReadings: [HUDMiscReading] {
        enabled ? HUDMiscReading.allCases.filter { readings.contains($0) } : []
    }

    var showsCoreCounts: Bool { visibleReadings.contains(.chip) && chipMode == .full }
    var rowCount: Int { visibleReadings.count + (showsCoreCounts ? 2 : 0) }

    // Merge the former independent categories without revealing readings that
    // were hidden. If both were off, retain their individual selections.
    func mergingLegacyMac(_ mac: HUDDeviceInfoOptions) -> Self {
        var merged = self
        merged.enabled = enabled || mac.enabled
        if mac.enabled && !enabled { merged.readings.removeAll() }
        if mac.enabled || !merged.enabled {
            if mac.chipMode != .off { merged.readings.insert(.chip) }
            if mac.os { merged.readings.insert(.os) }
        }
        merged.chipMode = mac.chipMode == .tier ? .tier : .full
        return merged
    }

    private enum CodingKeys: String, CodingKey { case enabled, readings, chipMode, highlighted }

    init(enabled: Bool = false, readings: Set<HUDMiscReading> = Set(HUDMiscReading.allCases),
         chipMode: HUDChipDisplayMode = .full, highlighted: Bool = false) {
        self.enabled = enabled
        self.readings = readings
        self.chipMode = chipMode == .tier ? .tier : .full
        self.highlighted = highlighted
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        readings = try values.decode(Set<HUDMiscReading>.self, forKey: .readings)
        chipMode = try values.decodeIfPresent(HUDChipDisplayMode.self, forKey: .chipMode) == .tier ? .tier : .full
        highlighted = try values.decodeIfPresent(Bool.self, forKey: .highlighted) ?? false
    }
}

nonisolated struct HUDResolution: Equatable, Sendable {
    let width: Int
    let height: Int

    init?(width: Double, height: Double) {
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              width <= 65_536, height <= 65_536,
              width.rounded() == width, height.rounded() == height else { return nil }
        self.width = Int(width)
        self.height = Int(height)
    }

    var text: String { "\(width) × \(height)" }
}

nonisolated struct HUDRefreshRate: Equatable, Sendable {
    let minimum: Double
    let maximum: Double

    init?(modeRate: Double, minimumInterval: Double, maximumInterval: Double) {
        func valid(_ rate: Double) -> Bool { rate.isFinite && rate >= 1 && rate <= 1_000 }
        let fastest = 1 / minimumInterval
        let slowest = 1 / maximumInterval
        // A variable mode reports a supported range, not instantaneous panel Hz.
        if valid(fastest), valid(slowest), fastest - slowest > 0.5 {
            minimum = slowest; maximum = fastest
        } else if valid(modeRate) {
            minimum = modeRate; maximum = modeRate
        } else if valid(fastest), valid(slowest), abs(fastest - slowest) <= 0.5 {
            minimum = fastest; maximum = fastest
        } else { return nil }
    }

    var text: String {
        func format(_ rate: Double) -> String {
            if abs(rate - rate.rounded()) < 0.01 { return String(Int(rate.rounded())) }
            return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), rate)
        }
        return minimum == maximum ? "\(format(maximum)) Hz" : "\(format(minimum))–\(format(maximum)) Hz"
    }
}

struct HUDMiscSample: Equatable {
    var process: String?
    var resolution: HUDResolution?
    var refreshRate: HUDRefreshRate?
    var gameMode: Bool?
    var thermal: String?

    func text(for reading: HUDMiscReading, info: HUDDeviceInfo = .current) -> String {
        switch reading {
        case .process: return process ?? ""
        case .resolution: return resolution?.text ?? "-"
        case .refreshRate: return refreshRate?.text ?? ""
        case .gameMode: return gameMode.map { $0 ? "on" : "off" } ?? ""
        case .thermal: return thermal ?? ""
        case .chip: return info.chipName
        case .os: return info.macOSVersion
        }
    }
}
