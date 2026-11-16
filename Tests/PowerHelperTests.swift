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
        check(HUDMetric.battery.rawValue == 8 && HUDMetric(rawValue: 9) == nil && HUDMetric.fpsGraph.rawValue == 10,
              "removing Mac preserves all other metric identifiers")
        check(HUDMetric.allCases.allSatisfy { HUDAlignment.vertical.allows($0) }, "vertical permits all metric choices")
        check(!HUDAlignment.horizontal.allows(.fpsGraph) && !HUDAlignment.horizontal.allows(.misc),
              "horizontal excludes history and Misc")
        check(HUDAlignment.horizontal.allows(.fps) && HUDAlignment.horizontal.allows(.aneTotal)
              && HUDAlignment.horizontal.allows(.battery), "horizontal retains main readings")
        for legacy in HUDUsageMode.allCases {
            var options = HUDResourceOptions(enabled: true, temperature: false, totalUse: legacy != .app,
                                             focusedApp: legacy != .total, details: false, pressure: false).systemOnly
            check(!options.focusedApp && options.selectedUsageMode == .total, "Legacy modes resolve to system usage")
            options.setUsagePresentation(visible: true, highlighted: true)
            check(options.visibleMetrics(for: .ram) == [.ramTotal] && options.usageHighlighted, "Use shows only system memory")
            options.setUsagePresentation(visible: false, highlighted: false)
            check(options.visibleMetrics(for: .ram).isEmpty, "Use off leaves no usage row")
            options.enabled = false
            check(options.visibleMetrics(for: .ram).isEmpty, "Master switch hides system usage")
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
                for pressure in [false, true] {
                    for usage in [false, true] {
                        for enabled in [false, true] {
                            var options = HUDResourceOptions(enabled: enabled, temperature: false,
                                totalUse: usage, focusedApp: false, details: details, pressure: pressure, usageMode: mode)
                            options.setUsagePresentation(visible: usage, highlighted: false)
                            var expected: Set<HUDMetric> = !enabled || (!details && !usage) ? []
                                : [.ramTotal]
                            if enabled && pressure { expected.insert(.ramTotal) }
                            check(options.visibleMetrics(for: .ram) == expected,
                                  "independent Details, Pressure and Use keep the correct memory sources in every mode")
                            check(options.showsDetails == (enabled && details), "Details follows only its own and the master checkbox")
                            check(options.showsPressure == (enabled && pressure),
                                  "Pressure remains available with Use and Details off, independently of old source modes")
                        }
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

        // Regression: watt continuity used to discard all CPU/GPU frequency
        // fields before the sample reached PowerMonitor and the HUD.
        var frequencyContinuity = PowerReadingContinuity(cpuCoreGroups: [[0, 1]])
        let cpuFrequencies = CPUFrequencySample(frequencies: [0: 2, 1: 4], activeResidencies: [0: 0.25, 1: 0.75])
        let frequencyReading = HelperPowerReading(cpu: 4, gpu: 2, package: 6, timestamp: base,
            cpuFrequencies: cpuFrequencies, gpuFrequency: 1.35)
        let displayed = frequencyContinuity.update(frequencyReading, now: base)
        check(displayed?.cpuFrequencies == cpuFrequencies && displayed?.gpuFrequency == 1.35,
              "CPU and GPU GHz survive the watt continuity stage")
        check(displayed?.cpuFrequencies.average(for: [0, 1]) == 3.5,
              "Clock values retain residency weights from the same sample")
        let delayed = frequencyContinuity.update(nil, now: base.addingTimeInterval(2))
        check(delayed?.cpuFrequencies == cpuFrequencies && delayed?.gpuFrequency == 1.35,
              "Brief missing replies retain the whole frequency sample")
        let changedFrequencies = CPUFrequencySample(frequencies: [0: 1, 1: 3], activeResidencies: [0: 0.75, 1: 0.25])
        let changedFrequencyReading = HelperPowerReading(cpu: 3, gpu: 1, package: 4,
            timestamp: base.addingTimeInterval(3), cpuFrequencies: changedFrequencies, gpuFrequency: 0.5)
        let changedDisplay = frequencyContinuity.update(changedFrequencyReading, now: base.addingTimeInterval(3))
        check(changedDisplay?.cpuFrequencies.average(for: [0, 1]) == 1.5 && changedDisplay?.gpuFrequency == 0.5,
              "New clocks and weights replace the previous interval together")
        let oldFrequencyReply = frequencyContinuity.update(frequencyReading, now: base.addingTimeInterval(4))
        check(oldFrequencyReply?.cpuFrequencies == changedFrequencies && oldFrequencyReply?.gpuFrequency == 0.5,
              "An older reply cannot overwrite newer frequency readings")
        check(frequencyContinuity.update(nil, now: base.addingTimeInterval(8.1)) == nil,
              "Frequency continuity expires without renewing the original timestamp")
        _ = frequencyContinuity.update(frequencyReading, now: base)
        let idleFrequencyReading = HelperPowerReading(cpu: 1, gpu: 0, package: 1, timestamp: base.addingTimeInterval(1),
            cpuFrequencies: .init(frequencies: [0: 2, 1: 4], activeResidencies: [0: 0, 1: 0]))
        let idleDisplay = frequencyContinuity.update(idleFrequencyReading, now: base.addingTimeInterval(1))
        check(idleDisplay?.cpuFrequencies == cpuFrequencies && idleDisplay?.gpuFrequency == 1.35,
              "A brief idle or unavailable frequency retains the last valid interval")
        frequencyContinuity.reset()
        check(frequencyContinuity.update(nil, now: base.addingTimeInterval(2)) == nil,
              "Stop and disconnect clear frequency continuity too")

        // Super and Efficiency can become unavailable independently, including
        // one type spanning clusters with different clocks and residency weights.
        var perType = PowerReadingContinuity(cpuCoreGroups: [[0, 1], [2, 3]])
        func typedReading(_ offset: Double, frequencies: [Int: Double], weights: [Int: Double], gpu: Double? = nil) -> HelperPowerReading {
            HelperPowerReading(cpu: 3, gpu: 1, package: 4, timestamp: base.addingTimeInterval(offset),
                cpuFrequencies: .init(frequencies: frequencies, activeResidencies: weights), gpuFrequency: gpu)
        }
        let original = typedReading(0, frequencies: [0: 2, 1: 4, 2: 1, 3: 1],
            weights: [0: 0.25, 1: 0.75, 2: 0.5, 3: 0.5], gpu: 1.35)
        _ = perType.update(original, now: base)
        for offset in [1.0, 4.0, 5.0] {
            let partial = typedReading(offset, frequencies: [0: 0, 1: 0, 2: 2, 3: 2],
                weights: [0: 0, 1: 0, 2: 0.9, 3: 0.1])
            let result = perType.update(partial, now: base.addingTimeInterval(offset))!
            check(result.cpuFrequencies.average(for: [0, 1]) == 3.5
                  && result.cpuFrequencies.activeResidencies[0] == 0.25
                  && result.cpuFrequencies.average(for: [2, 3]) == 2 && result.gpuFrequency == 1.35,
                  "Only the unavailable type is retained, with its original clocks and weights")
        }
        let expired = perType.update(typedReading(5.01, frequencies: [2: 2.5, 3: 2.5],
            weights: [2: 0.5, 3: 0.5]), now: base.addingTimeInterval(5.01))!
        check(expired.cpuFrequencies.average(for: [0, 1]) == nil
              && expired.cpuFrequencies.average(for: [2, 3]) == 2.5 && expired.gpuFrequency == nil,
              "Fresh watts and Efficiency samples cannot renew expired Super or GPU GHz")
        let lowerClock = typedReading(6, frequencies: [0: 0.8, 1: 1.2], weights: [0: 0.5, 1: 0.5], gpu: 0.3)
        let recovered = perType.update(lowerClock, now: base.addingTimeInterval(6))!
        check(recovered.cpuFrequencies.average(for: [0, 1]) == 1
              && recovered.cpuFrequencies.average(for: [2, 3]) == 2.5 && recovered.gpuFrequency == 0.3,
              "A valid lower clock immediately replaces the last display, without averaging lag")
        let repeatedOld = perType.update(original, now: base.addingTimeInterval(6.5))!
        check(repeatedOld.cpuFrequencies.average(for: [0, 1]) == 1 && repeatedOld.gpuFrequency == 0.3,
              "An old sample cannot overwrite or extend a recovered frequency")
        perType.reset()
        check(perType.update(nil, now: base.addingTimeInterval(6.5)) == nil,
              "Reset clears each retained core type")
        check(perType.update(lowerClock, now: base.addingTimeInterval(6.5))?.cpuFrequencies.average(for: [0, 1]) == 1,
              "Reset preserves the runtime topology for later samples")

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
        check(launches >= 2, "exited child restarts during active sampling")
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
        print("PASS: ANE options/power/IPC, helper health/availability, power parser, stale/malformed data, streaming, child exit recovery, stop/resume, and lease expiry")
    }
}
