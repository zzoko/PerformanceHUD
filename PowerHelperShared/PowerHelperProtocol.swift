import Foundation
import Security

// No commands, paths, PIDs, or sampling parameters cross this interface.
@objc nonisolated protocol PowerHelperProtocol {
    func sample(reply: @escaping (NSDictionary) -> Void)
    func stop(reply: @escaping () -> Void)
}

nonisolated enum PowerHelperIdentity {
    static let app = "andrei.PerformanceHUD"
    static let service = "andrei.PerformanceHUD.PowerHelper"
    static let plist = service + ".plist"

    // Trust our signature, not editable preferences. Personal builds can use
    // another team's certificate provided both app and helper match.
    static func requirement(for identifier: String) -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let team = (information as NSDictionary?)?[kSecCodeInfoTeamIdentifier] as? String,
              team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else { return nil }
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }
}

nonisolated struct HelperPowerReading: Sendable {
    let cpu: Double?
    let gpu: Double?
    let package: Double?
    let timestamp: Date

    static func parse(_ data: Data) -> Self? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              root["is_delta"] as? Bool == true,
              let elapsed = root["elapsed_ns"] as? NSNumber,
              (100_000_000...3_000_000_000).contains(elapsed.doubleValue),
              let stamp = root["timestamp"] as? Date,
              abs(stamp.timeIntervalSinceNow) < 4,
              let values = root["processor"] as? [String: Any] else { return nil }
        func watts(_ key: String) -> Double? {
            guard let n = values[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
            let value = n.doubleValue / 1000 // powermetrics plist uses milliwatts.
            return value.isFinite && (0...2_000).contains(value) ? value : nil
        }
        let cpu = watts("cpu_power").flatMap { $0 > 0 ? $0 : nil }
        let gpu = watts("gpu_power")
        let ane = watts("ane_power")
        guard cpu != nil || gpu != nil else { return nil }
        let package = cpu.flatMap { c in gpu.flatMap { g in ane.map { c + g + $0 } } }
        return Self(cpu: cpu, gpu: gpu, package: package, timestamp: stamp)
    }

    var reply: NSDictionary {
        var values: [String: Any] = ["version": 1, "timestamp": timestamp.timeIntervalSince1970]
        if let cpu { values["cpu"] = cpu }
        if let gpu { values["gpu"] = gpu }
        if let package { values["package"] = package }
        return values as NSDictionary
    }

    init(cpu: Double?, gpu: Double?, package: Double?, timestamp: Date) {
        self.cpu = cpu; self.gpu = gpu; self.package = package; self.timestamp = timestamp
    }

    init?(reply: NSDictionary) {
        guard reply["version"] as? Int == 1,
              let time = reply["timestamp"] as? Double,
              time.isFinite, abs(Date().timeIntervalSince1970 - time) < 3 else { return nil }
        func value(_ key: String) -> Double? {
            guard let n = reply[key] as? Double, n.isFinite, (0...6_000).contains(n) else { return nil }
            return n
        }
        let cpu = value("cpu").flatMap { $0 > 0 ? $0 : nil }
        guard cpu != nil || value("gpu") != nil else { return nil }
        self.init(cpu: cpu, gpu: value("gpu"), package: value("package"), timestamp: Date(timeIntervalSince1970: time))
    }
}
