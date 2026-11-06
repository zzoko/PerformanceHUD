import Foundation
import IOKit.ps

nonisolated enum BatteryAvailability: Sendable {
    case unknown, available, unavailable

    static func isInternalBattery(_ description: [String: Any]) -> Bool {
        description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            && description[kIOPSIsPresentKey] as? Bool != false
    }

    static func from(_ descriptions: [[String: Any]]?) -> Self {
        guard let descriptions else { return .unknown }
        if descriptions.contains(where: isInternalBattery) { return .available }
        // An unreadable description is not proof that hardware is absent.
        if descriptions.contains(where: { $0[kIOPSTypeKey] as? String == nil }) { return .unknown }
        return .unavailable
    }
}

nonisolated struct BatterySample: Sendable {
    enum Source: String, Sendable {
        case battery = "Battery"
        case powerAdapter = "Power Adapter"
    }
    let percentage: Double?
    let source: Source?
    let temperature: Double?
    let power: Double?

    init(percentage: Double?, source: Source?, temperature: Double? = nil, power: Double? = nil) {
        self.percentage = percentage
        self.source = source
        self.temperature = temperature
        self.power = power.flatMap { BatteryPowerRate.valid($0) }
    }

    static func from(_ description: [String: Any], temperature: Double? = nil, power: Double? = nil) -> BatterySample {
        let source: Source?
        switch description[kIOPSPowerSourceStateKey] as? String {
        case kIOPSBatteryPowerValue: source = .battery
        case kIOPSACPowerValue: source = .powerAdapter
        default: source = nil
        }
        var percentage: Double?
        if let current = description[kIOPSCurrentCapacityKey] as? NSNumber,
           let maximum = description[kIOPSMaxCapacityKey] as? NSNumber,
           maximum.doubleValue > 0 {
            let value = current.doubleValue / maximum.doubleValue * 100
            if value.isFinite { percentage = min(100, max(0, value)) }
        }
        return BatterySample(percentage: percentage, source: source, temperature: temperature, power: power)
    }
}

@MainActor
final class BatteryMonitor {
    var onBatteryUpdate: ((BatterySample?) -> Void)?
    var onAvailabilityChange: ((BatteryAvailability) -> Void)?
    private(set) var availability = BatteryAvailability.from(BatteryReader.powerSourceDescriptions())
    private let poller = MetricPoller<BatteryObservation>(label: "PerformanceHUD.Battery")
    private var includesTemperature = false
    private var includesPower = false
    func start(temperature: Bool = true, power: Bool = false) {
        guard availability != .unavailable else { return }
        guard !poller.isRunning || includesTemperature != temperature || includesPower != power else { return }
        includesTemperature = temperature
        includesPower = power
        let reader = temperature || power ? SMCTemperatureReader() : nil
        poller.start(interval: 1, sample: {
            BatteryReader.readBattery(sensorReader: reader, temperature: temperature, power: power)
        }) { [weak self] observation in
            guard let self else { return }
            if let observed = observation?.availability, observed != .unknown, observed != availability {
                availability = observed
                onAvailabilityChange?(observed)
            }
            onBatteryUpdate?(observation?.sample)
        }
    }
    func stop() { poller.stop() }
}

nonisolated private struct BatteryObservation: Sendable {
    let availability: BatteryAvailability
    let sample: BatterySample?
}

nonisolated private enum BatteryReader {
    static func powerSourceDescriptions() -> [[String: Any]]? {
        guard let info = IOPSCopyPowerSourcesInfo() else { return nil }
        let snapshot = info.takeRetainedValue()
        guard let list = IOPSCopyPowerSourcesList(snapshot) else { return nil }
        let sources = list.takeRetainedValue() as [CFTypeRef]
        var descriptions: [[String: Any]] = []
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source),
                  let description = info.takeUnretainedValue() as? [String: Any] else { return nil }
            descriptions.append(description)
        }
        return descriptions
    }

    static func readBattery(sensorReader: SMCTemperatureReader?, temperature includesTemperature: Bool, power: Bool)
        -> BatteryObservation
    {
        let descriptions = powerSourceDescriptions()
        let availability = BatteryAvailability.from(descriptions)
        if let description = descriptions?.first(where: BatteryAvailability.isInternalBattery) {
            var temperature = includesTemperature ? sensorReader?.readBatteryTemperature(keepingConnectionForPower: power) : nil
            let sensorPower = power ? sensorReader?.readBatteryPower() : nil
            // Fetch the controller snapshot only for missing sensor readings.
            let needsController = (power && sensorPower == nil) || (includesTemperature && temperature == nil)
            let controller = needsController ? controllerProperties() : nil
            if includesTemperature, temperature == nil,
               let raw = controller?["Temperature"] as? NSNumber {
                temperature = SMCTemperatureReader.validBatteryTemperature(raw.doubleValue / 100)
            }
            let watts = power ? sensorPower ?? BatteryPowerRate.watts(controller: controller) : nil
            return BatteryObservation(availability: .available,
                sample: BatterySample.from(description, temperature: temperature, power: watts))
        }
        return BatteryObservation(availability: availability, sample: nil)
    }

    private static func controllerProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let values = properties?.takeRetainedValue() as? [String: Any],
              values["BatteryInstalled"] as? Bool != false else { return nil }
        return values
    }

}
