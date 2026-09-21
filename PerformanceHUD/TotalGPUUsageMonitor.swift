import Foundation
import IOKit

@MainActor
final class TotalGPUUsageMonitor {
    var onGPUUsageUpdate: ((Double?) -> Void)?
    private let poller = MetricPoller<Double>(label: "PerformanceHUD.TotalGPUUsage")
    func start() {
        guard !poller.isRunning else { return }
        let sampler = TotalGPUSampler()
        poller.start(sample: { sampler.sample() }) { [weak self] in self?.onGPUUsageUpdate?($0) }
    }
    func stop() { poller.stop() }
}

nonisolated private final class TotalGPUSampler: @unchecked Sendable {
    private var acceleratorService: io_service_t = 0
    deinit { if acceleratorService != 0 { IOObjectRelease(acceleratorService) } }
    // MARK: - Sample

    func sample() -> Double? {

        /*
         If the cached service disappeared,
         attempt to find it again.
        */

        if acceleratorService == 0 {

            acceleratorService =
                findAcceleratorService()
        }

        guard
            acceleratorService != 0
        else {

            return nil
        }

        guard
            let usage =
                readTotalGPUUsage(
                    from:
                        acceleratorService
                )
        else {

            /*
             The service may have changed.
             Release it so the next sample
             attempts discovery again.
            */

            IOObjectRelease(
                acceleratorService
            )

            acceleratorService = 0

            return nil
        }

        let normalized =
            min(
                max(
                    usage,
                    0
                ),
                100
            )

        return normalized
    }

    // MARK: - Find GPU

    private func findAcceleratorService()
        -> io_service_t
    {

        guard
            let matching =
                IOServiceMatching(
                    "IOAccelerator"
                )
        else {
            return 0
        }

        var iterator:
            io_iterator_t = 0

        let result =
            IOServiceGetMatchingServices(
                kIOMainPortDefault,
                matching,
                &iterator
            )

        guard
            result == KERN_SUCCESS
        else {
            return 0
        }

        defer {

            IOObjectRelease(
                iterator
            )
        }

        /*
         Most Apple Silicon Macs expose one
         primary accelerator.

         Return the first accelerator that
         exposes usable PerformanceStatistics.
        */

        while true {

            let service =
                IOIteratorNext(
                    iterator
                )

            guard
                service != 0
            else {
                break
            }

            if readTotalGPUUsage(
                from: service
            ) != nil {

                /*
                 Do NOT release this service here.

                 We retain ownership and cache it
                 until stop().
                */

                return service
            }

            IOObjectRelease(
                service
            )
        }

        return 0
    }

    // MARK: - Read Utilization

    private func readTotalGPUUsage(
        from service: io_service_t
    ) -> Double? {

        guard
            let property =
                IORegistryEntryCreateCFProperty(
                    service,
                    "PerformanceStatistics"
                        as CFString,
                    kCFAllocatorDefault,
                    0
                )
        else {
            return nil
        }

        let stats =
            property
                .takeRetainedValue()

        guard
            let dictionary =
                stats as? [String: Any]
        else {
            return nil
        }

        /*
         Prefer Apple's common Apple-Silicon
         device-wide utilization field.

         The fallbacks make this a little more
         tolerant of driver / GPU differences.
        */

        let preferredKeys = [

            "Device Utilization %",

            "GPU Activity(%)",

            "GPU Activity %",

            "GPU Utilization %",

            "GPU Busy %",

            "accelBusyPercent",

            "Renderer Utilization",

            "Device Utilization"
        ]

        for key in preferredKeys {

            guard
                let rawValue =
                    numericValue(
                        dictionary[key]
                    )
            else {
                continue
            }

            return normalize(
                rawValue,
                key: key
            )
        }

        return nil
    }

    // MARK: - Value Conversion

    private func numericValue(
        _ object: Any?
    ) -> Double? {

        if let number =
            object as? NSNumber {

            return number.doubleValue
        }

        if let string =
            object as? String {

            return Double(string)
        }

        return nil
    }

    private func normalize(
        _ value: Double,
        key: String
    ) -> Double? {

        guard value.isFinite else {
            return nil
        }

        /*
         Some driver values may be represented
         as a 0...1 fraction instead of 0...100.

         Explicit percentage fields normally
         already use 0...100.
        */

        if !key.contains("%"),
           value >= 0,
           value <= 1 {

            return value * 100.0
        }

        return value
    }

}
