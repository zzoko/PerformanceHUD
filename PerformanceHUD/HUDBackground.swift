import Foundation

enum HUDBackground: String, CaseIterable {
    case transparent
    case light
    case dark
    case off

    // Off remains supported in code; uncomment its entry to restore the menu option.
    static let menuOptions: [HUDBackground] = [
        .transparent, .light, .dark,
        // .off,
    ]

    var menuTitle: String {
        switch self {
        case .transparent: return "Transparent"
        case .light: return "Light"
        case .dark: return "Dark"
        case .off: return "Off"
        }
    }
}
