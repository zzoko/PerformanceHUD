import Foundation

struct HUDFPSAvailability {
    static let collapseDelay: TimeInterval = 3
    private(set) var hasReading = false
    private(set) var unavailableSince: TimeInterval?
    private(set) var expanded = false

    mutating func receivedReading() {
        hasReading = true
        unavailableSince = nil
        expanded = true
    }
    mutating func unavailable(at now: TimeInterval) {
        hasReading = false
        // Repeated callbacks must not continually postpone collapse.
        if expanded && unavailableSince == nil { unavailableSince = now }
    }
    mutating func advance(to now: TimeInterval) {
        if let unavailableSince, now - unavailableSince >= Self.collapseDelay {
            expanded = false
            self.unavailableSince = nil
        }
    }
}
