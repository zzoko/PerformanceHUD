import AppKit
import Sparkle

@MainActor
final class HUDUpdater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!
    private var observations: [NSKeyValueObservation] = []
    private(set) var startupError: String?
    private(set) var availableVersion: String?
    var onChange: (() -> Void)?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false,
                                                  updaterDelegate: self, userDriverDelegate: self)
        controller.updater.httpHeaders = HUDUpdatePolicy.headers
        do {
            try controller.updater.start()
        } catch {
            startupError = error.localizedDescription
        }
        // Sparkle documents these notifications as main-thread only.
        observations = [
            controller.updater.observe(\.canCheckForUpdates) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.onChange?() }
            },
            controller.updater.observe(\.automaticallyChecksForUpdates) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.onChange?() }
            },
            controller.updater.observe(\.updateCheckInterval) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.onChange?() }
            }
        ]
    }

    var canCheck: Bool { startupError != nil || controller.updater.canCheckForUpdates }
    var schedule: HUDUpdateSchedule {
        HUDUpdateSchedule(automatic: controller.updater.automaticallyChecksForUpdates,
                          interval: controller.updater.updateCheckInterval)
    }

    func setSchedule(_ schedule: HUDUpdateSchedule) {
        if schedule != .off { controller.updater.updateCheckInterval = schedule.interval }
        controller.updater.automaticallyChecksForUpdates = schedule != .off
        onChange?()
    }

    func checkForUpdates() {
        if let startupError {
            let alert = NSAlert()
            alert.messageText = "Updates are unavailable"
            alert.informativeText = startupError
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        guard canCheck else { return }
        controller.checkForUpdates(nil)
    }

    // Scheduled checks only add a menu reminder, including immediately after launch.
    // Sparkle presents its normal install UI when the user clicks Check for updates.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString
        onChange?()
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
        onChange?()
    }

    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
}
