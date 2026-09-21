// PerformanceHUDGlassBackground.swift
// Standalone extraction of GlassTest mode 30. Add this ONE file to your macOS app target.
// Requires macOS 15+; no assets, packages, test menus or sample metrics.
//
// Integration:
//   let glass = PerformanceHUDGlassBackground(frame: hudBounds, style: .transparent)
//   container.addSubview(glass, positioned: .below, relativeTo: metricsView)
//   window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
//   // Keep 24 points of transparent window padding around the glass for its shadow.
//   // Once the window is visible:
//   glass.start()
//
// Lifecycle REQUIRED in the host: stop() before hiding/removing the HUD and on quit;
// start() after showing; refreshGeometry() after moving/resizing or changing screens/
// backing scale (including ancestor layout changes). Theme changes restart automatically.
// Detaching the view also stops capture. This component does not create/manage your window.
// Your metrics remain separate native views, with independent updates and sharp text.
//
// Screen-recording permission is required for the HOST APP, not the GlassTest grant.
// Keep a stable signing identity across builds. Captured frames stay in memory.
// Same crop (24pt blur padding), display resolution, max-rate request, full shader and
// CGImage/CALayer output as selected mode 30. Includes its measured capture overhead.
// No native window shadow, native glass, IOSurface output experiment or 1× reduction.

import AppKit
import ScreenCaptureKit
import Metal
import CoreVideo
import CoreMedia
import QuartzCore
import Darwin

nonisolated enum HUDGlassCaptureState: Equatable, Sendable {
    case off, starting, active, permissionRequired
    case failed(String)

    var needsAttention: Bool {
        switch self {
        case .permissionRequired, .failed: return true
        default: return false
        }
    }
    var description: String {
        switch self {
        case .off: return "Off"
        case .starting: return "Starting"
        case .active: return "Active"
        case .permissionRequired: return "Screen Recording permission needed"
        case .failed(let message): return "Failed: \(message)"
        }
    }
    static func failure(_ error: NSError) -> Self {
        error.domain == SCStreamErrorDomain && error.code == SCStreamError.Code.userDeclined.rawValue
            ? .permissionRequired : .failed(error.localizedDescription)
    }
}

nonisolated enum PerformanceHUDGlassStyle: Int, CaseIterable {
    case dark, light, transparent
    var title: String { ["Dark", "Light", "Transparent"][rawValue] }
}

nonisolated struct PerformanceHUDGlassAppearance {
    let theme: PerformanceHUDGlassStyle
    init(isDark: Bool) { theme = isDark ? .dark : .light }
    init(theme: PerformanceHUDGlassStyle) { self.theme = theme }
    var isDark: Bool { theme != .light }
    var tint: SIMD4<Float> {
        // Transparent favours scene colour and lens depth over text contrast.
        if theme == .transparent { return SIMD4(0.045, 0.065, 0.085, 0.16) }
        return isDark ? SIMD4(0.065, 0.073, 0.082, 0.48) : SIMD4(0.92, 0.935, 0.94, 0.68)
    }
    // Corner radius, blur sigma, saturation, style (0 dark, 1 light, 2 transparent). Units: points.
    var optics: SIMD4<Float> {
        if theme == .transparent { return SIMD4(10, 3.5, 1.04, 2) }
        return SIMD4(10, 7, isDark ? 0.88 : 0.78, isDark ? 0 : 1)
    }
    var cornerRadius: CGFloat { CGFloat(optics.x) }
    var textColor: NSColor { NSColor(white: isDark ? 0.96 : 0.10, alpha: 1) }
    var secondaryTextColor: NSColor { NSColor(white: isDark ? 0.76 : 0.31, alpha: 1) }
    var separatorColor: NSColor { NSColor(white: isDark ? 1 : 0, alpha: isDark ? 0.12 : 0.11) }

    // Native NSWindow shadow remains disabled. The known rounded path prevents sampling text
    // or recomputing a silhouette from changing HUD contents. Parent must not clip this layer.
    @MainActor func applyShadow(to view: NSView, enabled: Bool) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.masksToBounds = false
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = enabled ? (isDark ? 0.32 : 0.24) : 0
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: -2)
        layer.shadowPath = CGPath(roundedRect: view.bounds, cornerWidth: cornerRadius,
                                 cornerHeight: cornerRadius, transform: nil)
        CATransaction.commit()
    }
}


