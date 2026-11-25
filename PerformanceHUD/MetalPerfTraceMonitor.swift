import Foundation

/// Displayed-frame intervals for the same Metal layer and reporting second as FPS.
nonisolated struct MetalFrameTiming: Equatable, Sendable {
    let averageMS: Double
    let worstMS: Double?

    init?(averageMS: Double?, worstMS: Double?) {
        guard let averageMS, averageMS.isFinite, averageMS > 0 else { return nil }
        self.averageMS = averageMS
        self.worstMS = worstMS.flatMap { $0.isFinite && $0 >= averageMS ? $0 : nil }
    }

    enum Hitch { case warning, severe }
    var hitch: Hitch? {
        guard let worstMS, worstMS >= 25, worstMS >= 2.5 * averageMS else { return nil }
        return worstMS >= 100 ? .severe : .warning
    }
}

@MainActor
final class MetalPerfTraceMonitor {
    nonisolated struct MetalMetrics: Sendable {
        let fps: Double?
        let gpuUsage: Double?
        var resolution: HUDResolution? = nil
        var frameTiming: MetalFrameTiming? = nil
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
            resetScan()
            return []
        }
        incomingData.append(data)
        var updates: [MetalPerfTraceMonitor.MetalMetrics] = []
        while let object = extractNextJSONObject() {
            if let metrics = parseJSON(object) { updates.append(metrics) }
        }
        return updates
    }

    // Where the scan of incomingData stopped, so an object that arrives in
    // several pieces is read once instead of from the start for each piece.
    private var scanned = 0
    private var objectStart: Int?
    private var depth = 0
    private var insideString = false, escaped = false

    private func resetScan() {
        scanned = 0; objectStart = nil; depth = 0; insideString = false; escaped = false
    }

    private func extractNextJSONObject() -> Data? {
        var object: Data?
        var consumed = 0
        incomingData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var index = scanned
            while index < bytes.count {
                let byte = bytes[index]
                defer { index += 1 }
                if insideString {
                    if escaped { escaped = false }
                    else if byte == 0x5C { escaped = true }
                    else if byte == 0x22 { insideString = false }
                    continue
                }
                // Ignore preamble text until an object begins.
                if byte == 0x22 && depth > 0 { insideString = true }
                else if byte == 0x7B {
                    if depth == 0 { objectStart = index }
                    depth += 1
                } else if byte == 0x7D && depth > 0 {
                    depth -= 1
                    if depth == 0, let start = objectStart {
                        object = Data(bytes[start...index])
                        consumed = index + 1
                        return
                    }
                }
            }
            scanned = bytes.count
        }
        if let object {
            incomingData.removeFirst(consumed)
            resetScan()
            return object
        }
        // Nothing complete yet: keep only an object that has begun.
        if let start = objectStart, start > 0 {
            incomingData.removeFirst(start)
            scanned -= start
            objectStart = 0
        } else if objectStart == nil {
            incomingData.removeAll(keepingCapacity: true)
            scanned = 0
        }
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
            let resolution = HUDResolution(width: width, height: height)
            let area = resolution.map { Double($0.width) * Double($0.height) } ?? 0
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
                let intervals = performance["Frame-On-Glass Interval Stats"] as? [String: Any]
                let count = (intervals?["Count"] as? NSNumber)?.intValue ?? 0
                let timing = count > 0 ? MetalFrameTiming(
                    averageMS: (intervals?["Average (ms)"] as? NSNumber)?.doubleValue,
                    worstMS: (intervals?["Max (ms)"] as? NSNumber)?.doubleValue) : nil
                selected = .init(fps: fps, gpuUsage: gpuUsage, resolution: resolution, frameTiming: timing)
            }
        }
        return selected
    }
}
