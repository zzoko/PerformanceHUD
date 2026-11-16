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
    let ane: Double?
    let timestamp: Date
    var cpuFrequencies = CPUFrequencySample.unavailable
    var gpuFrequency: Double? = nil

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
        guard cpu != nil || gpu != nil || ane != nil else { return nil }
        let package = cpu.flatMap { c in gpu.flatMap { g in ane.map { c + g + $0 } } }
        return Self(cpu: cpu, gpu: gpu, package: package, timestamp: stamp, ane: ane, cpuFrequencies: parseFrequencies(values),
                    gpuFrequency: gigahertz((root["gpu"] as? [String: Any])?["freq_hz"]))
    }

    // Frequencies and residency weights come from the SAME one-second sample.
    // Prefer the shared cluster clock; per-core frequencies are only a fallback.
    // CPU IDs join the powermetrics clusters to the runtime core-type topology.
    static func parseFrequencies(_ processor: [String: Any]) -> CPUFrequencySample {
        guard let clusters = processor["clusters"] as? [[String: Any]], clusters.count <= 128 else { return .unavailable }
        var result = CPUFrequencySample.unavailable
        var seen = Set<Int>()
        for cluster in clusters {
            guard let cores = cluster["cpus"] as? [[String: Any]], cores.count <= 1024 else { continue }
            let sharedClock = gigahertz(cluster["freq_hz"])
            for core in cores {
                guard let n = core["cpu"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                      n.doubleValue == Double(n.intValue), (0..<1024).contains(n.intValue),
                      seen.insert(n.intValue).inserted else { return .unavailable }
                if let speed = sharedClock ?? gigahertz(core["freq_hz"]) { result.frequencies[n.intValue] = speed }
                if let idle = core["idle_ratio"] as? NSNumber, CFGetTypeID(idle) != CFBooleanGetTypeID(),
                   idle.doubleValue.isFinite, (0...1).contains(idle.doubleValue) {
                    result.activeResidencies[n.intValue] = 1 - idle.doubleValue
                }
            }
        }
        return result
    }

    static func gigahertz(_ raw: Any?) -> Double? {
        guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let value = n.doubleValue
        guard value.isFinite, value >= 0 else { return nil }
        // GPU reports MHz under freq_hz; CPU schemas have used both Hz and MHz.
        let result = value <= 10_000 ? value / 1_000 : value / 1_000_000_000
        return (0...20).contains(result) ? result : nil
    }

    var reply: NSDictionary {
        var values: [String: Any] = ["version": 1, "timestamp": timestamp.timeIntervalSince1970]
        if let cpu { values["cpu"] = cpu }
        if let gpu { values["gpu"] = gpu }
        if let package { values["package"] = package }
        if let ane { values["ane"] = ane }
        values["cpuFrequencies"] = Dictionary(uniqueKeysWithValues: cpuFrequencies.frequencies.map { (String($0.key), $0.value) })
        values["cpuActiveResidencies"] = Dictionary(uniqueKeysWithValues: cpuFrequencies.activeResidencies.map { (String($0.key), $0.value) })
        if let gpuFrequency { values["gpuFrequency"] = gpuFrequency }
        return values as NSDictionary
    }

    init(cpu: Double?, gpu: Double?, package: Double?, timestamp: Date, ane: Double? = nil, cpuFrequencies: CPUFrequencySample = .unavailable, gpuFrequency: Double? = nil) {
        self.cpu = cpu; self.gpu = gpu; self.package = package; self.timestamp = timestamp
        self.ane = ane
        self.cpuFrequencies = cpuFrequencies
        self.gpuFrequency = gpuFrequency
    }

    init?(reply: NSDictionary) {
        guard reply["version"] as? Int == 1,
              let time = reply["timestamp"] as? Double,
              time.isFinite, abs(Date().timeIntervalSince1970 - time) < 3 else { return nil }
        func value(_ key: String) -> Double? {
            guard let number = reply[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, (0...6_000).contains(number.doubleValue) else { return nil }
            return number.doubleValue
        }
        let cpu = value("cpu").flatMap { $0 > 0 ? $0 : nil }
        guard cpu != nil || value("gpu") != nil || value("ane") != nil else { return nil }
        self.init(cpu: cpu, gpu: value("gpu"), package: value("package"), timestamp: Date(timeIntervalSince1970: time),
                  ane: value("ane"))
        func dictionary(_ key: String, maximum: Double) -> [Int: Double] {
            guard let values = reply[key] as? [String: NSNumber], values.count <= 1024 else { return [:] }
            var result: [Int: Double] = [:]
            for (key, number) in values {
                guard let id = Int(key), (0..<1024).contains(id), CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, (0...maximum).contains(number.doubleValue) else { continue }
                result[id] = number.doubleValue
            }
            return result
        }
        cpuFrequencies = CPUFrequencySample(frequencies: dictionary("cpuFrequencies", maximum: 20),
                                           activeResidencies: dictionary("cpuActiveResidencies", maximum: 1))
        if let frequency = value("gpuFrequency"), frequency <= 20 { gpuFrequency = frequency }
    }
}

/// Active-time-weighted GHz for one core type, which may span several clusters.
/// Residency is per core, so larger/busier clusters contribute their actual work.
nonisolated struct CPUFrequencySample: Sendable, Equatable {
    var frequencies: [Int: Double] = [:]
    var activeResidencies: [Int: Double] = [:]
    static let unavailable = Self()

    func average(for ids: [Int]) -> Double? {
        guard !ids.isEmpty else { return nil }
        let weights = ids.compactMap { activeResidencies[$0] }
        if weights.count == ids.count {
            var weighted = 0.0, active = 0.0
            for id in ids {
                let weight = activeResidencies[id]!
                guard weight.isFinite, (0...1).contains(weight) else { return nil }
                if weight == 0 { continue }
                guard let speed = frequencies[id], speed.isFinite, speed > 0, speed <= 20 else { return nil }
                weighted += speed * weight; active += weight
            }
            return active > 0 ? weighted / active : nil
        }
        // One reported shared clock needs no averaging. Never invent weights
        // for differing clocks or mix activity from another polling interval.
        let speeds = ids.compactMap { frequencies[$0] }
        guard speeds.count == ids.count, let first = speeds.first, first.isFinite, first > 0,
              first <= 20, speeds.allSatisfy({ $0 == first }) else { return nil }
        return first
    }
}