/// Attach behind your existing HUD labels. Call start only after the host window is visible.
@MainActor
final class PerformanceHUDGlassBackground: NSView {
    private let surface = HUDGlassSurfaceView(frame: .zero)
    private let capture = HUDGlassCaptureController()
    private var running = false
    private var systemAsleep = false
    private var screensAsleep = false
    private var recoveryTask: Task<Void, Never>?
    private var recoveryAttempts = 0
    private var suspended: Bool { systemAsleep || screensAsleep }
    private struct Geometry: Equatable {
        let rect: CGRect
        let screenFrame: CGRect
        let displayID: UInt32
        let scale: CGFloat
        let style: PerformanceHUDGlassStyle
    }
    private var lastGeometry: Geometry?
    private var geometryInvalidated = false
    var isShowingFallback: Bool { surface.isShowingFallback }
    var onFallbackChange: (() -> Void)?
    var style: PerformanceHUDGlassStyle {
        didSet { if oldValue != style { updateAppearance(); refreshGeometry() } }
    }
    // Compatibility: setting isDark explicitly selects Light/Dark, replacing Transparent.
    var isDark: Bool {
        get { style != .light }
        set { style = newValue ? .dark : .light }
    }
    var showsShadow = true { didSet { updateAppearance() } }
    var glassAppearance: PerformanceHUDGlassAppearance { PerformanceHUDGlassAppearance(theme: style) }
    var captureStatus: String { capture.state.description }
    var captureState: HUDGlassCaptureState { capture.state }
    var onCaptureStateChange: ((HUDGlassCaptureState) -> Void)?
    var capturedRegion: String { capture.regionDescription }

