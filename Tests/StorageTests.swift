import AppKit

@main struct StorageTests {
    typealias Volume = StorageSampler.Volume

    static func grouping() -> [StorageDrive] {
        let volumes = [
            Volume(driveID: 1, driverID: 11, poolID: 100, name: "Macintosh HD", internalDrive: true, startup: true, freeBytes: 180_000_000_000),
            Volume(driveID: 1, driverID: 11, poolID: 100, name: "Work", internalDrive: true, startup: false, freeBytes: 180_000_000_000),
            Volume(driveID: 2, driverID: 22, poolID: 200, name: "Games", internalDrive: false, startup: false, freeBytes: 1_210_000_000_000),
            Volume(driveID: 2, driverID: 22, poolID: 201, name: "Media", internalDrive: false, startup: false, freeBytes: 32_000_000_000)]
        let result = StorageSampler.grouped(volumes.reversed())
        precondition(result.map(\.driverID) == [11, 22])
        let drives = result.map(\.drive)
        precondition(drives.map(\.name) == ["Macintosh HD", "Games / Media"])
        precondition(drives.map(\.freeText) == ["180 GB free", "1.24 TB free"])
        return drives
    }

    @MainActor static func freeSpaceFormattingAndWidth() {
        let cases: [(Int64?, String)] = [
            (nil, "—"), (0, "0 B free"), (9, "9 B free"), (999, "999 B free"),
            (1_000, "1.00 kB free"), (9_820_000, "9.82 MB free"),
            (9_820_000_000, "9.82 GB free"), (9_999_000_000, "10.0 GB free"),
            (48_700_000_000, "48.7 GB free"), (99_999_000_000, "100 GB free"),
            (256_000_000_000, "256 GB free"), (999_499_999_999, "999 GB free"),
            (999_500_000_000, "1.00 TB free"), (1_210_000_000_000, "1.21 TB free"),
            (Int64.max, "9.22 EB free")
        ]
        for horizontal in [false, true] {
            let view = HUDStorageView(horizontal: horizontal)
            for scale in [HUDScale.small, .normal, .large] {
                var initialFrame: NSRect?
                for (bytes, expected) in cases {
                    let drive = StorageDrive(id: 1, name: "Macintosh HD", internalDrive: true, freeBytes: bytes)
                    precondition(drive.freeText == expected, "Expected \(expected), got \(drive.freeText)")
                    view.configure([drive], options: .init(enabled: true, details: false, freeSpaceHighlighted: true),
                                   scale: scale, background: .dark)
                    let width = horizontal ? view.contentSize.width : 257 * CGFloat(scale.rawValue)
                    view.setFrameSize(NSSize(width: width, height: view.contentSize.height))
                    view.layoutSubtreeIfNeeded()
                    let fields = view.subviews[0].subviews.compactMap { $0 as? NSTextField }
                    let field = fields.first { !$0.isHidden && $0.stringValue == expected }!
                    let frame = field.alignmentRect(forFrame: field.frame)
                    precondition(frame.width >= field.intrinsicContentSize.width, "Clipped \(expected)")
                    if let initialFrame { precondition(frame == initialFrame, "Moving free-space column") }
                    else { initialFrame = frame }
                }
            }
        }
    }

    static func rates() {
        let old = StorageSampler.Counters(read: 1_000_000, write: 2_000_000, time: 1)
        let new = StorageSampler.Counters(read: 127_300_000, write: 6_650_000, time: 2.5)
        let (read, write) = new.rates(since: old)
        precondition(StorageDrive.rateText(read) == "84.2 MB/s" && StorageDrive.rateText(write) == "3.1 MB/s")
        precondition(old.rates(since: nil).0 == nil && old.rates(since: new).0 == nil)
        precondition(StorageSampler.Counters(read: 0, write: 0, time: 3).rates(since: old).0 == nil)
        precondition(StorageSampler.Counters(read: old.read, write: old.write, time: 2).rates(since: old).0 == 0)
    }

