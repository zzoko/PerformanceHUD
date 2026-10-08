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

    var onPressureUpdate: ((Level?) -> Void)?
    private let poller = MetricPoller<Level>(label: "PerformanceHUD.MemoryPressure")

    func start() {
        guard !poller.isRunning else { return }
        // Read the current global state once per second, rather than retaining
        // the last notification while waiting for another event to arrive.
        poller.start(sample: { Self.readCurrentPressure() }) { [weak self] level in
            self?.onPressureUpdate?(level)
        }
    }
    func stop() { poller.stop() }
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
