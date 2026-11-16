import Foundation
import Darwin
import IOKit

nonisolated struct CPUCoreTopology: Sendable {
    struct Group: Sendable, Equatable {
        let name: String
        let ids: [Int]
    }
    let groups: [Group]

    // IODeviceTree identifies processor indices; never infer them from perflevel order.
    static let current: Self = {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard entry != 0 else { return Self(groups: []) }
        defer { IOObjectRelease(entry) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIODeviceTreePlane, &iterator) == KERN_SUCCESS else { return Self(groups: []) }
        defer { IOObjectRelease(iterator) }
        var ids: [String: [Int]] = [:]
        while case let cpu = IOIteratorNext(iterator), cpu != 0 {
            defer { IOObjectRelease(cpu) }
            func data(_ key: String) -> Data? {
                IORegistryEntryCreateCFProperty(cpu, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data
            }
            guard let rawID = data("cpu-id"), rawID.count == 4,
                  let type = data("cluster-type"),
                  let code = String(data: type.prefix { $0 != 0 }, encoding: .utf8) else { continue }
            let id = rawID.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
            guard id < 1024 else { continue }
            ids[code, default: []].append(id)
        }
        return resolve(types: HUDDeviceInfo.current.coreTypes, ids: ids)
    }()

    static func resolve(types: [HUDCPUCoreType], ids: [String: [Int]]) -> Self {
        var result: [Group] = []
        let names = Set(types.map(\.name))
        for type in types {
            let code: String
            switch type.name {
            case "Efficiency": code = "E"
            case "Performance": code = "P"
            // Older M5 firmware still calls its sole fast tier P in the device tree.
            case "Super": code = ids["S"] != nil ? "S" : names.contains("Performance") ? "S" : "P"
            default: continue
            }
            guard let cores = ids[code]?.sorted(), cores.count == type.count,
                  Set(cores).count == cores.count else { continue }
            result.append(.init(name: type.name, ids: cores))
        }
        return Self(groups: result)
    }
}

nonisolated struct CPUCoreSample: Sendable {
    let usage: [Int: Double]
    static let unavailable = Self(usage: [:])
    func average(for ids: [Int]) -> Double? {
        let values = ids.compactMap { usage[$0] }
        guard !ids.isEmpty, values.count == ids.count else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

nonisolated final class CPUCoreSampler: @unchecked Sendable {
    private var previous: [[UInt32]]?
    func sample() -> CPUCoreSample? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var count: natural_t = 0
        var info: processor_info_array_t?
        var size: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &count, &info, &size) == KERN_SUCCESS,
              let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(size) * vm_size_t(MemoryLayout<integer_t>.size)) }
        guard count > 0, count <= 1024, Int(size) >= Int(count) * Int(CPU_STATE_MAX) else { return nil }
        let current = (0..<Int(count)).map { index in
            (0..<Int(CPU_STATE_MAX)).map { UInt32(bitPattern: info[index * Int(CPU_STATE_MAX) + $0]) }
        }
        defer { previous = current }
        guard let previous, previous.count == current.count else { return nil }
        return Self.delta(previous: previous, current: current)
    }

    static func delta(previous: [[UInt32]], current: [[UInt32]]) -> CPUCoreSample {
        var usage: [Int: Double] = [:]
        for (id, pair) in zip(previous, current).enumerated() {
            guard pair.0.count == Int(CPU_STATE_MAX), pair.1.count == Int(CPU_STATE_MAX) else { continue }
            let delta = zip(pair.0, pair.1).map { Double($1 &- $0) }
            let total = delta.reduce(0, +)
            guard total > 0 else { continue }
            usage[id] = max(0, min(100, (total - delta[Int(CPU_STATE_IDLE)]) / total * 100))
        }
        return CPUCoreSample(usage: usage)
    }
}

@MainActor
final class CPUCoreMonitor {
    var onUpdate: ((CPUCoreSample) -> Void)?
    private let poller = MetricPoller<CPUCoreSample>(label: "PerformanceHUD.CPUCores")
    func configure(enabled: Bool) {
        guard enabled else { poller.stop(); onUpdate?(.unavailable); return }
        guard !poller.isRunning else { return }
        let sampler = CPUCoreSampler()
        poller.start(sample: { sampler.sample() }) { [weak self] in self?.onUpdate?($0 ?? .unavailable) }
    }
    func stop() { poller.stop() }
}
