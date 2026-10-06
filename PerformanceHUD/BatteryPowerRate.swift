import Foundation

/// Presentation only: preserve real readings for logging, including idle zeros.
/// Separate show/hide thresholds and a short idle delay avoid flicker near zero.
nonisolated struct BatteryFlowVisibility {
    private(set) var isVisible = false
    private var idleSince: TimeInterval?

    mutating func update(power: Double?, now: TimeInterval) {
        guard let power, let valid = BatteryPowerRate.valid(power) else {
            self = Self()
            return
        }
        let magnitude = abs(valid)
        if magnitude >= 0.2 {
            isVisible = true
            idleSince = nil
        } else if magnitude <= 0.1, isVisible {
            if idleSince == nil { idleSince = now }
            if let idleSince, now - idleSince >= 3 { isVisible = false }
        } else {
            idleSince = nil
        }
    }
}

/// Battery terminal power, not adapter output or CPU/GPU package power.
/// IOPMPowerSource defines Voltage in mV and signed Amperage in mA:
/// https://github.com/apple-oss-distributions/xnu/blob/main/iokit/IOKit/pwr_mgt/IOPMPowerSource.h
nonisolated enum BatteryPowerRate {
    static func watts(controller: [String: Any]?) -> Double? {
        guard let controller else { return nil }
        let voltage = controller["Voltage"] as? NSNumber
        return watts(voltage: voltage, amperage: controller["InstantAmperage"] as? NSNumber)
            ?? watts(voltage: voltage, amperage: controller["Amperage"] as? NSNumber)
    }

    // Apple silicon B0AV is unsigned millivolts and B0AC is signed milliamps,
    // both little-endian. Their sign already matches positive in / negative out.
    // These units are also documented in Linux's macsmc-power driver.
    static func watts(smcVoltage: (type: UInt32, bytes: [UInt8]),
                      smcAmperage: (type: UInt32, bytes: [UInt8])) -> Double? {
        guard smcVoltage.type == SMCTemperatureReader.fourCC("ui16"), smcVoltage.bytes.count == 2,
              smcAmperage.type == SMCTemperatureReader.fourCC("si16"), smcAmperage.bytes.count == 2 else { return nil }
        let millivolts = UInt16(smcVoltage.bytes[0]) | UInt16(smcVoltage.bytes[1]) << 8
        let currentBits = UInt16(smcAmperage.bytes[0]) | UInt16(smcAmperage.bytes[1]) << 8
        return watts(voltage: NSNumber(value: millivolts), amperage: NSNumber(value: Int16(bitPattern: currentBits)))
    }

    static func watts(voltage: NSNumber?, amperage: NSNumber?) -> Double? {
        guard let voltage, let amperage,
              CFGetTypeID(voltage) != CFBooleanGetTypeID(),
              CFGetTypeID(amperage) != CFBooleanGetTypeID() else { return nil }
        let millivolts = voltage.doubleValue
        let rawCurrent = amperage.doubleValue
        guard millivolts.isFinite, (1...60_000).contains(millivolts),
              rawCurrent.isFinite, rawCurrent.rounded() == rawCurrent else { return nil }
        let milliamps: Double
        if abs(rawCurrent) <= 100_000 {
            milliamps = rawCurrent
        } else if let bits = UInt64(amperage.stringValue) {
            // IORegistry can expose negative current as an unsigned 32- or
            // 64-bit two's-complement number. Decode before converting to W.
            let signed = bits <= UInt32.max ? Int64(Int32(bitPattern: UInt32(bits))) : Int64(bitPattern: bits)
            guard (-100_000...100_000).contains(signed) else { return nil }
            milliamps = Double(signed)
        } else { return nil }
        return valid(millivolts * milliamps / 1_000_000)
    }

    static func valid(_ watts: Double) -> Double? {
        // Reject invalid controller values, allowing ample headroom for laptops.
        watts.isFinite && abs(watts) <= 1_000 ? watts : nil
    }

    static func text(_ watts: Double?) -> String {
        guard let watts, let value = valid(watts) else { return "" }
        let rounded = (value * 10).rounded() / 10
        // Do not display a misleading positive/negative zero after rounding.
        return rounded == 0 ? "0.0 W"
            : String(format: "%.1f W", locale: Locale(identifier: "en_US_POSIX"), rounded)
    }
}
