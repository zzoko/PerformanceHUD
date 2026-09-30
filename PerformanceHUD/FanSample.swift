import Foundation

nonisolated struct FanReading: Equatable, Sendable {
    let id: Int
    let rpm: Double?
    let maximumRPM: Double?

    var fraction: Double? {
        guard let rpm, let maximumRPM, rpm.isFinite, maximumRPM.isFinite,
              rpm >= 0, maximumRPM > 0 else { return nil }
        return min(1, rpm / maximumRPM)
    }

    var rpmText: String { rpm.map { "\(Int($0.rounded())) RPM" } ?? "" }
}

nonisolated struct FanSample: Equatable, Sendable {
    enum Status: Sendable { case checking, ready, noFans, unavailable }
    let status: Status
    let fans: [FanReading]

    static let checking = FanSample(status: .checking, fans: [])
    static let noFans = FanSample(status: .noFans, fans: [])
    static let unavailable = FanSample(status: .unavailable, fans: [])
    var canAverage: Bool { fans.count > 1 }
    var message: String? {
        switch status {
        case .checking: return "Checking fans…"
        case .noFans: return "No fans detected"
        case .unavailable: return "Fan readings unavailable"
        case .ready: return nil
        }
    }

    // Keep known rows during a read failure, but never retain a stale RPM.
    func preservingTopology(from previous: FanSample) -> FanSample {
        guard status == .unavailable, fans.isEmpty, !previous.fans.isEmpty else { return self }
        return FanSample(status: .unavailable, fans: previous.fans.map {
            FanReading(id: $0.id, rpm: nil, maximumRPM: $0.maximumRPM)
        })
    }

    func displayReadings(averaged: Bool) -> [FanDisplayReading] {
        guard averaged, canAverage else {
            return fans.map { FanDisplayReading(id: "\($0.id)", title: "FAN \($0.id + 1)",
                                               rpm: $0.rpm, fraction: $0.fraction) }
        }
        // Average each fan's normalized speed, not a ratio of average RPM/max.
        // Missing inputs must not silently turn into a partial-fan average.
        func mean(_ values: [Double?]) -> Double? {
            let valid = values.compactMap { $0 }.filter { $0.isFinite && $0 >= 0 }
            guard valid.count == fans.count else { return nil }
            return valid.reduce(0, +) / Double(valid.count)
        }
        return [FanDisplayReading(id: "average", title: "FAN AVG", rpm: mean(fans.map(\.rpm)),
                                  fraction: mean(fans.map(\.fraction)))]
    }
}

nonisolated struct FanDisplayReading: Equatable, Sendable {
    let id: String
    let title: String
    let rpm: Double?
    let fraction: Double?
    var rpmText: String { rpm.flatMap(FanDecoder.rpm).map { "\(Int($0.rounded())) RPM" } ?? "" }
}

enum HUDFanMode: String, CaseIterable {
    // Keep stored values compatible while presenting Total (bar), RPM, Both.
    case bar, rpm, both
    var title: String { self == .rpm ? "RPM" : self == .bar ? "Total" : "Both" }
    var showsRPM: Bool { self != .bar }
    var showsBar: Bool { self != .rpm }
}

struct HUDFanOptions: Equatable {
    var enabled = true
    var usage = true
    var mode: HUDFanMode = .both
    var average = true
    var averageMode: HUDFanAverageMode = .horizontal
    var rpmHighlighted = false

    func averages(in alignment: HUDAlignment) -> Bool {
        average && (averageMode == .both || averageMode.rawValue == alignment.rawValue)
    }
}

enum HUDFanAverageMode: String, CaseIterable {
    case vertical, horizontal, both
    var title: String { rawValue.capitalized }
}

/// Fan values are read from SMC metadata, not inferred from the Mac model.
nonisolated enum FanDecoder {
    static func identifiers(in keys: [String]) -> [Int] {
        Set(keys.compactMap { key -> Int? in
            let bytes = Array(key.utf8)
            guard bytes.count == 4, bytes[0] == 70, bytes[2] == 65, bytes[3] == 99 else { return nil }
            return Int(String(UnicodeScalar(bytes[1])), radix: 16)
        }).sorted()
    }

    static func number(type: String, bytes: [UInt8]) -> Double? {
        let value: Double
        switch (type, bytes.count) {
        case ("ui8 ", 1): value = Double(bytes[0])
        case ("ui16", 2): value = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case ("ui32", 4): value = Double(bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
        case ("fpe2", 2): value = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case ("flt ", 4):
            let bits = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[$1]) << (8 * $1) }
            value = Double(Float(bitPattern: bits))
        default: return nil
        }
        return value.isFinite && value >= 0 ? value : nil
    }

    static func count(_ value: Double?) -> Int? {
        // Bound corrupt sensor data; support discovery beyond today's four-fan Macs.
        guard let value, value.isFinite, value >= 0, value <= 16,
              value.rounded(.towardZero) == value else { return nil }
        return Int(value)
    }

    static func rpm(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, value <= 99_999 else { return nil }
        return value
    }
}
