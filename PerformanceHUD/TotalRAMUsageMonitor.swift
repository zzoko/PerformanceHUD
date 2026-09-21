import Foundation
import Darwin

@MainActor
final class TotalRAMUsageMonitor {
    var onRAMUsageUpdate: ((RAMUsageSample?) -> Void)?
    private let poller = MetricPoller<RAMUsageSample>(label: "PerformanceHUD.TotalRAMUsageMonitor")

    func start() {
        guard !poller.isRunning else { return }
        poller.start(sample: { TotalRAMUsageMonitorReader.read() }) { [weak self] in
            self?.onRAMUsageUpdate?($0)
        }
    }
    func stop() { poller.stop() }
}

nonisolated private enum TotalRAMUsageMonitorReader {
    static func read() -> RAMUsageSample? {
        let physicalMemory = Double(ProcessInfo.processInfo.physicalMemory)
        guard let statistics = readVMStatistics(), physicalMemory > 0 else { return nil }
        // Approximate Activity Monitor's App Memory + Wired + Compressed.
        let appPages = max(Double(statistics.internal_page_count) - Double(statistics.purgeable_count), 0)
        let usedBytes = (appPages + Double(statistics.wire_count) + Double(statistics.compressor_page_count))
            * Double(vm_kernel_page_size)
        return RAMUsageSample(percentage: min(100, usedBytes / physicalMemory * 100), usedBytes: UInt64(usedBytes), swapUsedBytes: readSwapUsedBytes())
    }
    // Current disk-backed swap in use, not the allocated swap-file capacity.
    static func readSwapUsedBytes() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0, size == MemoryLayout<xsw_usage>.size else { return nil }
        return usage.xsu_used
    }

    // MARK: - VM Statistics

    static func readVMStatistics()
        -> vm_statistics64_data_t?
    {

        var statistics =
            vm_statistics64_data_t()

        var count =
            mach_msg_type_number_t(
                MemoryLayout<
                    vm_statistics64_data_t
                >.size
                /
                MemoryLayout<
                    integer_t
                >.size
            )

        let result =
            withUnsafeMutablePointer(
                to: &statistics
            ) { pointer in

                pointer.withMemoryRebound(
                    to: integer_t.self,
                    capacity:
                        Int(count)
                ) { reboundPointer in

                    host_statistics64(
                        mach_host_self(),
                        HOST_VM_INFO64,
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

        return statistics
    }

}
