import Foundation

enum HUDBackground: String, CaseIterable {
    case transparent
    case light
    case dark
    case system
    case off

    // Off remains supported in code; uncomment its entry to restore the menu option.
    static let menuOptions: [HUDBackground] = [
        .transparent, .light, .dark,
        // .off,
    ]

    var menuTitle: String {
        switch self {
        case .transparent: return "Clear"
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "Follow system"
        case .off: return "Off"
        }
    }

    func resolved(isDark: Bool) -> HUDBackground {
        self == .system ? (isDark ? .dark : .light) : self
    }
}
