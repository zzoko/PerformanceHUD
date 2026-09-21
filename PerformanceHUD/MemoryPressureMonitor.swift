import Foundation
import Darwin

@MainActor
final class MemoryPressureMonitor {
    nonisolated enum Level: Sendable {

        case low
        case medium
        case high

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
    private var source: (any DispatchSourceMemoryPressure)?
    private var generation = UUID()
    private let queue = DispatchQueue(label: "PerformanceHUD.MemoryPressure", qos: .utility)

    func start() {
        guard source == nil else { return }
        let ticket = generation
        onPressureUpdate?(Self.readCurrentPressure())
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: queue)
        source.setEventHandler { [weak self, weak source] in
            guard let source else { return }
            let event = source.data
            let level: Level? = event.contains(.critical) ? .high : event.contains(.warning) ? .medium : event.contains(.normal) ? .low : nil
            DispatchQueue.main.async {
                guard let self, self.generation == ticket else { return }
                self.onPressureUpdate?(level)
            }
        }
        self.source = source
        source.activate()
    }
    func stop() { generation = UUID(); source?.cancel(); source = nil }
    deinit { source?.cancel() }
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
            result == 0
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
