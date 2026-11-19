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
    case aneTotal = 11
    case fans = 12
    case misc = 13
    case process = 14
    case cpuCores = 15
    case gpuCores = 16
    case storage = 17

    // MARK: - Menu Titles

    var menuTitle: String {

        switch self {
        case .storage: return "Storage"
        case .process: return "APP"
        case .cpuCores: return "CPU cores"
        case .gpuCores: return "GPU cores"

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

        case .aneTotal:
            return "ANE"

        case .ram:
            return "Unified Memory (only selected app)"

        case .ramTotal:
            return "Unified Memory Total"

        case .fans:
            return "Fans"

        case .battery:
            return "Battery"

        case .misc:
            return "Misc"
        }
    }

    // MARK: - HUD Titles

    var hudTitle: String {

        switch self {
        case .storage: return "Storage"
        case .process: return "APP"
        case .cpuCores: return "CPU cores"
        case .gpuCores: return "GPU cores"

        case .fps:
            return "FPS"

        case .fpsGraph:
            return "FPS History"

        case .gpu:
            return "GPU (App)"

        case .gpuTotal:
            return "GPU"

        case .cpu:
            return "CPU (App)"

        case .cpuTotal:
            return "CPU"

        case .aneTotal:
            return "ANE"

        case .ram:
            return "MEM (App)"

        case .ramTotal:
            return "MEM"

        case .fans:
            return "FAN"

        case .battery:
            return "Battery"

        case .misc:
            return "Misc"
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
             .aneTotal,
             .ramTotal,
             .fans,
             .battery:

            return true

        default:
            return false
        }
    }
}
