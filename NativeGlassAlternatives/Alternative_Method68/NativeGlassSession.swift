import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import QuartzCore

// Method 68 replacement ONLY. Keep this file OUT of the app target while using 67.
// Replace the main NativeGlassSession.swift with this file; never compile both.
// NativeGlassHUDBackground.swift is shared and does not need changing.
// Captures only this app's HUD window, then parks; no legacy refresh listener.
// Composited/uncapped rendering is observed behavior, not an API guarantee.

@available(macOS 26.0, *)
@MainActor
final class NativeGlassSession: NSObject, SCStreamOutput, SCStreamDelegate {
    private weak var window: NSWindow?
    private let workspaceNotifications = NSWorkspace.shared.notificationCenter
    private var enabled = false
    private var systemAsleep = false
    private var displayAsleep = false
    private var stream: SCStream?
    private var operation: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var firstFrameDeadline: Task<Void, Never>?
    private var generation = 0
    private var retryCount = 0
    private var starting = false
    private var parking = false

    private(set) var status = "Stopped"
    private(set) var isParked = false
    private(set) var completeFrames = 0
    private(set) var deliveredSize = CGSize.zero
    private(set) var lastFrameTime: CFTimeInterval?
    // Active means a stream exists, not that another app is uncapped.
    var isActive: Bool { stream != nil }

