import Foundation

/// Stable column identities, independent of fonts, formatting, and changing values.
enum HUDLogColumn: Hashable {
    case fps, gpuPower, gpuTemperature, gpuUsage, gpuAppUsage
    case cpuPower, cpuTemperature, cpuUsage, cpuAppUsage, anePower, socPower
    case memoryUsage, memoryPhysical, memorySwap, memoryPressure, memoryAppUsage, memoryAppPhysical
    case fanUsage(Int), fanRPM(Int), fanAverageUsage, fanAverageRPM
    case powerSource, batteryPower, batteryTemperature, batteryCharge, lowPowerMode, chip, os
    case process, resolutionWidth, resolutionHeight, refreshMinimum, refreshMaximum, gameMode, thermal

    var title: String {
        switch self {
        case .fps: return "FPS"
        case .gpuPower: return "GPU Power (W)"
        case .gpuTemperature: return "GPU Temperature (°C)"
        case .gpuUsage: return "GPU Usage (%)"
        case .gpuAppUsage: return "GPU App Usage (%)"
        case .cpuPower: return "CPU Power (W)"
        case .cpuTemperature: return "CPU Temperature (°C)"
        case .cpuUsage: return "CPU Usage (%)"
        case .cpuAppUsage: return "CPU App Usage (%)"
        case .anePower: return "ANE Power (W)"
        case .socPower: return "SOC Power (W)"
        case .memoryUsage: return "Memory Usage (%)"
        case .memoryPhysical: return "Memory Physical (GiB)"
        case .memorySwap: return "Memory Swap (GiB)"
        case .memoryPressure: return "Memory Pressure"
        case .memoryAppUsage: return "Memory App Usage (%)"
        case .memoryAppPhysical: return "Memory App Physical (GiB)"
        case .fanUsage(let id): return "Fan \(id + 1) Usage (%)"
        case .fanRPM(let id): return "Fan \(id + 1) RPM"
        case .fanAverageUsage: return "Fan Average Usage (%)"
        case .fanAverageRPM: return "Fan Average RPM"
        case .powerSource: return "Power Source"
        case .batteryPower: return "Battery Net Power (W)"
        case .batteryTemperature: return "Battery Temperature (°C)"
        case .batteryCharge: return "Battery Charge (%)"
        case .lowPowerMode: return "Low Power Mode (0/1)"
        case .chip: return "Chip"
        case .os: return "macOS"
        case .process: return "Process"
        case .resolutionWidth: return "Resolution Width (px)"
        case .resolutionHeight: return "Resolution Height (px)"
        case .refreshMinimum: return "Display Refresh Min (Hz)"
        case .refreshMaximum: return "Display Refresh Max (Hz)"
        case .gameMode: return "Game Mode (0/1)"
        case .thermal: return "Thermal State"
        }
    }

    private static let csvLocale = Locale(identifier: "en_US_POSIX")

    func formattedNumber(_ number: Double) -> String? {
        guard number.isFinite else { return nil }
        let places: Int
        switch self {
        case .fps, .gpuPower, .cpuPower, .anePower, .socPower, .batteryPower,
             .memoryPhysical, .memorySwap, .memoryAppPhysical, .refreshMinimum, .refreshMaximum:
            places = 2
        case .gpuTemperature, .cpuTemperature, .batteryTemperature,
             .gpuUsage, .gpuAppUsage, .cpuUsage, .cpuAppUsage,
             .memoryUsage, .memoryAppUsage, .fanUsage, .fanAverageUsage, .batteryCharge:
            places = 1
        case .fanRPM, .fanAverageRPM, .lowPowerMode, .resolutionWidth, .resolutionHeight, .gameMode:
            places = 0
        case .memoryPressure, .powerSource, .chip, .os, .process, .thermal:
            return nil
        }
        // Keep CSV numbers parseable regardless of the Mac's decimal separator.
        return String(format: "%.*f", locale: Self.csvLocale, places, number)
    }

    var isFan: Bool {
        switch self {
        case .fanUsage, .fanRPM, .fanAverageUsage, .fanAverageRPM: return true
        default: return false
        }
    }
}

/// Take a selection snapshot at Start. Later selection changes only blank cells;
/// adding columns halfway through a CSV would make it unsuitable for graphing.
struct HUDLogSelection {
    var fps: Bool
    var resources: [HUDResourceGroup: HUDResourceOptions]
    var package: HUDPackagePowerOptions
    var fans: HUDFanOptions
    var battery: HUDBatteryOptions
    var deviceInfo: Bool
    var alignment: HUDAlignment
    var misc = HUDMiscOptions()

    static var current: Self {
        Self(fps: HUDPreferences.fpsOptions.enabled,
             resources: Dictionary(uniqueKeysWithValues: HUDResourceGroup.allCases.map {
                 ($0, HUDPreferences.resourceOptions(for: $0))
             }), package: HUDPreferences.packagePowerOptions, fans: HUDPreferences.fanOptions,
             battery: HUDPreferences.batteryOptions,
             deviceInfo: HUDPreferences.visibleMetrics.contains(.deviceInfo),
             alignment: HUDPreferences.alignment, misc: HUDPreferences.miscOptions)
    }

