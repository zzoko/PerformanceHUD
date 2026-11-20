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

    static func make(hudEnabled: Bool, hudVisible: Bool, recordingColumns: Set<HUDLogColumn> = [],
                     autoHideMode: HUDAutoHideMode, selection: HUDLogSelection,
                     menuBar: HUDMenuBarOptions) -> Self {
        var demand = Self()
        let overlay = hudEnabled && hudVisible
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
        if !overlay && !recordingColumns.isEmpty {
            demand.includeRecording(recordingColumns, storageLocation: selection.storage.location)
        }
        return demand
    }

    // The CSV captures values, so it needs neither graph history nor the FPS
    // detector solely used to wake an automatically hidden overlay.
    private mutating func includeRecording(_ columns: Set<HUDLogColumn>, storageLocation: HUDStorageLocation) {
        var recordedMisc = Set<HUDMiscReading>()
        for column in columns {
            switch column {
            case .fps, .frameTimeAverage, .frameTimeWorst: fps = true
            case .gpuUsage: gpuUsage = true
            case .cpuUsage: cpuUsage = true
            case .gpuAppUsage: gpuAppUsage = true
            case .cpuAppUsage: cpuAppUsage = true
            case .gpuTemperature: gpuTemperature = true
            case .cpuTemperature: cpuTemperature = true
            case .cpuCoreUsage: cpuCores = true
            case .gpuFrequency: gpuCores = true; power = true
            case .gpuPower, .cpuPower, .anePower, .socPower, .cpuTypeFrequency: power = true
            case .memoryUsage, .memoryPhysical, .memorySwap: totalMemory = true
            case .memoryAppUsage, .memoryAppPhysical: appMemory = true
            case .memoryPressure: pressure = true
            case .fanUsage, .fanRPM, .fanAverageUsage, .fanAverageRPM: fans = true
            case .storageFree:
                if storage == nil { storage = .init(enabled: true, location: storageLocation, details: false) }
            case .storageRead, .storageWrite: storage = .init(enabled: true, location: storageLocation, details: true)
            case .powerSource, .batteryCharge, .lowPowerMode: battery = true
            case .batteryTemperature: battery = true; batteryTemperature = true
            case .batteryPower: battery = true; batteryPower = true
            case .resolutionWidth, .resolutionHeight: fps = true; recordedMisc.insert(.resolution)
            case .refreshMinimum, .refreshMaximum: recordedMisc.insert(.refreshRate)
            case .gameMode: recordedMisc.insert(.gameMode)
            case .thermal: recordedMisc.insert(.thermal)
            case .process, .os, .chip, .cpuCores, .cpuEfficiencyCores, .cpuPerformanceCores, .cpuSuperCores, .gpuCores:
                break // Supplied by focus events or static device information.
            }
        }
        misc = .init(enabled: !recordedMisc.isEmpty, readings: recordedMisc)
    }
}