    init(window: NSWindow) {
        self.window = window
        super.init()
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceNotifications.addObserver(self, selector: #selector(workspaceChanged(_:)), name: name, object: nil)
        }
        for name in [NSWindow.didChangeScreenNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowChanged(_:)), name: name, object: window)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged(_:)),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // Call AFTER ordering the HUD on screen, and BEFORE ordering it out.
    // AppKit has no general orderOut notification: the host must wire its visibility toggle.
    func setVisible(_ visible: Bool) {
        guard visible != enabled else { return }
        enabled = visible
        retryCount = 0
        refresh()
    }

    // Explicit retry after a bounded recovery has failed.
    // No permission prompt or TCC reset is performed by this helper.
    func retry() { retryCount = 0; refresh() }

    func shutdown() async {
        setVisible(false)
        await operation?.value
    }

    @objc private func workspaceChanged(_ note: Notification) {
        switch note.name {
        case NSWorkspace.willSleepNotification: systemAsleep = true
        case NSWorkspace.didWakeNotification: systemAsleep = false
        case NSWorkspace.screensDidSleepNotification: displayAsleep = true
        case NSWorkspace.screensDidWakeNotification: displayAsleep = false
        default: return
        }
        retryCount = 0; refresh()
    }

    @objc private func windowChanged(_ note: Notification) {
        if note.name == NSWindow.willCloseNotification { enabled = false }
        retryCount = 0; refresh()
    }

    @objc private func displaysChanged(_ note: Notification) {
        retryCount = 0; refresh()
    }

    private var shouldRun: Bool {
        enabled && !systemAsleep && !displayAsleep && window?.isVisible == true && window?.isMiniaturized == false
    }

    private func refresh() {
        generation += 1
        let token = generation
        retryTask?.cancel(); retryTask = nil
        firstFrameDeadline?.cancel(); firstFrameDeadline = nil
        isParked = false
        let previous = operation
        operation = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await self.stopCurrent()
            guard self.generation == token else { return }
            self.completeFrames = 0; self.deliveredSize = .zero; self.lastFrameTime = nil
            self.starting = false; self.parking = false
            guard self.shouldRun else { self.status = self.enabled ? "Suspended" : "Stopped"; return }
            do {
                self.status = "Finding this HUD's own window"
                let content = try await SCShareableContent.currentProcess
                guard self.generation == token, self.shouldRun else { return }
                guard let window = self.window, window.windowNumber > 0,
                      let own = content.windows.first(where: {
                          $0.windowID == CGWindowID(window.windowNumber) &&
                          $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
                      }) else {
                    self.status = "Own HUD window unavailable"; self.scheduleRecovery(token: token); return
                }
                // currentProcess exposes content available without TCC consent. Never
                // fall back to full-display capture or enumerate other apps' windows.
                let filter = SCContentFilter(desktopIndependentWindow: own)
                let next = SCStream(filter: filter, configuration: Self.configuration(interval: 1), delegate: self)
                try next.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
                self.stream = next; self.starting = true
                try await next.startCapture()
                self.starting = false
                guard self.generation == token, self.shouldRun else { await self.stopCurrent(); return }
                self.status = "Waiting for the first complete frame"
                self.firstFrameDeadline = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                    guard let self, self.generation == token, !self.isParked else { return }
                    self.failAndRecover("Capture did not park within five seconds", token: token)
                }
                self.parkAfterFirstFrame()
            } catch {
                self.starting = false
                guard self.generation == token else { return }
                self.failAndRecover("Capture error: \(error.localizedDescription)", token: token)
            }
        }
    }

    private static func configuration(interval: Int64) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = 2; config.height = 2
        config.queueDepth = 3
        config.minimumFrameInterval = CMTime(value: interval, timescale: 1)
        config.showsCursor = false; config.capturesAudio = false
        config.captureMicrophone = false
        config.includeChildWindows = false
        config.ignoreShadowsSingleWindow = true
        return config
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of outputType: SCStreamOutputType) {
        let info = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]]
        guard outputType == .screen, sampleBuffer.isValid,
              (info?.first?[.status] as? NSNumber)?.intValue == SCFrameStatus.complete.rawValue,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        // Only dimensions and counts leave this callback. No image is read, saved or displayed.
        Task { @MainActor [weak self] in
            guard let self, self.stream === stream else { return }
            self.completeFrames += 1; self.deliveredSize = size; self.lastFrameTime = CACurrentMediaTime()
            self.parkAfterFirstFrame()
        }
    }

    private func parkAfterFirstFrame() {
        guard !starting, !parking, completeFrames > 0, let current = stream else { return }
        parking = true
        let token = generation
        let previous = operation
        operation = Task { [weak self] in
            await previous?.value
            guard let self, self.generation == token, self.stream === current else { return }
            do {
                try await current.updateConfiguration(Self.configuration(interval: 3600))
                guard self.generation == token, self.stream === current else { return }
                self.firstFrameDeadline?.cancel(); self.firstFrameDeadline = nil
                self.isParked = true
                self.status = "Own-window capture parked: 2 × 2, one frame/hour requested"
                // An accepted update is not proof of zero WindowServer work. Check counters.
            } catch {
                guard self.generation == token else { return }
                self.failAndRecover("Could not park capture: \(error.localizedDescription)", token: token)
            }
        }
    }

    private func failAndRecover(_ message: String, token: Int) {
        guard generation == token else { return }
        generation += 1
        let recoveryToken = generation
        firstFrameDeadline?.cancel(); firstFrameDeadline = nil
        let old = stream
        stream = nil; isParked = false // Reject old frames immediately.
        status = message
        let previous = operation
        operation = Task { [weak self] in
            await previous?.value // Never race a stop against an in-flight start/update.
            if let old { try? await old.stopCapture() }
            guard let self, self.generation == recoveryToken else { return }
            self.scheduleRecovery(token: recoveryToken)
        }
    }

    private func scheduleRecovery(token: Int) {
        firstFrameDeadline?.cancel(); firstFrameDeadline = nil
        guard generation == token, shouldRun, retryCount < 2 else { return }
        retryCount += 1
        let delay = UInt64(retryCount) * 1_000_000_000
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard let self, self.generation == token, self.shouldRun else { return }
            self.refresh()
        }
    }

    private func stopCurrent() async {
        let old = stream
        stream = nil; isParked = false
        if let old {
            do { try await old.stopCapture() }
            catch { NSLog("NativeGlassSession stop: %@", error.localizedDescription) }
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.stream === stream else { return }
            self.failAndRecover("Capture interrupted: \(error.localizedDescription)", token: self.generation)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        workspaceNotifications.removeObserver(self)
        retryTask?.cancel(); firstFrameDeadline?.cancel()
        let old = stream
        Task { try? await old?.stopCapture() }
    }
}
