import Foundation

/// Both presentations share collectors. Only visible readings (or active HUD
/// logging) request data; a collapsed menu bar preserves choices without polling.
struct HUDMonitoringDemand {
    var fps = false
    var gpuUsage = false
    var gpuAppUsage = false
    var cpuCores = false
    var gpuCores = false
    var cpuUsage = false
    var cpuAppUsage = false
    var totalMemory = false
    var appMemory = false
    var pressure = false
    var pressureHistory = false
    var power = false
    var cpuTemperature = false
    var gpuTemperature = false
    var storage: HUDStorageOptions?
    var fans = false
    var battery = false
    var batteryTemperature = false
    var batteryPower = false
    var misc = HUDMiscOptions()

    static func make(hudEnabled: Bool, hudVisible: Bool, isLogging: Bool,
                     autoHideMode: HUDAutoHideMode, selection: HUDLogSelection,
                     menuBar: HUDMenuBarOptions) -> Self {
        var demand = Self()
        let overlay = hudEnabled && (hudVisible || isLogging)
        let pins = menuBar.activeReadings
        // All auto hide needs the FPS detector even while the overlay is hidden.
        demand.fps = pins.contains(.fps) || (hudEnabled && autoHideMode == .all)
            || (overlay && selection.fps)
        let process = overlay && selection.alignment == .vertical && selection.process.enabled
        demand.gpuAppUsage = process && selection.process.readings.contains(.gpu)
        demand.cpuAppUsage = process && selection.process.readings.contains(.cpu)
        demand.appMemory = process && selection.process.readings.contains(.memory)
        let cpuCoresShown = pins.contains(.cpuCores)
            || (overlay && selection.resources[.cpu]?.enabled == true && selection.cpuCores.enabled)
        let cpuCoreMode = selection.cpuCores.mode
        demand.cpuCores = cpuCoresShown && cpuCoreMode.showsBars
        demand.gpuCores = pins.contains(.gpuCores)
            || (overlay && selection.resources[.gpu]?.enabled == true && selection.gpuCores.enabled)
        for group in HUDResourceGroup.allCases {
            guard let options = selection.resources[group] else { continue }
            let shown = overlay && options.enabled
            switch group {
            case .gpu, .cpu:
                let gpu = group == .gpu
                let usagePinned = pins.contains(gpu ? .gpuUsage : .cpuUsage)
                let total = (shown && options.totalUse) || usagePinned
                let temperature = (shown && options.temperature) || pins.contains(gpu ? .gpuTemperature : .cpuTemperature)
                demand.power = demand.power || (shown && options.power) || pins.contains(gpu ? .gpuPower : .cpuPower)
                if gpu {
                    demand.gpuUsage = total; demand.gpuTemperature = temperature
                } else {
                    demand.cpuUsage = total; demand.cpuTemperature = temperature
                }
            case .ane:
                demand.power = demand.power || (shown && options.power) || pins.contains(.anePower)
            case .ram:
                let memoryPinned = !pins.isDisjoint(with: [.memoryUsage, .memoryDetails])
                demand.totalMemory = (shown && (options.totalUse || options.showsDetails)) || memoryPinned
                demand.pressure = (shown && options.showsPressure) || pins.contains(.memoryPressure)
                demand.pressureHistory = shown && options.showsPressure && options.pressureMode.resolved(for: selection.alignment).isHistory
            }
        }
        demand.power = demand.power || demand.gpuCores || (cpuCoresShown && cpuCoreMode.showsValue) || (overlay && selection.package.enabled) || pins.contains(.socPower)
        if overlay { demand.storage = selection.storage.monitoringOptions }
        demand.fans = (overlay && selection.fans.enabled) || pins.contains(.fanUsage)
        let batteryShown = overlay && selection.battery.enabled
        // Auto keeps sampling to detect returning flow; Off has no menu-bar
        // power demand, even though its selection is retained for later use.
        let batteryPowerPinned = pins.contains(.batteryPower) && selection.battery.flowMode != .off
        demand.battery = batteryShown || batteryPowerPinned || !pins.isDisjoint(with: [.batteryTemperature, .batteryEnergy])
        demand.batteryTemperature = (batteryShown && selection.battery.temperature) || pins.contains(.batteryTemperature)
        demand.batteryPower = (batteryShown && selection.battery.power) || batteryPowerPinned
        if overlay && selection.alignment == .vertical {
            demand.misc = selection.misc
            if selection.misc.visibleReadings.contains(.resolution) { demand.fps = true }
        }
        return demand
    }
}