    func columns(fanSample: FanSample) -> [HUDLogColumn] {
        var result: [HUDLogColumn] = fps ? [.fps] : []
        for group in [HUDResourceGroup.gpu, .cpu, .ane] {
            guard let options = resources[group], options.enabled else { continue }
            if group == .ane {
                if options.power { result.append(.anePower) }
                continue
            }
            let gpu = group == .gpu
            if options.power { result.append(gpu ? .gpuPower : .cpuPower) }
            if options.temperature { result.append(gpu ? .gpuTemperature : .cpuTemperature) }
            if options.totalUse { result.append(gpu ? .gpuUsage : .cpuUsage) }
            if options.focusedApp { result.append(gpu ? .gpuAppUsage : .cpuAppUsage) }
        }
        if package.enabled { result.append(.socPower) }
        if let memory = resources[.ram], memory.enabled {
            // The menu places Details before Usage; Total precedes App in Both.
            if memory.showsDetails {
                if memory.selectedUsageMode != .app { result += [.memoryPhysical, .memorySwap, .memoryPressure] }
                if memory.selectedUsageMode != .total { result.append(.memoryAppPhysical) }
            }
            if memory.totalUse { result.append(.memoryUsage) }
            if memory.focusedApp { result.append(.memoryAppUsage) }
        }
        if fans.enabled && fans.usage {
            if fans.averages(in: alignment) && fanSample.canAverage {
                if fans.mode.showsBar { result.append(.fanAverageUsage) }
                if fans.mode.showsRPM { result.append(.fanAverageRPM) }
            } else {
                for fan in fanSample.fans.sorted(by: { $0.id < $1.id }) {
                    if fans.mode.showsBar { result.append(.fanUsage(fan.id)) }
                    if fans.mode.showsRPM { result.append(.fanRPM(fan.id)) }
                }
            }
        }
        if battery.enabled {
            result.append(.powerSource)
            if battery.power { result.append(.batteryPower) }
            if battery.temperature { result.append(.batteryTemperature) }
            if battery.charge { result += [.batteryCharge, .lowPowerMode] }
        }
        for reading in misc.visibleReadings where alignment == .vertical {
            switch reading {
            case .process: result.append(.process)
            case .resolution: result += [.resolutionWidth, .resolutionHeight]
            case .refreshRate: result += [.refreshMinimum, .refreshMaximum]
            case .gameMode: result.append(.gameMode)
            case .thermal: result.append(.thermal)
            }
        }
        if deviceInfo && alignment == .vertical { result += [.chip, .os] }
        return result
    }
}

/// Values come directly from the same monitor callbacks as the HUD, never from
/// rounded display strings. Missing/non-finite values remain empty, not zero.
struct HUDLogSnapshot {
    private(set) var values: [HUDLogColumn: String] = [:]

    mutating func set(_ column: HUDLogColumn, _ number: Double?) {
        values[column] = number.flatMap { column.formattedNumber($0) }
    }

    mutating func setText(_ column: HUDLogColumn, _ text: String?) { values[column] = text }

    mutating func clear(_ columns: [HUDLogColumn]) {
        for column in columns { values[column] = nil }
    }

    mutating func updatePower(_ sample: PowerSample) {
        set(.cpuPower, sample.cpu); set(.gpuPower, sample.gpu)
        set(.anePower, sample.ane); set(.socPower, sample.package)
    }

    mutating func updateMemory(_ sample: RAMUsageSample?, app: Bool) {
        set(app ? .memoryAppUsage : .memoryUsage, sample?.percentage)
        set(app ? .memoryAppPhysical : .memoryPhysical, sample.map { Double($0.usedBytes) / 1_073_741_824 })
        if !app { set(.memorySwap, sample?.swapUsedBytes.map { Double($0) / 1_073_741_824 }) }
    }

    mutating func updateFans(_ sample: FanSample) {
        values = values.filter { !$0.key.isFan }
        guard sample.status == .ready else { return }
        for fan in sample.fans {
            set(.fanUsage(fan.id), fan.fraction.map { $0 * 100 })
            set(.fanRPM(fan.id), fan.rpm)
        }
        if sample.canAverage, let average = sample.displayReadings(averaged: true).first {
            set(.fanAverageUsage, average.fraction.map { $0 * 100 })
            set(.fanAverageRPM, average.rpm)
        }
    }

    mutating func updateBattery(_ sample: BatterySample?) {
        setText(.powerSource, sample?.source?.rawValue)
        set(.batteryPower, sample?.power)
        set(.batteryTemperature, sample?.temperature)
        set(.batteryCharge, sample?.percentage)
    }

    mutating func updateMisc(_ sample: HUDMiscSample) {
        setText(.process, sample.process)
        set(.resolutionWidth, sample.resolution.map { Double($0.width) })
        set(.resolutionHeight, sample.resolution.map { Double($0.height) })
        set(.refreshMinimum, sample.refreshRate?.minimum)
        set(.refreshMaximum, sample.refreshRate?.maximum)
        set(.gameMode, sample.gameMode.map { $0 ? 1 : 0 })
        setText(.thermal, sample.thermal)
    }
}
