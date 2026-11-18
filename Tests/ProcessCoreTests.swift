import AppKit

@main struct ProcessCoreTests {
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }
    @MainActor static func balancedCoreRows() {
        let fixtures: [(Int, [Int])] = [(0, []), (1, [1]), (8, [8]), (11, [11]), (12, [12]),
            (13, [7, 6]), (18, [9, 9]), (22, [11, 11]), (24, [12, 12]), (25, [9, 8, 8]),
            (32, [11, 11, 10]), (36, [12, 12, 12]), (64, [11, 11, 11, 11, 10, 10])]
        for (count, expected) in fixtures {
            precondition(HUDCoreBarLayout.rowSizes(for: count) == expected,
                         "Wrap at twelve, evenly distributed with longer rows first")
            let bounds = NSRect(x: 5, y: 7, width: 70, height: CGFloat(max(0, expected.count - 1) * 14 + 10))
            let rects = HUDCoreBarLayout.rects(for: count, in: bounds, scale: 1)
            precondition(rects.count == count)
            var offset = 0
            for (row, size) in expected.enumerated() {
                let line = Array(rects[offset..<(offset + size)])
                precondition(line.last!.maxX == bounds.maxX, "Every row ends at the same reading edge")
                precondition(line.allSatisfy { $0.size == NSSize(width: 4, height: 10)
                    && $0.maxY == bounds.maxY - CGFloat(row * 14) && bounds.contains($0) })
                precondition(zip(line, line.dropFirst()).allSatisfy { $1.minX - $0.maxX == 2 },
                             "Core order runs left to right with unchanged bar widths and gaps")
                offset += size
            }
        }

        let types = [HUDCPUCoreType(name: "Super", count: 12), .init(name: "Performance", count: 24)]
        let info = HUDDeviceInfo(chipName: "Simulated Ultra", macOSVersion: "macOS",
            cpuCores: 36, gpuCores: 80, coreTypes: types)
        let topology = CPUCoreTopology(groups: [.init(name: "Super", ids: Array(0..<12)),
            .init(name: "Performance", ids: Array(12..<36))])
        let hud = HUDWindowController(deviceInfo: info, cpuTopology: topology)
        defer { hud.shutdown() }
        hud.setAlignment(.vertical)
        hud.setHUDScale(.normal)
        for group in [HUDResourceGroup.gpu, .cpu] {
            hud.setResourceOptions(.init(enabled: true, temperature: true, totalUse: true,
                focusedApp: false, power: true), for: group)
        }
        hud.setGPUCoreOptions(.init(enabled: true))
        hud.setCPUCoreOptions(.init(enabled: true, mode: .both))
        let panel: HUDPanel = member(hud, "panel")
        let container: NSView = member(hud, "container")
        let cpu: HUDCoreDetailView = member(hud, "cpuCoreView")
        let gpu: HUDCoreDetailView = member(hud, "gpuCoreView")
        let bars = cpu.subviews.filter { String(describing: type(of: $0)).contains("BarsView") }
        let fields = cpu.subviews.compactMap { $0 as? NSTextField }.filter {
            $0.accessibilityLabel()?.contains("active-time-weighted frequency") == true
        }
        let gpuField = gpu.subviews.compactMap { $0 as? NSTextField }.first {
            $0.accessibilityLabel() == "GPU average active frequency during sample"
        }!
        let powers: [HUDMetric: NSTextField] = member(hud, "powerLabels")
        func rect(_ field: NSTextField) -> NSRect {
            field.superview!.convert(field.alignmentRect(forFrame: field.frame), to: container)
        }
        for bold in [false, true] {
            hud.setResourceOptions(.init(enabled: true, temperature: true, totalUse: true,
                focusedApp: false, power: true, highlighted: bold ? [.power, .temperature, .totalUse] : []), for: .cpu)
            hud.setCPUCoreOptions(.init(enabled: true, mode: .both, highlighted: bold))
            panel.contentView?.layoutSubtreeIfNeeded()
            let wattsEdge = rect(powers[.cpuTotal]!).maxX
            precondition(fields.count == 2 && bars.count == 2)
            precondition(fields.allSatisfy { $0.alignment == .right && abs(rect($0).maxX - wattsEdge) < 0.01 })
            precondition(abs(rect(gpuField).maxX - wattsEdge) < 0.01, "GPU follows the right-aligned CPU GHz edge")
            precondition(bars[0].frame.height == 10 && bars[1].frame.height == 24,
                         "12 Super cores occupy one line; 24 Performance cores occupy two")
            precondition(abs(container.bounds.width - 285) < 0.01, "Large core counts never widen the HUD")
            for (field, bar) in zip(fields, bars) {
                precondition(bar.frame.minX - field.alignmentRect(forFrame: field.frame).maxX >= 13,
                             "A full twelve-bar row leaves a clear gap after GHz")
            }
            for label in cpu.subviews.compactMap({ $0 as? NSTextField }).filter({ !fields.contains($0) }) {
                precondition(label.alignmentRect(forFrame: label.frame).width >= label.intrinsicContentSize.width,
                             "Full core-type captions still fit")
            }
            var minimal = HUDResourceOptions(enabled: true, temperature: false, totalUse: false,
                focusedApp: false, power: true)
            minimal.highlighted = bold ? [.power, .temperature, .totalUse] : []
            hud.setResourceOptions(minimal, for: .cpu)
            panel.contentView?.layoutSubtreeIfNeeded()
            precondition(fields.allSatisfy { abs(rect($0).maxX - wattsEdge) < 0.01 },
                         "Hiding temperature and usage does not shift GHz into the bars")
        }
    }
    @MainActor static func normalizedProcessCPU() {
        let second = 1_000_000_000.0
        func value(_ busySeconds: Double, cores: Int = 10, interval: Double = 1) -> Double? {
            ProcessCPUUsage.percentage(cpuNanoseconds: busySeconds * second,
                elapsedNanoseconds: interval * second, logicalCPUCount: cores)
        }
        precondition(value(1) == 10 && value(4) == 40 && value(10) == 100,
                     "Process CPU uses the same whole-Mac capacity scale as total CPU")
        precondition(value(1, cores: 1) == 100 && value(8, cores: 16) == 50)
        precondition(value(0) == 0 && value(10.01) == 100, "Zero is real; sampling skew cannot exceed 100%")
        precondition(value(-1) == nil && value(.nan) == nil && value(.infinity) == nil
                     && value(1, cores: 0) == nil && value(1, interval: 0) == nil,
                     "Invalid samples remain unavailable")
        let precise = value(4.249)!
        precondition(abs(precise - 42.49) < 0.0001, "Normalize before rounding")
        var snapshot = HUDLogSnapshot()
        snapshot.set(.cpuAppUsage, precise)
        precondition(snapshot.numbers[.cpuAppUsage] == precise && snapshot.values[.cpuAppUsage] == "42.5",
                     "CSV receives the normalized percentage with its normal precision")
        let view = HUDProcessView(frame: NSRect(x: 0, y: 0, width: 257, height: 21))
        view.setName("A long process name for checking remaining space")
        let fields: [HUDProcessReading: NSTextField] = member(view, "values")
        let name: NSTextField = member(view, "name")
        func rect(_ field: NSTextField) -> NSRect { field.alignmentRect(forFrame: field.frame) }
        for mask in 0..<8 {
            let selected = Set(HUDProcessReading.allCases.enumerated().compactMap { index, reading in
                mask & (1 << index) != 0 ? reading : nil
            })
            var savedFrames: [NSRect]?
            for emphasized in [false, true] {
                view.configure(options: .init(enabled: true, readings: selected,
                    highlighted: emphasized ? selected : []), scale: .normal, background: .dark)
                for usage in [nil, 0.0, 9.0, precise, 100.0] {
                    view.setValue(usage.map { "\(Int($0.rounded()))%" }, for: .cpu)
                    view.setValue(usage.map { "\(Int($0.rounded()))%" }, for: .gpu)
                    view.setValue(usage == nil ? nil : "13.00 GB", for: .memory)
                    view.layoutSubtreeIfNeeded()
                    let visible = HUDProcessReading.allCases.filter { selected.contains($0) }.map { fields[$0]! }
                    let frames = [rect(name)] + visible.map(rect)
                    if let savedFrames { precondition(frames == savedFrames, "Digits, dashes and B keep Process columns stable") }
                    else { savedFrames = frames }
                    for (left, right) in zip(frames, frames.dropFirst()) {
                        precondition(abs(right.minX - left.maxX - HUDStyle.metricColumnSpacing(scale: .normal)) < 0.01,
                                     "Process preserves the shared 8 pt gaps between enabled columns")
                    }
                    precondition(rect(name).width > 30, "Bounded percentages leave room for the process name")
                    if selected.contains(.gpu) && selected.contains(.cpu) {
                        precondition(rect(fields[.gpu]!).width == rect(fields[.cpu]!).width,
                                     "GPU and CPU reserve equal 0–100% slots")
                    }
                }
            }
        }
    }
    @MainActor static func powerPlaceholders() {
        let hud = HUDWindowController()
        defer { hud.shutdown() }
        let powers: [HUDMetric: NSTextField] = member(hud, "powerLabels")
        let package: NSTextField = member(hud, "packageValueLabel") as NSTextField?
            ?? { fatalError("Missing SOC value") }()
        let horizontal: HUDHorizontalView = member(hud, "horizontalView")
        for alignment in HUDAlignment.allCases {
            hud.setAlignment(alignment)
            for group in [HUDResourceGroup.gpu, .cpu, .ane] {
                hud.setResourceOptions(.init(enabled: true, temperature: false, totalUse: true,
                    focusedApp: false, power: true), for: group)
            }
            hud.updatePower(.unavailable)
            hud.setPackagePowerOptions(.init(enabled: true))
            precondition([HUDMetric.gpuTotal, .cpuTotal, .aneTotal].allSatisfy {
                powers[$0]?.stringValue == "—"
            } && package.stringValue == "—", "Enabled watts use the same unavailable dash as GHz")
            if alignment == .horizontal {
                let labels: [String: NSTextField] = member(horizontal, "labels")
                let ids = [HUDMetric.gpuTotal, .cpuTotal, .aneTotal].map { "\($0.rawValue).power" } + ["package.power"]
                precondition(ids.allSatisfy { labels[$0]?.stringValue == "—" && labels[$0]?.isHidden == false },
                             "Horizontal power slots also show unavailable dashes")
            }
            hud.updatePower(.init(cpu: 1, gpu: 0, package: 1, ane: 0))
            precondition(powers[.gpuTotal]?.stringValue == "0.0 W" && powers[.aneTotal]?.stringValue == "0.0 W",
                         "Valid zero watts remain numeric")
            hud.setResourceOptions(.init(enabled: true, temperature: false, totalUse: true,
                focusedApp: false, power: false), for: .gpu)
            hud.setPackagePowerOptions(.init(enabled: false))
            precondition(powers[.gpuTotal]?.stringValue.isEmpty == true && powers[.gpuTotal]?.isHidden == true
                         && package.stringValue.isEmpty, "Disabled power stays hidden rather than becoming a dash")
        }
    }
    @MainActor static func horizontalCores() throws {
        let types = [HUDCPUCoreType(name: "Super", count: 4), .init(name: "Performance", count: 24),
                     .init(name: "Efficiency", count: 16)]
        let topology = CPUCoreTopology(groups: [.init(name: "Super", ids: Array(0..<4)),
            .init(name: "Performance", ids: Array(4..<28)), .init(name: "Efficiency", ids: Array(28..<44))])
        let info = HUDDeviceInfo(chipName: "Fixture", macOSVersion: "", cpuCores: 44, gpuCores: 0, coreTypes: types)
        let hud = HUDWindowController(deviceInfo: info, cpuTopology: topology)
        defer { hud.shutdown() }
        let panel: HUDPanel = member(hud, "panel")
        panel.alphaValue = 0
        hud.setHUDEnabled(true)
        hud.setAutoHideMode(.off)
        hud.setAlignment(.horizontal)
        hud.setPackagePowerOptions(.init(enabled: false))
        for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: false) }
        let horizontal: HUDHorizontalView = member(hud, "horizontalView")
        let frequencies = CPUFrequencySample(frequencies: Dictionary(uniqueKeysWithValues:
            topology.groups.flatMap { group in group.ids.map { ($0, group.name == "Efficiency" ? 2.1 : 3.7) } }))
        for count in 1...3 {
            let view = HUDCoreDetailView(frame: .zero, types: Array(types.prefix(count)), topology: topology)
            view.configure(options: .init(enabled: true, mode: .bars), scale: .normal, background: .dark)
            let strip = HUDHorizontalView(frame: .zero)
            let size = strip.configure(sections: [view.horizontalReadings()], showsBattery: false,
                                       scale: .normal, background: .dark)
            let bars: [String: HUDCPUCoreBarsView] = member(strip, "coreBars")
            let ordered = types.prefix(count).map { bars["\(HUDMetric.cpuCores.rawValue).\($0.name)"]!.frame }
            precondition(size.height == 21 && (ordered.first!.midY + ordered.last!.midY) / 2 == size.height / 2)
            precondition(zip(ordered, ordered.dropFirst()).allSatisfy { $0.midY - $1.midY == (count == 2 ? 18 : 14) })
        }
        var expectedHeight: CGFloat?
        for mode in HUDCoreDisplayMode.allCases {
            hud.setCPUCoreOptions(.init(enabled: true, mode: mode, highlighted: true))
            hud.setGPUCoreOptions(.init(enabled: true))
            for mask in 0..<8 {
                for group in [HUDResourceGroup.gpu, .cpu] {
                    hud.setResourceOptions(.init(enabled: true, temperature: mask & 2 != 0,
                        totalUse: mask & 4 != 0, focusedApp: false, power: mask & 1 != 0), for: group)
                    hud.updateMetric(group.totalMetric, value: "42%")
                }
                hud.updateTemperatures(.init(cpu: 48, gpu: 46))
                hud.updatePower(.init(cpu: 1.7, gpu: 3.5, package: 5.2, cpuFrequencies: frequencies, gpuFrequency: 1.2))
                panel.contentView?.layoutSubtreeIfNeeded()
                let labels: [String: NSTextField] = member(horizontal, "labels")
                let ids = ["\(HUDMetric.gpuCores.rawValue).Cores"]
                    + types.map { "\(HUDMetric.cpuCores.rawValue).\($0.name)" }
                for id in ids {
                    let title = labels["\(id).title"]!
                    let showsGHz = id == ids[0] || mode.showsValue
                    precondition(!title.isHidden && (labels["\(id).value"]?.isHidden == false) == showsGHz)
                    if mode.showsBars && id != ids[0] {
                        let stacks: [String: HUDCPUCoreBarsView] = member(horizontal, "coreBars")
                        let view = stacks[id]!
                        let count = types.first { id.hasSuffix("." + $0.name) }!.count
                        precondition(view.frame.width == CGFloat(count * 6 - 2) && view.frame.height == 10)
                        precondition(view.singleRow && horizontal.bounds.contains(view.frame))
                        precondition(abs(title.frame.midY - view.frame.midY) <= 1)
                    }
                    let abbreviations = ["Cores": "C", "Super": "S", "Performance": "P", "Efficiency": "E"]
                    let fullName = String(id.split(separator: ".").last!)
                    precondition(title.stringValue == (abbreviations[fullName] ?? fullName),
                                 "Horizontal uses compact core-type labels and preserves their full accessible names")
                    guard showsGHz else { continue }
                    let value = labels["\(id).value"]!
                    precondition(value.stringValue.hasSuffix(" GHz"))
                    if id != ids[0] && mode.showsBars { continue }
                    let titleRect = title.alignmentRect(forFrame: title.frame)
                    let valueRect = value.alignmentRect(forFrame: value.frame)
                    let visibleGap = valueRect.maxX - value.intrinsicContentSize.width
                        - titleRect.minX - title.intrinsicContentSize.width
                    let expectedGap = HUDStyle.memoryLabelValueSpacing + titleRect.width - title.intrinsicContentSize.width
                    precondition(abs(visibleGap - expectedGap) < 0.1,
                                 "Core pair gap \(visibleGap), id \(id), mode \(mode), mask \(mask), title \(titleRect) / \(title.intrinsicContentSize), value \(valueRect) / \(value.intrinsicContentSize)")
                }
                let visible = labels.values.filter { !$0.isHidden }.sorted { $0.frame.minX < $1.frame.minX }
                for (left, right) in zip(visible, visible.dropFirst()) {
                    guard abs(left.frame.midY - right.frame.midY) < 1 else { continue }
                    let l = left.alignmentRect(forFrame: left.frame), r = right.alignmentRect(forFrame: right.frame)
                    let leftEnd = left.alignment == .right ? l.maxX : l.minX + left.intrinsicContentSize.width
                    let rightStart = right.alignment == .right ? r.maxX - right.intrinsicContentSize.width : r.minX
                    precondition(rightStart - leftEnd >= HUDStyle.memoryLabelValueSpacing - 0.1,
                                 "Adjacent horizontal text never crowds or overlaps")
                }
                if mode.showsBars {
                    let stacks: [String: HUDCPUCoreBarsView] = member(horizontal, "coreBars")
                    let views = ids.dropFirst().map { stacks[$0]! }
                    precondition(views.allSatisfy { $0.frame.minX == views[0].frame.minX })
                    precondition(zip(views, views.dropFirst()).allSatisfy { $0.frame.midY - $1.frame.midY == HUDCoreBarLayout.rowStride })
                    hud.updateCPUCores(.init(usage: [4: 75, 27: 100, 43: 65]))
                    precondition(views[1].values[0] == 75 && views[1].values[23] == 100 && views[2].values[15] == 65)
                }
                if let expectedHeight { precondition(panel.frame.height == expectedHeight, "Horizontal cores never add bar rows") }
                else { expectedHeight = panel.frame.height }
                let size = panel.frame.size
                hud.updatePower(.unavailable)
                let visibleIDs = mode.showsValue ? ids : [ids[0]]
                precondition(visibleIDs.allSatisfy { labels["\($0).value"]?.stringValue == "—" }
                             && panel.frame.size == size, "Missing clocks use stable-width dash placeholders")
                hud.updatePower(.init(cpu: 1.7, gpu: 3.5, package: 5.2, cpuFrequencies: frequencies, gpuFrequency: 1.2))
            }
        }
        if CommandLine.arguments.contains("--preview") {
            let bitmap = horizontal.bitmapImageRepForCachingDisplay(in: horizontal.bounds)!
            horizontal.cacheDisplay(in: horizontal.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(
                to: URL(fileURLWithPath: "/tmp/performancehud-v34-horizontal-cores.png"))
        }
        hud.setCPUCoreOptions(.init(enabled: false)); hud.setGPUCoreOptions(.init(enabled: false))
        let labels: [String: NSTextField] = member(horizontal, "labels")
        precondition(labels.filter { $0.key.hasPrefix("\(HUDMetric.cpuCores.rawValue).")
            || $0.key.hasPrefix("\(HUDMetric.gpuCores.rawValue).") }.values.allSatisfy(\.isHidden),
                     "Disabling core controls removes their Horizontal readings")
    }
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let suite = "ProcessCoreTests.\(UUID())"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        let defaults = UserDefaults.standard
        let old = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(old, forName: UserDefaults.argumentDomain) }
        defaults.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "off", "hud.scale": 1.0,
            "hud.background": "dark", "hud.alignment": "vertical"], forName: UserDefaults.argumentDomain)
        powerPlaceholders()
        try horizontalCores()
        normalizedProcessCPU()
        balancedCoreRows()
        let balanced = HUDPresetConfiguration.builtIn(.balanced)
        let detailed = HUDPresetConfiguration.builtIn(.full)
        precondition(!balanced.process.enabled && balanced.cpuCores == .cpuDefault && balanced.gpuCores == .gpuDefault)
        precondition(balanced.cpuCores.enabled && balanced.cpuCores.mode == .bars && !balanced.gpuCores.enabled)
        precondition(HUDPreferences.gpuCoreOptions(in: store) == .gpuDefault,
                     "Fresh settings leave GPU GHz off like Balanced")
        precondition(detailed.process.enabled && detailed.cpuCores.enabled && detailed.gpuCores.enabled && detailed.cpuCores.mode == .both)
        precondition(detailed.resources.values.allSatisfy { !$0.focusedApp })
        detailed.apply(in: store)
        precondition(HUDPresetConfiguration.capture(in: store).matches(detailed))
        HUDPreferences.resetOptions(in: store)
        precondition(HUDPresetConfiguration.capture(in: store).matches(balanced))
        let decoded = try JSONDecoder().decode(HUDPresetConfiguration.self, from: JSONEncoder().encode(detailed))
        precondition(decoded == detailed)
        let oldGPUOptions = HUDCoreOptions(enabled: true, mode: .bars, highlighted: true)
        store.set(try JSONEncoder().encode(oldGPUOptions), forKey: "hud.gpu.cores")
        precondition(HUDPreferences.gpuCoreOptions(in: store) == .init(enabled: true, mode: .value, highlighted: true),
                     "Old GPU modes keep visibility and emphasis while switching to frequency")
        var oldGPUPreset = detailed
        oldGPUPreset.gpuCores.mode = .bars
        precondition(oldGPUPreset.matches(detailed), "Removed GPU modes must not make a preset Custom")

        let topology = CPUCoreTopology.resolve(types: [.init(name: "Super", count: 4), .init(name: "Efficiency", count: 6)],
            ids: ["P": [6, 7, 8, 9], "E": [0, 1, 2, 3, 4, 5]])
        precondition(topology.groups.map(\.name) == ["Super", "Efficiency"])
        precondition(topology.groups[0].ids == [6, 7, 8, 9])
        let three = CPUCoreTopology.resolve(types: [.init(name: "Super", count: 2), .init(name: "Performance", count: 2), .init(name: "Efficiency", count: 2)],
            ids: ["S": [4, 5], "P": [2, 3], "E": [0, 1]])
        precondition(three.groups.count == 3)
        let malformed = CPUCoreTopology.resolve(types: [.init(name: "Super", count: 4)], ids: ["P": [0, 1]])
        precondition(malformed.groups.isEmpty, "Incomplete topology must not invent processor indices")
        let info = HUDDeviceInfo(chipName: "M5", macOSVersion: "macOS", cpuCores: 10, gpuCores: 10,
                                coreTypes: [.init(name: "Super", count: 4), .init(name: "Efficiency", count: 6)])
        precondition(info.cpuConfiguration == "4 Super + 6 Efficiency" && info.gpuConfiguration == "10")
        let noE = HUDDeviceInfo(chipName: "M5 Pro", macOSVersion: "macOS", cpuCores: 18, gpuCores: 20,
                               coreTypes: [.init(name: "Super", count: 6), .init(name: "Performance", count: 12)])
        precondition(noE.cpuConfiguration == "6 Super + 12 Performance")
        let sample = CPUCoreSampler.delta(previous: [[0, 0, 0, 0], [0, 0, 0, 0]],
                                          current: [[10, 10, 80, 0], [50, 10, 40, 0]])
        precondition(abs(sample.usage[0]! - 20) < 0.001 && abs(sample.average(for: [0, 1])! - 40) < 0.001)
        precondition(sample.average(for: [0, 2]) == nil)
        let wrapping = CPUCoreSampler.delta(previous: [[UInt32.max - 4, 0, 0, 0]], current: [[5, 0, 10, 0]])
        precondition(wrapping.usage[0] == 50)
        let frequencies = HelperPowerReading.parseFrequencies(["clusters": [
            ["freq_hz": 2_100_000_000, "cpus": [["cpu": 0], ["cpu": 1]]],
            ["freq_hz": 3700, "cpus": [["cpu": 6], ["cpu": 7, "freq_hz": 3_800_000_000]]]]])
        precondition(frequencies.frequencies[0] == 2.1 && frequencies.frequencies[6] == 3.7 && frequencies.frequencies[7] == 3.7)
        let helper = HelperPowerReading(cpu: 1, gpu: 0, package: 1, timestamp: Date(), cpuFrequencies: frequencies)
        precondition(HelperPowerReading(reply: helper.reply)?.cpuFrequencies == frequencies)
        precondition(HelperPowerReading.parseFrequencies(["clusters": [["cpus": [["cpu": 0, "freq_hz": Double.nan]]]]]).frequencies.isEmpty)
        let weighted = CPUFrequencySample(frequencies: [0: 2, 1: 2, 2: 4, 3: 4],
                                          activeResidencies: [0: 0.1, 1: 0.1, 2: 0.9, 3: 0.9])
        precondition(abs(weighted.average(for: [0, 1, 2, 3])! - 3.8) < 0.0001, "Busy clusters carry more weight")
        precondition(weighted.average(for: [0, 1]) == 2, "A single shared cluster clock is exact")
        precondition(CPUFrequencySample(frequencies: [0: 2, 1: 4]).average(for: [0, 1]) == nil,
                     "Never invent activity weights for differing clocks")
        precondition(CPUFrequencySample(frequencies: [0: 2], activeResidencies: [0: 0]).average(for: [0]) == nil,
                     "An entirely idle sample has no active frequency")
        let parsedActivity = HelperPowerReading.parseFrequencies(["clusters": [["freq_hz": 2_000_000_000,
            "cpus": [["cpu": 0, "idle_ratio": 0.25, "freq_hz": 1_900_000_000], ["cpu": 1, "idle_ratio": 0.75]]]]])
        precondition(parsedActivity.activeResidencies == [0: 0.75, 1: 0.25] && parsedActivity.average(for: [0, 1]) == 2)
        // Two same-type clusters with different clocks, sizes and activity,
        // plus another core type. Do not average cluster clocks equally.
        let multiTopology = CPUCoreTopology.resolve(types: [.init(name: "Performance", count: 6), .init(name: "Efficiency", count: 4)],
            ids: ["P": Array(4..<10), "E": Array(0..<4)])
        let multiCluster = HelperPowerReading.parseFrequencies(["clusters": [
            ["freq_hz": 2000, "cpus": (4..<6).map { ["cpu": $0, "idle_ratio": 0.75] as [String: Any] }],
            ["freq_hz": 4000, "cpus": (6..<10).map { ["cpu": $0, "idle_ratio": 0.25] as [String: Any] }],
            ["freq_hz": 1200, "cpus": (0..<4).map { ["cpu": $0, "idle_ratio": 0.8] as [String: Any] }]
        ]])
        let multiReply = HelperPowerReading(reply: HelperPowerReading(cpu: 1, gpu: 1, package: 2,
            timestamp: Date(), cpuFrequencies: multiCluster).reply)!
        precondition(abs(multiReply.cpuFrequencies.average(for: multiTopology.groups[0].ids)! - 26.0 / 7.0) < 0.0001
                     && abs(multiReply.cpuFrequencies.average(for: multiTopology.groups[1].ids)! - 1.2) < 0.0001,
                     "All same-type clusters contribute per-core active-time weights through helper IPC")
        let gpuHelper = HelperPowerReading(cpu: 1, gpu: 2, package: 3, timestamp: Date(), cpuFrequencies: weighted, gpuFrequency: 1.35)
        let roundTrip = HelperPowerReading(reply: gpuHelper.reply)!
        precondition(roundTrip.gpuFrequency == 1.35 && roundTrip.cpuFrequencies == weighted)
        let powerPlist: [String: Any] = ["is_delta": true, "elapsed_ns": 1_000_000_000,
            "timestamp": Date(), "processor": ["cpu_power": 1000, "gpu_power": 2000,
                "clusters": [["freq_hz": 3_700_000_000, "cpus": [["cpu": 0, "idle_ratio": 0.5]]]]],
            "gpu": ["freq_hz": 1350]]
        let powerData = try PropertyListSerialization.data(fromPropertyList: powerPlist, format: .xml, options: 0)
        let decodedPower = HelperPowerReading.parse(powerData)!
        precondition(decodedPower.gpuFrequency == 1.35 && decodedPower.cpuFrequencies.average(for: [0]) == 3.7,
                     "A full powermetrics plist decodes GPU MHz and CPU Hz")
        precondition(HelperPowerReading.gigahertz(true) == nil && HelperPowerReading.gigahertz(-1) == nil
                     && HelperPowerReading.gigahertz(Double.infinity) == nil)
        let sampler = CPUCoreSampler()
        _ = sampler.sample()
        Thread.sleep(forTimeInterval: 0.12)
        let live = sampler.sample()
        precondition(live?.usage.count == ProcessInfo.processInfo.activeProcessorCount, "Live per-core counter coverage")

        var selection = HUDLogSelection(fps: false, resources: balanced.resources, package: .init(enabled: false),
            fans: .init(enabled: false), battery: .init(enabled: false, temperature: false, charge: false), alignment: .vertical,
            process: .init(enabled: true), cpuCores: .init(enabled: true), gpuCores: .init(enabled: true))
        let demand = HUDMonitoringDemand.make(hudEnabled: true, hudVisible: true, isLogging: false, autoHideMode: .off, selection: selection, menuBar: .init())
        precondition(demand.cpuAppUsage && demand.gpuAppUsage && demand.appMemory && demand.cpuCores && demand.gpuCores)
        let columns = selection.columns(fanSample: .unavailable)
        precondition(Array(columns.prefix(4)) == [.process, .gpuAppUsage, .cpuAppUsage, .memoryAppPhysical])
        selection.alignment = .horizontal
        let horizontal = HUDMonitoringDemand.make(hudEnabled: true, hudVisible: true, isLogging: false, autoHideMode: .off, selection: selection, menuBar: .init())
        precondition(!horizontal.cpuAppUsage && !horizontal.gpuAppUsage && !horizontal.appMemory
                     && horizontal.cpuCores && horizontal.gpuCores && horizontal.power,
                     "Horizontal Both collects clocks and per-core usage")
        precondition(!selection.columns(fanSample: .unavailable).contains(.process))
        var coresOnly = selection
        coresOnly.alignment = .vertical; coresOnly.process.enabled = false
        coresOnly.resources = Dictionary(uniqueKeysWithValues: HUDResourceGroup.allCases.map {
            ($0, HUDResourceOptions(enabled: $0 == .cpu || $0 == .gpu, temperature: false,
                                   totalUse: false, focusedApp: false, power: false, details: false, pressure: false))
        })
        coresOnly.cpuCores.mode = .bars; coresOnly.gpuCores.enabled = false
        let barsDemand = HUDMonitoringDemand.make(hudEnabled: true, hudVisible: true, isLogging: false,
            autoHideMode: .off, selection: coresOnly, menuBar: .init())
        precondition(barsDemand.cpuCores && !barsDemand.gpuUsage && !barsDemand.power && !barsDemand.cpuAppUsage,
                     "CPU bars work independently of power, system Use, and Process")
        var gpuOnly = coresOnly
        gpuOnly.cpuCores.enabled = false; gpuOnly.gpuCores.enabled = true
        for mode in HUDCoreDisplayMode.allCases {
            gpuOnly.gpuCores.mode = mode
            let ghzDemand = HUDMonitoringDemand.make(hudEnabled: true, hudVisible: true, isLogging: false,
                autoHideMode: .off, selection: gpuOnly, menuBar: .init())
            precondition(ghzDemand.power && !ghzDemand.gpuUsage && !ghzDemand.cpuCores
                         && gpuOnly.columns(fanSample: .noFans) == [.gpuFrequency],
                         "GPU Cores requests and logs only GHz, regardless of its old mode")
        }
        var cpuOnly = coresOnly
        cpuOnly.gpuCores.enabled = false
        cpuOnly.cpuCores.mode = .value
        let frequencyOnly = HUDMonitoringDemand.make(hudEnabled: true, hudVisible: true, isLogging: false,
            autoHideMode: .off, selection: cpuOnly, menuBar: .init())
        precondition(frequencyOnly.power && !frequencyOnly.cpuCores && !frequencyOnly.gpuUsage,
                     "CPU Value selects GHz without polling per-core usage")
        for mode in HUDCoreDisplayMode.allCases {
            cpuOnly.cpuCores.mode = mode
            let expected = HUDDeviceInfo.current.coreTypes.flatMap { type -> [HUDLogColumn] in
                var columns: [HUDLogColumn] = mode.showsValue ? [.cpuTypeFrequency(type.name)] : []
                if mode.showsBars {
                    columns += (CPUCoreTopology.current.groups.first { $0.name == type.name }?.ids ?? []).map(HUDLogColumn.cpuCoreUsage)
                }
                return columns
            }
            precondition(cpuOnly.columns(fanSample: .noFans) == expected,
                         "CPU Cores logs only the selected GHz and/or individual core usage")
            var horizontalCPU = cpuOnly
            horizontalCPU.alignment = .horizontal
            let horizontalDemand = HUDMonitoringDemand.make(hudEnabled: true, hudVisible: true, isLogging: false,
                autoHideMode: .off, selection: horizontalCPU, menuBar: .init())
            precondition(horizontalDemand.power == mode.showsValue && horizontalDemand.cpuCores == mode.showsBars
                         && horizontalCPU.columns(fanSample: .noFans) == expected,
                         "Horizontal core sampling and CSV follow the selected mode")
        }
        let hiddenDemand = HUDMonitoringDemand.make(hudEnabled: true, hudVisible: false, isLogging: false,
            autoHideMode: .all, selection: coresOnly, menuBar: .init())
        precondition(!hiddenDemand.power && !hiddenDemand.cpuCores && !hiddenDemand.gpuUsage)
        // Core details alone keep their resource title in Horizontal.
        let coreStore = UserDefaults.standard
        let coreDomain = coreStore.volatileDomain(forName: UserDefaults.argumentDomain)
        var coreOnly = coreDomain
        for group in ["cpu", "gpu"] {
            coreOnly["hud.group.\(group).enabled"] = true
            coreOnly["hud.group.\(group).power"] = false
            coreOnly["hud.group.\(group).temperature"] = false
            coreOnly["hud.metric.\(group)Total"] = false
            coreOnly["hud.\(group).cores"] = try JSONEncoder().encode(HUDCoreOptions(enabled: true))
        }
        coreOnly["hud.alignment"] = "horizontal"
        coreStore.setVolatileDomain(coreOnly, forName: UserDefaults.argumentDomain)
        precondition(HUDPreferences.visibleMetrics.isSuperset(of: [.cpuTotal, .gpuTotal, .cpuCores, .gpuCores])
                     && !HUDPreferences.visibleMetrics.contains(.process))
        coreStore.setVolatileDomain(coreDomain, forName: UserDefaults.argumentDomain)
        let menu = HUDProcessMenuView(options: .init(enabled: true), alignment: .vertical)
        let controls: [HUDProcessReading: HUDReadingCheckbox] = member(menu, "controls")
        var changed: HUDProcessOptions?
        menu.onChange = { changed = $0 }
        controls[.gpu]!.performClick(nil)
        precondition(changed?.readings == [.cpu, .memory])
        menu.update(alignment: .horizontal)
        precondition(controls.values.allSatisfy { !$0.isEnabled })
        menu.update(alignment: .vertical)
        precondition(controls[.gpu]!.state == .off && controls[.cpu]!.state == .on)

        let hud = HUDWindowController()
        defer { hud.shutdown() }
        hud.setPackagePowerOptions(.init(enabled: false))
        for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: false) }
        hud.setProcessOptions(.init(enabled: true))
        hud.setProcessName("A very long game name that should truncate at the end")
        hud.updateMetric(.gpu, value: "100%")
        hud.updateMetric(.cpu, value: "100%")
        hud.updateRAM(.ram, usage: .init(percentage: 5, usedBytes: 13_000_000_000, swapUsedBytes: nil))
        hud.setResourceOptions(balanced.resources[.gpu]!, for: .gpu)
        hud.setGPUCoreOptions(.init(enabled: true))
        hud.updateMetric(.gpuTotal, value: "42%")
        hud.setResourceOptions(balanced.resources[.cpu]!, for: .cpu)
        hud.setCPUCoreOptions(.init(enabled: true))
        hud.updateMetric(.cpuTotal, value: "15%")
        hud.updateTemperatures(.init(cpu: 48, gpu: 46))
        hud.updatePower(.init(cpu: 1.7, gpu: 3.5, package: 5.2, gpuFrequency: 1.2))
        let actualTopology = CPUCoreTopology.current
        var usages: [Int: Double] = [:], speeds: [Int: Double] = [:]
        for group in actualTopology.groups {
            for (offset, id) in group.ids.enumerated() {
                usages[id] = Double(10 + offset * 9)
                speeds[id] = group.name == "Efficiency" ? 2.1 : 3.7
            }
        }
        hud.updateCPUCores(.init(usage: usages)); hud.updateCPUFrequencies(.init(frequencies: speeds))
        let panel: HUDPanel = member(hud, "panel")
        let container: NSView = member(hud, "container")
        panel.contentView?.layoutSubtreeIfNeeded()
        let process: HUDProcessView = member(hud, "processView")
        let labels: [HUDProcessReading: NSTextField] = member(process, "values")
        let name: NSTextField = member(process, "name")
        precondition(name.frame.maxX <= labels[.gpu]!.frame.minX, "The app name cannot overlap GPU")
        precondition(labels[.gpu]!.frame.maxX < labels[.cpu]!.frame.minX && labels[.cpu]!.frame.maxX < labels[.memory]!.frame.minX)
        precondition(name.frame.width > 30, "Maximum Process readings leave room for the process name")
        let enabled: Set<HUDMetric> = member(hud, "enabledMetrics")
        precondition(enabled.contains(.process) && enabled.contains(.cpuCores) && !enabled.contains(.cpu))
        let coreView: HUDCoreDetailView = member(hud, "cpuCoreView")
        let frequencyFields = coreView.subviews.compactMap { $0 as? NSTextField }.filter {
            $0.accessibilityLabel()?.contains("active-time-weighted frequency") == true
        }
        let coreBars = coreView.subviews.filter { String(describing: type(of: $0)).contains("BarsView") }
        let gpuCoreView: HUDCoreDetailView = member(hud, "gpuCoreView")
        let gpuFrequency = gpuCoreView.subviews.compactMap { $0 as? NSTextField }.first {
            $0.accessibilityLabel() == "GPU average active frequency during sample"
        }!
        precondition(gpuCoreView.subviews.count == 2 && gpuFrequency.stringValue == "1.2 GHz",
                     "GPU detail contains only its label and frequency")
        func readingRect(_ field: NSTextField) -> NSRect {
            field.superview!.convert(field.alignmentRect(forFrame: field.frame), to: container)
        }
        func checkMatchingFrequencyColumns() {
            let gpu = readingRect(gpuFrequency), cpu = readingRect(frequencyFields[0])
            precondition(abs(gpu.minX - cpu.minX) < 0.01 && abs(gpu.maxX - cpu.maxX) < 0.01
                         && gpuFrequency.alignment == frequencyFields[0].alignment,
                         "GPU GHz follows the CPU GHz column while the CPU frequency is visible")
        }
        var barFrames: [NSRect]?, frequencyFrames: [NSRect]?
        let usageLabels: [HUDMetric: NSTextField] = member(hud, "valueLabels")
        for mode in [HUDCoreDisplayMode.both, .bars, .value, .both] {
            hud.setCPUCoreOptions(.init(enabled: true, mode: mode))
            panel.contentView?.layoutSubtreeIfNeeded()
            if mode.showsValue { checkMatchingFrequencyColumns() }
            else {
                precondition(gpuFrequency.alignment == .right
                             && abs(readingRect(gpuFrequency).maxX - readingRect(usageLabels[.gpuTotal]!).maxX) < 0.01,
                             "CPU Bars-only cannot move GPU GHz away from the right edge")
            }
            precondition(frequencyFields.allSatisfy {
                $0.isHidden == !mode.showsValue && $0.alignment == .right
            })
            precondition(coreBars.allSatisfy { $0.isHidden == !mode.showsBars })
            precondition(coreView.subviews.compactMap { $0 as? NSTextField }.allSatisfy {
                $0.isHidden || !$0.stringValue.hasSuffix("%")
            }, "CPU detail modes never add a group percentage")
            if let barFrames, let frequencyFrames {
                precondition(coreBars.map(\.frame) == barFrames, "The graph column stays fixed across modes")
                if mode == .value {
                    precondition(frequencyFields.allSatisfy {
                        abs(readingRect($0).maxX - readingRect(usageLabels[.cpuTotal]!).maxX) < 0.01
                    }, "CPU Value-only aligns GHz with the numeric right edge")
                } else {
                    precondition(frequencyFields.map(\.frame) == frequencyFrames,
                                 "CPU Bars and Both retain the same frequency column")
                }
            } else {
                barFrames = coreBars.map(\.frame); frequencyFrames = frequencyFields.map(\.frame)
            }
        }
        let powerLabels: [HUDMetric: NSTextField] = member(hud, "powerLabels")
        let powerLabel = powerLabels[.cpuTotal]!
        let powerRect = powerLabel.superview!.convert(powerLabel.alignmentRect(forFrame: powerLabel.frame), to: container)
        let frequencyRect = coreView.convert(frequencyFields[0].alignmentRect(forFrame: frequencyFields[0].frame), to: container)
        precondition(abs(frequencyRect.maxX - powerRect.maxX) < 0.01,
                     "GHz ends at the full CPU watts column's right edge")
        func checkGPUAtRightEdge() {
            precondition(gpuFrequency.alignment == .right
                         && abs(readingRect(gpuFrequency).maxX - readingRect(usageLabels[.gpuTotal]!).maxX) < 0.01,
                         "GPU GHz returns to the numeric right edge without CPU Cores")
        }
        hud.setCPUCoreOptions(.init(enabled: false))
        panel.contentView?.layoutSubtreeIfNeeded()
        checkGPUAtRightEdge()
        hud.setCPUCoreOptions(.init(enabled: true))
        var cpuResource = balanced.resources[.cpu]!
        cpuResource.enabled = false
        hud.setResourceOptions(cpuResource, for: .cpu)
        panel.contentView?.layoutSubtreeIfNeeded()
        checkGPUAtRightEdge()
        cpuResource.enabled = true
        cpuResource.highlighted = [.power, .temperature, .totalUse]
        hud.setResourceOptions(cpuResource, for: .cpu)
        hud.setGPUCoreOptions(.init(enabled: true, highlighted: true))
        panel.contentView?.layoutSubtreeIfNeeded()
        checkMatchingFrequencyColumns()
        for scale in [HUDScale.small, .large, .normal] {
            hud.setHUDScale(scale)
            panel.contentView?.layoutSubtreeIfNeeded()
            checkMatchingFrequencyColumns()
            hud.setCPUCoreOptions(.init(enabled: false))
            panel.contentView?.layoutSubtreeIfNeeded()
            checkGPUAtRightEdge()
            hud.setCPUCoreOptions(.init(enabled: true))
            panel.contentView?.layoutSubtreeIfNeeded()
            checkMatchingFrequencyColumns()
        }
        hud.setResourceOptions(balanced.resources[.cpu]!, for: .cpu)
        hud.setGPUCoreOptions(.init(enabled: true))
        panel.contentView?.layoutSubtreeIfNeeded()
        checkMatchingFrequencyColumns()
        // Large chips wrap at twelve bars without widening the HUD. Row text
        // stays on the first line and every graph slot ends at the numeric reading edge.
        for count in [4, 8, 12, 13, 18, 24, 25, 32, 36, 64] {
            let types = [HUDCPUCoreType(name: "Super", count: count), .init(name: "Efficiency", count: 6)]
            let big = HUDCoreDetailView(frame: NSRect(x: 0, y: 0, width: 257, height: 250), types: types,
                topology: .init(groups: [.init(name: "Super", ids: Array(0..<count)), .init(name: "Efficiency", ids: Array(count..<(count + 6)))]))
            big.configure(options: .init(enabled: true), scale: .normal, background: .dark)
            let expected = HUDStyle.rowSpacing(scale: .normal) + 2 * HUDStyle.ramDetailHeight(scale: .normal)
                + CGFloat((count - 1) / 12) * 14
            precondition(big.height(scale: .normal) == expected, "One extra bar line per twelve cores")
            big.layoutSubtreeIfNeeded()
            let bars = big.subviews.filter { String(describing: type(of: $0)).contains("BarsView") }
            precondition(bars.count == 2 && bars[0].frame.maxX == bars[1].frame.maxX, "Graph right edges align")
            big.configure(options: .init(enabled: true, mode: .value), scale: .normal, background: .dark)
            precondition(big.height(scale: .normal) == HUDStyle.rowSpacing(scale: .normal) + 2 * HUDStyle.ramDetailHeight(scale: .normal))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--frequency-sample"),
           CommandLine.arguments.indices.contains(index + 1) {
            // Replay an actual captured plist through IPC decoding, continuity,
            // PowerMonitor and the HUD. Only rebase its freshness timestamp.
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            let document = Data(data.split(separator: 0).first!)
            var root = try PropertyListSerialization.propertyList(from: document, format: nil) as! [String: Any]
            root["timestamp"] = Date()
            let refreshed = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
            let raw = HelperPowerReading.parse(refreshed)!
            let transported = HelperPowerReading(reply: raw.reply)!
            var continuity = PowerReadingContinuity(cpuCoreGroups: actualTopology.groups.map(\.ids))
            let monitor = PowerMonitor()
            monitor.onUpdate = { hud.updatePower($0) }
            monitor.helper.onUpdate?(continuity.update(transported))
            for field in frequencyFields {
                let group = actualTopology.groups.first { field.accessibilityLabel()?.hasPrefix($0.name) == true }!
                let expected = raw.cpuFrequencies.average(for: group.ids)!
                precondition(field.stringValue == String(format: "%.1f GHz", expected),
                             "Captured CPU frequency reaches its actual core-type HUD row")
                print("Captured \(group.name): \(field.stringValue)")
            }
            precondition(gpuFrequency.stringValue == String(format: "%.1f GHz", raw.gpuFrequency!),
                         "Captured GPU frequency reaches the HUD")
            print("Captured GPU: \(gpuFrequency.stringValue)")
        }
        if CommandLine.arguments.contains("--preview") {
            let glass: NativeGlassHUDBackground = member(hud, "backgroundView")
            let surface: NSView = member(glass, "glass")
            surface.isHidden = true
            container.wantsLayer = true; container.layer?.backgroundColor = NSColor(white: 0.14, alpha: 1).cgColor
            let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds)!
            container.cacheDisplay(in: container.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/performancehud-v32-process-core-preview.png"))
        }
        print("PASS: Process controls, core visibility in both layouts, Horizontal GHz spacing/modes, collector demand, presets, topology, live sampling, frequency decoding, CSV, and compact layout")
    }
}