    convenience init(frame: NSRect, isDark: Bool = true) {
        self.init(frame: frame, style: isDark ? .dark : .light)
    }
    init(frame: NSRect, style: PerformanceHUDGlassStyle) {
        self.style = style
        super.init(frame: frame)
        capture.onStateChange = { [weak self] state in
            guard let self else { return }
            self.onCaptureStateChange?(state)
            switch state {
            case .active:
                self.cancelRecovery()
                self.recoveryAttempts = 0
            case .permissionRequired:
                self.cancelRecovery() // Never retry a denied permission automatically.
            case .failed, .off:
                self.scheduleRecovery()
            case .starting:
                break
            }
        }
        surface.onFallbackChange = { [weak self] in self?.onFallbackChange?() }
        wantsLayer = true
        surface.frame = bounds
        surface.autoresizingMask = [.width, .height]
        surface.wantsLayer = true
        surface.layer?.cornerRadius = glassAppearance.cornerRadius
        surface.layer?.masksToBounds = false // Shader already supplies rounded alpha.
        addSubview(surface)
        updateAppearance()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            center.addObserver(self, selector: #selector(captureWillSleep(_:)), name: name, object: nil)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(self, selector: #selector(captureDidWake(_:)), name: name, object: nil)
        }
    }
    deinit {
        recoveryTask?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:isDark:)") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
    }
    override func layout() {
        super.layout()
        updateAppearance()
    }
    private func updateAppearance() {
        glassAppearance.applyShadow(to: self, enabled: showsShadow)
        surface.layer?.backgroundColor = NSColor.clear.cgColor
    }
    func start() {
        guard !running, let window, window.isVisible else { return }
        window.hasShadow = false
        running = true
        recoveryAttempts = 0
        refreshGeometry()
        if lastGeometry == nil { scheduleRecovery() }
    }
    func stop() {
        recoveryTask?.cancel()
        recoveryTask = nil
        guard running else { return }
        running = false
        lastGeometry = nil
        geometryInvalidated = false
        capture.stop()
        surface.showFallback()
        updateAppearance()
    }
    func retry() {
        guard running else { start(); return }
        cancelRecovery()
        recoveryAttempts = 0
        lastGeometry = nil
        refreshGeometry()
        if lastGeometry == nil { scheduleRecovery() }
    }

    private func cancelRecovery() {
        recoveryTask?.cancel()
        recoveryTask = nil
    }

    private func scheduleRecovery(forceRestart: Bool = false) {
        // Standalone launches can precede WindowServer/ScreenCaptureKit discovery
        // of our window. Retry without requiring a move, toggle or wake event.
        let delays = [500, 1500, 3000]
        guard recoveryTask == nil, recoveryAttempts < delays.count,
              running, !suspended, window?.isVisible == true, !isHidden,
              capture.state != .permissionRequired else { return }
        let delay = delays[recoveryAttempts]
        recoveryAttempts += 1
        recoveryTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.recoveryTask = nil
            guard self.running, !self.suspended, self.window?.isVisible == true,
                  !self.isHidden, self.capture.state != .permissionRequired else { return }
            if !forceRestart {
                // A geometry change may already have started another attempt.
                // Its own failure or first-frame timeout will request recovery.
                if self.capture.state == .active || self.capture.state == .starting { return }
            }
            self.lastGeometry = nil
            self.refreshGeometry()
            if self.lastGeometry == nil { self.scheduleRecovery() }
        }
    }
    @objc private func captureWillSleep(_ notification: Notification) {
        let wasSuspended = suspended
        if notification.name == NSWorkspace.willSleepNotification { systemAsleep = true }
        if notification.name == NSWorkspace.screensDidSleepNotification { screensAsleep = true }
        recoveryTask?.cancel()
        recoveryTask = nil
        guard running, !wasSuspended else { return }
        lastGeometry = nil
        geometryInvalidated = false
        // Keep the user's enabled setting, but retire the stream that sleep will invalidate.
        // Preserve a permission denial so waking never repeatedly prompts for access.
        if capture.state != .permissionRequired { capture.stop() }
        surface.showFallback()
    }

    @objc private func captureDidWake(_ notification: Notification) {
        if notification.name == NSWorkspace.didWakeNotification { systemAsleep = false }
        if notification.name == NSWorkspace.screensDidWakeNotification { screensAsleep = false }
        guard running, !suspended, capture.state != .permissionRequired else { return }
        cancelRecovery()
        recoveryAttempts = 0
        // A wake/unlock can invalidate a stream even without a stop callback.
        scheduleRecovery(forceRestart: true)
    }

    private func currentGeometry() -> Geometry? {
        guard running, !suspended, let window, window.isVisible, !isHidden,
              let screen = window.screen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return Geometry(rect: window.convertToScreen(convert(bounds, to: nil)),
                        screenFrame: screen.frame, displayID: number.uint32Value,
                        scale: screen.backingScaleFactor, style: style)
    }

    // Stop stale frames immediately; the host still coalesces expensive stream restarts.
    func prepareForGeometryChange() {
        guard let geometry = currentGeometry(), geometry != lastGeometry, !geometryInvalidated else { return }
        geometryInvalidated = true
        surface.showFallback()
        capture.invalidateFrames()
    }

    /// Host calls after the overlay's screen position/size/scale changes; not per metric update.
    func refreshGeometry() {
        guard let geometry = currentGeometry() else { return }
        guard geometry != lastGeometry || geometryInvalidated else { return }
        lastGeometry = geometry
        geometryInvalidated = false
        surface.frame = bounds
        surface.showFallback()
        updateAppearance()
        capture.configure(view: surface, appearance: glassAppearance)
    }
}

