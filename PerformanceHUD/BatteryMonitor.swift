import Foundation
import IOKit.ps

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
    private let poller = MetricPoller<BatterySample>(label: "PerformanceHUD.Battery")
    private var includesTemperature = false
    private var includesPower = false
    func start(temperature: Bool = true, power: Bool = false) {
        guard !poller.isRunning || includesTemperature != temperature || includesPower != power else { return }
        includesTemperature = temperature
        includesPower = power
        let reader = temperature || power ? SMCTemperatureReader() : nil
        poller.start(interval: 1, sample: {
            BatteryReader.readBattery(sensorReader: reader, temperature: temperature, power: power)
        }) { [weak self] in
            self?.onBatteryUpdate?($0)
        }
    }
    func stop() { poller.stop() }
}

nonisolated private enum BatteryReader {
    // MARK: - Read Battery

    static func readBattery(sensorReader: SMCTemperatureReader?, temperature includesTemperature: Bool, power: Bool)
        -> BatterySample?
    {

        let snapshot =
            IOPSCopyPowerSourcesInfo()
                .takeRetainedValue()

        let sources =
            IOPSCopyPowerSourcesList(
                snapshot
            )
            .takeRetainedValue() as [CFTypeRef]

        for source in sources {

            guard
                let description =
                    IOPSGetPowerSourceDescription(
                        snapshot,
                        source
                    )
                    .takeUnretainedValue()
                    as? [String: Any]
            else {
                continue
            }

            /*
             We only care about an internal
             battery, not a UPS or another
             possible power source.
            */

            guard
                let type =
                    description[
                        kIOPSTypeKey
                    ] as? String,

                type ==
                    kIOPSInternalBatteryType
            else {
                continue
            }

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
            return BatterySample.from(description, temperature: temperature, power: watts)
        }

        return nil
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
