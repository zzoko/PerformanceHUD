import AppKit

@main struct LoggingTests {
    @MainActor static func main() throws {
        func check(_ condition: Bool, _ message: String = "Logging assertion failed", file: StaticString = #file, line: UInt = #line) {
            precondition(condition, message, file: file, line: line)
        }
        _ = NSApplication.shared
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("PerformanceHUD-logging-tests-" + UUID().uuidString)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let recovery = root.appendingPathComponent("Recovery")
        let desktop = root.appendingPathComponent("Desktop")
        try files.createDirectory(at: desktop, withIntermediateDirectories: true)
        let disabled = HUDResourceOptions(enabled: false, temperature: false, totalUse: false, focusedApp: false)
        var selection = HUDLogSelection(fps: false,
            resources: Dictionary(uniqueKeysWithValues: HUDResourceGroup.allCases.map { ($0, disabled) }),
            package: .init(enabled: false), fans: .init(enabled: false),
            battery: .init(enabled: false, temperature: false, charge: false),
            deviceInfo: false, alignment: .vertical)
        check(selection.columns(fanSample: .noFans).isEmpty)
        selection.fps = true
        selection.resources[.gpu] = .init(enabled: true, temperature: true, totalUse: true, focusedApp: true, power: true)
        selection.resources[.cpu] = .init(enabled: true, temperature: true, totalUse: true, focusedApp: false, power: true)
        selection.resources[.ane] = .init(enabled: true, temperature: false, totalUse: false, focusedApp: false, power: true)
        selection.package.enabled = true
        selection.resources[.ram] = .init(enabled: true, temperature: false, totalUse: true, focusedApp: true, details: true)
        selection.fans = .init(enabled: true, usage: true, mode: .both, average: false)
        selection.battery = .init(enabled: true, temperature: true, charge: true)
        selection.deviceInfo = true
        let fans = FanSample(status: .ready, fans: [.init(id: 1, rpm: 4000, maximumRPM: 8000), .init(id: 0, rpm: 0, maximumRPM: 6000)])
        let expected: [HUDLogColumn] = [.fps, .gpuPower, .gpuTemperature, .gpuUsage, .gpuAppUsage,
            .cpuPower, .cpuTemperature, .cpuUsage, .anePower, .socPower,
            .memoryPhysical, .memorySwap, .memoryPressure, .memoryAppPhysical, .memoryUsage, .memoryAppUsage,
            .fanUsage(0), .fanRPM(0), .fanUsage(1), .fanRPM(1), .powerSource,
            .batteryCharge, .lowPowerMode, .batteryTemperature, .chip, .os]
        check(selection.columns(fanSample: fans) == expected, "Columns must follow menu order with individual fans sorted")
        selection.resources[.gpu]?.enabled = false
        selection.resources[.ram]?.setUsagePresentation(visible: false, highlighted: false)
        selection.fans.mode = .rpm
        selection.fans.average = true
        selection.alignment = .horizontal
        selection.battery.charge = false
        selection.battery.temperature = false
        let changed = selection.columns(fanSample: fans)
        check(!changed.contains(.gpuPower) && !changed.contains(.gpuUsage))
        check(changed.contains(.memoryPhysical) && changed.contains(.memoryAppPhysical))
        check(!changed.contains(.memoryUsage) && !changed.contains(.memoryAppUsage))
        check(changed.contains(.fanAverageRPM) && !changed.contains(.fanAverageUsage))
        check(changed.contains(.powerSource) && !changed.contains(.batteryCharge) && !changed.contains(.chip))
        selection.resources[.ram]?.selectUsageMode(.app)
        check(!selection.columns(fanSample: fans).contains(.memoryPressure))
        let oneFan = FanSample(status: .ready, fans: [fans.fans[0]])
        check(selection.columns(fanSample: oneFan).contains(.fanRPM(1)))
        check(!selection.columns(fanSample: oneFan).contains(.fanAverageRPM))
        check(!selection.columns(fanSample: .noFans).contains(where: \.isFan))

        var snapshot = HUDLogSnapshot()
        snapshot.set(.fps, 120.5)
        snapshot.updatePower(.init(cpu: 0, gpu: 5.126, package: 6, ane: nil))
        snapshot.updateMemory(.init(percentage: 51.25, usedBytes: 2_147_483_648, swapUsedBytes: 0), app: false)
        snapshot.updateMemory(.init(percentage: 20, usedBytes: 1_073_741_824), app: true)
        snapshot.updateFans(fans)
        snapshot.updateBattery(.init(percentage: 95, source: .powerAdapter, temperature: nil))
        check(snapshot.values[.memoryPhysical] == "2.00" && snapshot.values[.memoryAppPhysical] == "1.00")
        check(snapshot.values[.memorySwap] == "0.00")
        check(snapshot.values[.fanRPM(0)] == "0" && snapshot.values[.fanUsage(1)] == "50.0")
        check(snapshot.values[.fanAverageRPM] == "2000" && snapshot.values[.fanAverageUsage] == "25.0")
        check(snapshot.values[.batteryTemperature] == nil && snapshot.values[.anePower] == nil)
        snapshot.updateFans(.unavailable)
        check(!snapshot.values.keys.contains(where: \.isFan), "Read failures cannot keep stale fan readings")
        snapshot.set(.cpuUsage, .nan); snapshot.set(.gpuUsage, .infinity)
        check(snapshot.values[.cpuUsage] == nil && snapshot.values[.gpuUsage] == nil)
        snapshot.updateMemory(nil, app: true)
        check(snapshot.values[.memoryAppPhysical] == nil && snapshot.values[.memoryAppUsage] == nil)
        check(HUDCSVLogger.row(["a,b", "a\"b", "a\nb", "", "0"]) == "\"a,b\",\"a\"\"b\",\"a\nb\",,0\r\n")

        // Exercise every numeric kind, including averages and per-app readings.
        let precisionGroups: [([HUDLogColumn], String)] = [
            ([.fps, .gpuPower, .cpuPower, .anePower, .socPower, .memoryPhysical, .memorySwap, .memoryAppPhysical], "12.35"),
            ([.gpuTemperature, .cpuTemperature, .batteryTemperature, .gpuUsage, .gpuAppUsage,
              .cpuUsage, .cpuAppUsage, .memoryUsage, .memoryAppUsage, .fanUsage(0), .fanAverageUsage, .batteryCharge], "12.3"),
            ([.fanRPM(0), .fanAverageRPM], "12")
        ]
        var rounded = HUDLogSnapshot()
        for (columns, expected) in precisionGroups {
            for column in columns {
                rounded.set(column, 12.3467)
                check(rounded.values[column] == expected, "Unexpected precision for \(column.title)")
                rounded.set(column, nil)
                check(rounded.values[column] == nil)
            }
        }
        rounded.set(.fanRPM(0), 1234.5678)
        rounded.set(.lowPowerMode, 1)
        check(rounded.values[.fanRPM(0)] == "1235" && rounded.values[.lowPowerMode] == "1")
        rounded.setText(.memoryPressure, "normal")
        check(rounded.values[.memoryPressure] == "normal")

        let logger = HUDCSVLogger()
        let wholeSecond = Date(timeIntervalSince1970: 1_800_000_000)
        let start = wholeSecond.addingTimeInterval(0.665)
        var enabled: Set<HUDLogColumn> = [.fps, .gpuPower, .cpuPower, .batteryTemperature]
        let schema: [HUDLogColumn] = [.fps, .gpuPower, .cpuPower, .batteryTemperature]
        try logger.start(columns: schema, recoveryDirectory: recovery, at: start, scheduled: false) { (snapshot, enabled) }
        check(logger.isLogging && logger.columns == schema)
        let activeFile = logger.recoveryURL!
        // Every row is already on disk, rather than held in a growing memory array.
        let header = "Time,FPS,GPU Power (W),CPU Power (W),Battery Temperature (°C)\r\n"
        check(try Data(contentsOf: activeFile).prefix(3) == Data([0xEF, 0xBB, 0xBF]))
        check(try String(contentsOf: activeFile, encoding: .utf8).hasPrefix(header))
        snapshot.set(.fps, nil) // Alt-tab or a stale FPS sample.
        enabled.remove(.gpuPower) // A disabled checkbox blanks an existing column.
        enabled.insert(.memoryPhysical) // A newly enabled checkbox cannot change the schema.
        try logger.record(at: start.addingTimeInterval(1))
        let output = try logger.stop(savingTo: desktop)!
        check(!logger.isLogging && logger.recoveryURL == nil && !files.fileExists(atPath: activeFile.path))
        let text = try String(contentsOf: output, encoding: .utf8)
        let rows = text.components(separatedBy: "\r\n")
        check(rows.count == 4 && rows[1].hasSuffix(",120.50,5.13,0.00,") && rows[2].hasSuffix(",,,0.00,"))
        let timeParser = ISO8601DateFormatter(); timeParser.formatOptions = [.withInternetDateTime]
        check(timeParser.date(from: String(rows[1].split(separator: ",")[0])) == wholeSecond)
        check(!rows[1].split(separator: ",")[0].contains("."), "CSV timestamps must omit milliseconds")
        check(timeParser.date(from: String(rows[2].split(separator: ",")[0])) == wholeSecond.addingTimeInterval(1))
        check(try logger.stop(savingTo: desktop) == nil, "Stop must be idempotent for Disable followed by Quit")
        try logger.record(at: start.addingTimeInterval(2))
        check(try String(contentsOf: output, encoding: .utf8) == text)
        try logger.start(columns: schema, recoveryDirectory: recovery, at: start, scheduled: false) { (snapshot, enabled) }
        let second = try logger.stop(savingTo: desktop)!
        check(second != output && second.lastPathComponent.hasSuffix("-1.csv"))
        check(try String(contentsOf: output, encoding: .utf8) == text, "Never replace a previous recording")

        try logger.start(columns: schema, recoveryDirectory: recovery, at: start, scheduled: false) { (snapshot, enabled) }
        let recoverable = logger.recoveryURL!
        do {
            _ = try logger.stop(savingTo: root.appendingPathComponent("DoesNotExist"))
            preconditionFailure("Saving to an unavailable destination must fail")
        } catch {
            check(!logger.isLogging && logger.recoveryURL == recoverable)
            check(files.fileExists(atPath: recoverable.path))
            let retained = try String(contentsOf: recoverable, encoding: .utf8)
            check(retained.hasPrefix(header) && retained.components(separatedBy: "\r\n").count == 3)
        }
        do {
            try logger.start(columns: [], recoveryDirectory: recovery, scheduled: false) { (snapshot, enabled) }
            preconditionFailure("An empty selection should explain why there is nothing to log")
        } catch HUDCSVLogger.Failure.noReadings { }
        let unwritable = root.appendingPathComponent("NotADirectory")
        try Data().write(to: unwritable)
        do {
            try logger.start(columns: schema, recoveryDirectory: unwritable) { (snapshot, enabled) }
            preconditionFailure("A failed start cannot claim to be logging")
        } catch { check(!logger.isLogging) }

        // Exercise the real timer in AppKit menu-tracking mode, not just manual rows.
        var ticks = 0
        try logger.start(columns: [.fps], recoveryDirectory: recovery) {
            ticks += 1
            return (snapshot, [.fps])
        }
        let until = Date().addingTimeInterval(2.2)
        while Date() < until { RunLoop.main.run(mode: .eventTracking, before: until) }
        _ = try logger.stop(savingTo: desktop)
        check(ticks == 3, "Expected immediate sample plus two one-second samples while menu is open, got \(ticks)")

        let suite = "PerformanceHUD.LoggingTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "hud.logging.explanationDismissed")
        defaults.set(false, forKey: "hud.autoHide.explanationDismissed")
        defaults.set(false, forKey: "hud.resetOptions.confirmationDismissed")
        HUDPreferences.resetOptions(in: defaults)
        check(defaults.bool(forKey: "hud.logging.explanationDismissed"))
        check(!defaults.bool(forKey: "hud.autoHide.explanationDismissed"))
        check(!defaults.bool(forKey: "hud.resetOptions.confirmationDismissed"))
        print("PASS: logging selection/order, rounded numeric values and whole-second timestamps, unavailable blanks, fans, memory, CSV encoding, fixed columns, timer during menu tracking, collision-safe saves, failure recovery, idempotent stop, and independent suppression")
    }
}