@MainActor
private final class HUDGlassSurfaceView: NSView {
    private let checkerboard = HUDCaptureCheckerboardView()
    private(set) var isShowingFallback = true
    var onFallbackChange: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        checkerboard.wantsLayer = true
        checkerboard.frame = bounds
        checkerboard.autoresizingMask = [.width, .height]
        addSubview(checkerboard)
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func showFallback() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.contents = nil
        checkerboard.isHidden = false
        CATransaction.commit()
        let changed = !isShowingFallback
        isShowingFallback = true
        if changed { onFallbackChange?() }
    }

    func show(image: CGImage, scale: CGFloat) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.contents = image
        layer?.contentsScale = scale
        checkerboard.isHidden = true
        CATransaction.commit()
        let changed = isShowingFallback
        isShowingFallback = false
        if changed { onFallbackChange?() }
    }
}

@MainActor
private final class HUDCaptureCheckerboardView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).addClip()
        NSColor(white: 0.07, alpha: 1).setFill()
        bounds.fill()
        NSColor(white: 0.19, alpha: 1).setFill()
        let cell: CGFloat = 8
        for row in 0..<Int(ceil(bounds.height / cell)) {
            for column in 0..<Int(ceil(bounds.width / cell)) where (row + column).isMultiple(of: 2) {
                NSRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell).fill()
            }
        }
    }
}

// Crop geometry is in display-local top-left points; AppKit screen coordinates are bottom-left.
private struct HUDGlassCaptureGeometry {
    let source: CGRect
    let offset: CGPoint
    let size: CGSize
    let scale: CGFloat
    init(square: CGRect, screen: CGRect, scale: CGFloat) {
        let local = CGRect(x: square.minX-screen.minX, y: screen.maxY-square.maxY,
                           width: square.width, height: square.height)
        source = local.insetBy(dx: -24, dy: -24).intersection(CGRect(origin: .zero, size: screen.size))
        offset = CGPoint(x: local.minX-source.minX, y: local.minY-source.minY)
        size = square.size
        self.scale = scale
    }
}

@MainActor private final class HUDGlassCaptureController {
    private var revision = 0
    private var transition: Task<Void, Never>?
    private var firstFrameTask: Task<Void, Never>?
    private var stream: SCStream?
    private var feed: HUDGlassCaptureFeed?
    var onStateChange: ((HUDGlassCaptureState) -> Void)?
    private(set) var state: HUDGlassCaptureState = .off {
        didSet { if oldValue != state { onStateChange?(state) } }
    }
    private(set) var frames = 0
    private var measurementStart: CFTimeInterval = 0
    private var processingTotal: Double = 0
    private var sourceAgeTotal: Double = 0
    private var sourceAgeCount = 0
    private(set) var receivedFrames = 0
    var timingSummary: String {
        let elapsed = max(0.001, CACurrentMediaTime() - measurementStart)
        guard frames > 1 else { return "Waiting for timing samples" }
        let rate = Double(frames-1)/elapsed
        let age = sourceAgeCount > 0 ? String(format: "%.1f ms", sourceAgeTotal/Double(sourceAgeCount)) : "unavailable"
        return String(format: "%.1f processed fps; %.2f ms worker time (includes GPU/drawable waits); ", rate, processingTotal/Double(frames)) + "received: \(receivedFrames); metadata age: \(age) (\(sourceAgeCount) valid samples, not screen latency)"
    }
    private(set) var regionDescription = "none"

