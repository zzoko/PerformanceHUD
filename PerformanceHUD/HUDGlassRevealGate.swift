import Foundation

// Wait only when revealing a HUD that has no usable glass yet. Existing visible
// glass is held by the capture surface while its replacement is prepared.
@MainActor
final class HUDGlassRevealGate {
    private(set) var isWaiting = false
    private var timeoutTask: Task<Void, Never>?
    private let timeout: Duration
    var onWait: (() -> Void)?
    var onFinish: ((_ cancelled: Bool) -> Void)?

    init(timeout: Duration = .seconds(1)) { self.timeout = timeout }

    func begin(hasFrame: Bool, needsAttention: Bool) {
        guard !isWaiting, !hasFrame, !needsAttention else { return }
        isWaiting = true
        onWait?()
        timeoutTask = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    func update(hasFrame: Bool, needsAttention: Bool) {
        if hasFrame || needsAttention { finish() }
    }

    func finish(cancelled: Bool = false) {
        guard isWaiting else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        isWaiting = false
        onFinish?(cancelled)
    }

    deinit { timeoutTask?.cancel() }
}
