import Foundation
import Darwin

@MainActor
final class CPUUsageMonitor {
    var onCPUUsageUpdate: ((Double?) -> Void)?
    private let poller = MetricPoller<Double>(label: "PerformanceHUD.CPUUsage")
    private var targetPID: pid_t?

    func start(pid: pid_t) {
        guard targetPID != pid || !poller.isRunning else { return }
        targetPID = pid
        let sampler = CPUCounterSampler(pid: pid)
        poller.start(sample: { sampler.sample() }) { [weak self] in self?.onCPUUsageUpdate?($0) }
    }
    func stop() { targetPID = nil; poller.stop() }
}

// A fresh sampler per session, confined to MetricPoller's serial sampling queue.
nonisolated private final class CPUCounterSampler: @unchecked Sendable {
    private let pid: pid_t
    private var previousTime: UInt64?
    private var previousTimestamp: UInt64?
    init(pid: pid_t) { self.pid = pid }
    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t(); mach_timebase_info(&info); return info
    }()
    func sample() -> Double? {
        let now = DispatchTime.now().uptimeNanoseconds
        guard let current = readCPUTime(for: pid) else {
            previousTime = nil; previousTimestamp = nil
            return nil
        }
        defer { previousTime = current; previousTimestamp = now }
        guard let previousTime, let previousTimestamp,
              current >= previousTime, now > previousTimestamp else { return nil }
        let delta = Double(current - previousTime) * Double(timebase.numer) / Double(timebase.denom)
        let usage = delta / Double(now - previousTimestamp) * 100
        guard usage.isFinite, usage >= 0 else { return nil }
        // One fully used logical CPU is 100%; app CPU can exceed 100%.
        return usage
    }
    // MARK: - Read Process CPU Time

    private func readCPUTime(
        for pid: pid_t
    ) -> UInt64? {

        var usage =
            rusage_info_v4()

        let result =
            withUnsafeMutablePointer(
                to: &usage
            ) { pointer -> Int32 in

                pointer.withMemoryRebound(
                    to: rusage_info_t?.self,
                    capacity: 1
                ) { reboundPointer in

                    proc_pid_rusage(
                        pid,
                        Int32(
                            RUSAGE_INFO_V4
                        ),
                        reboundPointer
                    )
                }
            }

        guard
            result == 0
        else {
            return nil
        }

        /*
         These are cumulative CPU-time counters.

         Do not include child process time here:
         this HUD entry is for the selected PID.
        */

        return usage.ri_user_time
            &+ usage.ri_system_time
    }

}