    // All start/stop operations are serialized. Old frames are rejected immediately by revision.
    func stop() { configure(view: nil) }
    func invalidateFrames() {
        firstFrameTask?.cancel()
        firstFrameTask = nil
        revision += 1
        feed?.deactivate()
        if !state.needsAttention { state = .starting }
    }
    func configure(view: NSView?, appearance: PerformanceHUDGlassAppearance = PerformanceHUDGlassAppearance(isDark: true)) {
        firstFrameTask?.cancel()
        firstFrameTask = nil
        revision += 1
        let ticket = revision
        feed?.deactivate()
        state = view == nil ? .off : .starting
        frames = 0; receivedFrames = 0; processingTotal = 0; sourceAgeTotal = 0; sourceAgeCount = 0; measurementStart = CACurrentMediaTime()
        let previous = transition
        transition = Task { [weak self, weak view] in
            await previous?.value
            guard let self else { return }
            if let old = self.stream {
                // An interrupted/sleeping stream may already be stopped. Cleanup failure
                // must not prevent creating its replacement; stale callbacks are invalidated.
                try? await old.stopCapture()
            }
            self.stream = nil; self.feed = nil
            guard self.revision == ticket else { return }
            guard let view, let window = view.window, window.isVisible,
                  let screen = window.screen,
                  let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                self.state = .off; self.regionDescription = "none"; return
            }
            self.state = .starting
            do {
                // Starting this component can prompt for screen-recording permission.
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard self.revision == ticket else { return }
                guard let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else {
                    throw self.failure("The overlay display is not available for capture.")
                }
                // Exclude the host app by bundle ID and PID, avoiding capture feedback.
                let excluded = content.applications.filter {
                    $0.processID == ProcessInfo.processInfo.processIdentifier || $0.bundleIdentifier == Bundle.main.bundleIdentifier
                }
                guard !excluded.isEmpty else { throw self.failure("Couldn't exclude the host app from capture.") }
                let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
                let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
                let geometry = HUDGlassCaptureGeometry(square: rect, screen: screen.frame, scale: screen.backingScaleFactor)
                guard !geometry.source.isEmpty else { throw self.failure("Capture region is outside the display.") }
                let config = SCStreamConfiguration()
                config.sourceRect = geometry.source
                config.width = max(1, Int((geometry.source.width*geometry.scale).rounded()))
                config.height = max(1, Int((geometry.source.height*geometry.scale).rounded()))
                config.minimumFrameInterval = .zero // Selected mode 30: maximum supported delivery rate.
                config.queueDepth = 3
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.colorSpaceName = CGColorSpace.sRGB
                config.showsCursor = false
                config.capturesAudio = false
                config.captureMicrophone = false
                let processor = try HUDGlassRenderer(geometry: geometry, glass: true, appearance: appearance)
                let feed = HUDGlassCaptureFeed(processor: processor)
                feed.onFrame = { [weak self, weak view] image, milliseconds, age, received in
                    guard let self, self.revision == ticket else { return }
                    if self.frames == 0 { self.measurementStart = CACurrentMediaTime() }
                    self.frames += 1
                    self.receivedFrames = received
                    self.processingTotal += milliseconds
                    if let age { self.sourceAgeTotal += age; self.sourceAgeCount += 1 }
                    if let image, let view {
                        (view as? HUDGlassSurfaceView)?.show(image: image, scale: geometry.scale)
                        self.firstFrameTask?.cancel()
                        self.firstFrameTask = nil
                        self.state = .active
                    }
                }
                feed.onError = { [weak self, weak view] error in
                    guard let self, self.revision == ticket else { return }
                    self.fail(error, view: view, appearance: appearance)
                }
                let stream = SCStream(filter: filter, configuration: config, delegate: feed)
                try stream.addStreamOutput(feed, type: .screen, sampleHandlerQueue: feed.deliveryQueue)
                self.feed = feed; self.stream = stream
                self.regionDescription = "\(config.width)×\(config.height) px, crop \(geometry.source), excluded host app"
                try await stream.startCapture()
                // Keep Starting until the first complete frame arrives. Start
                // this deadline only after the permission/start request returns.
                guard self.revision == ticket, self.state == .starting else { return }
                self.firstFrameTask = Task { [weak self, weak view] in
                    do { try await Task.sleep(for: .seconds(4)) } catch { return }
                    guard !Task.isCancelled, let self, self.revision == ticket,
                          self.state == .starting else { return }
                    self.fail(self.failure("Screen capture started but did not deliver a frame."),
                              view: view, appearance: appearance)
                }
            } catch {
                guard self.revision == ticket else { return }
                self.fail(error as NSError, view: view, appearance: appearance)
            }
        }
    }
    private func fail(_ error: NSError, view: NSView?, appearance: PerformanceHUDGlassAppearance) {
        firstFrameTask?.cancel()
        firstFrameTask = nil
        revision += 1 // Reject already queued frames from this failed stream.
        feed?.deactivate()
        let failedStream = stream
        stream = nil; feed = nil
        state = view == nil ? .off : .failure(error)
        if let view { Self.showFallback(in: view, appearance: appearance) }
        // Finish cleanup before any explicit retry, without erasing the error state.
        let previous = transition
        transition = Task {
            await previous?.value
            if let failedStream { try? await failedStream.stopCapture() }
        }
    }
    private func failure(_ message: String) -> NSError {
        NSError(domain: "HUDGlass.Capture", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    static func showFallback(in view: NSView, appearance: PerformanceHUDGlassAppearance) {
        (view as? HUDGlassSurfaceView)?.showFallback()
        // The host menu explains persistent failures; the checkerboard also signals waiting.
    }
}

// One current render + one replaceable newest frame. Never process an accumulating FIFO.
private final class HUDGlassCaptureFeed: NSObject, SCStreamOutput, SCStreamDelegate {
    struct Frame { let buffer: CVPixelBuffer; let displayTicks: UInt64? }
    let deliveryQueue = DispatchQueue(label: "HUDGlass.capture.delivery")
    private let worker = DispatchQueue(label: "HUDGlass.capture.render", qos: .userInteractive)
    private let lock = NSLock()
    private var active = true
    private var busy = false
    private var pending: Frame?
    private var received = 0
    let processor: HUDGlassRenderer?
    var onFrame: (@MainActor (CGImage?, Double, Double?, Int) -> Void)?
    var onError: (@MainActor (NSError) -> Void)?
    init(processor: HUDGlassRenderer?) { self.processor = processor }
    func deactivate() { lock.lock(); active = false; pending = nil; lock.unlock() }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.onError?(error as NSError) }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, raw == SCFrameStatus.complete.rawValue,
              let buffer = sampleBuffer.imageBuffer else { return }
        let frame = Frame(buffer: buffer, displayTicks: (attachments.first?[.displayTime] as? NSNumber)?.uint64Value)
        lock.lock()
        guard active else { lock.unlock(); return }
        received += 1
        if busy { pending = frame; lock.unlock(); return }
        busy = true; lock.unlock()
        process(frame)
    }
    private func process(_ frame: Frame) {
        worker.async {
            self.lock.lock(); let active = self.active; self.lock.unlock()
            guard active else { return }
            let start = CACurrentMediaTime()
            let result = Result { try self.processor?.render(buffer: frame.buffer) }
            let milliseconds = (CACurrentMediaTime()-start)*1000
            DispatchQueue.main.async {
                self.lock.lock()
                let active = self.active; let received = self.received
                let next = self.pending; self.pending = nil
                if next == nil { self.busy = false }
                self.lock.unlock()
                guard active else { return }
                var age: Double?
                if let ticks = frame.displayTicks {
                    let now = mach_absolute_time()
                    if now >= ticks {
                        var base = mach_timebase_info_data_t()
                        mach_timebase_info(&base)
                        age = Double(now-ticks)*Double(base.numer)/Double(base.denom)/1_000_000
                    }
                }
                switch result {
                case .success(let image): self.onFrame?(image, milliseconds, age, received)
                case .failure(let error): self.onError?(error as NSError)
                }
                if let next { self.process(next) }
            }
        }
    }
}

