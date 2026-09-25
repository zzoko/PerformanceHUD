import Foundation
import IOKit

nonisolated struct TemperatureSample: Sendable {
    let cpu: Double?
    let gpu: Double?
}

@MainActor
final class TemperatureMonitor {
    var onUpdate: ((TemperatureSample) -> Void)?
    private let poller = MetricPoller<TemperatureSample>(label: "PerformanceHUD.Temperature")
    private var requestedCPU = false
    private var requestedGPU = false

    func configure(cpu: Bool, gpu: Bool) {
        guard cpu != requestedCPU || gpu != requestedGPU else { return }
        requestedCPU = cpu
        requestedGPU = gpu
        poller.stop()
        guard cpu || gpu else { return }
        // The reader and its IOKit connection are used only on the poller's serial queue.
        let reader = SMCTemperatureReader()
        poller.start(interval: 2, sample: { reader.read(cpu: cpu, gpu: gpu) }, deliver: { [weak self] sample in
            self?.onUpdate?(sample ?? TemperatureSample(cpu: nil, gpu: nil))
        })
    }

    func stop() { configure(cpu: false, gpu: false) }
}

// SMC protocol and GPU sensor-prefix reference: vladkens/macmon (MIT).
// CPU keys use the generation-specific mappings in CPUTemperatureSensors.
// See ThirdPartyNotices.txt. This reader only requests key metadata and values;
// it never writes sensor values or changes thermal/fan settings.
// Apple's sensor keys are private, so missing/invalid readings remain unavailable.
nonisolated final class SMCTemperatureReader: @unchecked Sendable {
    private var connection: io_connect_t = 0
    private var metadata: [UInt32: (size: UInt32, type: UInt32)] = [:]
    private(set) var cpuKeys: [String] = []
    private(set) var gpuKeys: [String] = []
    private var nextOpenAttempt: TimeInterval = 0
    private let chipName: String

    init(chipName: String = HUDDeviceInfo.current.chipName) {
        self.chipName = chipName
    }

    deinit { close() }

    func read(cpu: Bool, gpu: Bool) -> TemperatureSample {
        if connection == 0 {
            let now = ProcessInfo.processInfo.systemUptime
            guard now >= nextOpenAttempt else { return TemperatureSample(cpu: nil, gpu: nil) }
            nextOpenAttempt = now + 30
            guard open() else { return TemperatureSample(cpu: nil, gpu: nil) }
            discoverSensors()
        }
        let cpuValue = cpu ? Self.average(cpuKeys.compactMap { temperature(for: $0) }) : nil
        let gpuValue = gpu ? Self.average(gpuKeys.compactMap { temperature(for: $0) }) : nil
        if (cpu && !cpuKeys.isEmpty || gpu && !gpuKeys.isEmpty), cpuValue == nil && gpuValue == nil {
            close() // Reconnect after a sleep/wake or an unavailable SMC service.
        }
        return TemperatureSample(cpu: cpuValue, gpu: gpuValue)
    }

    static func average(_ values: [Double]) -> Double? {
        let valid = values.filter { $0.isFinite && $0 > 0 && $0 < 150 }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    // Battery sensor names and the controller fallback follow Stats' battery reader.
    // These identify the battery pack, not nearby CPU/GPU or enclosure sensors.
    func readBatteryTemperature() -> Double? {
        if connection == 0 {
            let now = ProcessInfo.processInfo.systemUptime
            guard now >= nextOpenAttempt else { return nil }
            nextOpenAttempt = now + 30
            guard open() else { return nil }
        }
        let readings = ["TB1T", "TB2T"].compactMap { temperature(for: $0) }
            .compactMap { Self.validBatteryTemperature($0) }
        guard !readings.isEmpty else {
            close() // Re-open after wake; the battery controller remains the fallback.
            return nil
        }
        return readings.reduce(0, +) / Double(readings.count)
    }

    static func validBatteryTemperature(_ value: Double) -> Double? {
        value.isFinite && value > 0 && value < 100 ? value : nil
    }

    static func sensorGroup(for key: String, chipName: String) -> HUDResourceGroup? {
        guard key.utf8.count == 4 else { return nil }
        if CPUTemperatureSensors.keys(for: chipName).contains(key) { return .cpu }
        if key.hasPrefix("Tg") { return .gpu }
        return nil
    }

    private func open() -> Bool {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iterator) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            var name = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(service, &name) == KERN_SUCCESS,
                  String(cString: name) == "AppleSMCKeysEndpoint" else { continue }
            if IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS { return true }
            connection = 0
        }
        return false
    }

    private func close() {
        if connection != 0 { IOServiceClose(connection); connection = 0 }
        metadata.removeAll()
        cpuKeys.removeAll()
        gpuKeys.removeAll()
    }

    private func discoverSensors() {
        guard let countBytes = value(for: "#KEY"), countBytes.bytes.count == 4 else { return }
        let count = countBytes.bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard count > 0, count <= 16_384 else { return }
        for index in 0..<count {
            guard let response = request(command: 8, index: index) else { continue }
            let keyID = Self.uint32(response, at: 0)
            let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: keyID >> $0) }
            guard let key = String(bytes: bytes, encoding: .ascii),
                  let group = Self.sensorGroup(for: key, chipName: chipName), let info = keyInfo(Self.fourCC(key)),
                  (info.type == Self.fourCC("flt ") && info.size == 4)
                    || (info.type == Self.fourCC("sp78") && info.size == 2) else { continue }
            // Keep mapped keys even if they have no current reading; unsupported
            // or invalid readings are excluded when calculating the average.
            if group == .cpu { cpuKeys.append(key) }
            else { gpuKeys.append(key) }
        }
    }

    private func temperature(for key: String) -> Double? {
        guard let value = value(for: key) else { return nil }
        return Self.decodeTemperature(type: value.type, bytes: value.bytes)
    }

    static func decodeTemperature(type: UInt32, bytes: [UInt8]) -> Double? {
        let value: Double
        if type == fourCC("flt "), bytes.count == 4 {
            value = Double(Float(bitPattern: uint32(bytes, at: 0)))
        } else if type == fourCC("sp78"), bytes.count == 2 {
            value = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        } else { return nil }
        return value.isFinite && value > 0 && value < 150 ? value : nil
    }

    private func keyInfo(_ key: UInt32) -> (size: UInt32, type: UInt32)? {
        if let info = metadata[key] { return info }
        guard let response = request(command: 9, key: key) else { return nil }
        let info = (size: Self.uint32(response, at: 28), type: Self.uint32(response, at: 32))
        guard info.size > 0, info.size <= 32 else { return nil }
        metadata[key] = info
        return info
    }

    private func value(for name: String) -> (type: UInt32, bytes: [UInt8])? {
        let key = Self.fourCC(name)
        guard let info = keyInfo(key),
              let response = request(command: 5, key: key, size: info.size, type: info.type) else { return nil }
        return (info.type, Array(response[48..<(48 + Int(info.size))]))
    }

    private func request(command: UInt8, key: UInt32 = 0, index: UInt32 = 0,
                         size: UInt32 = 0, type: UInt32 = 0) -> [UInt8]? {
        // Fixed 80-byte AppleSMC KeyData ABI. Explicit offsets avoid Swift struct padding.
        guard connection != 0, [5, 8, 9].contains(command) else { return nil }
        var input = [UInt8](repeating: 0, count: 80)
        var output = [UInt8](repeating: 0, count: 80)
        for (offset, value) in [(0, key), (28, size), (32, type), (44, index)] {
            for byte in 0..<4 { input[offset + byte] = UInt8(truncatingIfNeeded: value >> (byte * 8)) }
        }
        input[42] = command
        var outputSize = 80
        let result = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                IOConnectCallStructMethod(connection, 2, source.baseAddress, 80, destination.baseAddress, &outputSize)
            }
        }
        guard result == KERN_SUCCESS, outputSize == 80, output[40] == 0 else { return nil }
        return output
    }

    static func fourCC(_ text: String) -> UInt32 {
        text.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
    }
}
