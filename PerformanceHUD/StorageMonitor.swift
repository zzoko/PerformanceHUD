import Foundation
import DiskArbitration
import IOKit

nonisolated enum HUDStorageLocation: String, CaseIterable, Codable, Sendable {
    case `internal`, external, both

    func includes(internalDrive: Bool) -> Bool {
        self == .both || (internalDrive ? self == .internal : self == .external)
    }
}

nonisolated struct HUDStorageOptions: Codable, Equatable, Sendable {
    var enabled = false
    var location: HUDStorageLocation = .both
    var details = true
    var freeSpaceHighlighted = false
    var detailsHighlighted = false

    var monitoringOptions: Self? {
        enabled ? Self(enabled: true, location: location, details: details) : nil
    }
}

extension HUDStorageOptions {
    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        location = try values.decode(HUDStorageLocation.self, forKey: .location)
        details = try values.decode(Bool.self, forKey: .details)
        freeSpaceHighlighted = try values.decodeIfPresent(Bool.self, forKey: .freeSpaceHighlighted) ?? false
        detailsHighlighted = try values.decodeIfPresent(Bool.self, forKey: .detailsHighlighted) ?? false
    }
}

nonisolated struct StorageDrive: Equatable, Sendable {
    let id: UInt64
    let name: String
    let internalDrive: Bool
    let freeBytes: Int64?
    var readMBps: Double?
    var writeMBps: Double?

    var freeText: String {
        guard let freeBytes, freeBytes >= 0 else { return "" }
        guard freeBytes >= 1000 else { return "\(freeBytes) B free" }
        var amount = Decimal(freeBytes) / 1000
        var unit = "kB"
        for nextUnit in ["MB", "GB", "TB", "PB", "EB"] {
            // At three significant digits, 999.5 rounds up to 1.00 of the next unit.
            guard amount >= 999.5 else { break }
            amount = max(1, amount / 1000)
            unit = nextUnit
        }
        let number = amount.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))
            .grouping(.never).precision(.significantDigits(3)))
        return "\(number) \(unit) free"
    }

    static func rateText(_ rate: Double?) -> String {
        guard let rate else { return "" }
        return rate >= 1000 ? String(format: "%.2f GB/s", rate / 1000) : String(format: "%.1f MB/s", rate)
    }
}

