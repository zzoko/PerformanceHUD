import Foundation
import IOKit

@MainActor
final class GPUUsageMonitor {
    var onGPUUsageUpdate: ((Double?) -> Void)?
    private let poller = MetricPoller<Double>(label: "PerformanceHUD.GPUUsage")
    private var targetPID: pid_t?

    func start(pid: pid_t) {
        guard targetPID != pid || !poller.isRunning else { return }
        targetPID = pid
        let sampler = GPUCounterSampler(pid: pid)
        poller.start(sample: { sampler.sample() }) { [weak self] in self?.onGPUUsageUpdate?($0) }
    }
    func stop() { targetPID = nil; poller.stop() }
}

// A fresh sampler per session, confined to MetricPoller's serial sampling queue.
nonisolated private final class GPUCounterSampler: @unchecked Sendable {
    private let pid: pid_t
    private var previousTime: UInt64?
    private var previousTimestamp: UInt64?
    init(pid: pid_t) { self.pid = pid }
    func sample() -> Double? {
        let now = DispatchTime.now().uptimeNanoseconds
        guard let current = readAccumulatedGPUTime(for: pid) else {
            previousTime = nil; previousTimestamp = nil
            return nil
        }
        defer { previousTime = current; previousTimestamp = now }
        guard let previousTime, let previousTimestamp,
              current >= previousTime, now > previousTimestamp else { return nil }
        let delta = Double(current - previousTime)
        let usage = delta / Double(now - previousTimestamp) * 100
        guard usage.isFinite, usage >= 0 else { return nil }
        // GPU counters and elapsed time both use nanoseconds.
        return min(usage, 100)
    }
    // MARK: - Read GPU Counter

    private func readAccumulatedGPUTime(
        for pid: pid_t
    ) -> UInt64? {

        /*
         AGXDeviceUserClient entries aren't
         reliably returned by matching them
         directly.

         Start from IOAccelerator and walk
         its registry children instead.
        */

        guard
            let matching =
                IOServiceMatching(
                    "IOAccelerator"
                )
        else {
            return nil
        }

        var acceleratorIterator:
            io_iterator_t = 0

        let result =
            IOServiceGetMatchingServices(
                kIOMainPortDefault,
                matching,
                &acceleratorIterator
            )

        guard
            result == KERN_SUCCESS
        else {
            return nil
        }

        defer {

            IOObjectRelease(
                acceleratorIterator
            )
        }

        var totalGPUTime:
            UInt64 = 0

        var foundMatchingClient =
            false

        while true {

            let accelerator =
                IOIteratorNext(
                    acceleratorIterator
                )

            guard
                accelerator != 0
            else {
                break
            }

            var registryIterator:
                io_iterator_t = 0

            let iteratorResult =
                IORegistryEntryCreateIterator(
                    accelerator,
                    kIOServicePlane,
                    IOOptionBits(
                        kIORegistryIterateRecursively
                    ),
                    &registryIterator
                )

            if iteratorResult ==
                KERN_SUCCESS
            {

                while true {

                    let entry =
                        IOIteratorNext(
                            registryIterator
                        )

                    guard
                        entry != 0
                    else {
                        break
                    }

                    if
                        let properties =
                            properties(
                                for: entry
                            ),

                        let creator =
                            properties[
                                "IOUserClientCreator"
                            ] as? String,

                        creatorBelongsToPID(
                            creator,
                            pid: pid
                        )
                    {

                        let result =
                            gpuTime(
                                from:
                                    properties[
                                        "AppUsage"
                                    ]
                            )

                        if let result {

                            foundMatchingClient =
                                true

                            totalGPUTime &+=
                                result
                        }
                    }

                    IOObjectRelease(
                        entry
                    )
                }

                IOObjectRelease(
                    registryIterator
                )
            }

            IOObjectRelease(
                accelerator
            )
        }

        guard
            foundMatchingClient
        else {
            return nil
        }

        return totalGPUTime
    }

    // MARK: - Registry Properties

    private func properties(
        for entry: io_registry_entry_t
    ) -> [String: Any]? {

        var unmanagedProperties:
            Unmanaged<CFMutableDictionary>?

        let result =
            IORegistryEntryCreateCFProperties(
                entry,
                &unmanagedProperties,
                kCFAllocatorDefault,
                0
            )

        guard
            result == KERN_SUCCESS,
            let unmanagedProperties
        else {
            return nil
        }

        let dictionary =
            unmanagedProperties
                .takeRetainedValue()
                as NSDictionary

        return dictionary
            as? [String: Any]
    }

    // MARK: - PID Matching

    private func creatorBelongsToPID(
        _ creator: String,
        pid: pid_t
    ) -> Bool {

        /*
         Typical value:

         "pid 10178, Stray-Mac-Shipping"
        */

        let prefix =
            "pid \(pid),"

        if creator.hasPrefix(
            prefix
        ) {
            return true
        }

        /*
         Handle a value containing only
         the PID just in case.
        */

        return creator ==
            "pid \(pid)"
    }

    // MARK: - AppUsage Parsing

    private func gpuTime(
        from appUsageObject: Any?
    ) -> UInt64? {

        guard
            let usageEntries =
                appUsageObject
                    as? [Any]
        else {
            return nil
        }

        var total:
            UInt64 = 0

        var found =
            false

        for object in usageEntries {

            guard
                let usage =
                    object
                        as? [String: Any]
            else {
                continue
            }

            guard
                let gpuTime =
                    usage[
                        "accumulatedGPUTime"
                    ] as? NSNumber
            else {
                continue
            }

            found =
                true

            total &+=
                gpuTime.uint64Value
        }

        return found
            ? total
            : nil
    }

}
