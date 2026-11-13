import Foundation
import Darwin
import IOKit

enum HUDChipDisplayMode: String, CaseIterable, Codable {
    case tier, full, off
    var title: String { rawValue.capitalized }
}

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

    static let current: HUDDeviceInfo = {
        let cores = readCPUCoreCounts()
        return HUDDeviceInfo(chipName: chipName(from: readString("machdep.cpu.brand_string")),
            macOSVersion: versionText(ProcessInfo.processInfo.operatingSystemVersion),
            efficiencyCores: cores.efficiency, performanceCores: cores.performance,
            cpuCores: readCount("hw.physicalcpu_max"), gpuCores: readGPUCoreCount())
    }()

    var cpuConfiguration: String {
        if let efficiencyCores, let performanceCores {
            return "(\(efficiencyCores) E-Cores + \(performanceCores) P-Cores)"
        }
        if let cpuCores { return "(\(cpuCores) CPU-Cores)" }
        return "CPU cores unavailable"
    }

    var gpuConfiguration: String {
        gpuCores.map { "(\($0) GPU-Cores)" } ?? "GPU cores unavailable"
    }

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

    private static func readCPUCoreCounts() -> (efficiency: Int?, performance: Int?) {
        guard let levels = readCount("hw.nperflevels"), levels <= 16 else { return (nil, nil) }
        var efficiency = 0, performance = 0
        for index in 0..<levels {
            let prefix = "hw.perflevel\(index)"
            guard let name = readString("\(prefix).name")?.lowercased(),
                  let count = readCount("\(prefix).physicalcpu_max") else { return (nil, nil) }
            switch name {
            case "efficiency": efficiency += count
            // macOS reports M5 performance cores as Super.
            case "performance", "super": performance += count
            default: return (nil, nil)
            }
        }
        return efficiency > 0 && performance > 0 ? (efficiency, performance) : (nil, nil)
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
