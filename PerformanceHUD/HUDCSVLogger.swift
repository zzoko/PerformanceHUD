import Foundation

/// Streams one row per second, keeping memory use constant for long sessions.
/// A local recovery file survives failed Desktop saves and unexpected app exits.
@MainActor
final class HUDCSVLogger {
    enum Failure: LocalizedError {
        case alreadyLogging, noReadings
        var errorDescription: String? {
            switch self {
            case .alreadyLogging: return "A logging session is already running."
            case .noReadings: return "Select at least one available HUD reading before starting logging."
            }
        }
    }
    typealias Sample = () -> (snapshot: HUDLogSnapshot, enabled: Set<HUDLogColumn>)
    private(set) var isLogging = false
    private(set) var recoveryURL: URL?
    private(set) var columns: [HUDLogColumn] = []
    var onFailure: ((Error, URL?) -> Void)?
    private var handle: FileHandle?
    private var timer: Timer?
    private var sample: Sample?
    private var fileName = ""
    private let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func row(_ cells: [String]) -> String {
        cells.map { cell in
            guard cell.contains(",") || cell.contains("\"") || cell.contains("\n") || cell.contains("\r") else { return cell }
            return "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }.joined(separator: ",") + "\r\n"
    }

    func start(columns: [HUDLogColumn], recoveryDirectory: URL, at date: Date = Date(),
               scheduled: Bool = true, sample: @escaping Sample) throws {
        guard !isLogging else { throw Failure.alreadyLogging }
        guard !columns.isEmpty else { throw Failure.noReadings }
        let files = FileManager.default
        try files.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        fileName = "PerformanceHUD-\(formatter.string(from: date)).csv"
        let url = recoveryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        // UTF-8 BOM helps spreadsheet apps recognize the degree sign in headers.
        let header = "\u{FEFF}" + Self.row(["Time"] + columns.map(\.title))
        try Data(header.utf8).write(to: url, options: .atomic)
        do {
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            handle = try FileHandle(forWritingTo: url)
            try handle?.seekToEnd()
        } catch {
            try? files.removeItem(at: url) // Header only; no samples have been taken.
            throw error
        }
        self.columns = columns
        self.sample = sample
        recoveryURL = url
        isLogging = true
        do { try record(at: date) }
        catch { endWriting(); throw error }
        if scheduled {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = 0.05
            self.timer = timer
            // Continue recording while the status menu is open or being dragged.
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func record(at date: Date) throws {
        guard isLogging, let sample, let handle else { return }
        let reading = sample()
        let cells = columns.map { reading.enabled.contains($0) ? reading.snapshot.values[$0] ?? "" : "" }
        try handle.write(contentsOf: Data(Self.row([timestamp.string(from: date)] + cells).utf8))
    }

    private func tick() {
        do { try record(at: Date()) }
        catch {
            endWriting()
            onFailure?(error, recoveryURL)
        }
    }

    /// Stops first, even when saving fails. Never overwrite a previous recording.
    @discardableResult
    func stop(savingTo directory: URL) throws -> URL? {
        guard isLogging else { return nil }
        timer?.invalidate(); timer = nil
        isLogging = false
        sample = nil
        let writer = handle
        handle = nil
        do { try writer?.synchronize(); try writer?.close() }
        catch { try? writer?.close(); throw error }
        guard let source = recoveryURL else { return nil }
        let files = FileManager.default
        // Publish the completed copy with a same-folder rename. A failed copy
        // must not leave a truncated file masquerading as a finished CSV.
        let staging = directory.appendingPathComponent(".PerformanceHUD-" + UUID().uuidString + ".partial")
        defer { try? files.removeItem(at: staging) }
        try files.copyItem(at: source, to: staging)
        let stem = (fileName as NSString).deletingPathExtension
        var suffix = 0
        while true {
            let name = suffix == 0 ? fileName : "\(stem)-\(suffix).csv"
            let destination = directory.appendingPathComponent(name)
            // Do not overwrite even when another session finished in the same second.
            if files.fileExists(atPath: destination.path) { suffix += 1; continue }
            do { try files.moveItem(at: staging, to: destination) }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                suffix += 1
                continue
            }
            // Keep the recovery copy until the destination has been saved successfully.
            try? files.removeItem(at: source)
            recoveryURL = nil
            return destination
        }
    }

    private func endWriting() {
        timer?.invalidate(); timer = nil
        isLogging = false
        sample = nil
        try? handle?.close()
        handle = nil
    }

    deinit { timer?.invalidate(); try? handle?.close() }
}