    @MainActor static func layouts(_ drives: [StorageDrive]) {
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
        defaults.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "off", "hud.scale": 1.0],
                                   forName: UserDefaults.argumentDomain)
        let hud = HUDWindowController()
        defer { hud.shutdown() }
        func member<T>(_ name: String) -> T {
            Mirror(reflecting: hud).children.first { $0.label == name }!.value as! T
        }
        hud.setAlignment(.vertical)
        hud.setStorageOptions(.init(enabled: true))
        let view: HUDStorageView = member("storageView")
        precondition(view.isHidden)
        hud.updateStorage([drives[0]])
        let one = view.contentSize.height
        precondition(!view.isHidden && one == HUDStyle.rowHeight(scale: .normal) + HUDStyle.ramDetailHeight(scale: .normal))
        hud.updateStorage(drives)
        precondition(view.contentSize.height == 2 * one + HUDStyle.rowSpacing(scale: .normal))
        hud.setStorageOptions(.init(enabled: true, location: .external, details: false))
        precondition(view.contentSize.height == HUDStyle.rowHeight(scale: .normal))
        hud.updateStorage([drives[0]])
        precondition(view.isHidden && view.contentSize.height == 0)
        hud.updateStorage(drives)
        precondition(!view.isHidden)
        hud.setStorageOptions(.init(enabled: true))
        hud.setAlignment(.horizontal)
        let strip: HUDHorizontalView = member("horizontalView")
        let size: NSSize = member("expandedHUDSize")
        let width = strip.storage.frame.width
        precondition(!strip.storage.isHidden && width > 0 && strip.bounds.contains(strip.storage.frame))
        precondition(size.height == HUDStyle.rowHeight(scale: .normal) + 2 * HUDStyle.verticalPadding(scale: .normal))
        hud.updateStorage([drives[0]])
        let single: NSSize = member("expandedHUDSize")
        precondition(single.width < size.width && single.height == size.height)
        hud.setStorageOptions(.init(enabled: true, location: .external))
        precondition(strip.storage.isHidden)
    }

    @MainActor static func main() {
        _ = NSApplication.shared
        let drives = grouping()
        freeSpaceFormattingAndWidth()
        rates()
        layouts(drives)
        for horizontal in [false, true] {
            let view = HUDStorageView(horizontal: horizontal)
            var drive = drives[0]
            drive.readMBps = 84.2
            drive.writeMBps = 3.1
            for freeBold in [false, true] {
                for ratesBold in [false, true] {
                    view.configure([drive], options: .init(enabled: true, freeSpaceHighlighted: freeBold,
                        detailsHighlighted: ratesBold), scale: .normal, background: .dark)
                    let fields = view.subviews[0].subviews.compactMap { $0 as? NSTextField }
                    func font(_ text: String) -> NSFont? { fields.first { $0.stringValue == text }?.font }
                    precondition(font(drive.freeText) == HUDStyle.readingFont(scale: .normal, highlighted: freeBold))
                    let ratesFont = HUDStyle.readingFont(scale: .normal, highlighted: ratesBold)
                    precondition(font("84.2 MB/s") == ratesFont && font("3.1 MB/s") == ratesFont)
                    precondition(font("Read") == HUDStyle.smallLabelFont(scale: .normal))
                }
            }
        }
        var selection = HUDLogSelection.current
        selection.storage = .init(enabled: true, location: .external)
        let external = drives[1]
        let columns = selection.columns(fanSample: .noFans, drives: drives)
        precondition(columns.contains(.storageFree(external.id, external.name)) && columns.contains(.storageRead(external.id, external.name)))
        precondition(!columns.contains(.storageFree(drives[0].id, drives[0].name)))
        let renamed = StorageDrive(id: external.id, name: "Renamed", internalDrive: false,
                                   freeBytes: 2_000_000_000, readMBps: 1.25, writeMBps: 3)
        var snapshot = HUDLogSnapshot()
        snapshot.updateStorage([renamed], recording: [external])
        precondition(snapshot.values[.storageFree(external.id, external.name)] == "2.00")
        precondition(snapshot.values[.storageRead(external.id, external.name)] == "1.25")
        let replacement = StorageDrive(id: 99, name: external.name, internalDrive: false, freeBytes: 1)
        snapshot.updateStorage([replacement], recording: [external])
        precondition(snapshot.values[.storageFree(external.id, external.name)] == nil)
        precondition(snapshot.values[.storageRead(external.id, external.name)] == nil)
        func demand(visible: Bool, logging: Bool) -> HUDStorageOptions? {
            HUDMonitoringDemand.make(hudEnabled: true, hudVisible: visible, isLogging: logging,
                                     autoHideMode: .all, selection: selection, menuBar: .init()).storage
        }
        precondition(demand(visible: false, logging: false) == nil)
        precondition(demand(visible: true, logging: false) == selection.storage)
        precondition(demand(visible: false, logging: true) == selection.storage)
        let originalDemand = demand(visible: true, logging: false)
        selection.storage.detailsHighlighted = true
        selection.storage.freeSpaceHighlighted = true
        precondition(demand(visible: true, logging: false) == originalDemand)
        selection.storage.details = false
        precondition(!selection.columns(fanSample: .noFans, drives: drives).contains(.storageWrite(external.id, external.name)))
        if CommandLine.arguments.contains("--live") {
            let sampler = StorageSampler()
            _ = sampler.sample(options: .init(enabled: true))
            Thread.sleep(forTimeInterval: 1.1)
            let drives = sampler.sample(options: .init(enabled: true))
            precondition(!drives.isEmpty && Set(drives.map(\.id)).count == drives.count)
            for drive in drives {
                print(drive.name, drive.freeText, "Read", StorageDrive.rateText(drive.readMBps), "Write", StorageDrive.rateText(drive.writeMBps))
            }
        }
        print("PASS: physical drive grouping, capacity, rates, CSV selection and both HUD layouts")
    }
}
