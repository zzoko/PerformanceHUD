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
}
