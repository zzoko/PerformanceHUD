import Foundation

/// Known CPU temperature keys, selected by generation and intersected with the
/// keys the machine actually exposes. This is an average of identified sensors,
/// not a promise that every physical core exposes exactly one sensor.
/// Mapping reference: exelban/Stats, Modules/CPU/readers.swift (MIT), 2026-09-21.
/// See ThirdPartyNotices.txt. Do not infer new chips from matching key prefixes:
/// the same prefix can include unrelated temperatures or change between chips.
nonisolated enum CPUTemperatureSensors {
    static func keys(for chipName: String) -> Set<String> {
        let name = chipName.hasPrefix("Apple ") ? String(chipName.dropFirst(6)) : chipName
        let parts = name.split(separator: " ").map(String.init)
        guard let family = parts.first,
              parts.count == 1 || (parts.count == 2 && ["Pro", "Max", "Ultra"].contains(parts[1])) else {
            return []
        }
        switch family {
        case "M1":
            return ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"]
        case "M2":
            return ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"]
        case "M3":
            return ["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"]
        case "M4":
            return ["Te05", "Te09", "Te0H", "Te0S", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
        case "M5":
            return ["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"]
        default:
            return [] // Unknown hardware stays blank instead of guessing.
        }
    }
}
