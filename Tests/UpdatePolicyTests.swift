import Foundation

@main
struct UpdatePolicyTests {
    static func main() throws {
        precondition(HUDUpdateSchedule(automatic: false, interval: 0) == .off)
        precondition(HUDUpdateSchedule(automatic: false, interval: 2_592_000) == .off)
        precondition(HUDUpdateSchedule(automatic: true, interval: 604_800) == .weekly)
        precondition(HUDUpdateSchedule(automatic: true, interval: 2_592_000) == .monthly)
        precondition(HUDUpdateSchedule.weekly.interval == 604_800)
        precondition(HUDUpdateSchedule.monthly.interval == 2_592_000)
        checkFirstLaunchPolicy()
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as! [String: Any]
        for key in ["SUEnableAutomaticChecks", "SUAllowsAutomaticUpdates", "SUAutomaticallyUpdate", "SUEnableSystemProfiling"] {
            precondition(info[key] as? Bool == false, "\(key) must default off")
        }
        for key in ["SUVerifyUpdateBeforeExtraction", "SURequireSignedFeed"] {
            precondition(info[key] as? Bool == true, "\(key) must be enforced")
        }
        precondition(info["SUSignedFeedFailureExpirationInterval"] as? Int == 0)
        precondition(Data(base64Encoded: info["SUPublicEDKey"] as! String)?.count == 32)
        precondition((info["SUFeedURL"] as! String).hasPrefix("https://"))
        print("Update defaults, first-launch, and schedule checks passed")
    }

    private static func checkFirstLaunchPolicy() {
        let domain = "andrei.PerformanceHUD.FirstLaunchPolicyTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }

        precondition(HUDUpdatePolicy.claimFirstLaunchCheck(in: defaults), "A new installation should check once")
        precondition(!HUDUpdatePolicy.claimFirstLaunchCheck(in: defaults), "The same launch must not claim twice")
        precondition(!HUDUpdatePolicy.claimFirstLaunchCheck(in: UserDefaults(suiteName: domain)!),
                     "The first-launch marker must persist across instances")
        precondition(defaults.object(forKey: "SUEnableAutomaticChecks") == nil)
        precondition(defaults.object(forKey: "SUScheduledCheckInterval") == nil)

        // Existing users do not get another first-launch offer on upgrading.
        for legacyKey in ["SUHasLaunchedBefore", "SULastCheckTime"] {
            defaults.removePersistentDomain(forName: domain)
            if legacyKey == "SUHasLaunchedBefore" {
                defaults.set(true, forKey: legacyKey)
            } else {
                defaults.set(Date(timeIntervalSince1970: 1), forKey: legacyKey)
            }
            precondition(!HUDUpdatePolicy.claimFirstLaunchCheck(in: defaults), "Skip existing user: \(legacyKey)")
            defaults.removeObject(forKey: legacyKey)
            precondition(!HUDUpdatePolicy.claimFirstLaunchCheck(in: defaults), "Migration must save the one-time marker")
        }

        // Claiming the first check is independent of the automatic-check choice.
        for schedule in HUDUpdateSchedule.allCases {
            defaults.removePersistentDomain(forName: domain)
            defaults.set(false, forKey: "SUHasLaunchedBefore")
            defaults.set(schedule != .off, forKey: "SUEnableAutomaticChecks")
            defaults.set(schedule.interval, forKey: "SUScheduledCheckInterval")
            defaults.set(false, forKey: "SUAutomaticallyUpdate")
            precondition(HUDUpdatePolicy.claimFirstLaunchCheck(in: defaults))
            precondition(defaults.bool(forKey: "SUEnableAutomaticChecks") == (schedule != .off))
            precondition(defaults.double(forKey: "SUScheduledCheckInterval") == schedule.interval)
            precondition(!defaults.bool(forKey: "SUAutomaticallyUpdate"))
            precondition(!HUDUpdatePolicy.claimFirstLaunchCheck(in: defaults))
        }
    }
}
