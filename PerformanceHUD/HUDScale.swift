import Foundation

enum HUDScale: Double, CaseIterable, Hashable {

    case normal = 1.0
    case large = 1.25
    case extraLarge = 1.5

    var menuTitle: String {

        switch self {

        case .normal:
            return "1x"

        case .large:
            return "1.25x"

        case .extraLarge:
            return "1.5x"
        }
    }
}
