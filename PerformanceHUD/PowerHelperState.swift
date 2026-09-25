import Foundation

nonisolated enum PowerHelperAvailability {
    case idle, ready, starting, setupRequired, approvalRequired, updating, failed

    var usesNormalAppearance: Bool { self == .idle || self == .ready }
    var allowsPowerToggle: Bool { usesNormalAppearance || self == .starting }

    // An approved helper has nothing to respond to while sampling is off.
    static func approved(samplingRequested: Bool, receivedLiveReading: Bool) -> Self {
        guard samplingRequested else { return .idle }
        return receivedLiveReading ? .ready : .starting
    }

    func shouldTurnPowerOff(setupOffered: Bool) -> Bool {
        switch self {
        case .idle, .ready, .starting, .updating: return false
        case .approvalRequired, .failed: return true
        case .setupRequired: return setupOffered
        }
    }

    var explanation: String? {
        switch self {
        case .idle, .ready: return nil
        case .starting: return "Starting power readings. Waiting for the helper’s first valid sample."
        case .setupRequired: return "Power readings need helper setup. Click Power to set up or update the helper."
        case .approvalRequired: return "Power readings need macOS approval. Click Power to open approval settings."
        case .updating: return "Power helper setup is in progress."
        case .failed: return "The power helper could not provide readings. Click Power to repair its setup."
        }
    }
}

// Missing individual samples are normal during startup and bounded process
// handoffs. Only repeated communication failures or a sustained lack of data
// make power unavailable; sleeping and manually stopping reset this window.
nonisolated struct PowerHelperHealth {
    private var failures = 0
    private var waitingSince: TimeInterval?

    mutating func reset() { failures = 0; waitingSince = nil }

    mutating func connectionFailed() -> Bool {
        failures += 1
        return failures >= 3
    }

    mutating func receivedSample(valid: Bool, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        failures = 0
        if valid { waitingSince = nil; return false }
        if waitingSince == nil { waitingSince = now }
        return now - (waitingSince ?? now) >= 30
    }
}

// An enabled background switch can outlive the actual launchd registration.
// Recovery is limited to one refresh of an already approved helper per session.
nonisolated struct PowerHelperRecovery {
    private(set) var attempted = false

    mutating func beginIfApproved(_ approved: Bool) -> Bool {
        guard approved, !attempted else { return false }
        attempted = true
        return true
    }
}
