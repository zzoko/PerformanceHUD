import AppKit

/// Metadata only: no capture, Accessibility access, helper, or target injection.
@MainActor
final class HUDMiscMonitor {
    var onUpdate: ((HUDMiscSample) -> Void)?
    private var options = HUDMiscOptions()
    private var pid: pid_t?
    private var processName: String?
    private var resolution: HUDResolution?
    private var refreshRate: HUDRefreshRate?
    private var gameMode: Bool?
    private let gameModeMonitor = GameModeMonitor()
    private var thermal: String?
    private var sample = HUDMiscSample()
    private var displayTimer: Timer?
    private var thermalObserver: NSObjectProtocol?

    init() {
        gameModeMonitor.onUpdate = { [weak self] value in
            guard let self else { return }
            gameMode = value
            publish()
        }
    }

    func setTarget(_ app: NSRunningApplication) {
        if pid != app.processIdentifier { resolution = nil; refreshRate = nil }
        pid = app.processIdentifier
        processName = app.localizedName ?? app.executableURL?.lastPathComponent
        if options.visibleReadings.contains(.refreshRate) { readDisplay() }
        publish()
    }

    func updateResolution(_ value: HUDResolution?) {
        resolution = value
        publish()
    }

    func configure(_ options: HUDMiscOptions) {
        guard self.options != options else { return }
        self.options = options
        displayTimer?.invalidate(); displayTimer = nil
        if let thermalObserver { NotificationCenter.default.removeObserver(thermalObserver) }
        thermalObserver = nil
        let visible = options.visibleReadings
        gameModeMonitor.configure(enabled: visible.contains(.gameMode))
        refreshRate = nil; thermal = nil
        if visible.contains(.refreshRate) {
            readDisplay()
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.readDisplay(); self?.publish() }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            displayTimer = timer
        }
        if visible.contains(.thermal) {
            readThermal() // Access the property before subscribing, as Foundation requires.
            thermalObserver = NotificationCenter.default.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.readThermal(); self?.publish() }
            }
        }
        publish()
    }

    func stop() { configure(HUDMiscOptions()) }

    private func readThermal() {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = nil
        }
    }

    private func readDisplay() {
        guard let pid else { refreshRate = nil; return }
        let screens = NSScreen.screens
        // CGWindowList's bounds/owner/layer metadata does not require capture
        // permission. Do not request window titles or any image content.
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let window = windows.first { info in
            (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid
                && (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
                && ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0
        }
        let bounds = (window?[kCGWindowBounds as String] as? [String: Any])
            .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
        let displayRects = screens.map { CGDisplayBounds(Self.displayID($0)) }
        let index = Self.displayIndex(window: bounds, screens: displayRects)
        guard let index else { refreshRate = nil; return }
        let screen = screens[index]
        refreshRate = HUDRefreshRate(modeRate: CGDisplayCopyDisplayMode(Self.displayID(screen))?.refreshRate ?? 0,
                                    minimumInterval: screen.minimumRefreshInterval,
                                    maximumInterval: screen.maximumRefreshInterval)
    }

    // Frontmost app's frontmost visible window, on the display covering most of
    // it. With several displays and no window metadata, report unavailable.
    static func displayIndex(window: CGRect?, screens: [CGRect]) -> Int? {
        guard let window, !window.isEmpty else { return screens.count == 1 ? 0 : nil }
        var best: Int?, largest: CGFloat = 0
        for (index, frame) in screens.enumerated() {
            let overlap = window.intersection(frame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > largest { largest = area; best = index }
        }
        return best
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private func publish() {
        let visible = options.visibleReadings
        let next = HUDMiscSample(process: visible.contains(.process) ? processName : nil,
                                 resolution: visible.contains(.resolution) ? resolution : nil,
                                 refreshRate: visible.contains(.refreshRate) ? refreshRate : nil,
                                 gameMode: visible.contains(.gameMode) ? gameMode : nil,
                                 thermal: visible.contains(.thermal) ? thermal : nil)
        guard next != sample else { return }
        sample = next
        onUpdate?(sample)
    }

    deinit {
        displayTimer?.invalidate()
        if let thermalObserver { NotificationCenter.default.removeObserver(thermalObserver) }
    }
}
