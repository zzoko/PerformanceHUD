import AppKit
import Sparkle

@MainActor
final class HUDUpdater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!
    private var observations: [NSKeyValueObservation] = []
    private(set) var startupError: String?
    private(set) var availableVersion: String?
    private(set) var isPerformingFirstLaunchCheck = false
    var onChange: (() -> Void)?

    override init() {
        super.init()
        let shouldCheckOnFirstLaunch = HUDUpdatePolicy.claimFirstLaunchCheck()
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
        // Sparkle supports an immediate check after start(), before its queued
        // startup cycle. This avoids a second scheduled check on the same launch.
        // Consume the first launch even if offline; later checks follow the user's schedule.
        if shouldCheckOnFirstLaunch && startupError == nil {
            isPerformingFirstLaunchCheck = true
            controller.updater.checkForUpdatesInBackground()
        }
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

    // Only the first launch offers an update directly. Recurring checks keep
    // their gentle menu reminder and leave download/restart choices to the user.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        isPerformingFirstLaunchCheck
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString
        onChange?()
        if isPerformingFirstLaunchCheck && handleShowingUpdate {
            // Bring the already-found offer forward even on a slow first check.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isPerformingFirstLaunchCheck,
                      self.controller.updater.sessionInProgress,
                      self.controller.updater.canCheckForUpdates else { return }
                self.controller.checkForUpdates(nil)
            }
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
        onChange?()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard isPerformingFirstLaunchCheck else { return }
        isPerformingFirstLaunchCheck = false
        onChange?()
    }

    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
}
