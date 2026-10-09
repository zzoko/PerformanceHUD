import Foundation

@MainActor
final class FanMonitor {
    var onUpdate: ((FanSample) -> Void)?
    private let poller = MetricPoller<FanSample>(label: "PerformanceHUD.Fans")
    private(set) var sample = FanSample.checking
    private var readingsRequested = false
    private var lastProbe: TimeInterval = -.infinity

    func configure(readings: Bool) {
        readingsRequested = readings
        if !readings { poller.stop() }
        // Discover hardware once even when the category is hidden, so the menu
        // can distinguish no fans from unavailable readings. Retry failures slowly.
        let needsProbe = sample.status == .checking
            || (sample.status == .unavailable && ProcessInfo.processInfo.systemUptime - lastProbe >= 30)
        guard !poller.isRunning, needsProbe || (readings && sample.status != .noFans) else { return }
        lastProbe = ProcessInfo.processInfo.systemUptime
        let reader = SMCTemperatureReader()
        let readSample: @Sendable () -> FanSample? = { reader.readFans() }
        poller.start(interval: 1, sample: readSample, deliver: { [weak self] result in
            guard let self else { return }
            sample = (result ?? .unavailable).preservingTopology(from: sample)
            onUpdate?(sample)
            if !readingsRequested || sample.status == .noFans { poller.stop() }
        })
    }

    func stop() { readingsRequested = false; poller.stop() }
}
