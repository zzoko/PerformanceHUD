import Foundation
import Darwin
import IOKit

enum HUDChipDisplayMode: String, CaseIterable, Codable {
    // Off is retained only for decoding pre-v3.2 Mac selections.
    case tier, full, off
    static let selectable: [Self] = [.tier, .full]
    var title: String { rawValue.capitalized }
}

/// Legacy Mac category options, retained only for preferences/preset migration.
struct HUDDeviceInfoOptions: Codable, Equatable {
    var enabled = false
    var chipMode: HUDChipDisplayMode = .full
    var os = true

    var showsChip: Bool { enabled && chipMode != .off }
    var showsOS: Bool { enabled && os }
    var isVisible: Bool { showsChip || showsOS }
}

/// Hardware and OS information is read once; displaying this section needs no polling.
nonisolated struct HUDDeviceInfo {
    let chipName: String
    let macOSVersion: String
    var efficiencyCores: Int?
    var performanceCores: Int?
    var cpuCores: Int?
    var gpuCores: Int?
    var superCores: Int? = nil
    var coreTypes: [HUDCPUCoreType] = []

    static let current: HUDDeviceInfo = {
        let cores = readCPUCoreTypes()
        return HUDDeviceInfo(chipName: chipName(from: readString("machdep.cpu.brand_string")),
            macOSVersion: versionText(ProcessInfo.processInfo.operatingSystemVersion),
            efficiencyCores: cores.isEmpty ? nil : cores.first { $0.name == "Efficiency" }?.count ?? 0,
            performanceCores: cores.isEmpty ? nil : cores.first { $0.name == "Performance" }?.count ?? 0,
            cpuCores: readCount("hw.physicalcpu_max"), gpuCores: readGPUCoreCount(),
            superCores: cores.isEmpty ? nil : cores.first { $0.name == "Super" }?.count ?? 0, coreTypes: cores)
    }()

    var cpuConfiguration: String {
        if !coreTypes.isEmpty { return coreTypes.map { "\($0.count) \($0.name)" }.joined(separator: " + ") }
        let parts = [("Super", superCores), ("Performance", performanceCores), ("Efficiency", efficiencyCores)]
            .compactMap { name, count in count.flatMap { $0 > 0 ? "\($0) \(name)" : nil } }
        if !parts.isEmpty { return parts.joined(separator: " + ") }
        return cpuCores.map(String.init) ?? "Not available"
    }

    var gpuConfiguration: String { gpuCores.map(String.init) ?? "Not available" }

    static func chipName(from brand: String?) -> String {
        guard let brand = brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty else {
            return "Mac" // Avoid claiming a chip model when the query is unavailable.
        }
        return brand.hasPrefix("Apple ") ? String(brand.dropFirst("Apple ".count)) : brand
    }

    static func versionText(_ version: OperatingSystemVersion) -> String {
        let patch = version.patchVersion == 0 ? "" : ".\(version.patchVersion)"
        return "macOS \(version.majorVersion).\(version.minorVersion)\(patch)"
    }

    private static func readString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0,
              size > 0, size <= 4096 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        let result = bytes.withUnsafeMutableBytes {
            sysctlbyname(name, $0.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return nil }
        return String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8)
    }

    private static func readCount(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout.size(ofValue: value)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, value > 0 else { return nil }
        return Int(value)
    }

    private static func readCPUCoreTypes() -> [HUDCPUCoreType] {
        guard let levels = readCount("hw.nperflevels"), levels <= 16 else { return [] }
        let types: [HUDCPUCoreType] = (0..<levels).compactMap { index in
            let prefix = "hw.perflevel\(index)"
            guard let name = readString("\(prefix).name"), !name.isEmpty,
                  let count = readCount("\(prefix).physicalcpu_max") else { return nil }
            return HUDCPUCoreType(name: name, count: count)
        }
        guard types.count == levels, Set(types.map(\.name)).count == levels,
              types.reduce(0, { $0 + $1.count }) == readCount("hw.physicalcpu_max") else { return [] }
        return types
    }

    private static func readGPUCoreCount() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let number = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber,
              number.intValue > 0 else { return nil }
        return number.intValue
    }
}

/// Preserve every name reported by macOS, including machines without E-cores.
nonisolated struct HUDCPUCoreType: Equatable, Sendable {
    let name: String
    let count: Int
}
