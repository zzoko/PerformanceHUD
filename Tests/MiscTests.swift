import AppKit
import Darwin

@main struct MiscTests {
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }

    @MainActor static func main() throws {
        _ = NSApplication.shared
        UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "off", "hud.background": "dark"],
                                                forName: UserDefaults.argumentDomain)
        func check(_ condition: Bool, _ message: String) { precondition(condition, message) }
        let suite = "PerformanceHUD.MiscTests." + UUID().uuidString
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        check(!HUDPreferences.miscOptions(in: store).enabled, "Misc must default off")
        check(HUDPreferences.miscOptions(in: store).readings.count == 5, "All five choices start selected")
        HUDPreferences.setMiscOptions(.init(enabled: true, readings: [.thermal]), in: store)
        check(HUDPreferences.miscOptions(in: store).visibleReadings == [.thermal], "Remember individual choice")
        HUDPreferences.setMiscOptions(.init(enabled: false, readings: []), in: store)
        check(HUDPreferences.miscOptions(in: store).readings.isEmpty, "An empty selection must survive relaunch")
        HUDPreferences.resetOptions(in: store)
        check(HUDPreferences.miscOptions(in: store) == HUDMiscOptions(), "Reset restores disabled default")
        check(!HUDAlignment.horizontal.allows(.misc), "Misc is vertical-only")
        for reading in HUDMiscReading.allCases {
            check(HUDMiscSample().text(for: reading).isEmpty, "Unavailable values stay blank")
        }
        check(HUDMiscSample(gameMode: true).text(for: .gameMode) == "on", "Enabled Game Mode")
        check(HUDMiscSample(gameMode: false).text(for: .gameMode) == "off", "Disabled Game Mode")
        testGameModeNotifications()

        check(HUDResolution(width: .infinity, height: 1080) == nil, "Reject invalid resolution")
        check(HUDResolution(width: -1, height: 1080) == nil, "Reject negative resolution")
        let resolution = HUDResolution(width: 3840, height: 2160)!
        let fixed = HUDRefreshRate(modeRate: 59.94, minimumInterval: 1/60, maximumInterval: 1/60)!
        let variable = HUDRefreshRate(modeRate: 0, minimumInterval: 1/120, maximumInterval: 1/48)!
        check(fixed.text == "59.94 Hz", "Keep fractional mode rates")
        check(variable.text == "48–120 Hz", "Label VRR as a range")
        check(HUDRefreshRate(modeRate: 0, minimumInterval: 0, maximumInterval: 0) == nil, "No invented zero-Hz reading")
        let displays = [CGRect(x: 0, y: 0, width: 1920, height: 1080), CGRect(x: 1920, y: 0, width: 1920, height: 1080)]
        check(HUDMiscMonitor.displayIndex(window: CGRect(x: 1800, y: 50, width: 800, height: 600), screens: displays) == 1,
              "Choose display covering most of the window")
        check(HUDMiscMonitor.displayIndex(window: nil, screens: displays) == nil, "Do not guess a display")

        func layer(width: Double, height: Double, fps: Double) -> [String: Any] {
            ["Configuration": ["Width (pixels)": width, "Height (pixels)": height],
             "Performance Stats": ["Presented Frame Stats": ["FPS": fps]]]
        }
        let json = try JSONSerialization.data(withJSONObject: ["PID": 123, "Layers": [
            layer(width: 320, height: 180, fps: 90), layer(width: 3840, height: 2160, fps: 60)]])
        let parser = MetalMetricsParser(pid: 123)
        check(parser.consume(json.prefix(20)).isEmpty, "Wait for complete streamed JSON")
        let result = parser.consume(json.dropFirst(20)).first!
        check(result.resolution == resolution && result.fps == 60, "FPS and resolution must use the same largest layer")
        check(MetalMetricsParser(pid: 124).consume(json).isEmpty, "Never attribute another process's resolution")

        let monitor = HUDMiscMonitor()
        var live = HUDMiscSample()
        monitor.onUpdate = { live = $0 }
        monitor.setTarget(NSRunningApplication.current)
        monitor.updateResolution(resolution)
        monitor.configure(.init(enabled: true))
        check(live.process != nil && live.resolution == resolution && live.thermal != nil, "Read native process/thermal metadata")
        print("LIVE: thermal=\(live.thermal ?? "unavailable"), refresh=\(live.refreshRate?.text ?? "unavailable"), gameMode=\(live.gameMode.map { $0 ? "On" : "Off" } ?? "unavailable")")
        monitor.updateResolution(nil)
        check(live.resolution == nil, "Clear unavailable resolution")
        monitor.stop()
        check(live == HUDMiscSample(), "Stop must clear every reading")
        let timer: Timer? = member(monitor, "displayTimer")
        check(timer == nil, "Disabled Misc must not poll displays")
        let gameReader: GameModeMonitor = member(monitor, "gameModeMonitor")
        check(!gameReader.isRunning, "Disabled Misc must unsubscribe from Game Mode")

        let disabled = HUDResourceOptions(enabled: false, temperature: false, totalUse: false, focusedApp: false)
        var selection = HUDLogSelection(fps: false, resources: [.gpu: disabled], package: .init(enabled: false),
            fans: .init(enabled: false), battery: .init(enabled: false, temperature: false, charge: false),
            deviceInfo: true, alignment: .vertical, misc: .init(enabled: true))
        check(selection.columns(fanSample: .noFans) == [.process, .resolutionWidth, .resolutionHeight,
            .refreshMinimum, .refreshMaximum, .gameMode, .thermal, .chip, .os], "CSV follows Misc/menu order")
        selection.alignment = .horizontal
        check(selection.columns(fanSample: .noFans).isEmpty, "Horizontal logs exclude Misc")
        selection.alignment = .vertical
        var snapshot = HUDLogSnapshot()
        snapshot.updateMisc(.init(process: "Test", resolution: resolution, refreshRate: variable, gameMode: true, thermal: "fair"))
        check(snapshot.values[.gameMode] == "1", "Game Mode has a numeric CSV column")
        check(snapshot.values[.resolutionWidth] == "3840" && snapshot.values[.refreshMaximum] == "120.00", "Numeric CSV columns")
        snapshot.updateMisc(HUDMiscSample())
        check(snapshot.values.isEmpty, "Unavailable metadata logs as blank, not dash or zero")
        selection.misc.enabled = false
        check(selection.columns(fanSample: .noFans) == [.chip, .os], "No hidden Misc columns")

        let menu = HUDMiscMenuView(options: .init())
        let choices: NSSegmentedControl = member(menu, "choices")
        let master: HUDResourceMasterButton = member(menu, "master")
        check(!choices.isEnabled && master.state == .off, "Category checkbox is off by default")
        var changed = HUDMiscOptions()
        menu.onChange = { changed = $0 }
        master.performClick(nil)
        choices.setSelected(false, forSegment: 1)
        _ = choices.sendAction(choices.action, to: choices.target)
        check(changed.enabled && changed.readings == [.process, .refreshRate, .gameMode, .thermal], "Buttons toggle independently")
        master.performClick(nil); master.performClick(nil)
        check(!choices.isSelected(forSegment: 1), "Master remembers individual readings")
        menu.update(alignment: .horizontal)
        check(!master.isEnabled && master.state == .off && !choices.isEnabled, "Horizontal forces Misc off")
        menu.update(alignment: .vertical)
        check(master.isEnabled && master.state == .on && choices.isEnabled, "Vertical restores Misc")
        check(!choices.isSelected(forSegment: 1) && choices.isSelected(forSegment: 3), "Layout switch remembers each choice")
        menu.layoutSubtreeIfNeeded()
        check(menu.bounds.contains(choices.frame), "All five buttons fit the menu")

        let hud = HUDWindowController()
        hud.setHUDEnabled(false)
        hud.setAutoHideMode(.off)
        let panel: HUDPanel = member(hud, "panel")
        let misc: HUDMiscView = member(hud, "miscView")
        let fields: [HUDMiscReading: (NSTextField, NSTextField)] = member(misc, "fields")
        for background in [HUDBackground.light, .dark] {
            misc.configure(options: .init(enabled: true), scale: .normal, background: background)
            for (title, value) in fields.values {
                check(title.textColor == HUDStyle.TextStyle.label.color(background: background), "Names keep Label style")
                check(value.textColor == HUDStyle.TextStyle.reading.color(background: background), "Values use Reading style")
                check(value.font == HUDStyle.readingFont(scale: .normal, highlighted: false), "Regular reading font")
                check(title.font?.pointSize == value.font?.pointSize, "Text size is unchanged")
            }
        }
        let container: NSView = member(hud, "container")
        let horizontal: HUDHorizontalView = member(hud, "horizontalView")
        let glass: NativeGlassHUDBackground = member(hud, "backgroundView")
        let surface: NSView = member(glass, "glass")
        surface.isHidden = true
        glass.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
        let sample = HUDMiscSample(process: "Metro Exodus", resolution: resolution, refreshRate: variable, gameMode: true, thermal: "nominal")
        for alignment in HUDAlignment.allCases {
            UserDefaults.standard.setVolatileDomain([
                "hud.enabled": false, "hud.autoHide.mode": "off", "hud.background": "dark",
                "hud.alignment": alignment.rawValue, "hud.metric.misc": true,
                "hud.misc.readings": HUDMiscReading.allCases.map(\.rawValue)
            ], forName: UserDefaults.argumentDomain)
            hud.setAlignment(alignment)
            check(HUDPreferences.visibleMetrics.contains(.misc) == (alignment == .vertical), "Effective preferences filter Misc by alignment")
            check(misc.isHidden == (alignment == .horizontal), "Layout switch immediately updates Misc visibility")
            for factor in [0.5, 1.0, 2.0] {
                hud.setHUDScale(HUDScale(rawValue: factor))
                let horizontalSize = panel.frame.size
                for mask in 0..<32 {
                    let selected = Set(HUDMiscReading.allCases.enumerated().compactMap {
                        (mask & (1 << $0.offset)) != 0 ? $0.element : nil
                    })
                    hud.setMiscOptions(.init(enabled: true, readings: selected))
                    hud.updateMisc(sample)
                    panel.contentView?.layoutSubtreeIfNeeded()
                    let original = panel.frame.size
                    hud.updateMisc(.init(process: String(repeating: "Very long process name ", count: 8),
                                         resolution: nil, refreshRate: nil, thermal: "critical"))
                    panel.contentView?.layoutSubtreeIfNeeded()
                    check(panel.frame.size == original, "Metadata must not resize HUD: \(alignment) \(factor) \(mask)")
                    check(misc.isHidden == (selected.isEmpty || alignment == .horizontal), "Horizontal or empty selection hides Misc")
                    if alignment == .horizontal {
                        check(panel.frame.size == horizontalSize, "Misc never changes horizontal geometry")
                    }
                    let host: NSView = alignment == .vertical ? misc : horizontal
                    for field in host.subviews.compactMap({ $0 as? NSTextField }) where !field.isHidden {
                        check(host.bounds.insetBy(dx: -3, dy: -1).contains(field.frame),
                              "Metadata label outside its row: \(field.stringValue) at \(factor): \(field.frame) / \(host.bounds)")
                        check(field.frame.height + 1 >= field.intrinsicContentSize.height, "Text height clips")
                        if field.stringValue == "critical" {
                            check(field.frame.width >= field.intrinsicContentSize.width, "Thermal value must fit in full")
                        }
                    }
                }
                hud.updateMisc(sample)
                if factor == 1, CommandLine.arguments.contains("--preview") {
                    panel.contentView?.layoutSubtreeIfNeeded()
                    let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds)!
                    container.cacheDisplay(in: container.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/phud-misc-\(alignment).png"))
                }
            }
        }
        var restoredPreferences = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        restoredPreferences["hud.alignment"] = HUDAlignment.vertical.rawValue
        UserDefaults.standard.setVolatileDomain(restoredPreferences, forName: UserDefaults.argumentDomain)
        hud.setAlignment(.vertical)
        check(!misc.isHidden && HUDPreferences.miscOptions.readings.count == 5, "Returning to Vertical restores saved Misc selection")
        hud.shutdown()
        if CommandLine.arguments.contains("--preview") {
            let window = NSWindow(contentRect: menu.bounds, styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = menu; window.isReleasedWhenClosed = false
            window.orderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            menu.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let bitmap = menu.bitmapImageRepForCachingDisplay(in: menu.bounds)!
            menu.cacheDisplay(in: menu.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/phud-misc-menu.png"))
            window.orderOut(nil)
        }
        print("PASS: Misc styles, blank values, preferences/reset, parser, display mapping, lifecycle, logging, vertical-only buttons, and 32 selections at 0.5/1/2× in both layouts")
    }

    // Exercise the real Darwin event API using a private test name. Never post
    // to, or write the state of, macOS's Game Mode notification.
    @MainActor static func testGameModeNotifications() {
        precondition(GameModeMonitor.enabledState(rawValue: 0) == false)
        precondition(GameModeMonitor.enabledState(rawValue: 1) == true)
        precondition(GameModeMonitor.enabledState(rawValue: 2) == false)
        precondition(GameModeMonitor.enabledState(rawValue: 3) == nil)
        typealias Register = @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<Int32>) -> UInt32
        typealias SetState = @convention(c) (Int32, UInt64) -> UInt32
        typealias Post = @convention(c) (UnsafePointer<CChar>) -> UInt32
        typealias Cancel = @convention(c) (Int32) -> UInt32
        let library = dlopen(nil, RTLD_LAZY)!
        defer { dlclose(library) }
        let register = unsafeBitCast(dlsym(library, "notify_register_check")!, to: Register.self)
        let setState = unsafeBitCast(dlsym(library, "notify_set_state")!, to: SetState.self)
        let post = unsafeBitCast(dlsym(library, "notify_post")!, to: Post.self)
        let cancel = unsafeBitCast(dlsym(library, "notify_cancel")!, to: Cancel.self)
        let name = "andrei.PerformanceHUD.tests.gameMode." + UUID().uuidString
        var publisher: Int32 = -1
        precondition(register(name, &publisher) == 0)
        defer { _ = cancel(publisher) }
        let observer = GameModeMonitor(notificationName: name)
        var updates: [Bool?] = []
        observer.onUpdate = { updates.append($0) }
        precondition(setState(publisher, 0) == 0)
        observer.configure(enabled: true)
        precondition(observer.isRunning && updates == [false], "Read initial state")
        for (raw, expected): (UInt64, Bool?) in [(1, true), (2, false), (99, nil), (0, false)] {
            let previous = updates.count
            precondition(setState(publisher, raw) == 0 && post(name) == 0)
            let deadline = Date().addingTimeInterval(1)
            while updates.count == previous && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            precondition(updates.count > previous && updates.last! == expected, "Deliver changed state")
        }
        // A queued callback from the old registration must not leak into a new one.
        precondition(setState(publisher, 1) == 0 && post(name) == 0)
        observer.stop()
        precondition(!observer.isRunning && updates.last! == nil, "Stop clears and cancels")
        precondition(setState(publisher, 2) == 0)
        observer.configure(enabled: true)
        precondition(updates.last! == false, "Restart reads current state")
        observer.stop()
        let stopped = updates.count
        precondition(setState(publisher, 1) == 0 && post(name) == 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(updates.count == stopped, "Stopped callbacks stay cancelled")
        print("PASS: Game Mode decoding, real event delivery, unknown states, stop/restart, and stale callback cancellation")
    }
}
