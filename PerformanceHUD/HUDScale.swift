import Foundation

struct HUDScale: RawRepresentable, CaseIterable, Hashable {
    static let minimum = 0.5
    static let maximum = 2.0
    static let step = 0.01

    static let small = HUDScale(rawValue: minimum)
    static let normal = HUDScale(rawValue: 1)
    static let large = HUDScale(rawValue: maximum)
    static let allCases = (0...Int(((maximum - minimum) / step).rounded())).map {
        HUDScale(rawValue: minimum + Double($0) * step)
    }

    let rawValue: Double

    init(rawValue: Double) {
        let value = rawValue.isFinite ? min(Self.maximum, max(Self.minimum, rawValue)) : 1
        // Canonical hundredths keep slider steps and saved preferences identical.
        let stepped = Self.minimum + ((value - Self.minimum) / Self.step).rounded() * Self.step
        self.rawValue = (stepped * 100).rounded() / 100
    }

    var menuTitle: String {
        String(format: "%g×", locale: Locale(identifier: "en_US_POSIX"), rawValue)
    }
}
