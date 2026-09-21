import Foundation

@MainActor
final class MetalPerfTraceMonitor {
    nonisolated struct MetalMetrics: Sendable {
        let fps: Double?
        let gpuUsage: Double?
    }
    var onMetricsUpdate: ((MetalMetrics) -> Void)?
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var watchdog: Task<Void, Never>?
    private var targetPID: pid_t?
    private var generation = UUID()
    private var lastValidSample: TimeInterval?
    private var unavailable = true
    private let processingQueue = DispatchQueue(label: "PerformanceHUD.MetalPerfTrace", qos: .utility)
    private static let staleInterval: TimeInterval = 3

    func start(pid: pid_t) throws {
        guard targetPID != pid || process?.isRunning != true else { return }
        stop()
        targetPID = pid
        let ticket = generation
        let parser = MetalMetricsParser(pid: pid) // Never shared with the next process session.
        let queue = processingQueue
        let process = Process()
        let output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/metalperftrace")
        process.arguments = ["listen", "--json", "--pid", String(pid), "--interval", "1"]
        // Flush each reading to the pipe instead of delivering multi-second batches.
        // Set this explicitly so exported apps do not depend on Xcode's environment.
        var environment = ProcessInfo.processInfo.environment
        environment["NSUnbufferedIO"] = "YES"
        process.environment = environment
        process.standardOutput = output
        process.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let receivedAt = ProcessInfo.processInfo.systemUptime
            queue.async {
                let updates = parser.consume(data)
                DispatchQueue.main.async {
                    guard let self, self.generation == ticket else { return }
                    for metrics in updates { self.receive(metrics, receivedAt: receivedAt) }
                }
            }
        }
        // Always drain stderr so a child cannot block on a full pipe.
        errors.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == ticket else { return }
                self.stop()
                self.publishUnavailable()
            }
        }
        self.process = process
        outputPipe = output
        errorPipe = errors
        publishUnavailable()
        do { try process.run() }
        catch { stop(); publishUnavailable(); throw error }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.generation == ticket else { return }
                self.expireIfNeeded(now: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    func stop() {
        generation = UUID()
        watchdog?.cancel(); watchdog = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if let process, process.isRunning { process.terminate() }
        process = nil; outputPipe = nil; errorPipe = nil
        targetPID = nil; lastValidSample = nil; unavailable = true
    }

    private func receive(_ metrics: MetalMetrics, receivedAt: TimeInterval) {
        guard ProcessInfo.processInfo.systemUptime - receivedAt < Self.staleInterval,
              let fps = metrics.fps, fps.isFinite, fps >= 0, fps < Double(Int.max) else { return }
        lastValidSample = receivedAt
        unavailable = false
        onMetricsUpdate?(metrics)
    }

    private func expireIfNeeded(now: TimeInterval) {
        guard !unavailable, let lastValidSample, now - lastValidSample >= Self.staleInterval else { return }
        publishUnavailable()
    }

    private func publishUnavailable() {
        unavailable = true
        lastValidSample = nil
        onMetricsUpdate?(MetalMetrics(fps: nil, gpuUsage: nil))
    }

    deinit {
        watchdog?.cancel()
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if let process, process.isRunning { process.terminate() }
    }
}

/// Confined to one serial processing queue. Cancellation never mutates its buffer.
nonisolated final class MetalMetricsParser: @unchecked Sendable {
    private var incomingData = Data()
    private let pid: pid_t
    private static let maximumBufferSize = 4 * 1024 * 1024
    init(pid: pid_t) { self.pid = pid }

    func consume(_ data: Data) -> [MetalPerfTraceMonitor.MetalMetrics] {
        // Bound malformed/incomplete output instead of retaining it indefinitely.
        guard incomingData.count + data.count <= Self.maximumBufferSize else {
            incomingData.removeAll(keepingCapacity: false)
            return []
        }
        incomingData.append(data)
        var updates: [MetalPerfTraceMonitor.MetalMetrics] = []
        while let object = extractNextJSONObject() {
            if let metrics = parseJSON(object) { updates.append(metrics) }
        }
        return updates
    }

    private func extractNextJSONObject() -> Data? {
        var start: Int?
        var depth = 0
        var insideString = false, escaped = false
        for (index, byte) in incomingData.enumerated() {
            if insideString {
                if escaped { escaped = false }
                else if byte == 0x5C { escaped = true }
                else if byte == 0x22 { insideString = false }
                continue
            }
            // Ignore preamble text until an object begins.
            if byte == 0x22 && depth > 0 { insideString = true }
            else if byte == 0x7B {
                if depth == 0 { start = index }
                depth += 1
            } else if byte == 0x7D && depth > 0 {
                depth -= 1
                if depth == 0, let start {
                    let object = Data(incomingData.dropFirst(start).prefix(index + 1 - start))
                    incomingData = Data(incomingData.dropFirst(index + 1))
                    return object
                }
            }
        }
        if let start, start > 0 { incomingData = Data(incomingData.dropFirst(start)) }
        else if start == nil { incomingData.removeAll(keepingCapacity: true) }
        return nil
    }

    private func parseJSON(_ data: Data) -> MetalPerfTraceMonitor.MetalMetrics? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let layers = root["Layers"] as? [[String: Any]] else { return nil }
        if let reportedPID = root["PID"] as? NSNumber, reportedPID.int32Value != pid { return nil }
        var selected: MetalPerfTraceMonitor.MetalMetrics?
        var selectedArea: Double = -1
        for layer in layers {
            guard let performance = layer["Performance Stats"] as? [String: Any],
                  let presented = performance["Presented Frame Stats"] as? [String: Any],
                  let fps = (presented["FPS"] as? NSNumber)?.doubleValue,
                  fps.isFinite, fps >= 0, fps < Double(Int.max) else { continue }
            let config = layer["Configuration"] as? [String: Any]
            let width = (config?["Width (pixels)"] as? NSNumber)?.doubleValue ?? 0
            let height = (config?["Height (pixels)"] as? NSNumber)?.doubleValue ?? 0
            let area = width * height
            var gpuUsage: Double?
            if let seconds = (performance["Time Active (sec)"] as? NSNumber)?.doubleValue,
               let gpu = presented["On-GPU Walltime Stats"] as? [String: Any],
               let milliseconds = (gpu["Total (ms)"] as? NSNumber)?.doubleValue,
               seconds > 0 {
                let usage = milliseconds / (seconds * 1000) * 100
                if usage.isFinite { gpuUsage = min(max(usage, 0), 100) }
            }
            if selected == nil || area > selectedArea {
                selectedArea = area
                selected = .init(fps: fps, gpuUsage: gpuUsage)
            }
        }
        return selected
    }
}