private final class HUDGlassRenderer {
    struct Params {
        var sourceSize: SIMD2<Float>
        var outputSize: SIMD2<Float>
        var offset: SIMD2<Float>
        var scale: Float
        var glass: Float
        var tint: SIMD4<Float>
        var optics: SIMD4<Float>
    }
    let device: MTLDevice
    let queue: MTLCommandQueue
    let blur: MTLComputePipelineState
    let composite: MTLComputePipelineState
    var cache: CVMetalTextureCache!
    let geometry: HUDGlassCaptureGeometry
    let glass: Bool
    let appearance: PerformanceHUDGlassAppearance
    private var scratchA: MTLTexture?
    private var scratchB: MTLTexture?
    private var output: MTLTexture?
    init(geometry: HUDGlassCaptureGeometry, glass: Bool, appearance: PerformanceHUDGlassAppearance = PerformanceHUDGlassAppearance(isDark: true)) throws {
        self.geometry = geometry; self.glass = glass; self.appearance = appearance
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw NSError(domain: "Metal unavailable", code: 1)
        }
        self.device = device; self.queue = queue
        let library = try device.makeLibrary(source: Self.source, options: nil)
        blur = try device.makeComputePipelineState(function: library.makeFunction(name: "blurPass")!)
        composite = try device.makeComputePipelineState(function: library.makeFunction(name: "compose")!)
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess else {
            throw NSError(domain: "Texture cache unavailable", code: 2)
        }
    }
    private func texture(_ width: Int, _ height: Int) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]; d.storageMode = .shared
        guard let t = device.makeTexture(descriptor: d) else { throw NSError(domain: "Texture allocation failed", code: 3) }
        return t
    }
    func render(buffer: CVPixelBuffer) throws -> CGImage? {
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let ow = max(1, Int((geometry.size.width*geometry.scale).rounded()))
        let oh = max(1, Int((geometry.size.height*geometry.scale).rounded()))
        var reference: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, .bgra8Unorm, w, h, 0, &reference) == kCVReturnSuccess,
              let reference, let input = CVMetalTextureGetTexture(reference) else { throw NSError(domain: "Capture texture import failed", code: 4) }
        if output == nil { output = try texture(ow, oh) }
        let target = output!
        if glass && (scratchA?.width != w || scratchA?.height != h) {
            scratchA = try texture(w, h); scratchB = try texture(w, h)
        }
        guard let command = queue.makeCommandBuffer() else { throw NSError(domain: "Command allocation failed", code: 5) }
        var params = Params(sourceSize: SIMD2(Float(w), Float(h)), outputSize: SIMD2(Float(ow), Float(oh)),
                            offset: SIMD2(Float(geometry.offset.x*geometry.scale), Float(geometry.offset.y*geometry.scale)),
                            scale: Float(geometry.scale), glass: glass ? 1 : 0, tint: appearance.tint, optics: appearance.optics)
        func encode(_ pipeline: MTLComputePipelineState, input: MTLTexture, target: MTLTexture, direction: SIMD2<Float>) throws {
            guard let encoder = command.makeComputeCommandEncoder() else { throw NSError(domain: "Encoder allocation failed", code: 6) }
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(input, index: 0); encoder.setTexture(target, index: 1)
            encoder.setBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
            var direction = direction
            encoder.setBytes(&direction, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            encoder.dispatchThreads(MTLSize(width: target.width, height: target.height, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: pipeline.threadExecutionWidth, height: 4, depth: 1))
            encoder.endEncoding()
        }
        if glass {
            try encode(blur, input: input, target: scratchA!, direction: SIMD2(1,0))
            try encode(blur, input: scratchA!, target: scratchB!, direction: SIMD2(0,1))
        }
        try encode(composite, input: glass ? scratchB! : input, target: target, direction: .zero)
        command.commit(); command.waitUntilCompleted() // Worker queue, never the app's main thread.
        withExtendedLifetime(reference) {}
        if let error = command.error { throw error }
        var bytes = [UInt8](repeating: 0, count: ow*oh*4)
        bytes.withUnsafeMutableBytes { output!.getBytes($0.baseAddress!, bytesPerRow: ow*4, from: MTLRegionMake2D(0,0,ow,oh), mipmapLevel: 0) }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: ow, height: oh, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: ow*4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }
    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct Params { float2 sourceSize; float2 outputSize; float2 offset; float scale; float glass; float4 tint; float4 optics; };
    constexpr sampler linearSample(coord::normalized, address::clamp_to_edge, filter::linear);
    kernel void blurPass(texture2d<float, access::sample> input [[texture(0)]], texture2d<float, access::write> out [[texture(1)]],
                         constant Params& p [[buffer(0)]], constant float2& direction [[buffer(1)]], uint2 id [[thread_position_in_grid]]) {
        if (id.x >= out.get_width() || id.y >= out.get_height()) return;
        float sigma = p.optics.y*p.scale;
        float4 sum = 0; float weights = 0;
        for (int i=-16; i<=16; i++) {
            float x = float(i)/16.0*3.0;
            float weight = exp(-0.5*x*x);
            sum += input.sample(linearSample,(float2(id)+0.5+direction*x*sigma)/p.sourceSize)*weight;
            weights += weight;
        }
        out.write(sum/weights,id);
    }
    float sdf(float2 v, float2 halfSize, float r) {
        float2 q=abs(v)-halfSize+r;
        return length(max(q,0.0))+min(max(q.x,q.y),0.0)-r;
    }
    kernel void compose(texture2d<float, access::sample> input [[texture(0)]], texture2d<float, access::write> out [[texture(1)]],
                        constant Params& p [[buffer(0)]], uint2 id [[thread_position_in_grid]]) {
        if(id.x>=out.get_width() || id.y>=out.get_height()) return;
        float2 pixel=float2(id)+0.5;
        float2 local=(pixel-p.outputSize*0.5)/p.scale;
        float2 halfSize=p.outputSize*0.5/p.scale-0.5;
        float radius=min(p.optics.x,min(halfSize.x,halfSize.y)*0.9);
        float d=sdf(local,halfSize,radius);
        float alpha=1.0-smoothstep(-0.6/p.scale,0.6/p.scale,d);
        if(alpha<=0) { out.write(float4(0),id); return; }
        float depth=max(0.0,-d);
        float2 n=normalize(float2(sdf(local+float2(0.1,0),halfSize,radius)-sdf(local-float2(0.1,0),halfSize,radius),
                                 sdf(local+float2(0,0.1),halfSize,radius)-sdf(local-float2(0,0.1),halfSize,radius))+0.00001);
        bool transparentStyle=p.optics.w>1.5;
        float edge=exp(-depth/(transparentStyle ? 6.0 : 4.5));
        float2 warped=pixel;
        if(p.glass>0) warped=p.outputSize*0.5+(pixel-p.outputSize*0.5)*(transparentStyle ? 0.975 : 0.985)
            +n*edge*(transparentStyle ? 6.0 : 4.0)*p.scale;
        float3 color=input.sample(linearSample,(p.offset+warped)/p.sourceSize).rgb;
        if(p.glass>0) {
            float luminance=dot(color,float3(0.2126,0.7152,0.0722));
            // Retain scene color while compressing contrast for stable text legibility.
            // This tint applies to already captured/blurred pixels; it is not transparency
            // over the live scene (which would reveal sharp details beneath the text).
            color=mix(float3(luminance),color,p.optics.z);
            color=mix(color,p.tint.rgb,p.tint.a);
            float lighting=dot(n,normalize(float2(-0.6,-0.8)));
            float rim=exp(-pow((depth-0.7)/0.55,2.0));
            float lightStyle=transparentStyle ? 0.0 : p.optics.w;
            color=mix(color,float3(1.0),rim*(0.08+0.16*max(lighting,0.0)+lightStyle*0.09));
            // Thin neutral boundary plus inner shading, quieter than a thick luminous bevel.
            float boundary=exp(-pow(depth/0.35,2.0));
            color*=1.0-boundary*(0.08+lightStyle*0.08);
            color-=edge*(0.012+lightStyle*0.006);
            if(transparentStyle) {
                // Broader inner reflection and a bright directional lip; no added render passes.
                float reflection=exp(-depth/2.4)*pow(max(lighting,0.0),2.0);
                color=mix(color,float3(0.90,0.96,1.0),reflection*0.22);
                color=mix(color,float3(1.0),rim*0.12);
                color-=edge*max(-lighting,0.0)*0.045;
            }
        }
        // Opaque captured interior is essential: alpha blending here would reintroduce sharp game details.
        out.write(float4(clamp(color,0.0,1.0)*alpha,alpha),id);
    }
    """
}
