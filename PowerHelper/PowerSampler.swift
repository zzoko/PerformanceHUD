import Foundation
import Darwin

// Queue-confined state. One child serves authenticated connections. Five-second
// leases cover lost stop messages; bounded children also limit orphan lifetime
// if the helper itself is killed. No launch arguments come from an XPC client.
final class PowerSampler {
    private let queue = DispatchQueue(label: "PerformanceHUD.PowerHelper", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var leases: [UUID: TimeInterval] = [:]
    private var process: Process?
    private var outputDrained = false
    private var stopping = false
    private var buffer = Data()
    private var reading: HelperPowerReading?
    private var lastOutput: TimeInterval = 0
    private var nextStart: TimeInterval = 0
    private let plistEnd = Data("</plist>".utf8)
    private let makeProcess: () -> Process

    init(makeProcess: @escaping () -> Process = PowerSampler.powerProcess) {
        self.makeProcess = makeProcess
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.maintain() }
        self.timer = timer
        timer.resume()
    }

    static func powerProcess() -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        // Pipes otherwise buffer output, which delays samples until they are stale.
        p.arguments = ["--samplers", "cpu_power,gpu_power", "--sample-rate", "1000",
                       "--sample-count", "5", "--format", "plist", "--buffer-size", "0"]
        p.environment = ["PATH": "/usr/bin:/bin", "LANG": "C"]
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        return p
    }

    func sample(client: UUID, reply: @escaping (NSDictionary) -> Void) {
        queue.async {
            self.startTimer()
            self.leases[client] = Date.timeIntervalSinceReferenceDate + 5
            self.maintain()
            if let reading = self.reading, abs(reading.timestamp.timeIntervalSinceNow) < 3 {
                reply(reading.reply)
            } else { reply([:]) }
        }
    }

    func stop(client: UUID, reply: @escaping () -> Void = {}) {
        queue.async {
            self.leases.removeValue(forKey: client)
            self.maintain()
            reply()
        }
    }

    private func maintain() {
        let now = Date.timeIntervalSinceReferenceDate
        // EOF and process exit can arrive in either order. Finish only once both
        // happened, without waitUntilExit (which can stall in a launchd daemon).
        if let child = process, outputDrained, !child.isRunning {
            process = nil
            buffer.removeAll(keepingCapacity: true)
            nextStart = now + (stopping || child.terminationStatus == 0 ? 0 : 10)
        }
        leases = leases.filter { $0.value > now }
        guard !leases.isEmpty else {
            timer?.cancel(); timer = nil
            terminate(); reading = nil; return
        }
        if let process {
            if process.isRunning && now - lastOutput > 4 { terminate() }
        } else if now >= nextStart { launch() }
    }

    private func launch() {
        stopping = false
        outputDrained = false
        let child = makeProcess()
        let pipe = Pipe()
        child.standardOutput = pipe
        process = child
        buffer.removeAll(keepingCapacity: true)
        lastOutput = Date.timeIntervalSinceReferenceDate
        child.terminationHandler = { [weak self] child in
            self?.queue.async { [weak self] in
                guard let self, self.process === child else { return }
                self.maintain()
            }
        }
        do { try child.run() }
        catch {
            process = nil; reading = nil
            nextStart = Date.timeIntervalSinceReferenceDate + 10
            return
        }
        // Drain to EOF before completing a child. A Process termination callback
        // can arrive ahead of the final pipe callback and lose the last sample.
        let handle = pipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var bytes = [UInt8](repeating: 0, count: 65_536)
            while true {
                let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { break }
                let data = Data(bytes.prefix(count))
                self?.queue.async { [weak self] in
                    guard let self, self.process === child, !self.stopping else { return }
                    self.consume(data)
                }
            }
            try? handle.close()
            self?.queue.async { [weak self] in
                guard let self, self.process === child else { return }
                self.outputDrained = true
                // All reads have been queued before this completion. Keep the
                // latest sample during the handoff to the next bounded child.
                self.maintain()
            }
        }
    }

    private func consume(_ bytes: Data) {
        guard !bytes.isEmpty else { return }
        guard buffer.count + bytes.count <= 1_048_576 else { terminate(); return }
        buffer.append(bytes)
        // powermetrics emits NUL-separated XML documents, not NUL-terminated
        // documents. Waiting for the separator delays every sample by one
        // interval and loses the final sample when the bounded child exits.
        while let end = buffer.range(of: plistEnd) {
            let data = Data(buffer[..<end.upperBound].drop(while: {
                $0 == 0 || $0 == 10 || $0 == 13 || $0 == 32 || $0 == 9
            }))
            buffer.removeSubrange(..<end.upperBound)
            if let sample = HelperPowerReading.parse(data) {
                reading = sample
                lastOutput = Date.timeIntervalSinceReferenceDate
            }
        }
    }

    private func terminate() {
        reading = nil
        guard let child = process, child.isRunning else { return }
        stopping = true
        child.terminate()
        // Keep this Process until exit; do not signal a stale/reused PID.
        queue.asyncAfter(deadline: .now() + 1) {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }

    deinit { timer?.cancel(); if process?.isRunning == true { process?.terminate() } }
}
