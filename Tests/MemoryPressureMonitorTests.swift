import Foundation

@main struct MemoryPressureMonitorTests {
    @MainActor static func main() {
        let monitor = MemoryPressureMonitor()
        var deliveries: [TimeInterval] = []
        var hasLiveReading = false
        monitor.onPressureUpdate = { level in
            deliveries.append(Date.timeIntervalSinceReferenceDate)
            hasLiveReading = hasLiveReading || level != nil
        }
        monitor.start()
        monitor.start()
        RunLoop.current.run(until: Date().addingTimeInterval(2.2))
        precondition((2...4).contains(deliveries.count), "Repeated starts keep a single one-second sampler")
        precondition(hasLiveReading, "The live macOS pressure state is readable")
        let intervals = zip(deliveries.dropFirst(), deliveries).map { $0 - $1 }
        precondition(intervals.allSatisfy { (0.5...1.5).contains($0) }, "Pressure refreshes once per second")
        monitor.stop()
        let stoppedCount = deliveries.count
        RunLoop.current.run(until: Date().addingTimeInterval(1.1))
        precondition(deliveries.count == stoppedCount, "Stopped monitoring rejects queued results")
        monitor.start()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        precondition(deliveries.count == stoppedCount + 1, "Restart samples immediately")
        monitor.stop()
        print("PASS: live pressure, one-second cadence, idempotent start, stop and restart")
    }
}
