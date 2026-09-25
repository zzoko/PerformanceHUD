import Foundation

struct HUDScale: RawRepresentable, CaseIterable, Hashable {
    static let minimum = 0.75
    static let maximum = 1.25
    static let step = 0.05

    static let small = HUDScale(rawValue: minimum)
    static let normal = HUDScale(rawValue: 1)
    static let large = HUDScale(rawValue: maximum)
    static let allCases = (0...10).map { HUDScale(rawValue: minimum + Double($0) * step) }

    let rawValue: Double

    init(rawValue: Double) {
        let value = rawValue.isFinite ? min(Self.maximum, max(Self.minimum, rawValue)) : 1
        // Canonical hundredths keep slider steps and saved preferences identical.
        self.rawValue = ((value * 100 / 5).rounded() * 5) / 100
    }

    var menuTitle: String {
        String(format: "%g×", locale: Locale(identifier: "en_US_POSIX"), rawValue)
    }
}
