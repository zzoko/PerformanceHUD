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
        var history: [MemoryPressureMonitor.Sample] = []
        monitor.onHistoryUpdate = { history.append($0) }
        monitor.start()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        precondition(history.isEmpty, "Text and meter do not sample numeric history")
        monitor.start(includeHistory: true)
        monitor.start(includeHistory: true)
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        precondition((1...2).contains(history.count), "Enabling history starts one sampler, not two")
        precondition(history.allSatisfy { $0.numericValue.map { $0.isFinite && (0...100).contains($0) } == true },
                     "The live numeric pressure source is available and in range")
        monitor.start(includeHistory: false)
        let previousCount = history.count
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        precondition(history.count == previousCount, "Returning to meter cancels queued numeric samples")
        monitor.stop()
        print("PASS: live state and numeric pressure, one-second cadence, demand changes, stop and restart")
    }
}
