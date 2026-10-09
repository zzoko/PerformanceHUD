import AppKit

@main struct PressureHistoryTests {
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }

    @MainActor static func main() throws {
        _ = NSApplication.shared
        var history = HUDMemoryPressureHistory()
        for time in 0..<40 {
            history.append(.init(time: Double(time), level: .low, numericValue: 20))
        }
        precondition(history.samples.count == 31 && history.samples.first!.time == 9, "The complete 30-second interval survives")
        history.append(.init(time: 39, level: .low, numericValue: 90))
        precondition(history.samples.count == 31 && history.samples.last!.numericValue == 20, "Duplicate samples cannot rewrite history")
        history.append(.init(time: 40, level: nil, numericValue: nil))
        history.append(.init(time: 41, level: .medium, numericValue: 45))
        precondition(history.runs.count == 2, "Missing numeric readings leave a gap")
        history.append(.init(time: 44, level: .medium, numericValue: 46))
        precondition(history.runs.count == 3, "Suspended sampling never draws across a gap")
        history.append(.init(time: 45, level: .high, numericValue: .nan))
        history.append(.init(time: 46, level: .high, numericValue: 101))
        precondition(history.runs.flatMap { $0 }.allSatisfy { $0.numericValue!.isFinite && $0.numericValue! <= 100 },
                     "Invalid values cannot enter a drawn contour")
        history.append(.init(time: 100, level: .low, numericValue: 20))
        precondition(history.samples.count == 1, "Returning after a long pause drops stale history")
        history.clear()
        precondition(history.runs.isEmpty, "Clear removes all retained samples")

        var time: TimeInterval = 0
        for index in 0..<1200 {
            time += [0.93, 1.11, 0.99, 1.02][index % 4]
            history.append(.init(time: time, level: .low, numericValue: 20 + Double(index % 5)))
            if time > 32 {
                precondition(abs(history.runs[0][0].time - (time - 30)) < 0.000001,
                             "Filled history stays at the exact left edge despite sampling jitter")
                precondition(history.samples.count <= 33, "Only one boundary predecessor is retained")
            }
        }
        history.clear()
        for index in 0...31 {
            history.append(.init(time: Double(index), level: .low, numericValue: Double(index * 2)))
        }
        history.append(.init(time: 31.5, level: .low, numericValue: 63))
        precondition(history.runs[0][0].time == 1.5 && history.runs[0][0].numericValue == 3,
                     "The boundary interpolates the actual readings on each side")
        history.clear()
        for index in 0...31 {
            history.append(.init(time: Double(index), level: .low, numericValue: index == 1 ? nil : 20))
        }
        history.append(.init(time: 31.5, level: .low, numericValue: 20))
        precondition(history.runs[0][0].time == 2, "A missing reading at the boundary cannot be bridged")
        history.clear()
        for index in 0...31 where index != 1 {
            history.append(.init(time: Double(index), level: .low, numericValue: 20))
        }
        history.append(.init(time: 31.5, level: .low, numericValue: 20))
        precondition(history.runs[0][0].time == 2, "A sampling pause at the boundary cannot be bridged")

        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
        defaults.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "off", "hud.scale": 1.0,
            "hud.background": "light", "hud.alignment": "vertical"], forName: UserDefaults.argumentDomain)
        let hud = HUDWindowController()
        defer { hud.shutdown() }
        hud.setHUDEnabled(false)
        hud.setHUDScale(.normal)
        hud.setPackagePowerOptions(.init(enabled: false))
        for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: false) }
        let cpuOptions = HUDResourceOptions(enabled: true, temperature: true, totalUse: true,
                                            focusedApp: false, power: true)
        hud.setResourceOptions(cpuOptions, for: .cpu)
        let powers: [HUDMetric: NSTextField] = member(hud, "powerLabels")
        let cpuPower = powers[.cpuTotal]!
        cpuPower.stringValue = "0.0 W"
        hud.setBatteryOptions(.init(enabled: true, temperature: true, charge: true, flowMode: .off))
        hud.updateBattery(.init(percentage: 80, source: .powerAdapter, temperature: 36))
        var options = HUDResourceOptions(enabled: true, temperature: false, totalUse: true,
            focusedApp: false, pressureMode: .colorMeter)
        hud.setResourceOptions(options, for: .ram)
        hud.updateRAM(.ramTotal, usage: .init(percentage: 83, usedBytes: UInt64(19.92 * 1_073_741_824),
                                            swapUsedBytes: UInt64(1.79 * 1_073_741_824)))
        hud.updateMemoryPressure("warning")
        let panel: HUDPanel = member(hud, "panel")
        let container: NSView = member(hud, "container")
        let graph: HUDMemoryPressureHistoryView = member(hud, "ramPressureHistory")
        let title: NSTextField = member(hud, "ramPressureTitleLabel") as NSTextField? ?? { fatalError() }()
        let meter: HUDMemoryPressureMeterView = member(hud, "ramPressureMeter")
        let dividers: [Int: NSView] = member(hud, "groupDividers")
        panel.contentView?.layoutSubtreeIfNeeded()
        let originalSize = panel.frame.size
        let originalWindowTop = panel.frame.maxY
        let titleFrame = title.convert(title.bounds, to: container)
        let titleTopInset = container.bounds.maxY - titleFrame.maxY
        let originalPlotHeight = graph.plotBounds.height
        let meterFrame = meter.convert(meter.bounds, to: container)
        for mode in [HUDMemoryPressureMode.history, .colorHistory] {
            options.selectPressureMode(mode)
            hud.setResourceOptions(options, for: .ram)
            panel.contentView?.layoutSubtreeIfNeeded()
            precondition(panel.frame.width == originalSize.width
                         && abs(panel.frame.height - originalSize.height - 12.375) < 1,
                         "History adds only the extra plot height to the vertical HUD")
            precondition(abs(panel.frame.maxY - originalWindowTop) < 0.5, "The HUD expands downward from its existing top")
            let newTitleFrame = title.convert(title.bounds, to: container)
            precondition(abs(container.bounds.maxY - newTitleFrame.maxY - titleTopInset) < 0.5,
                         "The Pressure caption keeps its position from the top")
            precondition(abs(graph.plotBounds.height - originalPlotHeight * 1.5) < 0.6,
                         "The numeric pressure plot is 1.5 times its original height")
            let frame = graph.convert(graph.bounds, to: container)
            precondition(frame.width > meterFrame.width && frame.maxX > meterFrame.maxX,
                         "Graph extends left and uses the remaining space at the right")
            let powerFrame = cpuPower.convert(cpuPower.alignmentRect(forFrame: cpuPower.frame), from: cpuPower.superview)
            let powerRight = cpuPower.convert(powerFrame, to: container).maxX
            let graphLeft = graph.convert(NSPoint(x: graph.plotBounds.minX, y: 0), to: container).x
            precondition(abs(graphLeft - (powerRight - cpuPower.intrinsicContentSize.width)) < 0.5,
                         "The graph's left guide aligns with 0.0 W in the complete reading columns")
            var reducedCPU = cpuOptions
            reducedCPU.power = false
            reducedCPU.temperature = false
            hud.setResourceOptions(reducedCPU, for: .cpu)
            panel.contentView?.layoutSubtreeIfNeeded()
            precondition(graph.convert(graph.bounds, to: container) == frame, "Hiding CPU readings cannot shrink the graph")
            hud.setResourceOptions(cpuOptions, for: .cpu)
            cpuPower.stringValue = "0.0 W"
            panel.contentView?.layoutSubtreeIfNeeded()
            precondition(container.bounds.contains(frame), "The fade fits within the existing HUD")
            let divider = dividers[4]!
            let line = divider.convert(NSRect(x: 0, y: 4, width: 1, height: 0.5), to: container)
            let plot = graph.convert(graph.plotBounds, to: container)
            let dividerFrame = divider.convert(divider.bounds, to: container)
            precondition(abs(plot.minY - line.midY) < 0.5,
                         "The zero baseline and borders meet the divider: plot \(plot), line \(line)")
            precondition(abs(plot.maxX - dividerFrame.maxX) < 0.5, "The right border reaches the divider's right edge")
            let zero = graph.point(for: .init(time: 30, level: .low, numericValue: 0), latestTime: 30)
            let hundred = graph.point(for: .init(time: 30, level: .high, numericValue: 100), latestTime: 30)
            precondition(zero.y == graph.plotBounds.minY && hundred.y == graph.plotBounds.maxY,
                         "Numeric 0–100 spans the full filled plot without an extra base")
            let forty = graph.point(for: .init(time: 30, level: .low, numericValue: 40), latestTime: 30)
            precondition(abs((forty.y - zero.y) / (hundred.y - zero.y) - 0.4) < 0.000001,
                         "A reading of 40 sits 40 percent above the bottom of the filled plot")
            for center in [zero, hundred] {
                precondition(graph.bounds.contains(NSRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)),
                             "The current dot and halo fit even at numeric 0 and 100")
            }
            graph.clear()
            for index in 0..<30 {
                let value = 48 + Double(index % 5)
                hud.updateMemoryPressureHistory(.init(time: Double(index), level: .medium, numericValue: value))
            }
            var bitmap = graph.bitmapImageRepForCachingDisplay(in: graph.bounds)!
            graph.cacheDisplay(in: graph.bounds, to: bitmap)
            let ratio = CGFloat(bitmap.pixelsWide) / graph.bounds.width
            func pixel(x: CGFloat, y: CGFloat) -> NSColor {
                bitmap.colorAt(x: Int(x * ratio), y: bitmap.pixelsHigh - 1 - Int(y * ratio))!.usingColorSpace(.deviceRGB)!
            }
            let top = pixel(x: 40, y: 12)
            let bottom = pixel(x: 40, y: 4)
            precondition(top.alphaComponent > 0.07 && bottom.alphaComponent < 0.05,
                         "Fill fades to transparent at its base")
            precondition(pixel(x: 40, y: 1).alphaComponent == 0, "There is no decorative fill below numeric zero")
            let oldest = graph.point(for: graph.history.runs[0][0], latestTime: 29)
            let faded = pixel(x: oldest.x + 1, y: 9)
            let solid = pixel(x: oldest.x + 8, y: 9)
            precondition(solid.alphaComponent > 0.04 && faded.alphaComponent < solid.alphaComponent * 0.5,
                         "The oldest edge fades in over six points while the interior retains its fill")
            if mode == .history {
                precondition(abs(top.redComponent - top.blueComponent) < 0.02, "Style 3 is neutral")
            } else {
                precondition(top.redComponent > top.blueComponent + 0.4, "Style 4 uses the sample's yellow pressure state")
            }
            let endpoint = graph.point(for: graph.history.samples.last!, latestTime: 29)
            let dot = pixel(x: endpoint.x, y: endpoint.y)
            precondition(dot.alphaComponent > 0.9, "The endpoint dot remains visible")
            if mode == .history {
                precondition(abs(dot.redComponent - dot.blueComponent) < 0.02, "Style 3 uses a neutral endpoint dot")
            } else {
                precondition(dot.redComponent > dot.blueComponent + 0.4, "Style 4 colours the endpoint by current pressure state")
            }

            graph.append(.init(time: 30, level: nil, numericValue: nil))
            bitmap = graph.bitmapImageRepForCachingDisplay(in: graph.bounds)!
            graph.cacheDisplay(in: graph.bounds, to: bitmap)
            precondition(pixel(x: endpoint.x, y: endpoint.y).alphaComponent < 0.35,
                         "An unavailable current reading cannot leave a stale endpoint dot")
        }
        options.selectPressureMode(.text)
        hud.setResourceOptions(options, for: .ram)
        precondition(graph.isHidden && graph.history.samples.isEmpty, "Text hides and clears unused history")
        precondition(panel.frame.size == originalSize, "Returning to Text restores the compact HUD height")
        options.selectPressureMode(.colorHistory)
        hud.setResourceOptions(options, for: .ram)
        hud.updateMemoryPressureHistory(.init(time: 100, level: .low, numericValue: 20))
        hud.setAlignment(.horizontal)
        precondition(graph.isHidden && graph.history.samples.isEmpty, "Horizontal never retains a live history overlay")

        if CommandLine.arguments.contains("--preview") {
            hud.setAlignment(.vertical)
            hud.setResourceOptions(options, for: .ram)
            let glass: NativeGlassHUDBackground = member(hud, "backgroundView")
            let surface: NSView = member(glass, "glass")
            surface.isHidden = true
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor(srgbRed: 0.70, green: 0.86, blue: 0.98, alpha: 1).cgColor
            for index in 0...35 {
                hud.updateMemoryPressureHistory(.init(time: Double(index + 200), level: index < 12 ? .medium : .low,
                                                      numericValue: (index < 12 ? 82 : 45) + Double(index % 3)))
            }
            panel.contentView?.layoutSubtreeIfNeeded()
            let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds)!
            container.cacheDisplay(in: container.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/phud-v23-pressure-preview.png"))
        }
        print("PASS: stable history boundary/gaps, fixed numeric scale, current-state dot, faded rendering, and taller vertical plot geometry")
    }
}
