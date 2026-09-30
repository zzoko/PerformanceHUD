import Foundation

@main struct Tests {
    static func fixture(cpu: Any = 4250.0, gpu: Any = 1500.0, ane: Any? = 250.0,
                        age: Double = 0, elapsed: Double = 1e9, delta: Bool = true) -> Data {
        var processor: [String: Any] = ["cpu_power": cpu, "gpu_power": gpu]
        if let ane { processor["ane_power"] = ane }
        return try! PropertyListSerialization.data(fromPropertyList: ["is_delta": delta,
            "elapsed_ns": elapsed, "timestamp": Date().addingTimeInterval(-age), "processor": processor],
            format: .xml, options: 0)
    }
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
    static func main() {
        if CommandLine.arguments.contains("--producer") {
            for index in 0..<5 {
                Thread.sleep(forTimeInterval: 0.5)
                // Match powermetrics: separator before the next document,
                // with no trailing NUL after the final sample.
                let data = (index == 0 ? Data() : Data([0])) + fixture(cpu: 4250.0 + Double(index))
                let split = data.count - 4
                FileHandle.standardOutput.write(data.prefix(split))
                FileHandle.standardOutput.write(data.suffix(4))
            }
            return
        }
        check(HUDMetric.battery.rawValue == 8 && HUDMetric.deviceInfo.rawValue == 9 && HUDMetric.fpsGraph.rawValue == 10,
              "adding ANE preserves existing saved metric identifiers")
        check(HUDMetric.allCases.allSatisfy { HUDAlignment.vertical.allows($0) }, "vertical permits all metric choices")
        check(!HUDAlignment.horizontal.allows(.fpsGraph) && !HUDAlignment.horizontal.allows(.deviceInfo),
              "horizontal excludes history and device info")
        check(HUDAlignment.horizontal.allows(.fps) && HUDAlignment.horizontal.allows(.aneTotal)
              && HUDAlignment.horizontal.allows(.battery), "horizontal retains main readings")
        for mode in HUDUsageMode.allCases {
            var options = HUDResourceOptions(enabled: true, temperature: false, totalUse: mode != .app,
                                             focusedApp: mode != .total, details: false)
            check(options.selectedUsageMode == mode, "existing usage choices migrate to the corresponding mode")
            options.setUsagePresentation(visible: true, highlighted: true)
            options.selectUsageMode(.both)
            check(options.visibleMetrics(for: .ram) == [.ram, .ramTotal] && options.usageHighlighted,
                  "Both includes both readings and preserves emphasis")
            options.setUsagePresentation(visible: false, highlighted: false)
            options.selectUsageMode(mode)
            check(options.visibleMetrics(for: .ram).isEmpty && options.selectedUsageMode == mode,
                  "changing mode while Usage is off remembers mode without showing readings")
            options.setUsagePresentation(visible: true, highlighted: false)
            let expected: Set<HUDMetric> = mode == .total ? [.ramTotal] : mode == .app ? [.ram] : [.ram, .ramTotal]
            check(options.visibleMetrics(for: .ram) == expected && !options.usageHighlighted,
                  "enabling Usage restores the chosen mode with faint text")
            options.enabled = false
            check(options.visibleMetrics(for: .ram).isEmpty, "master switch still hides all usage modes")
        }
        for mode in HUDUsageMode.allCases {
            for rememberedDetails in [false, true] {
                var options = HUDResourceOptions(enabled: true, temperature: false, totalUse: true,
                                                 focusedApp: false, details: rememberedDetails)
                options.selectUsageMode(mode)
                check(options.detailsAvailable && options.showsDetails == rememberedDetails,
                      "Details supports Total, App and Both")
                options.setUsagePresentation(visible: false, highlighted: false)
                check(options.detailsAvailable && options.showsDetails == rememberedDetails,
                      "Usage off keeps Details independently available")
                options.setUsagePresentation(visible: true, highlighted: false)
                check(options.showsDetails == rememberedDetails,
                      "Usage on restores the saved Details selection")
            }
        }
        var emphasizedDetails = HUDResourceOptions(enabled: true, temperature: false, totalUse: true,
                                                    focusedApp: false, highlighted: [.details])
        emphasizedDetails.setUsagePresentation(visible: false, highlighted: false)
        check(emphasizedDetails.showsDetails && emphasizedDetails.highlighted.contains(.details),
              "Usage off remembers Details emphasis")
        emphasizedDetails.selectUsageMode(.app)
        emphasizedDetails.setUsagePresentation(visible: true, highlighted: true)
        check(emphasizedDetails.showsDetails && emphasizedDetails.highlighted.contains(.details),
              "Details emphasis survives usage and mode changes")
        for mode in HUDUsageMode.allCases {
            for details in [false, true] {
                for usage in [false, true] {
                    for enabled in [false, true] {
                        var options = HUDResourceOptions(enabled: enabled, temperature: false,
                            totalUse: usage, focusedApp: false, details: details, usageMode: mode)
                        options.setUsagePresentation(visible: usage, highlighted: false)
                        let expected: Set<HUDMetric> = !enabled || (!details && !usage) ? []
                            : mode == .total ? [.ramTotal] : mode == .app ? [.ram] : [.ram, .ramTotal]
                        check(options.visibleMetrics(for: .ram) == expected,
                              "independent Details/Usage keep the correct memory sources in every mode")
                        check(options.showsDetails == (enabled && details), "Details follows only its own and the master checkbox")
                    }
                }
            }
        }
        for mask in 0..<64 {
            var resources: [HUDResourceGroup: HUDResourceOptions] = [:]
            for (index, group) in [HUDResourceGroup.cpu, .gpu, .ane].enumerated() {
                resources[group] = HUDResourceOptions(enabled: mask & (1 << (index * 2)) != 0,
                    temperature: false, totalUse: false, focusedApp: false,
                    power: mask & (1 << (index * 2 + 1)) != 0)
            }
            let individualDemand = resources.values.contains { $0.enabled && $0.power }
            for enabled in [false, true] {
                for packageEnabled in [false, true] {
                    let package = HUDPackagePowerOptions(enabled: packageEnabled)
                    check(HUDPowerDemand.isNeeded(hudEnabled: enabled,
                        resources: resources, package: package)
                        == (enabled && (individualDemand || packageEnabled)),
                        "helper demand covers Package-only, hidden groups and disabled HUD")
                }
            }
        }
        check(HUDResourceGroup.ane.appMetric == nil && !HUDResourceGroup.ane.supportsTemperature,
              "ANE has no invented per-app or temperature metric")
        for power in [false, true] {
            for usage in [false, true] {
                for enabled in [false, true] {
                    let options = HUDResourceOptions(enabled: enabled, temperature: true, totalUse: usage, focusedApp: true, power: power)
                    let expected: Set<HUDMetric> = enabled && power ? [.aneTotal] : []
                    check(options.visibleMetrics(for: .ane) == expected, "ANE visibility follows supported options and its master switch")
                }
            }
        }
        check(!PowerHelperAvailability.setupRequired.shouldTurnPowerOff(setupOffered: false), "first launch offers setup before clearing default choices")
        check(PowerHelperAvailability.setupRequired.shouldTurnPowerOff(setupOffered: true), "declined or removed helper clears Power choices")
        check(PowerHelperAvailability.approvalRequired.shouldTurnPowerOff(setupOffered: false), "pending or denied approval clears Power choices")
        check(PowerHelperAvailability.failed.shouldTurnPowerOff(setupOffered: true), "confirmed failure clears Power choices")
        check(!PowerHelperAvailability.updating.shouldTurnPowerOff(setupOffered: true), "setup in progress does not clear choices prematurely")
        check(!PowerHelperAvailability.ready.shouldTurnPowerOff(setupOffered: true), "approved helper preserves manual choices")
        let idle = PowerHelperAvailability.approved(samplingRequested: false, receivedLiveReading: false)
        check(idle == .idle && idle.usesNormalAppearance && idle.explanation == nil,
              "launch with Power off uses normal controls without waiting for a sample")
        check(idle.allowsPowerToggle && !idle.shouldTurnPowerOff(setupOffered: true),
              "approved idle helper preserves choices and allows enabling Power")
        check(PowerHelperAvailability.approved(samplingRequested: true, receivedLiveReading: false) == .starting,
              "enabling Power starts waiting for the first sample")
        check(PowerHelperAvailability.approved(samplingRequested: true, receivedLiveReading: true) == .ready,
              "receiving power data finishes startup")
        check(PowerHelperAvailability.approved(samplingRequested: false, receivedLiveReading: true) == .idle,
              "stopping sampling returns to idle after successful readings too")
        check(!PowerHelperAvailability.starting.usesNormalAppearance, "approval alone is not proof of live readings")
        check(PowerHelperAvailability.starting.allowsPowerToggle, "startup still allows the user to stop sampling")
        check(!PowerHelperAvailability.starting.shouldTurnPowerOff(setupOffered: true), "initial connection preserves Power selections")
        var recovery = PowerHelperRecovery()
        check(!recovery.beginIfApproved(false), "automatic recovery cannot register a denied or unapproved helper")
        check(recovery.beginIfApproved(true), "an approved missing service gets one recovery attempt")
        check(!recovery.beginIfApproved(true), "repeated failures cannot cause a registration loop")
        var health = PowerHelperHealth()
        check(!health.connectionFailed(), "one lost connection must not turn Power off")
        check(!health.connectionFailed(), "allow a second connection attempt")
        check(health.connectionFailed(), "three consecutive failures confirm helper failure")
        check(!health.receivedSample(valid: true, now: 0), "a valid sample restores connection health")
        check(!health.connectionFailed(), "successful communication resets failure count")
        health.reset()
        check(!health.receivedSample(valid: false, now: 0), "empty startup reply is expected")
        check(!health.receivedSample(valid: false, now: 29), "brief sampling gaps preserve selections")
        check(health.receivedSample(valid: false, now: 30), "sustained unavailable readings confirm failure")
        check(!health.receivedSample(valid: true, now: 31), "valid data clears the missing-data window")
        check(!health.receivedSample(valid: false, now: 50), "a later gap starts a new window")
        health.reset()
        check(!health.receivedSample(valid: false, now: 100), "stop or sleep resets health timing")
        check(PowerHelperAvailability.ready.usesNormalAppearance, "approved helper uses normal Power controls")
        for state: PowerHelperAvailability in [.starting, .setupRequired, .approvalRequired, .updating, .failed] {
            check(!state.usesNormalAppearance && state.explanation != nil, "unavailable Power has a reason and muted controls")
        }

        let reading = HelperPowerReading.parse(fixture())!
        check(reading.cpu == 4.25 && reading.gpu == 1.5 && reading.package == 6, "mW to W / package sum")
        check(HelperPowerReading.parse(fixture(ane: nil))?.package == nil, "missing component must not count as zero")
        let stalled = HelperPowerReading.parse(fixture(cpu: 0))!
        check(stalled.cpu == nil && stalled.package == nil && stalled.gpu == 1.5, "stalled CPU preserves independent GPU")
        check(HelperPowerReading.parse(fixture(gpu: 0))?.gpu == 0, "idle GPU zero is valid")
        check(HelperPowerReading.parse(fixture(cpu: Double.nan))?.cpu == nil, "NaN rejected")
        check(HelperPowerReading.parse(fixture(cpu: -10))?.cpu == nil, "negative rejected")
        check(HelperPowerReading.parse(fixture(cpu: true))?.cpu == nil, "boolean rejected")
        check(HelperPowerReading.parse(fixture(cpu: 3_000_000))?.cpu == nil, "outlier rejected")
        check(HelperPowerReading.parse(fixture(age: 10)) == nil, "stale rejected")
        check(HelperPowerReading.parse(fixture(elapsed: 20e9)) == nil, "sleep-spanning delta rejected")
        check(HelperPowerReading.parse(fixture(delta: false)) == nil, "cumulative reading rejected")
        check(HelperPowerReading.parse(Data("not a plist".utf8)) == nil, "malformed rejected")
        check(HelperPowerReading(reply: reading.reply)?.package == 6, "IPC roundtrip")
        check(reading.ane == 0.25, "ANE milliwatts converted independently")
        check(HelperPowerReading.parse(fixture(ane: 0))?.ane == 0, "idle ANE power is a valid zero")
        check(HelperPowerReading.parse(fixture(ane: true))?.ane == nil, "boolean ANE power rejected")
        let aneOnly = HelperPowerReading.parse(fixture(cpu: -1, gpu: -1, ane: 750))
        check(aneOnly?.ane == 0.75 && aneOnly?.package == nil, "ANE survives unavailable CPU/GPU readings")
        check(HelperPowerReading(reply: aneOnly!.reply)?.ane == 0.75, "ANE-only sample survives IPC")
        check(HelperPowerReading.parse(fixture(ane: -10))?.package == nil, "invalid ANE leaves Package unavailable")
        let aneReading = HelperPowerReading(cpu: 4, gpu: 2, package: 7, timestamp: Date(), ane: 1)
        let roundtrip = HelperPowerReading(reply: aneReading.reply)
        check(roundtrip?.ane == 1 && roundtrip?.package == 7,
              "ANE values survive IPC without adding ANE twice to Package")
        let old = HelperPowerReading(cpu: 5, gpu: 2, package: 7, timestamp: Date().addingTimeInterval(-20))
        check(HelperPowerReading(reply: old.reply) == nil, "stale IPC result rejected")

        let base = Date(timeIntervalSince1970: 1_000)
        let full = HelperPowerReading(cpu: 4, gpu: 2, package: 7, timestamp: base, ane: 1)
        var continuity = PowerReadingContinuity()
        check(continuity.update(nil, now: base) == nil, "no invented startup reading")
        check(continuity.update(full, now: base)?.package == 7, "fresh sample appears immediately")
        check(continuity.update(nil, now: base.addingTimeInterval(3.5))?.cpu == 4,
              "brief delayed or empty reply does not blank watts")
        let partial = HelperPowerReading(cpu: nil, gpu: 0, package: nil,
                                         timestamp: base.addingTimeInterval(4), ane: 0)
        let bridged = continuity.update(partial, now: base.addingTimeInterval(4))
        check(bridged?.cpu == 4 && bridged?.gpu == 0 && bridged?.ane == 0 && bridged?.package == 7,
              "partial dropout retains CPU and coherent Package while fresh zero GPU/ANE values update")
        let repeated = continuity.update(full, now: base.addingTimeInterval(5.1))
        check(repeated?.cpu == nil && repeated?.package == nil && repeated?.gpu == 0,
              "old or repeated samples cannot extend component expiry or replace newer values")
        check(continuity.update(nil, now: base.addingTimeInterval(9.1)) == nil,
              "sustained loss eventually clears every cached value")
        _ = continuity.update(full, now: base)
        continuity.reset()
        check(continuity.update(nil, now: base.addingTimeInterval(1)) == nil,
              "explicit stop, sleep or disconnect clears continuity immediately")
        let resumed = HelperPowerReading(cpu: 6, gpu: 4, package: 10, timestamp: base.addingTimeInterval(10), ane: 0)
        check(continuity.update(resumed, now: base.addingTimeInterval(10))?.package == 10,
              "new readings replace retained values immediately")

        // Real subprocess lifecycle with a deterministic, unprivileged producer.
        let lock = NSLock()
        var children: [Process] = []
        let sampler = PowerSampler(makeProcess: {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            p.arguments = ["--producer"]
            p.standardError = FileHandle.nullDevice
            lock.lock(); children.append(p); lock.unlock()
            return p
        })
        let id = UUID()
        func sample() -> HelperPowerReading? {
            let sem = DispatchSemaphore(value: 0)
            var result: HelperPowerReading?
            sampler.sample(client: id) { result = HelperPowerReading(reply: $0); sem.signal() }
            check(sem.wait(timeout: .now() + 2) == .success, "sample callback timeout")
            return result
        }
        func live() -> Int {
            lock.lock(); defer { lock.unlock() }
            return children.filter { $0.isRunning }.count
        }
        _ = sample()
        Thread.sleep(forTimeInterval: 1.2)
        check(sample()?.cpu == 4.251, "latest complete sample parsed without waiting for next separator")
        for _ in 0..<5 { Thread.sleep(forTimeInterval: 1); check(sample() != nil, "readings remain present across child restarts"); check(live() <= 1, "only one sampler child") }
        lock.lock(); let launches = children.count; lock.unlock()
        check(launches >= 2, "bounded child restarts during active sampling")
        let stopped = DispatchSemaphore(value: 0)
        sampler.stop(client: id) { stopped.signal() }
        check(stopped.wait(timeout: .now() + 2) == .success, "stop callback")
        Thread.sleep(forTimeInterval: 1.3)
        check(live() == 0, "stop kills child")
        _ = sample()
        Thread.sleep(forTimeInterval: 1.2)
        check(sample()?.gpu == 1.5, "sampling resumes after toggle")
        Thread.sleep(forTimeInterval: 6.3)
        check(live() == 0, "lost heartbeat expires lease")
        print("PASS: ANE options/power/IPC, helper health/availability, power parser, stale/malformed data, streaming, bounded restarts, stop/resume, and lease expiry")
    }
}
