import Foundation
import Darwin

@MainActor
final class RAMUsageMonitor {
    var onRAMUsageUpdate: ((RAMUsageSample?) -> Void)?
    private let poller = MetricPoller<RAMUsageSample>(label: "PerformanceHUD.RAMUsageMonitor")
    private var targetPID: pid_t?

    func start(pid: pid_t) {
        guard targetPID != pid || !poller.isRunning else { return }
        targetPID = pid
        poller.start(sample: { RAMUsageMonitorReader.read(pid: pid) }) { [weak self] in
            self?.onRAMUsageUpdate?($0)
        }
    }
    func stop() { targetPID = nil; poller.stop() }
}

nonisolated private enum RAMUsageMonitorReader {
    static func read(pid: pid_t) -> RAMUsageSample? {
        let physicalMemory = Double(ProcessInfo.processInfo.physicalMemory)
        guard let footprint = readPhysicalFootprint(for: pid), physicalMemory > 0 else { return nil }
        return RAMUsageSample(percentage: min(100, Double(footprint) / physicalMemory * 100), usedBytes: footprint)
    }
    // MARK: - Read Process Footprint

    static func readPhysicalFootprint(
        for pid: pid_t
    ) -> UInt64? {

        var usage =
            rusage_info_v4()

        let result =
            withUnsafeMutablePointer(
                to: &usage
            ) { pointer -> Int32 in

                pointer.withMemoryRebound(
                    to:
                        Optional<
                            rusage_info_t
                        >.self,
                    capacity: 1
                ) { reboundPointer in

                    proc_pid_rusage(
                        pid,
                        RUSAGE_INFO_V4,
                        reboundPointer
                    )
                }
            }

        guard
            result == 0
        else {
            return nil
        }

        return usage
            .ri_phys_footprint
    }

}
