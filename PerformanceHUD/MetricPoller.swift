import Foundation

/// The owner and deliveries live on MainActor. A session's sampler is used only on
/// this serial queue and is never reset by start/stop while a read is in flight.
@MainActor
final class MetricPoller<Value: Sendable> {
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private var generation = UUID()
    var isRunning: Bool { timer != nil }

    init(label: String) { queue = DispatchQueue(label: label, qos: .utility) }

    func start(interval: Double = 1, sample: @escaping @Sendable () -> Value?,
               deliver: @escaping @MainActor (Value?) -> Void) {
        stop()
        let ticket = generation
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval,
                       leeway: .milliseconds(interval >= 5 ? 250 : 50))
        timer.setEventHandler { [weak self] in
            let value = sample()
            DispatchQueue.main.async {
                guard let self, self.generation == ticket else { return }
                deliver(value)
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        generation = UUID() // Reject results already queued for the main thread.
        timer?.cancel()
        timer = nil
    }

    deinit { timer?.cancel() }
}
