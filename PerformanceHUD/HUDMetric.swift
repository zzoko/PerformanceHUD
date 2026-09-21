import Foundation

enum HUDMetric: Int, CaseIterable, Hashable {

    case fps = 0
    case fpsGraph = 10
    case gpu = 1
    case gpuTotal
    case cpu
    case cpuTotal
    case ram
    case ramTotal
    // Preserve existing metric identifiers after removing the separate pressure option.
    case battery = 8
    case deviceInfo

    // MARK: - Menu Titles

    var menuTitle: String {

        switch self {

        case .fps:
            return "FPS"

        case .fpsGraph:
            return "FPS History"

        case .gpu:
            return "GPU (only selected app)"

        case .gpuTotal:
            return "GPU Total"

        case .cpu:
            return "CPU (only selected app)"

        case .cpuTotal:
            return "CPU Total"

        case .ram:
            return "RAM (only selected app)"

        case .ramTotal:
            return "RAM Total"

        case .battery:
            return "Battery"

        case .deviceInfo:
            return "Device Info"
        }
    }

    // MARK: - HUD Titles

    var hudTitle: String {

        switch self {

        case .fps:
            return "FPS"

        case .fpsGraph:
            return "FPS History"

        case .gpu:
            return "GPU (app)"

        case .gpuTotal:
            return "GPU"

        case .cpu:
            return "CPU (app)"

        case .cpuTotal:
            return "CPU"

        case .ram:
            return "RAM (app)"

        case .ramTotal:
            return "RAM"

        case .battery:
            return "Battery"

        case .deviceInfo:
            return "Device Info"
        }
    }

    // MARK: - Placeholder

    var placeholderValue: String {
        ""
    }

    // MARK: - Default Visibility

    var defaultEnabled: Bool {

        switch self {

        case .fps,
             .fpsGraph,
             .gpuTotal,
             .cpuTotal,
             .ramTotal,
             .battery,
             .deviceInfo:

            return true

        default:
            return false
        }
    }
}
