import AppKit
@main struct ScaleLayoutTests {
 @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
  Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
 }
 @MainActor static func main() throws {
  _ = NSApplication.shared
  UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "off", "hud.background": "dark", "hud.fps.dynamic": false], forName: UserDefaults.argumentDomain)
  let hud = HUDWindowController()
  hud.setHUDEnabled(false)
  hud.setAutoHideMode(.off)
  hud.setFPSOptions(.init(enabled: true, mode: .both))
  hud.setPackagePowerOptions(.init(enabled: true))
  hud.setBatteryOptions(.init(enabled: true, temperature: true, charge: true))
  hud.setMetricEnabled(.deviceInfo, enabled: true)
  hud.setFanOptions(.init(enabled: true, average: false))
  hud.updateFans(.init(status: .ready, fans: [.init(id: 0, rpm: 3000, maximumRPM: 6000), .init(id: 1, rpm: 3500, maximumRPM: 6000)]))
  let panel: HUDPanel = member(hud, "panel")
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
  func check(_ value: Bool, _ message: String) { if !value { issues.insert(message) } }
  for alignment in HUDAlignment.allCases {
   hud.setAlignment(alignment)
   for mode in [HUDUsageMode.total, .both] {
    for highlighted in [false, true] {
     for group in HUDResourceGroup.allCases {
      hud.setResourceOptions(.init(enabled: true, temperature: group.supportsTemperature, totalUse: group.supportsTotalUse, focusedApp: mode == .both && group.appMetric != nil, power: group.supportsPower, details: true, highlighted: highlighted ? Set(HUDReadingKind.allCases) : [], usageMode: mode), for: group)
     }
     for scale in HUDScale.allCases {
      hud.setHUDScale(scale)
      hud.updateFPS(144)
      hud.updatePower(.init(cpu: 99.9, gpu: 88.8, package: 196.7, ane: 8))
      hud.updateTemperatures(.init(cpu: 99, gpu: 89))
      hud.updateMetric(.cpuTotal, value: "100%")
      hud.updateMetric(.gpuTotal, value: "100%")
      hud.updateMetric(.cpu, value: "1200%")
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
       let visible = labels.values.filter { !$0.isHidden }.sorted { $0.frame.minX < $1.frame.minX }
       for (left, right) in zip(visible, visible.dropFirst()) {
        // Right-aligned memory values reserve extra width so readings stay stable.
        // Compare occupied text, not the deliberately overlapping empty frame space.
        let rightTextStart = right.alignment == .right
            ? right.frame.maxX - right.intrinsicContentSize.width : right.frame.minX
        let leftTextEnd = left.alignment == .left
            ? left.frame.minX + left.intrinsicContentSize.width : left.frame.maxX
        check(leftTextEnd <= rightTextStart + 1, "Overlapping horizontal labels at \(scale.rawValue): \(left.stringValue) / \(right.stringValue)")
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
  print("RESULT: \(issues.count) issues across 151 scales, both layouts, Total/Both, faint/bold, pressure transitions")
  hud.shutdown()
  if !issues.isEmpty { exit(1) }
 }
}
