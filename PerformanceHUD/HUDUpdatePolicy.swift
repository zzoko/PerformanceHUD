import Foundation

/// The settings themselves belong to Sparkle, so there is only one saved schedule.
enum HUDUpdateSchedule: Int, CaseIterable {
    case off, weekly, monthly

    var title: String {
        switch self {
        case .off: return "Off"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    var interval: TimeInterval {
        self == .monthly ? 30 * 24 * 60 * 60 : 7 * 24 * 60 * 60
    }

    init(automatic: Bool, interval: TimeInterval) {
        self = !automatic ? .off : (interval >= Self.monthly.interval ? .monthly : .weekly)
    }
}

enum HUDUpdatePolicy {
    // Request marker for the official update service.
    static let headers = ["X-PerformanceHUD-Updater": "1"]

    /// Consume once, independently of app versions and the recurring schedule.
    static func claimFirstLaunchCheck(in store: UserDefaults = .standard) -> Bool {
        let key = "hud.updates.firstLaunchCheckHandled"
        guard !store.bool(forKey: key) else { return false }
        store.set(true, forKey: key)
        // Older releases already recorded these Sparkle preferences. Use them
        // only for migration so updating an existing copy is not a first launch.
        return !store.bool(forKey: "SUHasLaunchedBefore")
            && store.object(forKey: "SULastCheckTime") == nil
    }
}
