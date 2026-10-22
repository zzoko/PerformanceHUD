import Foundation

enum HUDBuiltInPreset: String, CaseIterable, Codable {
    case fpsOnly, balanced, full

    var title: String {
        switch self {
        case .fpsOnly: return "FPS"
        case .balanced: return "Balanced"
        case .full: return "Detailed"
        }
    }
}

struct HUDPresetAvailability {
    var fansAvailable = true
    var powerAvailable = true
}

/// Category and reading choices from the scrollable menu section.
/// Layout, appearance, Auto hide, and app settings remain independent.
struct HUDPresetConfiguration: Codable, Equatable {
    var fps: HUDFPSOptions
    var resources: [HUDResourceGroup: HUDResourceOptions]
    var packagePower: HUDPackagePowerOptions
    var fans: HUDFanOptions
    var battery: HUDBatteryOptions
    var misc: HUDMiscOptions
    var deviceInfo: Bool
    var menuBarReadings: Set<HUDMenuBarReading> = []

    private enum CodingKeys: String, CodingKey {
        case fps, resources, packagePower, fans, battery, misc, deviceInfo, menuBarReadings
    }

    static func capture(in store: UserDefaults = .standard) -> Self {
        Self(fps: HUDPreferences.fpsOptions(in: store),
             resources: Dictionary(uniqueKeysWithValues: HUDResourceGroup.allCases.map {
                 ($0, HUDPreferences.resourceOptions(for: $0, in: store))
             }),
             packagePower: HUDPreferences.packagePowerOptions(in: store),
             fans: HUDPreferences.fanOptions(in: store),
             battery: HUDPreferences.batteryOptions(in: store),
             misc: HUDPreferences.miscOptions(in: store),
             deviceInfo: HUDPreferences.isMetricEnabled(.deviceInfo, in: store),
             menuBarReadings: HUDMenuBarOptions.load(in: store).readings)
            .canonicalized()
    }

    func apply(in store: UserDefaults = .standard) {
        guard isValid else { return }
        let configuration = canonicalized()
        HUDPreferences.setFPSOptions(configuration.fps, in: store)
        for group in HUDResourceGroup.allCases {
            if let options = configuration.resources[group] {
                HUDPreferences.setResourceOptions(options, for: group, in: store)
            }
        }
        HUDPreferences.setPackagePowerOptions(configuration.packagePower, in: store)
        HUDPreferences.setFanOptions(configuration.fans, in: store)
        HUDPreferences.setBatteryOptions(configuration.battery, in: store)
        HUDPreferences.setMiscOptions(configuration.misc, in: store)
        HUDPreferences.setMetricEnabled(.deviceInfo, enabled: configuration.deviceInfo, in: store)
        var menuBar = HUDMenuBarOptions.load(in: store)
        menuBar.readings = configuration.menuBarReadings
        menuBar.save(in: store)
    }

    static func builtIn(_ preset: HUDBuiltInPreset) -> Self {
        // These are the same resolved defaults as a fresh preferences domain.
        // Keep built-ins independent of the current user's settings and display.
        var configuration = Self(
            fps: HUDFPSOptions(enabled: true, mode: .both),
            resources: Dictionary(uniqueKeysWithValues: HUDResourceGroup.allCases.map { group in
                (group, HUDResourceOptions(enabled: true, temperature: group.supportsTemperature,
                    totalUse: group.supportsTotalUse, focusedApp: false, power: group.supportsPower,
                    usageMode: .total))
            }),
            packagePower: .init(), fans: .init(),
            battery: .init(enabled: true, temperature: true, charge: true),
            misc: .init(), deviceInfo: false)
        switch preset {
        case .balanced: break
        case .fpsOnly:
            configuration.fps.mode = .value
            for group in HUDResourceGroup.allCases { configuration.resources[group]?.enabled = false }
            configuration.packagePower.enabled = false
            configuration.fans.enabled = false
            configuration.battery.enabled = false
            configuration.misc.enabled = false
            configuration.deviceInfo = false
        case .full:
            for group in [HUDResourceGroup.gpu, .cpu, .ram] {
                configuration.resources[group]?.selectUsageMode(.both)
            }
            configuration.misc.enabled = true
            configuration.deviceInfo = true
        }
        return configuration.canonicalized()
    }

