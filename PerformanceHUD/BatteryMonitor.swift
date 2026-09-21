import Foundation
import IOKit.ps

nonisolated struct BatterySample: Sendable {
    enum Source: String, Sendable {
        case battery = "Battery"
        case powerAdapter = "Power Adapter"
    }
    let percentage: Double?
    let source: Source?

    static func from(_ description: [String: Any]) -> BatterySample {
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
        return BatterySample(percentage: percentage, source: source)
    }
}

@MainActor
final class BatteryMonitor {
    var onBatteryUpdate: ((BatterySample?) -> Void)?
    private let poller = MetricPoller<BatterySample>(label: "PerformanceHUD.Battery")
    func start() {
        guard !poller.isRunning else { return }
        poller.start(interval: 5, sample: { BatteryReader.readBattery() }) { [weak self] in
            self?.onBatteryUpdate?($0)
        }
    }
    func stop() { poller.stop() }
}

nonisolated private enum BatteryReader {
    // MARK: - Read Battery

    static func readBattery()
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

            return BatterySample.from(description)
        }

        return nil
    }

}
