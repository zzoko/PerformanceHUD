import AppKit
import ServiceManagement
import CryptoKit

@MainActor
final class PowerHelperClient {
    var onUpdate: ((HelperPowerReading?) -> Void)?
    var onStateChange: (() -> Void)?
    var onPowerSelectionChange: ((Bool) -> Void)?
    private var startupFailed = false
    private var receivedLiveReading = false
    private var recovery = PowerHelperRecovery()
    private var health = PowerHelperHealth()
    private let service = SMAppService.daemon(plistName: PowerHelperIdentity.plist)
    private var connection: NSXPCConnection?
    private var generation = UUID()
    private var pendingRequest: UUID?
    private var timer: Timer?
    private var desired = false {
        didSet {
            if desired != oldValue { onStateChange?() }
        }
    }
    private var sleeping = false
    private var observers: [NSObjectProtocol] = []
    private(set) var busy = false
    private(set) var lastError: String?
    private var lastStatus: SMAppService.Status?
    private var nextConnectionAttempt: TimeInterval = 0
    private let revisionKey = "powerHelperInstalledRevision"
    private let promptKey = "powerHelperSetupOffered"

    var status: SMAppService.Status { service.status }
    var availability: PowerHelperAvailability {
        if busy { return .updating }
        if startupFailed { return .failed }
        if needsUpdate { return .setupRequired }
        switch status {
        case .enabled:
            return .approved(samplingRequested: desired, receivedLiveReading: receivedLiveReading)
        case .requiresApproval: return .approvalRequired
        default: return .setupRequired
        }
    }
    private var canReadPower: Bool {
        !busy && !startupFailed && !needsUpdate && status == .enabled
    }
    var shouldTurnPowerOff: Bool {
        availability.shouldTurnPowerOff(setupOffered: UserDefaults.standard.bool(forKey: promptKey))
    }
    var canInstall: Bool { PowerHelperIdentity.requirement(for: PowerHelperIdentity.service) != nil }
    var needsUpdate: Bool {
        guard let installed = UserDefaults.standard.string(forKey: revisionKey) else { return false }
        return installed != bundledRevision
    }
    private lazy var bundledRevision: String? = {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/" + PowerHelperIdentity.service)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }()

    init() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleeping = true; self?.health.reset(); self?.disconnect() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleeping = false; self?.tick() }
        })
        // Approval can change while Power is unticked. Keep watching service
        // status without starting a sampler until a visible Power option needs it.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func configure(enabled: Bool) {
        if !enabled { stop(); return }
        desired = true
        tick()
    }

    func stop() {
        desired = false
        health.reset()
        disconnect()
    }

    func refreshStatus() {
        let current = status
        if current != lastStatus {
            let previous = lastStatus
            lastStatus = current
            // A later approval should restore both Power options, even though
            // they were unticked while waiting in System Settings.
            if previous != nil, previous != .enabled, current == .enabled, !busy, !needsUpdate {
                startupFailed = false; lastError = nil; health.reset()
                onPowerSelectionChange?(true)
            }
            onStateChange?()
        }
    }

    func offerSetupOnFirstLaunch() {
        refreshStatus()
        guard status != .requiresApproval,
              needsUpdate || (status != .enabled && !UserDefaults.standard.bool(forKey: promptKey)) else { return }
        requestSetup()
    }

    func requestSetup() {
        guard !busy else { return }
        busy = true; onStateChange?()
        UserDefaults.standard.set(true, forKey: promptKey)
        let alert = NSAlert()
        alert.messageText = needsUpdate ? "Update power readings helper?" : "Enable power readings?"
        alert.informativeText = "CPU, GPU, and Package watts use a small background helper to read macOS power measurements. macOS may ask for administrator approval. It only samples while a Power option and the HUD are enabled. You can remove it from the Power Helper menu."
        alert.addButton(withTitle: needsUpdate ? "Update Helper" : "Enable Power Readings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            busy = false; onStateChange?(); return
        }
        guard canInstall, bundledRevision != nil else {
            busy = false; startupFailed = true
            showError("The app and its bundled helper need matching Apple signing certificates. For a personal build, select your development team in Xcode for both targets.")
            return
        }
        startupFailed = false; receivedLiveReading = false; recovery = PowerHelperRecovery()
        health.reset(); nextConnectionAttempt = 0
        onStateChange?(); disconnect()
        Task {
            do {
                try await registerCurrentHelper()
                lastError = nil
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            } catch {
                startupFailed = true
                showError("Power helper setup failed: \(error.localizedDescription)")
            }
            busy = false
            refreshStatus()
            if canReadPower { onPowerSelectionChange?(true) }
            onStateChange?(); tick()
        }
    }

    private func registerCurrentHelper() async throws {
        if service.status == .enabled || service.status == .requiresApproval {
            try await service.unregister()
            // Background Task Management can finish removal just after the callback.
            try await Task.sleep(for: .seconds(1))
        }
        try await registerWithRetry()
        UserDefaults.standard.set(bundledRevision, forKey: revisionKey)
    }

    // Approval is not proof that launchd has a runnable job. A moved/replaced
    // app or reset background-item data can leave "enabled" with no service.
    // Refresh the existing approved registration once, never bypass approval or
    // repeatedly reinstall a failing helper.
    private func recoverApprovedHelper() -> Bool {
        guard desired, !sleeping, !busy, canInstall, bundledRevision != nil, !needsUpdate,
              recovery.beginIfApproved(status == .enabled) else { return false }
        busy = true; receivedLiveReading = false
        disconnect(); onStateChange?()
        Task {
            do {
                try await registerCurrentHelper()
                startupFailed = false; lastError = nil
                health.reset(); nextConnectionAttempt = 0
            } catch {
                startupFailed = true
                lastError = "Could not restart the power helper: \(error.localizedDescription)"
            }
            // Automatic recovery preserves the user's selections. A later
            // explicit macOS approval is still handled by refreshStatus().
            refreshStatus()
            busy = false; onStateChange?(); tick()
        }
        return true
    }

    private func registerWithRetry() async throws {
        for attempt in 0..<3 {
            do { try service.register(); return }
            catch {
                if service.status == .requiresApproval { return }
                let failure = error as NSError
                guard failure.domain == SMAppServiceErrorDomain, failure.code == 1,
                      service.status == .notRegistered, attempt < 2 else { throw error }
                try await Task.sleep(for: .seconds(1))
            }
        }
    }

    func remove() {
        guard !busy else { return }
        busy = true; disconnect(); onStateChange?()
        Task {
            do {
                try await service.unregister()
                UserDefaults.standard.removeObject(forKey: revisionKey)
                UserDefaults.standard.set(true, forKey: promptKey)
                startupFailed = false; health.reset(); lastError = nil
            } catch { showError("Could not remove the power helper: \(error.localizedDescription)") }
            busy = false; refreshStatus(); onStateChange?()
        }
    }

    func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }

    func requestPowerAccess() {
        guard !busy else { return }
        if status == .requiresApproval && !needsUpdate { openApprovalSettings() }
        else { requestSetup() }
    }

    private func connectionFailed(_ message: String) {
        lastError = message
        if recoverApprovedHelper() { return }
        nextConnectionAttempt = Date.timeIntervalSinceReferenceDate + 10
        let confirmed = health.connectionFailed()
        disconnect()
        if confirmed { startupFailed = true }
        onStateChange?()
    }

    private func showError(_ message: String) {
        lastError = message
        let alert = NSAlert()
        alert.messageText = "Power readings unavailable"
        alert.informativeText = message + " Other HUD metrics can still be used."
        alert.runModal()
        onStateChange?()
    }

    private func tick() {
        refreshStatus()
        guard desired, !sleeping, canReadPower else {
            if connection != nil || pendingRequest != nil { disconnect() }
            return
        }
        guard pendingRequest == nil else { return }
        if connection == nil {
            guard Date.timeIntervalSinceReferenceDate >= nextConnectionAttempt else { return }
            guard let requirement = PowerHelperIdentity.requirement(for: PowerHelperIdentity.service) else {
                startupFailed = true
                lastError = "This app needs an Apple signing certificate to connect to the power helper."
                onStateChange?()
                return
            }
            let c = NSXPCConnection(machServiceName: PowerHelperIdentity.service, options: .privileged)
            c.remoteObjectInterface = NSXPCInterface(with: PowerHelperProtocol.self)
            c.setCodeSigningRequirement(requirement)
            let ticket = generation
            let failed: () -> Void = { [weak self] in
                Task { @MainActor in
                    guard let self, self.generation == ticket else { return }
                    self.connectionFailed("The connection to the power helper was interrupted.")
                }
            }
            c.invalidationHandler = failed
            c.interruptionHandler = failed
            connection = c
            c.resume()
        }
        guard let connection else { return }
        let ticket = generation
        let request = UUID()
        pendingRequest = request
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in
                guard let self, self.generation == ticket else { return }
                self.connectionFailed(error.localizedDescription)
            }
        } as? PowerHelperProtocol
        proxy?.sample { [weak self] data in
            let sample = HelperPowerReading(reply: data)
            Task { @MainActor in
                guard let self, self.generation == ticket, self.desired, !self.sleeping else { return }
                self.pendingRequest = nil
                if self.health.receivedSample(valid: sample != nil) {
                    if self.recoverApprovedHelper() { return }
                    self.startupFailed = true
                    self.lastError = "The power helper has not provided a valid reading for 30 seconds."
                    self.disconnect(); self.onStateChange?()
                    return
                }
                if sample != nil {
                    self.lastError = nil
                    if !self.receivedLiveReading {
                        self.receivedLiveReading = true
                        self.onStateChange?()
                    }
                }
                self.onUpdate?(sample)
            }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.generation == ticket, self.pendingRequest == request else { return }
            self.connectionFailed("The power helper did not respond.")
        }
    }

    private func disconnect() {
        generation = UUID(); pendingRequest = nil
        if let c = connection {
            connection = nil
            c.invalidationHandler = nil; c.interruptionHandler = nil
            // Invalidation itself also removes the lease server-side if this
            // stop message cannot be delivered (including abrupt app exit).
            (c.remoteObjectProxy as? PowerHelperProtocol)?.stop { c.invalidate() }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                c.invalidate()
            }
        }
        onUpdate?(nil)
    }

    deinit {
        timer?.invalidate()
        connection?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