    func matches(_ other: Self, availability: HUDPresetAvailability = .init()) -> Bool {
        func comparable(_ source: Self) -> Self {
            var result = source.canonicalized()
            if !availability.fansAvailable {
                result.fans.enabled = false
                result.menuBarReadings.remove(.fanUsage)
            }
            if !availability.powerAvailable {
                result.packagePower.enabled = false
                for group in HUDResourceGroup.allCases where group.supportsPower {
                    result.resources[group]?.power = false
                }
            }
            return result
        }
        return comparable(self) == comparable(other)
    }

    var isValid: Bool {
        guard resources.count == HUDResourceGroup.allCases.count,
              HUDResourceGroup.allCases.allSatisfy({ resources[$0] != nil }),
              HUDHeatWarningOptions.allowedThresholds.contains(battery.heatWarning.thresholdCelsius)
        else { return false }
        return resources.values.allSatisfy {
            HUDHeatWarningOptions.allowedThresholds.contains($0.heatWarning.thresholdCelsius)
        }
    }

    private func canonicalized() -> Self {
        var result = self
        for group in HUDResourceGroup.allCases {
            guard var options = result.resources[group] else { continue }
            options.setUsagePresentation(visible: options.usageVisible, highlighted: options.usageHighlighted)
            options.temperature = group.supportsTemperature && options.temperature
            options.power = group.supportsPower && options.power
            if group != .ram {
                // RAM options share legacy preference keys; they are not GPU,
                // CPU or ANE display choices and must not leak into snapshots.
                options.details = true
                options.pressure = true
                options.pressureMode = .colorHistory
                options.pressureGraphStyle = .colorHistory
            } else {
                options.pressureGraphStyle = options.selectedPressureGraphStyle
            }
            result.resources[group] = options
        }
        return result
    }
}

extension HUDPresetConfiguration {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fps = try values.decode(HUDFPSOptions.self, forKey: .fps)
        resources = try values.decode([HUDResourceGroup: HUDResourceOptions].self, forKey: .resources)
        packagePower = try values.decode(HUDPackagePowerOptions.self, forKey: .packagePower)
        fans = try values.decode(HUDFanOptions.self, forKey: .fans)
        battery = try values.decode(HUDBatteryOptions.self, forKey: .battery)
        misc = try values.decode(HUDMiscOptions.self, forKey: .misc)
        deviceInfo = try values.decode(Bool.self, forKey: .deviceInfo)
        // Presets saved before menu-bar readings existed retain an all-off selection.
        menuBarReadings = try values.decodeIfPresent(Set<HUDMenuBarReading>.self, forKey: .menuBarReadings) ?? []
    }
}

struct HUDSavedPreset: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var configuration: HUDPresetConfiguration
}

enum HUDPresetSelection: Equatable {
    case builtIn(HUDBuiltInPreset)
    case saved(UUID, String)
    case custom

    var title: String {
        switch self {
        case .builtIn(let preset): return preset.title
        case .saved(_, let name): return name
        case .custom: return "Custom"
        }
    }
}

enum HUDPresetStoreError: LocalizedError {
    case emptyName, nameTooLong, invalidName, reservedName, duplicateName
    case notFound, invalidConfiguration, storageFailure

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name for this preset."
        case .nameTooLong: return "Use a name with no more than 60 characters."
        case .invalidName: return "Use a single line for the preset name."
        case .reservedName: return "Choose a name other than FPS, Balanced, Detailed or Custom."
        case .duplicateName: return "A saved preset already has this name."
        case .notFound: return "This saved preset is no longer available."
        case .invalidConfiguration: return "These HUD settings could not be saved as a preset."
        case .storageFailure: return "The preset could not be saved."
        }
    }
}

struct HUDPresetStore {
    private let defaults: UserDefaults
    private static let savedKey = "hud.presets.saved"
    private static let preferredKey = "hud.presets.preferredSavedID"

