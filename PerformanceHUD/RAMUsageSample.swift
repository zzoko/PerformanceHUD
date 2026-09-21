import Foundation

/// Percent and bytes from the same memory reading; GB is never inferred from rounded percent.
nonisolated struct RAMUsageSample: Sendable {
    let percentage: Double
    let usedBytes: UInt64
    let swapUsedBytes: UInt64?

    init(percentage: Double, usedBytes: UInt64, swapUsedBytes: UInt64? = nil) {
        self.percentage = percentage
        self.usedBytes = usedBytes
        self.swapUsedBytes = swapUsedBytes
    }

    var swapGigabytesText: String? {
        swapUsedBytes.map { String(format: "%.2f GB", Double($0) / 1_073_741_824) }
    }

    var gigabytesText: String {
        // Memory uses 1024-based units, matching macOS memory reporting conventions.
        String(format: "%.2f GB", Double(usedBytes) / 1_073_741_824)
    }
}
