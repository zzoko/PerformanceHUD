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

    init(percentage: Double?, source: Source?, temperature: Double? = nil) {
        self.percentage = percentage
        self.source = source
        self.temperature = temperature
    }

    static func from(_ description: [String: Any], temperature: Double? = nil) -> BatterySample {
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
        return BatterySample(percentage: percentage, source: source, temperature: temperature)
    }
}

@MainActor
final class BatteryMonitor {
    var onBatteryUpdate: ((BatterySample?) -> Void)?
    private let poller = MetricPoller<BatterySample>(label: "PerformanceHUD.Battery")
    private var includesTemperature = false
    func start(temperature: Bool = true) {
        guard !poller.isRunning || includesTemperature != temperature else { return }
        includesTemperature = temperature
        let reader = temperature ? SMCTemperatureReader() : nil
        poller.start(interval: 5, sample: { BatteryReader.readBattery(temperatureReader: reader) }) { [weak self] in
            self?.onBatteryUpdate?($0)
        }
    }
    func stop() { poller.stop() }
}

nonisolated private enum BatteryReader {
    // MARK: - Read Battery

    static func readBattery(temperatureReader: SMCTemperatureReader?)
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

            let temperature = temperatureReader.flatMap { $0.readBatteryTemperature() ?? controllerTemperature() }
            return BatterySample.from(description, temperature: temperature)
        }

        return nil
    }

    private static func controllerTemperature() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let property = IORegistryEntryCreateCFProperty(service, "Temperature" as CFString, kCFAllocatorDefault, 0),
              let raw = property.takeRetainedValue() as? NSNumber else { return nil }
        return SMCTemperatureReader.validBatteryTemperature(raw.doubleValue / 100)
    }

}
