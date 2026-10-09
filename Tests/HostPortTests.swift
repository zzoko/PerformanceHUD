import Foundation
import Darwin

@main struct HostPortTests {
    static func referenceCount(_ host: mach_port_t) -> mach_port_urefs_t {
        var count: mach_port_urefs_t = 0
        precondition(mach_port_get_refs(mach_task_self_, host, mach_port_right_t(MACH_PORT_RIGHT_SEND), &count)
            == KERN_SUCCESS, "The retained host port's send-right count must be readable")
        return count
    }

    static func main() {
        // Keep one right alive so every sample uses the same local port name.
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let cpu = TotalCPUSampler()
        _ = cpu.sample()
        precondition(TotalRAMUsageMonitorReader.read() != nil, "Live VM statistics must be available")

        // Warm up Foundation and both readers before measuring their ownership.
        let baseline = referenceCount(host)
        var validCPUReadings = 0
        for _ in 0..<256 {
            Thread.sleep(forTimeInterval: 0.002)
            if let usage = cpu.sample() {
                precondition(usage.isFinite && (0...100).contains(usage), "Live CPU usage stays in range")
                validCPUReadings += 1
            }
        }
        precondition(validCPUReadings > 0, "Repeated CPU samples must include a valid tick delta")
        precondition(referenceCount(host) == baseline, "CPU samples must release every acquired host send right")

        for _ in 0..<256 {
            guard let usage = TotalRAMUsageMonitorReader.read() else {
                preconditionFailure("Repeated RAM samples must preserve valid live readings")
            }
            precondition(usage.percentage.isFinite && (0...100).contains(usage.percentage),
                         "Live RAM usage stays in range")
            precondition(usage.usedBytes > 0, "Live RAM usage has a positive byte count")
        }
        precondition(referenceCount(host) == baseline, "RAM samples must release every acquired host send right")
        print("PASS: 256 live samples per reader preserve valid CPU/RAM readings and a stable host-port reference count")
    }
}
