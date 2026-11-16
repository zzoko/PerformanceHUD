import Foundation

nonisolated struct PowerSample: Sendable {
    let cpu: Double?
    let gpu: Double?
    let package: Double?
    var ane: Double? = nil
    var cpuFrequencies = CPUFrequencySample.unavailable
    var gpuFrequency: Double? = nil
    static let unavailable = PowerSample(cpu: nil, gpu: nil, package: nil)
}

@MainActor
final class PowerMonitor {
    var onUpdate: ((PowerSample) -> Void)?
    let helper = PowerHelperClient()

    init() {
        helper.onUpdate = { [weak self] reading in
            guard let reading else { self?.onUpdate?(.unavailable); return }
            self?.onUpdate?(PowerSample(cpu: reading.cpu, gpu: reading.gpu, package: reading.package, ane: reading.ane, cpuFrequencies: reading.cpuFrequencies, gpuFrequency: reading.gpuFrequency))
        }
    }

    func configure(enabled: Bool) { helper.configure(enabled: enabled) }
    func stop() { helper.stop() }
}
