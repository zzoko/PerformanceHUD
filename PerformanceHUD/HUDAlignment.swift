import Foundation

enum HUDAlignment: String, CaseIterable {
    case vertical, horizontal

    func allows(_ metric: HUDMetric) -> Bool {
        self == .vertical || (metric != .fpsGraph && metric != .deviceInfo)
    }
}
