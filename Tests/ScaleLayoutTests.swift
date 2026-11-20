import AppKit
@main struct ScaleLayoutTests {
 @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
  Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
 }
    @MainActor static func uniformFrames() {
        let hud = HUDWindowController()
        let panel: HUDPanel = member(hud, "panel")
        panel.alphaValue = 0
        hud.setHUDEnabled(true)
        hud.setAutoHideMode(.off)
        hud.setAlignment(.vertical)
        hud.setHUDScale(.normal)
        hud.setResourceOptions(.init(enabled: true, temperature: false, totalUse: true, focusedApp: false, details: true, pressure: true, pressureMode: .colorHistory), for: .ram)
        hud.setFanOptions(.init(mode: .both, average: false))
        hud.updateFans(.init(status: .ready, fans: [.init(id: 0, rpm: 2340, maximumRPM: 6000)]))
        hud.setStorageOptions(.init(enabled: true, details: true))
        hud.updateStorage([.init(id: 1, name: "Drive", internalDrive: true, freeBytes: 256_000_000_000, readMBps: 84.2, writeMBps: 3.1)])
        let body: NSView = member(hud, "container")
        let physical: [HUDMetric: NSTextField] = member(hud, "ramDetailTitleLabels")
        let swap: NSTextField = member(hud, "ramSwapValueLabel")
        let graph: HUDMemoryPressureHistoryView = member(hud, "ramPressureHistory")
        let fans: HUDFanView = member(hud, "fanView")
        let storage: HUDStorageView = member(hud, "storageView")
        let read = storage.subviews.flatMap(\.subviews).compactMap { $0 as? NSTextField }.first { $0.stringValue == "84.2 MB/s" }!
        let dividers: [Int: NSView] = member(hud, "groupDividers")
        let divider = dividers.sorted { $0.key < $1.key }.first { !$0.value.isHidden }!.value
        // Use the glass viewport's window-space origin so dragging and shadow
        // padding cannot hide a scaling error in a content frame.
        func frames() -> [String: NSRect] {
            panel.contentView!.layoutSubtreeIfNeeded()
            func frame(_ view: NSView, _ rect: NSRect? = nil) -> NSRect {
                view.convert(rect ?? view.bounds, to: body)
            }
            return ["Physical": frame(physical[.ramTotal]!), "Pressure": frame(graph), "Swap": frame(swap),
                    "Fan RPM": frame(fans, fans.frames(forFanAt: 0).rpm!), "Storage Read": frame(read), "Divider": frame(divider)]
        }
        let base = frames()
        func edges(_ rect: NSRect) -> [CGFloat] { [rect.minX, rect.minY, rect.maxX, rect.maxY] }
        for factor in [0.5, 1.37, 2.0, 1.0] {
            hud.setHUDScale(.init(rawValue: factor))
            for (name, rect) in frames() {
                let expected = edges(base[name]!).map { $0 * factor }
                let error = zip(edges(rect), expected).map { abs($0 - $1) }.max()! * panel.backingScaleFactor
                precondition(error <= 0.500001, "\(name) moved \(error) device pixels at \(factor)×")
            }
        }
        print("PASS: Physical, pressure, Swap, fan RPM, storage Read and divider edges scale to within half a device pixel")
        hud.shutdown()
    }
 @MainActor static func main() throws {
  _ = NSApplication.shared
  UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "off", "hud.background": "dark", "hud.fps.dynamic": false], forName: UserDefaults.argumentDomain)
  uniformFrames()
  if CommandLine.arguments.contains("--frames-only") { return }
  let hud = HUDWindowController()
  let panel: HUDPanel = member(hud, "panel")
  panel.alphaValue = 0
  hud.setHUDEnabled(true)
  hud.setAutoHideMode(.off)
  hud.setFPSOptions(.init(enabled: true, mode: .both))
  hud.setPackagePowerOptions(.init(enabled: true))
  hud.setBatteryOptions(.init(enabled: true, temperature: true, charge: true))
  hud.setMiscOptions(.init(enabled: true, readings: [.chip, .os]))
  hud.setFanOptions(.init(enabled: true, average: false))
  hud.updateFans(.init(status: .ready, fans: [.init(id: 0, rpm: 3000, maximumRPM: 6000), .init(id: 1, rpm: 3500, maximumRPM: 6000)]))
  let container: NSView = member(hud, "container")
  let horizontal: HUDHorizontalView = member(hud, "horizontalView")
  let glass: NativeGlassHUDBackground = member(hud, "backgroundView")
  let surface: NSView = member(glass, "glass")
  surface.isHidden = true
  glass.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1).cgColor
  let graph: HUDFPSGraphView = member(hud, "fpsGraphView")
  for index in 0..<60 { graph.append(144 + sin(Double(index) / 4) * 10) }
  var issues = Set<String>()
  var verticalWidths: [HUDScale: CGFloat] = [:]
  let scales: [HUDScale] = CommandLine.arguments.contains("--normal-size") ? [.normal] : HUDScale.allCases
  func check(_ value: Bool, _ message: String) { if !value { issues.insert(message) } }
  for alignment in HUDAlignment.allCases {
   hud.setAlignment(alignment)
   for mode in [HUDUsageMode.total, .both] {
    for highlighted in [false, true] {
     for group in HUDResourceGroup.allCases {
      hud.setResourceOptions(.init(enabled: true, temperature: group.supportsTemperature, totalUse: group.supportsTotalUse, focusedApp: mode == .both && group.appMetric != nil, power: group.supportsPower, details: true, highlighted: highlighted ? Set(HUDReadingKind.allCases) : [], usageMode: mode), for: group)
     }
     for scale in scales {
      hud.setHUDScale(scale)
      hud.updateFPS(144)
      hud.updatePower(.init(cpu: 99.9, gpu: 88.8, package: 196.7, ane: 8))
      hud.updateTemperatures(.init(cpu: 99, gpu: 89))
      hud.updateMetric(.cpuTotal, value: "100%")
      hud.updateMetric(.gpuTotal, value: "100%")
      hud.updateMetric(.cpu, value: "100%")
      hud.updateMetric(.gpu, value: "100%")
      for metric in [HUDMetric.ramTotal, .ram] {
       hud.updateRAM(metric, usage: .init(percentage: 100, usedBytes: 128 * 1_073_741_824, swapUsedBytes: 32 * 1_073_741_824))
      }
      hud.updateBattery(.init(percentage: 100, source: .powerAdapter, temperature: 39, power: -99.9))
      hud.updateMemoryPressure("normal")
      panel.contentView?.layoutSubtreeIfNeeded()
      let original = panel.frame.size
      if alignment == .vertical {
       if let expected = verticalWidths[scale] {
        check(original.width == expected, "Vertical options/emphasis resized at \(scale.rawValue)")
       } else { verticalWidths[scale] = original.width }
      }
      hud.updateMemoryPressure("critical")
      panel.contentView?.layoutSubtreeIfNeeded()
      check(panel.frame.size == original, "Pressure resized \(alignment) at \(scale.rawValue)")
      let host: NSView = alignment == .horizontal ? horizontal : container
      func inspect(_ view: NSView) {
       guard !view.isHidden else { return }
       if let label = view as? NSTextField, !label.stringValue.isEmpty {
        let rect = label.convert(label.bounds, to: host)
        let context = "\(alignment) \(mode) \(scale.rawValue) \(label.stringValue)"
        check(host.bounds.insetBy(dx: -1, dy: -1).contains(rect), "Outside HUD: \(context) \(rect) / \(host.bounds)")
        check(label.frame.width + 1 >= label.intrinsicContentSize.width, "Text width clipped: \(context)")
        check(label.frame.height + 1 >= label.intrinsicContentSize.height, "Text height clipped: \(context)")
       }
       for child in view.subviews { inspect(child) }
      }
      inspect(host)
      if alignment == .vertical {
       let powers: [HUDMetric: NSTextField] = member(hud, "powerLabels")
       let pkg: NSTextField? = member(hud, "packageValueLabel")
       let cpu = powers[.cpuTotal]!.convert(powers[.cpuTotal]!.bounds, to: container).maxX
       for field in [powers[.aneTotal], pkg].compactMap({ $0 }) {
        check(abs(field.convert(field.bounds, to: container).maxX - cpu) <= 1, "Power column misaligned at \(scale.rawValue)")
       }
      } else {
       let labels: [String: NSTextField] = member(horizontal, "labels")
       // Detail values reserve space while their short captions follow the
       // actual digits/dash. Sort by occupied text too: the value's empty frame
       // can begin before its own caption without the text overlapping.
       let visible = labels.values.filter { !$0.isHidden }.map { label -> (NSTextField, NSRect) in
        var rect = label.alignmentRect(forFrame: label.frame)
        let width = label.intrinsicContentSize.width
        if label.alignment == .right { rect.origin.x = rect.maxX - width }
        else if label.alignment == .center { rect.origin.x = rect.midX - width / 2 }
        rect.size.width = width
        return (label, rect)
       }.sorted { $0.1.minX < $1.1.minX }
       // Separate core-type rows deliberately share the same horizontal columns.
       for (index, left) in visible.enumerated() {
        for right in visible.dropFirst(index + 1) {
         if right.1.minX >= left.1.maxX - 1 { break }
         let overlap = left.1.intersection(right.1)
         check(overlap.width <= 1 || overlap.height <= 1, "Overlapping horizontal labels at \(scale.rawValue): \(left.0.stringValue) / \(right.0.stringValue)")
        }
       }
      }
      if CommandLine.arguments.contains("--preview"), mode == .total && !highlighted && [0.5, 1, 1.5, 2].contains(scale.rawValue) {
       let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds)!
       container.cacheDisplay(in: container.bounds, to: bitmap)
       try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/phud-scale-\(alignment)-\(scale.rawValue).png"))
       print("RENDER \(alignment) \(scale.rawValue): \(container.bounds.size)")
      }
     }
    }
   }
  }
  for issue in issues.sorted().prefix(40) { print(issue) }
  print("RESULT: \(issues.count) issues across \(scales.count) scales, both layouts, Total/Both, faint/bold, pressure transitions")
  hud.shutdown()
  if !issues.isEmpty { exit(1) }
 }
}
