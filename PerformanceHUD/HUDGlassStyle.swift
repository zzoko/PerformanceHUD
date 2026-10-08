import AppKit

enum HUDGlassMode: String {
    case strength, system
}

struct HUDGlassOptions: Equatable {
    var mode: HUDGlassMode = .system
    var strength: Double?

    func resolvedStrength(system: Double) -> Double {
        Self.clamped(mode == .strength ? (strength ?? system) : system)
    }

    mutating func select(_ mode: HUDGlassMode, system: Double) {
        if mode == .strength, strength == nil { strength = Self.clamped(system) }
        self.mode = mode
    }

    static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}

/// Applies the native material preference to this process only.
@MainActor
enum HUDGlassStyle {
    // Undocumented AppKit preference and refresh notification, verified on macOS 27.
    // Keep the override in memory: never write the macOS global preference domain.
    static let nativeKey = "NSGlassTintAmount"
    static let didChangeNotification = Notification.Name("NSGlassEffectDiffusionDidChangeNotification")

    static func systemStrength(in defaults: UserDefaults = .standard) -> Double {
        let value = defaults.persistentDomain(forName: UserDefaults.globalDomain)?[nativeKey] as? NSNumber
        return HUDGlassOptions.clamped(value?.doubleValue ?? 0)
    }

    static func apply(_ options: HUDGlassOptions, in defaults: UserDefaults = .standard) {
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        let previous = (arguments[nativeKey] as? NSNumber)?.doubleValue
        let next: Double? = options.mode == .strength
            ? options.resolvedStrength(system: systemStrength(in: defaults)) : nil
        guard previous != next else { return }
        if let next { arguments[nativeKey] = next }
        else { arguments.removeValue(forKey: nativeKey) }
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        // Re-evaluate existing glass without replacing the window or stopping monitoring.
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