/// Queue-confined by MetricPoller. Refresh mounts/free space less often than the two I/O counters.
nonisolated final class StorageSampler: @unchecked Sendable {
    struct Volume {
        let driveID: UInt64
        let driverID: UInt64?
        let poolID: UInt64
        let name: String
        let internalDrive: Bool
        let startup: Bool
        let freeBytes: Int64?
    }

    struct Counters {
        let read: UInt64
        let write: UInt64
        let time: TimeInterval

        func rates(since old: Self?) -> (Double?, Double?) {
            guard let old, time > old.time, time - old.time < 5,
                  read >= old.read, write >= old.write else { return (nil, nil) }
            let divisor = (time - old.time) * 1e6
            return (Double(read - old.read) / divisor, Double(write - old.write) / divisor)
        }
    }

    private let session = DASessionCreate(nil)
    private var inventory: [(drive: StorageDrive, driverID: UInt64?)] = []
    private var nextDiscovery = -Double.infinity
    private var previous: [UInt64: Counters] = [:]

    static func grouped(_ volumes: [Volume]) -> [(drive: StorageDrive, driverID: UInt64?)] {
        Dictionary(grouping: volumes, by: \.driveID).values.map { group in
            let sorted = group.sorted {
                if $0.startup != $1.startup { return $0.startup }
                return $0.name < $1.name
            }
            let first = sorted[0]
            // Sibling APFS volumes allocate from one pool. Separate mounted partitions add space.
            let capacities = Dictionary(grouping: group, by: \.poolID).values.map { $0.compactMap(\.freeBytes).max() }
            let free = capacities.contains(nil) ? nil : capacities.compactMap { $0 }.reduce(0, +)
            let name = first.startup ? first.name : sorted.map(\.name).joined(separator: " / ")
            let drive = StorageDrive(id: first.driveID, name: name, internalDrive: first.internalDrive, freeBytes: free)
            return (drive, first.driverID)
        }.sorted {
            if $0.0.internalDrive != $1.0.internalDrive { return $0.0.internalDrive }
            if $0.0.name != $1.0.name { return $0.0.name < $1.0.name }
            return $0.0.id < $1.0.id
        }
    }

    func sample(options: HUDStorageOptions) -> [StorageDrive] {
        let now = ProcessInfo.processInfo.systemUptime
        if !options.details || now >= nextDiscovery {
            let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [],
                                                              options: .skipHiddenVolumes) ?? []
            let volumes = urls.compactMap { volume(at: $0, location: options.location) }
            inventory = Self.grouped(volumes)
            nextDiscovery = now + 3
        }
        var current: [UInt64: Counters] = [:]
        let result = inventory.map { entry in
            var drive = entry.drive
            if options.details, let driver = entry.driverID, let counters = Self.counters(driver: driver, at: now) {
                (drive.readMBps, drive.writeMBps) = counters.rates(since: previous[drive.id])
                current[drive.id] = counters
            }
            return drive
        }
        previous = current
        return result
    }

    private func volume(at url: URL, location: HUDStorageLocation) -> Volume? {
        guard let session, let disk = DADiskCreateFromVolumePath(nil, session, url as CFURL),
              let description = DADiskCopyDescription(disk) as? [String: Any],
              let internalDrive = description[kDADiskDescriptionDeviceInternalKey as String] as? Bool,
              location.includes(internalDrive: internalDrive),
              let bus = description[kDADiskDescriptionDeviceProtocolKey as String] as? String,
              !["Virtual Interface", "Disk Image", "File"].contains(bus),
              let name = description[kDADiskDescriptionVolumeNameKey as String] as? String else { return nil }
        var node = DADiskCopyIOMedia(disk)
        var driveID: UInt64?
        var driverID: UInt64?
        var poolID: UInt64?
        while node != 0 {
            var id: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(node, &id) == KERN_SUCCESS {
                if poolID == nil || IOObjectConformsTo(node, "AppleAPFSContainer") != 0 { poolID = id }
                if IOObjectConformsTo(node, "IOMedia") != 0,
                   Self.property("Whole", of: node) as? Bool == true {
                    driveID = id // The outer whole medium is the physical device.
                }
                if IOObjectConformsTo(node, "IOBlockStorageDriver") != 0 {
                    driverID = id
                    IOObjectRelease(node)
                    break
                }
            }
            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(node, kIOServicePlane, &parent)
            IOObjectRelease(node)
            guard status == KERN_SUCCESS else { break }
            node = parent
        }
        guard let driveID, let poolID else { return nil }
        let capacity = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity
        return Volume(driveID: driveID, driverID: driverID, poolID: poolID, name: name, internalDrive: internalDrive,
                      startup: url.path == "/", freeBytes: capacity.map(Int64.init))
    }

    private static func property(_ key: String, of node: io_registry_entry_t) -> Any? {
        IORegistryEntryCreateCFProperty(node, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func counters(driver: UInt64, at time: TimeInterval) -> Counters? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(driver))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let stats = property("Statistics", of: entry) as? [String: Any],
              let read = stats["Bytes (Read)"] as? NSNumber, let write = stats["Bytes (Write)"] as? NSNumber else { return nil }
        return Counters(read: read.uint64Value, write: write.uint64Value, time: time)
    }
}

@MainActor
final class StorageMonitor {
    private let poller = MetricPoller<[StorageDrive]>(label: "PerformanceHUD.Storage")
    private var active: HUDStorageOptions?
    private(set) var drives: [StorageDrive] = []
    var onUpdate: (([StorageDrive]) -> Void)?

    func drivesForLogging(_ options: HUDStorageOptions) async -> [StorageDrive] {
        guard let options = options.monitoringOptions else { return [] }
        if active == options, !drives.isEmpty { return drives }
        // Logging may start while the HUD collectors are stopped.
        return await Task.detached(priority: .utility) {
            StorageSampler().sample(options: .init(enabled: true, location: options.location, details: false))
        }.value
    }

    func configure(_ options: HUDStorageOptions?) {
        guard options != active else { return }
        active = options
        drives = []
        guard let options else {
            poller.stop()
            onUpdate?([])
            return
        }
        let sampler = StorageSampler()
        poller.start(interval: options.details ? 1 : 3, sample: { sampler.sample(options: options) }) { [weak self] result in
            guard let self else { return }
            drives = result ?? []
            onUpdate?(drives)
        }
    }
}
