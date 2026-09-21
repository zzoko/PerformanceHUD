import Foundation
import Darwin

/// Hardware and OS information is read once; displaying this section needs no polling.
nonisolated struct HUDDeviceInfo {
    let chipName: String
    let macOSVersion: String

    static let current = HUDDeviceInfo(
        chipName: chipName(from: readCPUBrand()),
        macOSVersion: versionText(ProcessInfo.processInfo.operatingSystemVersion)
    )

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

    private static func readCPUBrand() -> String? {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0,
              size > 0, size <= 4096 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        let result = bytes.withUnsafeMutableBytes {
            sysctlbyname("machdep.cpu.brand_string", $0.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return nil }
        return String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8)
    }
}