    init(in store: UserDefaults = .standard) { defaults = store }

    // Each record is independent: a damaged entry cannot discard the others.
    private var records: [Any] { defaults.array(forKey: Self.savedKey) ?? [] }

    var savedPresets: [HUDSavedPreset] {
        var identifiers = Set<UUID>()
        var names = Set<String>()
        return records.compactMap { record in
            guard let preset = decode(record), identifiers.insert(preset.id).inserted,
                  names.insert(Self.comparisonName(preset.name)).inserted else { return nil }
            return preset
        }
    }

    var preferredSavedID: UUID? {
        get { defaults.string(forKey: Self.preferredKey).flatMap(UUID.init(uuidString:)) }
        nonmutating set {
            if let newValue { defaults.set(newValue.uuidString, forKey: Self.preferredKey) }
            else { defaults.removeObject(forKey: Self.preferredKey) }
        }
    }

    @discardableResult
    func add(name: String, configuration: HUDPresetConfiguration) throws -> HUDSavedPreset {
        let name = try validatedName(name)
        guard configuration.isValid else { throw HUDPresetStoreError.invalidConfiguration }
        let preset = HUDSavedPreset(id: UUID(), name: name, configuration: configuration)
        var records = records
        records.append(try encoded(preset))
        defaults.set(records, forKey: Self.savedKey)
        preferredSavedID = preset.id
        return preset
    }

    func rename(id: UUID, name: String) throws {
        let name = try validatedName(name, excluding: id)
        var records = records
        guard let index = records.firstIndex(where: { decode($0)?.id == id }),
              var preset = decode(records[index]) else { throw HUDPresetStoreError.notFound }
        preset.name = name
        records[index] = try encoded(preset)
        defaults.set(records, forKey: Self.savedKey)
    }

    func delete(id: UUID) {
        defaults.set(records.filter { decode($0)?.id != id }, forKey: Self.savedKey)
        if preferredSavedID == id { preferredSavedID = nil }
    }

    func selection(for configuration: HUDPresetConfiguration,
                   availability: HUDPresetAvailability = .init()) -> HUDPresetSelection {
        let saved = savedPresets
        if let preferred = saved.first(where: { $0.id == preferredSavedID }),
           configuration.matches(preferred.configuration, availability: availability) {
            return .saved(preferred.id, preferred.name)
        }
        if let builtIn = HUDBuiltInPreset.allCases.first(where: {
            configuration.matches(.builtIn($0), availability: availability)
        }) { return .builtIn(builtIn) }
        if let matching = saved.first(where: { configuration.matches($0.configuration, availability: availability) }) {
            return .saved(matching.id, matching.name)
        }
        return .custom
    }

    private func validatedName(_ name: String, excluding id: UUID? = nil) throws -> String {
        let name = try Self.cleanName(name)
        let comparison = Self.comparisonName(name)
        guard !savedPresets.contains(where: { $0.id != id && Self.comparisonName($0.name) == comparison })
        else { throw HUDPresetStoreError.duplicateName }
        return name
    }

    private static func cleanName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw HUDPresetStoreError.emptyName }
        guard name.count <= 60 else { throw HUDPresetStoreError.nameTooLong }
        guard name.rangeOfCharacter(from: .controlCharacters) == nil else { throw HUDPresetStoreError.invalidName }
        let reserved = HUDBuiltInPreset.allCases.map(\.title) + ["Custom"]
        guard !reserved.contains(where: { comparisonName($0) == comparisonName(name) })
        else { throw HUDPresetStoreError.reservedName }
        return name
    }

    private static func comparisonName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private func decode(_ record: Any) -> HUDSavedPreset? {
        guard let data = record as? Data,
              let preset = try? JSONDecoder().decode(HUDSavedPreset.self, from: data),
              preset.configuration.isValid,
              (try? Self.cleanName(preset.name)) == preset.name else { return nil }
        return preset
    }

    private func encoded(_ preset: HUDSavedPreset) throws -> Data {
        guard let data = try? JSONEncoder().encode(preset) else { throw HUDPresetStoreError.storageFailure }
        return data
    }
}
