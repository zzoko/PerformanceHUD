// Isolated Sparkle test app, never compiled into PerformanceHUD.
import AppKit
import CryptoKit
import Sparkle

@MainActor
final class FixtureDriver: NSObject, NSApplicationDelegate, SPUUserDriver {
    var updater: SPUUpdater!
    private var standardUpdater: HUDUpdater?
    private var root: URL {
        let path = Bundle.main.object(forInfoDictionaryKey: "FixtureRoot") as! String
        precondition(path.hasPrefix("/tmp/PerformanceHUD-updater-test-") || path.hasPrefix("/private/tmp/PerformanceHUD-updater-test-"))
        return URL(fileURLWithPath: path)
    }
    private func record(_ text: String) {
        let file = root.appendingPathComponent("events.log")
        if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
        let handle = try! FileHandle(forWritingTo: file)
        try! handle.seekToEnd()
        try! handle.write(contentsOf: Data((text + "\n").utf8))
        try! handle.close()
    }
    private func finish(_ text: String) {
        record(text)
        try! text.write(to: root.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        precondition(Bundle.main.bundleIdentifier?.hasPrefix("andrei.PerformanceHUD.UpdaterTest.") == true)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
        record("Launched build \(version)")
        let testCase = Bundle.main.object(forInfoDictionaryKey: "FixtureCase") as? String
        if testCase == "settings" { checkSavedSchedule(); return }
        if testCase == "scheduled" { checkScheduledReminder(); return }
        if version == "2" {
            finish(UserDefaults.standard.string(forKey: "FixturePreference") == "preserved" ? "INSTALLED; preferences preserved" : "FAILED: preferences lost")
            return
        }
        UserDefaults.standard.set("preserved", forKey: "FixturePreference")
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil)
        updater.httpHeaders = HUDUpdatePolicy.headers
        do {
            try updater.start()
            precondition(!updater.automaticallyChecksForUpdates)
            precondition(!updater.automaticallyDownloadsUpdates)
            updater.checkForUpdates()
        } catch { finish("FAILED: \(error)") }
    }

    private func checkSavedSchedule() {
        let service = HUDUpdater()
        standardUpdater = service
        precondition(service.startupError == nil)
        switch CommandLine.arguments.last {
        case "restore":
            precondition(service.schedule == .monthly)
            service.setSchedule(.off)
            finish("SETTINGS restored monthly; saved off")
        case "verify-off":
            precondition(service.schedule == .off)
            finish("SETTINGS retained off after relaunch")
        default:
            precondition(service.schedule == .off)
            service.setSchedule(.weekly)
            precondition(service.schedule == .weekly)
            precondition(UserDefaults.standard.double(forKey: "SUScheduledCheckInterval") == 604_800)
            service.setSchedule(.monthly)
            precondition(service.schedule == .monthly)
            precondition(UserDefaults.standard.double(forKey: "SUScheduledCheckInterval") == 2_592_000)
            finish("SETTINGS saved monthly")
        }
    }

    private func checkScheduledReminder() {
        // Make a genuine scheduled check overdue in this disposable preference
        // domain. The production wrapper and standard Sparkle UI handle it.
        UserDefaults.standard.set(true, forKey: "SUEnableAutomaticChecks")
        UserDefaults.standard.set(604_800, forKey: "SUScheduledCheckInterval")
        UserDefaults.standard.set(Date(timeIntervalSince1970: 0), forKey: "SULastCheckTime")
        let service = HUDUpdater()
        standardUpdater = service
        precondition(service.startupError == nil)
        service.onChange = { [weak self] in
            guard service.availableVersion == "2.0", let self else { return }
            DispatchQueue.main.async {
                precondition(service.canCheck, "The menu must be able to open a pending update")
                precondition(!NSApp.windows.contains(where: { $0.isVisible }), "Scheduled checks must not show windows")
                self.finish("SCHEDULED menu reminder; no popup")
            }
        }
    }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        finish("FAILED: unexpected automatic-check permission request")
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { record("Checking") }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        record("Found signed update \(appcastItem.versionString)")
        reply(.install) // Only this disposable fixture ever auto-accepts an install.
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) { finish("FAILED: release notes") }
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        finish("NO UPDATE")
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        record("Sparkle error: \(error as NSError)")
        acknowledgement()
        finish("REJECTED: \((error as NSError).code)")
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { record("Downloading") }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { record("Starting archive validation/extraction") }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        record("Ready to install")
        reply(.install)
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) { record("Installing") }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() { record("Session dismissed") }
}

@main
struct UpdaterFixture {
    @MainActor static func main() throws {
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--generate-test-key" {
            let key = Curve25519.Signing.PrivateKey()
            let url = URL(fileURLWithPath: CommandLine.arguments[2])
            try key.rawRepresentation.base64EncodedString().write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            print(key.publicKey.rawRepresentation.base64EncodedString())
            return
        }
        let app = NSApplication.shared
        let delegate = FixtureDriver()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
