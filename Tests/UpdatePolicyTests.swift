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
        print("Update defaults and schedule checks passed")
    }
}
