import Foundation
import Darwin

@MainActor
final class TotalCPUUsageMonitor {
    var onCPUUsageUpdate: ((Double?) -> Void)?
    private let poller = MetricPoller<Double>(label: "PerformanceHUD.TotalCPUUsage")
    func start() {
        guard !poller.isRunning else { return }
        let sampler = TotalCPUSampler()
        poller.start(sample: { sampler.sample() }) { [weak self] in self?.onCPUUsageUpdate?($0) }
    }
    func stop() { poller.stop() }
}

nonisolated private final class TotalCPUSampler: @unchecked Sendable {
    private var previousLoad: host_cpu_load_info_data_t?
    // MARK: - Sample

    func sample() -> Double? {

        guard
            let current =
                readCPULoad()
        else {

            return nil
        }

        guard
            let previous =
                previousLoad
        else {

            previousLoad =
                current

            return nil
        }

        /*
         CPU_STATE indexes are:

         0 = user
         1 = system
         2 = idle
         3 = nice

         Use wrapping subtraction because the
         underlying tick counters may wrap.
        */

        let user =
            current.cpu_ticks.0
            &- previous.cpu_ticks.0

        let system =
            current.cpu_ticks.1
            &- previous.cpu_ticks.1

        let idle =
            current.cpu_ticks.2
            &- previous.cpu_ticks.2

        let nice =
            current.cpu_ticks.3
            &- previous.cpu_ticks.3

        previousLoad =
            current

        let busyTicks =
            Double(user)
            + Double(system)
            + Double(nice)

        let totalTicks =
            busyTicks
            + Double(idle)

        guard
            totalTicks > 0
        else {

            return nil
        }

        let usage =
            busyTicks
            / totalTicks
            * 100.0

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

    // MARK: - Read Host CPU Ticks

    private func readCPULoad()
        -> host_cpu_load_info_data_t?
    {

        var info =
            host_cpu_load_info_data_t()

        var count =
            mach_msg_type_number_t(
                MemoryLayout<
                    host_cpu_load_info_data_t
                >.size
                /
                MemoryLayout<
                    integer_t
                >.size
            )

        let result =
            withUnsafeMutablePointer(
                to: &info
            ) { pointer in

                pointer.withMemoryRebound(
                    to: integer_t.self,
                    capacity:
                        Int(count)
                ) { reboundPointer in

                    host_statistics(
                        mach_host_self(),
                        HOST_CPU_LOAD_INFO,
                        reboundPointer,
                        &count
                    )
                }
            }

        guard
            result == KERN_SUCCESS
        else {
            return nil
        }

        return info
    }

}
