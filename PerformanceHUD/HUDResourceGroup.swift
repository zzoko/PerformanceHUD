import Foundation

enum HUDResourceGroup: String, CaseIterable {
    case gpu, cpu, ram

    var title: String { rawValue.uppercased() }
    var supportsTemperature: Bool { self != .ram }
    var appMetric: HUDMetric {
        switch self { case .gpu: return .gpu; case .cpu: return .cpu; case .ram: return .ram }
    }
    var totalMetric: HUDMetric {
        switch self { case .gpu: return .gpuTotal; case .cpu: return .cpuTotal; case .ram: return .ramTotal }
    }
}

struct HUDResourceOptions: Equatable {
    var enabled: Bool
    var temperature: Bool
    var totalUse: Bool
    var focusedApp: Bool

    func visibleMetrics(for group: HUDResourceGroup) -> Set<HUDMetric> {
        guard enabled else { return [] }
        var metrics = Set<HUDMetric>()
        if focusedApp { metrics.insert(group.appMetric) }
        if totalUse || (group.supportsTemperature && temperature) { metrics.insert(group.totalMetric) }
        return metrics
    }
}
