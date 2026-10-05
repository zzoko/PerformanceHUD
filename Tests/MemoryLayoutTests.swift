import AppKit

@main struct MemoryLayoutTests {
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }
    @MainActor static func main() throws {
        _ = NSApplication.shared
        UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "off",
            "hud.background": "dark", "hud.alignment": "vertical"], forName: UserDefaults.argumentDomain)
        let hud = HUDWindowController()
        hud.setHUDEnabled(false)
        let panel: HUDPanel = member(hud, "panel")
        let container: NSView = member(hud, "container")
        let horizontal: HUDHorizontalView = member(hud, "horizontalView")
        let glass: NativeGlassHUDBackground = member(hud, "backgroundView")
        let surface: NSView = member(glass, "glass")
        surface.isHidden = true // Offscreen preview uses a plain surface.
        let titles: [HUDMetric: NSTextField] = member(hud, "titleLabels")
        let usage: [HUDMetric: NSTextField] = member(hud, "valueLabels")
        let physical: [HUDMetric: NSTextField] = member(hud, "ramDetailLabels")
        let captions: [HUDMetric: NSTextField] = member(hud, "ramDetailTitleLabels")
        let swapTitle: NSTextField = member(hud, "ramSwapTitleLabel")
        let swap: NSTextField = member(hud, "ramSwapValueLabel")
        let pressure: NSTextField = member(hud, "ramPressureValueLabel")
        let pressureTitle: NSTextField = member(hud, "ramPressureTitleLabel")
        var issues = Set<String>()
        var configurations = 0
        func check(_ condition: Bool, _ message: String) { if !condition { issues.insert(message) } }
        for alignment in HUDAlignment.allCases {
            hud.setAlignment(alignment)
            hud.setPackagePowerOptions(.init(enabled: false))
            for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: false) }
            for scale in [HUDScale.small, .normal, .large] {
                hud.setHUDScale(scale)
                for mode in HUDUsageMode.allCases {
                    for details in [false, true] {
                        for showsUsage in [false, true] where details || showsUsage {
                            for emphasized in [false, true] {
                                hud.setResourceOptions(.init(enabled: true, temperature: false,
                                    totalUse: showsUsage && mode != .app, focusedApp: showsUsage && mode != .total,
                                    details: details, highlighted: emphasized ? [.details, .totalUse, .focusedApp] : [], usageMode: mode), for: .ram)
                                let size = panel.frame.size
                                configurations += 1
                                for state in ["normal", "warning", "critical", ""] {
                                    for gb in [0.0, 13.71, 999.99] {
                                        let sample = RAMUsageSample(percentage: gb == 0 ? 0 : 100,
                                            usedBytes: UInt64(gb * 1_073_741_824), swapUsedBytes: UInt64(gb * 1_073_741_824))
                                        hud.updateRAM(.ramTotal, usage: sample)
                                        hud.updateRAM(.ram, usage: sample)
                                        hud.updateMemoryPressure(state)
                                        panel.contentView?.layoutSubtreeIfNeeded()
                                        check(panel.frame.size == size, "Memory readings must not resize \(alignment), \(scale), \(mode)")
                                        let host: NSView = alignment == .vertical ? container : horizontal
                                        func inspect(_ view: NSView) {
                                            guard !view.isHidden else { return }
                                            if let label = view as? NSTextField, !label.stringValue.isEmpty {
                                                let context = "\(alignment) \(scale.rawValue) \(mode) \(details) \(showsUsage) \(emphasized) \(label.stringValue)"
                                                check(container.bounds.insetBy(dx: -1, dy: -1).contains(label.convert(label.bounds, to: container)), "Outside HUD: \(context)")
                                                check(label.frame.width + 1 >= label.intrinsicContentSize.width, "Clipped width: \(context)")
                                                check(label.frame.height + 1 >= label.intrinsicContentSize.height, "Clipped height: \(context)")
                                            }
                                            for child in view.subviews { inspect(child) }
                                        }
                                        inspect(host)
                                        if alignment == .horizontal && details {
                                            let labels: [String: NSTextField] = member(horizontal, "labels")
                                            for metric in [HUDMetric.ramTotal, .ram] {
                                                for caption in ["PHY", "SWP"] {
                                                    guard let title = labels["\(metric.rawValue).\(caption).title"],
                                                          let value = labels["\(metric.rawValue).\(caption).value"],
                                                          !title.isHidden && !value.isHidden else { continue }
                                                    let titleRect = title.alignmentRect(forFrame: title.frame)
                                                    let valueRect = value.alignmentRect(forFrame: value.frame)
                                                    let visibleValueStart = valueRect.maxX - value.intrinsicContentSize.width
                                                    let actualGap = visibleValueStart - titleRect.maxX
                                                    check(abs(actualGap - HUDStyle.memoryLabelValueSpacing * CGFloat(scale.rawValue)) <= 0.5, "Horizontal memory uses the shared 4 pt gap")
                                                }
                                            }
                                        }
                                        if alignment == .vertical && details && mode != .app {
                                            check(captions[.ramTotal]?.stringValue == "Physical" && swapTitle.stringValue == "Swap" && pressureTitle.stringValue == "Pressure", "Vertical uses full memory labels")
                                            func baseline(_ field: NSTextField) -> CGFloat {
                                                field.convert(field.bounds, to: container).maxY - field.firstBaselineOffsetFromTop
                                            }
                                            let rowSpacing = HUDStyle.ramDetailHeight(scale: scale)
                                            check(abs(baseline(physical[.ramTotal]!) - baseline(swap) - rowSpacing) <= 0.5, "Swap has its own row below Physical")
                                            check(abs(baseline(swap) - baseline(pressure) - rowSpacing) <= 0.5, "Pressure has its own row below Swap")
                                            func aligned(_ field: NSTextField) -> NSRect { field.alignmentRect(forFrame: field.frame) }
                                            for (caption, value) in [(captions[.ramTotal]!, physical[.ramTotal]!), (swapTitle, swap), (pressureTitle, pressure)] {
                                                check(abs(baseline(caption) - baseline(value)) <= 0.5, "Memory caption/value baseline matches")
                                                check(abs(aligned(caption).minX - aligned(titles[.ramTotal]!).minX) <= 0.5, "Memory labels share the left edge")
                                                check(abs(aligned(value).maxX - aligned(usage[.ramTotal]!).maxX) <= 0.5 && value.alignment == .right, "Memory values share the right edge")
                                                check(aligned(caption).maxX <= aligned(value).minX, "Memory caption and value do not overlap")
                                            }
                                            check(HUDStyle.rowHeight(for: .ramTotal, scale: scale) == HUDStyle.rowHeight(scale: scale) + 3 * rowSpacing, "Total memory reserves three separate detail rows")
                                        }
                                        if alignment == .vertical {
                                            check(pressure.isHidden == !details, "Details controls pressure visibility")
                                            check(pressureTitle.isHidden == !details, "Details controls the pressure caption")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        if CommandLine.arguments.contains("--preview") {
            hud.setAlignment(.vertical)
            hud.setHUDScale(.normal)
            hud.setFPSOptions(.init(enabled: true, mode: .both))
            hud.updateFPS(144)
            hud.setResourceOptions(.init(enabled: true, temperature: true, totalUse: true, focusedApp: false, power: true), for: .gpu)
            hud.setResourceOptions(.init(enabled: true, temperature: true, totalUse: true, focusedApp: false, power: true), for: .cpu)
            hud.updateMetric(.gpuTotal, value: "72%")
            hud.updateMetric(.cpuTotal, value: "26%")
            hud.updateTemperatures(.init(cpu: 46, gpu: 43))
            hud.updatePower(.init(cpu: 2.4, gpu: 1.8, package: 4.2, ane: 0))
            hud.setResourceOptions(.init(enabled: true, temperature: false, totalUse: true, focusedApp: false, details: true, highlighted: [.totalUse]), for: .ram)
            hud.updateRAM(.ramTotal, usage: .init(percentage: 57, usedBytes: UInt64(13.71 * 1_073_741_824), swapUsedBytes: 0))
            hud.updateMemoryPressure("normal")
            hud.setBatteryOptions(.init(enabled: true, temperature: true, charge: true))
            hud.updateBattery(.init(percentage: 80, source: .powerAdapter, temperature: 33))
            hud.setMetricEnabled(.deviceInfo, enabled: true)
            for appearance in [HUDBackground.dark] {
                hud.setBackground(appearance)
                surface.isHidden = true
                glass.layer?.backgroundColor = NSColor(calibratedWhite: appearance == .light ? 0.91 : 0.12, alpha: 1).cgColor
                panel.contentView?.layoutSubtreeIfNeeded()
                let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds)!
                container.cacheDisplay(in: container.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/phud-compact-memory-\(appearance.rawValue).png"))
            }
        }
        hud.shutdown()
        for issue in issues.sorted().prefix(30) { print(issue) }
        print("RESULT: \(issues.count) issues across \(configurations) memory configurations, pressure states and digit widths")
        if !issues.isEmpty { exit(1) }
    }
}
