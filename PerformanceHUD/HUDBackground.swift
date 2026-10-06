import Foundation

enum HUDBackground: String, CaseIterable {
    case light
    case dark
    case system

    static let menuOptions: [HUDBackground] = [.light, .dark]

    var next: HUDBackground {
        switch self {
        case .light: return .dark
        case .dark: return .system
        case .system: return .light
        }
    }

    var menuTitle: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "Follow system"
        }
    }

    func resolved(isDark: Bool) -> HUDBackground {
        self == .system ? (isDark ? .dark : .light) : self
    }
}
