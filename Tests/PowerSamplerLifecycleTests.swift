import Foundation
import Darwin

@main struct LifecycleTests {
    static func fixture() -> Data {
        try! PropertyListSerialization.data(fromPropertyList: ["is_delta": true, "elapsed_ns": 1e9,
            "timestamp": Date(), "processor": ["cpu_power": 4250.0, "gpu_power": 1500.0, "ane_power": 250.0]],
            format: .xml, options: 0)
    }
    static func producer(_ scenario: String, generation: Int) {
        precondition(PowerSamplerChild.joinParentProcessGroup(), "child must join parent group")
        if scenario == "empty-exit" && generation == 1 { return }
        if scenario == "slow-start" { Thread.sleep(forTimeInterval: 6) }
        if scenario == "startup-hung" && generation == 1 { Thread.sleep(forTimeInterval: 60) }
        var samples = 0
        while true {
            Thread.sleep(forTimeInterval: 0.5)
            if scenario == "stream-hung" && generation == 1 && samples > 0 { continue }
            FileHandle.standardOutput.write((samples > 0 ? Data([0]) : Data()) + fixture())
            samples += 1
        }
    }
    static func main() {
        let args = CommandLine.arguments
        if args[1] == "--producer" { producer(args[2], generation: Int(args[3])!); return }
        if args[1] == "--joined-idle" {
            precondition(PowerSamplerChild.joinParentProcessGroup())
            // No stdout writes: orphan cleanup cannot be attributed to SIGPIPE.
            while true { Thread.sleep(forTimeInterval: 1) }
        }
        if args[1] == "--job" {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: args[0]); child.arguments = ["--joined-idle"]
            child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
            try! child.run()
            Thread.sleep(forTimeInterval: 0.5)
            let metadata: [String: Int32] = ["parent":getpid(), "child":child.processIdentifier,
                                            "parentGroup":getpgrp(), "childGroup":getpgid(child.processIdentifier)]
            try! JSONSerialization.data(withJSONObject: metadata).write(to: URL(fileURLWithPath: args[2]))
            while true { Thread.sleep(forTimeInterval: 1) }
        }
        precondition(PowerSamplerChild.helperExecutableURL?.standardizedFileURL == URL(fileURLWithPath: args[0]).resolvingSymlinksInPath().standardizedFileURL,
                     "child launch must target the actual executable")
        let scenario = args[1]
        precondition(!PowerSamplerChild.arguments.contains("--sample-count"),
                     "continuous sampling must use the default, not a version-dependent zero count")
        precondition(PowerSampler.powerProcess().arguments == [PowerSamplerChild.argument])
        let lock = NSLock(); var children: [Process] = []
        let sampler = PowerSampler(makeProcess: {
            let child = Process(); child.executableURL = URL(fileURLWithPath: args[0])
            lock.lock(); children.append(child); let generation = children.count; lock.unlock()
            child.arguments = ["--producer", scenario, String(generation)]
            child.standardError = FileHandle.nullDevice
            return child
        })
        let id = UUID(); var continuity = PowerReadingContinuity()
        let began = ProcessInfo.processInfo.systemUptime
        var first: Double?; var lostAfterFirst = false; var maxChildren = 0; var last: HelperPowerReading?
        let duration: Double = (scenario == "startup-hung" || scenario == "empty-exit") ? 14 : scenario == "slow-start" ? 13 : 9
        while ProcessInfo.processInfo.systemUptime - began < duration {
            let done = DispatchSemaphore(value: 0)
            var raw: HelperPowerReading?
            sampler.sample(client: id) { raw = HelperPowerReading(reply: $0); done.signal() }
            precondition(done.wait(timeout: .now() + 2) == .success, "startup must not block replies")
            last = continuity.update(raw)
            if last != nil && first == nil { first = ProcessInfo.processInfo.systemUptime - began }
            if last == nil && first != nil { lostAfterFirst = true }
            lock.lock(); maxChildren = max(maxChildren,children.filter { $0.isRunning }.count); lock.unlock()
            Thread.sleep(forTimeInterval: 0.2)
        }
        precondition(first != nil && last != nil && maxChildren == 1)
        lock.lock(); let launches = children.count; lock.unlock()
        if scenario == "continuous" || scenario == "slow-start" {
            precondition(launches == 1 && !lostAfterFirst, "healthy sampler must not cycle or blank")
        } else { precondition(launches == 2, "stalled process must restart exactly once") }
        if scenario == "slow-start" { precondition(first! >= 6, "slow-start fixture did not exercise grace period") }
        if scenario == "empty-exit" {
            precondition(first! >= 10, "empty successful exits must back off before retrying")
        }
        let stopped = DispatchSemaphore(value: 0)
        sampler.stop(client: id) { stopped.signal() }
        precondition(stopped.wait(timeout: .now() + 2) == .success)
        Thread.sleep(forTimeInterval: 1.2)
        lock.lock(); let remaining = children.filter { $0.isRunning }.count; lock.unlock()
        precondition(remaining == 0, "stop must reap continuous child")
        print("PASS \(scenario): first=\(first!)s launches=\(launches) maxLive=\(maxChildren) remaining=\(remaining)")
    }
}
