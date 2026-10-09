import Foundation
import Darwin

@MainActor
final class MemoryPressureMonitor {
    nonisolated enum Level: Int, Sendable {

        case low
        case medium
        case high

        init?(displayText: String) {
            switch displayText {
            case "normal": self = .low
            case "warning": self = .medium
            case "critical": self = .high
            default: return nil
            }
        }

        var displayText: String {

            switch self {

            case .low:
                return "normal"

            case .medium:
                return "warning"

            case .high:
                return "critical"
            }
        }
    }

    nonisolated struct Sample: Sendable {
        let time: TimeInterval
        let level: Level?
        let numericValue: Double?
    }

    var onPressureUpdate: ((Level?) -> Void)?
    var onHistoryUpdate: ((Sample) -> Void)?
    private let poller = MetricPoller<Sample>(label: "PerformanceHUD.MemoryPressure")
    private var includesHistory = false

    func start(includeHistory: Bool = false) {
        guard !poller.isRunning || includesHistory != includeHistory else { return }
        includesHistory = includeHistory
        // Read the current global state once per second, rather than retaining
        // the last notification while waiting for another event to arrive.
        poller.start(sample: {
            Sample(time: ProcessInfo.processInfo.systemUptime, level: Self.readCurrentPressure(),
                   numericValue: includeHistory ? Self.readNumericPressure() : nil)
        }) { [weak self] sample in
            guard let sample else { return }
            self?.onPressureUpdate?(sample.level)
            if includeHistory { self?.onHistoryUpdate?(sample) }
        }
    }
    func stop() { poller.stop() }

    // Read-only numeric backing value used for pressure history. This is not RAM
    // usage percentage or a replacement for macOS's separate pressure state.
    nonisolated private static func readNumericPressure() -> Double? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_level", &value, &size, nil, 0) == 0,
              size == MemoryLayout<Int32>.size, (0...100).contains(value) else { return nil }
        return Double(100 - value)
    }
    // MARK: - Current Pressure

    nonisolated private static func readCurrentPressure()
        -> Level?
    {

        var value:
            Int32 = 0

        var size =
            MemoryLayout<Int32>.size

        let result =
            withUnsafeMutablePointer(
                to: &value
            ) { pointer in

                sysctlbyname(
                    "kern.memorystatus_vm_pressure_level",
                    pointer,
                    &size,
                    nil,
                    0
                )
            }

        guard
            result == 0, size == MemoryLayout<Int32>.size
        else {
            return nil
        }

        /*
         macOS values:

         1 = normal
         2 = warning
         4 = critical
        */

        switch value {

        case 1:
            return .low

        case 2:
            return .medium

        case 4:
            return .high

        default:
            return nil
        }
    }

}
