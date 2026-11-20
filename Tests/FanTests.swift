import AppKit

@main struct FanTests {
    static var context = "setup"
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), "\(message) [\(context)]")
    }
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }
    @MainActor static func main() {
        check(FanDecoder.number(type: "fpe2", bytes: [0x2a, 0x80]) == 2720, "Fixed-point RPM format")
        check(FanDecoder.number(type: "flt ", bytes: [0, 0, 0x2a, 0x45]) == 2720, "Apple silicon float RPM format")
        check(FanDecoder.number(type: "ui8 ", bytes: [4]) == 4, "Fan count")
        check(FanDecoder.number(type: "ui16", bytes: [0x0a, 0xa0]) == 2720, "Big-endian integer format")
        check(FanDecoder.number(type: "ui32", bytes: [0, 0, 9, 126]) == 2430, "Key count")
        check(FanDecoder.number(type: "flt ", bytes: [0, 0, 0, 0]) == 0, "Zero RPM is valid")
        for bytes: [UInt8] in [[0, 0, 0x80, 0x7f], [0, 0, 0xc0, 0x7f], [0, 0, 0x80, 0xbf], [0]] {
            check(FanDecoder.number(type: "flt ", bytes: bytes) == nil, "Reject nonfinite, negative or truncated samples")
        }
        check(FanDecoder.number(type: "bad ", bytes: [0, 0]) == nil, "Unsupported format")
        for value in [Double.nan, Double.infinity, -1, 0.5, 17] {
            check(FanDecoder.count(value) == nil, "Bound malformed counts")
        }
        check(FanDecoder.count(0) == 0 && FanDecoder.count(4) == 4, "No fans and four fans")
        check(FanDecoder.identifiers(in: ["F2Ac", "F0Ac", "F2Ac", "FNum", "F0Mx", "TEMP", "FqAc"]) == [0, 2], "Discover and deduplicate actual fan keys")
        check(FanDecoder.identifiers(in: ["TC0P", "TB1T"]).isEmpty, "A successful key list with no fans")
        check(FanDecoder.rpm(-1) == nil && FanDecoder.rpm(100_000) == nil, "RPM plausibility bounds")
        check(FanReading(id: 0, rpm: 3000, maximumRPM: 6000).fraction == 0.5, "Bar reflects actual/max RPM")
        check(FanReading(id: 0, rpm: 0, maximumRPM: 6000).fraction == 0, "Stopped fan has empty bar")
        check(FanReading(id: 0, rpm: 7000, maximumRPM: 6000).fraction == 1, "Bar never overflows")
        check(FanReading(id: 0, rpm: nil, maximumRPM: 6000).fraction == nil, "Missing RPM is unavailable")
        check(FanReading(id: 0, rpm: 3000, maximumRPM: 0).fraction == nil, "No invented maximum")
        let two = FanSample(status: .ready, fans: [FanReading(id: 0, rpm: 2720, maximumRPM: 6000), FanReading(id: 1, rpm: 2640, maximumRPM: 6000)])
        let failed = FanSample.unavailable.preservingTopology(from: two)
        check(failed.fans.count == 2 && failed.fans.allSatisfy { $0.rpm == nil }, "Failures retain rows but clear stale RPM")
        check(FanSample.noFans.preservingTopology(from: two).fans.isEmpty, "Confirmed no-fan result is distinct from failure")

        _ = NSApplication.shared
        UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "fps", "hud.alignment": "vertical"], forName: UserDefaults.argumentDomain)
        let menu = HUDFanMenuView(options: .init(), sample: .noFans)
        let useLabel: NSTextField = member(menu, "useLabel")
        let master: NSButton = member(menu, "master")
        let mode: NSSegmentedControl = member(menu, "mode")
        let average: HUDReadingCheckbox = member(menu, "average")
        check(!master.isEnabled && master.state == .off && !mode.isEnabled, "No fans disables and unchecks the category and its controls")
        check(!average.isEnabled && average.state == .off, "No fans also dims and unchecks Average")
        check(menu.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Not available" } && FanSample.noFans.message == "Not available", "Menu and HUD share the no-fan message")
        check((0..<mode.segmentCount).map { mode.label(forSegment: $0)! } == ["Bar", "RPM", "Both"] && mode.selectedSegment == 2, "Fan mode labels and Both default")
        menu.update(sample: two)
        check(master.isEnabled && master.state == .on && mode.isEnabled, "Category and saved usage return on detection")
        let averageMode: NSSegmentedControl = member(menu, "averageMode")
        check(average.isEnabled && average.state == .on && averageMode.selectedSegment == 1, "Saved average returns on detection with Horizontal default")
        let single = FanSample(status: .ready, fans: [FanReading(id: 0, rpm: 0, maximumRPM: 6000)])
        menu.update(sample: single)
        check(mode.isEnabled, "Single fan retains normal reading controls")
        check(!average.isEnabled && average.state == .off && !averageMode.isEnabled, "Single fan cannot enable average or its layout selector")
        check(single.displayReadings(averaged: true).map(\.title) == ["FAN 1"], "Saved averaging cannot rename a single fan to FAN AVG")
        menu.update(sample: two)
        check(average.isEnabled && average.state == .on && averageMode.isEnabled, "Average preference returns for multiple fans")
        let rpmHighlight: NSButton = member(menu, "rpmHighlight")
        func selectFanMode(_ index: Int) {
            mode.selectedSegment = index
            mode.sendAction(mode.action, to: mode.target)
        }
        var lastFanOptions: HUDFanOptions?
        menu.onChange = { lastFanOptions = $0 }
        check(HUDFanOptions().mode == .both && rpmHighlight.isEnabled, "Both is the default and allows RPM emphasis")
        selectFanMode(2)
        check(rpmHighlight.state == .off && rpmHighlight.isEnabled, "RPM emphasis defaults off and is available in Both")
        rpmHighlight.performClick(nil)
        check(lastFanOptions?.rpmHighlighted == true && lastFanOptions?.mode == .both, "Emphasis click preserves Both mode")
        selectFanMode(0)
        check(lastFanOptions?.mode == .bar && !rpmHighlight.isEnabled, "Total disables RPM emphasis")
        selectFanMode(1)
        check(lastFanOptions?.mode == .rpm && rpmHighlight.isEnabled && rpmHighlight.state == .on, "RPM restores saved emphasis")
        rpmHighlight.performClick(nil)
        check(lastFanOptions?.rpmHighlighted == false && lastFanOptions?.mode == .rpm, "Turning emphasis off does not change mode")
        selectFanMode(2)
        check(HUDAlignment.horizontal.allows(.fans), "Fans available horizontally")
        check(HUDFanOptions().averages(in: .horizontal) && !HUDFanOptions().averages(in: .vertical), "Default affects Horizontal only")
        let mixed = FanSample(status: .ready, fans: [FanReading(id: 0, rpm: 1000, maximumRPM: 2000), FanReading(id: 1, rpm: 3000, maximumRPM: 10000)])
        let avg = mixed.displayReadings(averaged: true)[0]
        check(avg.iconMarker == "A" && single.displayReadings(averaged: true)[0].iconMarker == "1", "Hub markers distinguish individuals and average")
        check(avg.title == "FAN AVG" && avg.rpm == 2000 && abs(avg.fraction! - 0.4) < 0.0001, "Mean of normalized speeds, not ratio of means")
        let missing = FanSample(status: .ready, fans: [mixed.fans[0], FanReading(id: 1, rpm: nil, maximumRPM: 10000)])
        check(missing.displayReadings(averaged: true)[0].rpm == nil && missing.displayReadings(averaged: true)[0].fraction == nil, "No partial averages")
        let noMaximum = FanSample(status: .ready, fans: [mixed.fans[0], FanReading(id: 1, rpm: 3000, maximumRPM: nil)])
        check(noMaximum.displayReadings(averaged: true)[0].rpm == 2000 && noMaximum.displayReadings(averaged: true)[0].fraction == nil, "RPM average does not require maximum speeds")
        check(FanSample.noFans.displayReadings(averaged: true).isEmpty, "No invented average on fanless Macs")
        let six = FanSample(status: .ready, fans: (0..<6).map { FanReading(id: $0, rpm: Double($0 * 1000), maximumRPM: 6000) })
        check(six.displayReadings(averaged: false).map(\.iconMarker) == ["1", "2", "3", "4"], "Only the first four individual fans are visible")
        check(six.displayReadings(averaged: true).first?.rpm == 2500, "Average includes fans beyond the display limit")
        let suiteName = "PerformanceHUD.FanTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for sample in [FanSample.checking, .unavailable, single, two] {
            check(!HUDPreferences.applyFanAvailability(sample, in: defaults), "Checking, errors and detected fans must not disable FAN")
            check(defaults.object(forKey: "hud.metric.fans") == nil, "Hardware with fans retains the enabled default, including 0 RPM")
        }
        check(HUDPreferences.applyFanAvailability(.noFans, in: defaults), "Confirmed fanless hardware defaults FAN off")
        check(defaults.object(forKey: "hud.metric.fans") as? Bool == false, "Persist the fanless default across launches")
        check(!HUDPreferences.applyFanAvailability(.noFans, in: defaults), "Repeated detection leaves the saved off choice alone")
        defaults.set(true, forKey: "hud.metric.fans")
        check(HUDPreferences.applyFanAvailability(.noFans, in: defaults) && !defaults.bool(forKey: "hud.metric.fans"), "Existing enabled settings are forced off on fanless Macs")
        menu.update(sample: .noFans, options: .init(enabled: false))
        check(master.state == .off && !master.isEnabled, "Confirmed fanless hardware disables the category")
        lastFanOptions = nil
        master.performClick(nil)
        master.sendAction(master.action, to: master.target)
        check(lastFanOptions == nil && master.state == .off && !mode.isEnabled, "Fanless category rejects clicks and direct actions")
        for status in [FanSample.checking, .unavailable] {
            menu.update(sample: status, options: .init())
            check(master.isEnabled && master.state == .on, "Unknown hardware or read failure cannot force the category off")
        }
        menu.update(sample: two, options: .init())
        for key in ["hud.fan.average", "hud.fan.averageMode", "hud.fan.rpmHighlighted"] { defaults.set("test", forKey: key) }
        HUDPreferences.resetOptions(in: defaults)
        check(HUDPreferences.applyFanAvailability(.noFans, in: defaults) && !defaults.bool(forKey: "hud.metric.fans"), "Options reset reapplies the known fanless default")
        check(defaults.object(forKey: "hud.fan.average") == nil && defaults.object(forKey: "hud.fan.averageMode") == nil, "Options reset includes average preferences")
        check(defaults.object(forKey: "hud.fan.rpmHighlighted") == nil, "Options reset clears RPM emphasis")
        let memMenu = HUDResourceMenuView(group: .ram, options: .init(enabled: true, temperature: false, totalUse: true, focusedApp: false))
        let menuCanvas = NSView(frame: NSRect(x: 0, y: 0, width: menu.frame.width,
                                            height: menu.frame.height + memMenu.frame.height))
        menu.frame.origin.y = 0; memMenu.frame.origin.y = menu.frame.height
        menuCanvas.addSubview(menu); menuCanvas.addSubview(memMenu)
        let menuWindow = NSWindow(contentRect: menuCanvas.frame, styleMask: [], backing: .buffered, defer: false)
        menuWindow.contentView = menuCanvas
        menuCanvas.layoutSubtreeIfNeeded()
        let memoryControls: [Int: NSButton] = member(memMenu, "controls")
        check(abs(average.frame.minX - memoryControls[5]!.convert(.zero, to: memMenu).x) < 1, "Average aligns under Details")
        check(useLabel.stringValue == "Use" && useLabel.frame.minX == HUDCategoryLayout.readingLeading + HUDCategoryLayout.readingLabelInset, "Use is a plain caption in the menu label column")
        check(average.frame.maxX < averageMode.frame.minX && useLabel.frame.maxY < average.frame.minY,
              "Fan controls occupy separate nonoverlapping rows")
        check(averageMode.frame.width >= averageMode.intrinsicContentSize.width, "Layout selector fits its labels")
        check(rpmHighlight.frame.minX > mode.frame.maxX && menu.bounds.contains(rpmHighlight.frame),
              "RPM emphasis fits the common right column")
        let hitPoint = menu.convert(NSPoint(x: rpmHighlight.frame.midX, y: rpmHighlight.frame.midY), to: menu.superview)
        check(menu.hitTest(hitPoint) === rpmHighlight, "RPM emphasis is independently clickable")

        let hud = HUDWindowController()
        let panel: HUDPanel = member(hud, "panel")
        panel.alphaValue = 0
        // Test the active renderer while leaving the fixture invisible.
        hud.setHUDEnabled(true)
        hud.setPackagePowerOptions(.init(enabled: false))
        for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: false) }
        let fanView: HUDFanView = member(hud, "fanView")
        let horizontal: HUDHorizontalView = member(hud, "horizontalView")
        if CommandLine.arguments.contains("--controls-only") {
            hud.setBackground(.dark)
            hud.setAlignment(.horizontal)
            hud.setHUDScale(.normal)
            hud.setFanOptions(.init(average: false))
            for sample in [FanSample.noFans, .checking, .unavailable] {
                hud.updateFans(sample)
                let labels: [String: NSTextField] = member(horizontal, "labels")
                let status = labels["fan.status"]!
                check(status.font == HUDStyle.smallLabelFont()
                      && status.textColor == HUDStyle.TextStyle.label.color(background: .dark),
                      "Fan status messages use Label style")
            }
            hud.updateFans(two)
            for highlighted in [false, true, false] {
                for mode in [HUDFanMode.rpm, .both] {
                    hud.setFanOptions(.init(mode: mode, average: false, rpmHighlighted: highlighted))
                    let labels: [String: NSTextField] = member(horizontal, "labels")
                    let rpm = labels["fan.0.rpm"]!
                    let style: HUDStyle.TextStyle = highlighted ? .emphasizedReading : .reading
                    check(rpm.font == style.font(ofSize: 12) && rpm.textColor == style.color(background: .dark),
                          "RPM uses Reading or Emphasized Reading in RPM and Both modes")
                }
            }
            if let index = CommandLine.arguments.firstIndex(of: "--preview"), CommandLine.arguments.indices.contains(index + 1) {
                let prefix = CommandLine.arguments[index + 1]
                func render(_ view: NSView, name: String, light: Bool = false) {
                    view.wantsLayer = true
                    view.layer?.backgroundColor = NSColor(white: light ? 0.90 : 0.12, alpha: 1).cgColor
                    let window = NSWindow(contentRect: view.frame, styleMask: [], backing: .buffered, defer: false)
                    window.contentView = view
                    window.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
                    view.layoutSubtreeIfNeeded()
                    let image = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                    view.cacheDisplay(in: view.bounds, to: image)
                    try! image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: prefix + name + ".png"))
                }
                menu.update(sample: two, options: .init(mode: .both, rpmHighlighted: true))
                render(menuCanvas, name: "-menu")
                let fps = HUDFPSMenuView(options: .init(enabled: true, mode: .both), alignment: .vertical)
                render(fps, name: "-fps-menu")
                let view = HUDFanView(frame: NSRect(x: 0, y: 0, width: HUDStyle.verticalValueColumnRight(), height: 21))
                for light in [false, true] {
                    let suffix = light ? "-light" : "-dark"
                    let background: HUDBackground = light ? .light : .dark
                    view.update(sample: .noFans, options: .init(), background: background)
                    render(view, name: "-status" + suffix, light: light)
                    for highlighted in [false, true] {
                        view.update(sample: single, options: .init(mode: .both, rpmHighlighted: highlighted), background: background)
                        render(view, name: (highlighted ? "-emphasized" : "-reading") + suffix, light: light)
                    }
                }
            }
            hud.shutdown()
            print("PASS: fan menu states, RPM emphasis placement/clicks, status Label style, RPM Reading/Emphasized Reading in both display modes")
            return
        }

        for alignment in HUDAlignment.allCases {
            hud.setAlignment(alignment)
            for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: false) }
            for scale in (CommandLine.arguments.contains("--normal-size") ? [.normal] : HUDScale.allCases) {
                hud.setHUDScale(scale)
                var horizontalPanelHeight: CGFloat?
                for count in [0, 1, 2, 3, 4, 16] {
                    for display in HUDFanMode.allCases {
                        for averageMode in HUDFanAverageMode.allCases {
                            for averaged in [false, true] {
                                let configuration = "alignment=\(alignment), scale=\(scale.rawValue), fans=\(count), mode=\(display), average=\(averaged), averageMode=\(averageMode)"
                                context = configuration
                                let options = HUDFanOptions(enabled: true, mode: display, average: averaged, averageMode: averageMode)
                                hud.setFanOptions(options)
                                let sample = FanSample(status: count == 0 ? .noFans : .ready, fans: (0..<count).map { FanReading(id: $0, rpm: 0, maximumRPM: 6000) })
                                hud.updateFans(sample)
                                panel.contentView?.layoutSubtreeIfNeeded()
                                let size = panel.frame.size
                                let expectedFans = count == 0 ? 0 : options.averages(in: alignment) ? 1 : min(count, 4)
                                if alignment == .vertical {
                                    let stack: NSView = member(hud, "stackView")
                                    let rows: [HUDMetric: NSView] = member(hud, "metricRows")
                                    check(stack.subviews.last(where: { !$0.isHidden }) === rows[.fans], "No divider follows FAN when it is the last category")
                                    check(fanView.rowCount == max(1, (expectedFans + 1) / 2), "Correct averaged/individual vertical rows")
                                    check(abs(fanView.frame.height - fanView.height()) <= 0.5, "All fan rows fit")
                                    let graph: HUDMemoryPressureHistoryView = member(hud, "ramPressureHistory")
                                    let target = graph.intrinsicContentSize.width - 4
                                    check(abs(fanView.barWidth - target) < 0.01,
                                          "Fan bar matches the pressure history plot width: actual=\(fanView.barWidth), target=\(target), bounds=\(fanView.bounds)")
                                    if expectedFans > 0 {
                                        let cell = fanView.frames(forFanAt: expectedFans - 1)
                                        check(cell.badge.width == HUDFanIcon.side
                                              && (cell.rpm != nil) == display.showsRPM && (cell.bar != nil) == display.showsBar,
                                              "Every fan entry keeps its badge with the selected readings")
                                        let gap = HUDStyle.metricColumnSpacing
                                        if let rpm = cell.rpm {
                                            let widest = ("99999 RPM" as NSString).size(withAttributes: [
                                                .font: HUDStyle.readingFont(highlighted: true)]).width
                                            check(rpm.width >= widest && rpm.minX >= cell.badge.maxX + gap,
                                                  "The five-digit RPM slot clears the badge")
                                        }
                                        if let rpm = cell.rpm, let bar = cell.bar, expectedFans == 1 {
                                            check(rpm.maxX <= bar.minX - gap, "Single RPM clears its bar")
                                        }
                                        if expectedFans >= 3 {
                                            let first = fanView.frames(forFanAt: (expectedFans - 1) % 2)
                                            check(cell.badge.minX == first.badge.minX && cell.badge.minY > first.badge.maxY,
                                                  "Later pairs reuse their columns and odd tails stay on the left")
                                        }
                                    }
                                } else {
                                    let labels: [String: NSTextField] = member(horizontal, "labels")
                                    let symbols: [String: NSImageView] = member(horizontal, "symbols")
                                    let icons = symbols.filter { $0.key.hasPrefix("fan.") && $0.key.hasSuffix(".title") && !$0.value.isHidden }
                                    check(icons.count == expectedFans, "All displayed horizontal fans have icons")
                                    let pixel = horizontal.convertFromBacking(NSSize(width: 1, height: 1)).width
                                    let bars: [String: HUDFanBarView] = member(horizontal, "bars")
                                    let fans = sample.displayReadings(averaged: options.averages(in: .horizontal))
                                    let panelHeight = HUDStyle.rowHeight + 2 * HUDStyle.verticalPadding
                                    if let horizontalPanelHeight {
                                        check(size.height == horizontalPanelHeight, "Fan count and display mode keep the same window height")
                                    } else {
                                        horizontalPanelHeight = size.height
                                    }
                                    check(abs(horizontal.bounds.height - panelHeight) <= pixel,
                                          "Stacking fans keeps the horizontal strip height: \(horizontal.bounds.height), expected \(panelHeight)")
                                    let parts: [(String, [String: NSView], Bool)] = [
                                        ("title", symbols, true), ("rpm", labels, display.showsRPM), ("bar", bars, display.showsBar)]
                                    for (part, views, shown) in parts {
                                        let frames = fans.compactMap { fan -> NSRect? in
                                            let id = "fan.\(fan.id).\(part)"
                                            return views[id].flatMap { $0.isHidden ? nil : $0.frame }
                                        }
                                        let expectedCount = shown ? expectedFans : 0
                                        check(frames.count == expectedCount, "Each fan shows its selected parts")
                                        for (i, frame) in frames.enumerated() {
                                            check(frame.minY >= horizontal.bounds.minY - pixel && frame.maxY <= horizontal.bounds.maxY + pixel,
                                                  "Fan \(part) fits inside the existing horizontal strip")
                                            if frames.count == 1 && part == "title" {
                                                check(abs(frame.midY - HUDStyle.rowHeight / 2) <= pixel, "One badge stays centered")
                                            }
                                            if i % 2 == 1 {
                                                let upper = frames[i - 1]
                                                check(frame.minX == upper.minX && abs(upper.midY - frame.midY - 23) <= pixel,
                                                      "Fans in a pair share a column and sit 23 pt apart at 1×")
                                            } else if i > 0 {
                                                check(frame.minX > frames[0].maxX && frame.minY == frames[0].minY,
                                                      "Fan 3 starts the next column level with fan 1, including with an empty slot below")
                                            }
                                        }
                                    }
                                    let columnGap = HUDStyle.metricColumnSpacing
                                    for (id, icon) in icons {
                                        check(icon.image != nil && abs(icon.frame.width - HUDFanIcon.side) <= pixel / 2 + 0.001
                                              && abs(icon.frame.height - icon.frame.width) < 0.001,
                                              "Icons retain their compact square size (\(icon.frame.size), pixel \(pixel))")
                                        if display.showsRPM {
                                            let rpm = labels[id.replacingOccurrences(of: ".title", with: ".rpm")]!
                                            let slot = rpm.alignmentRect(forFrame: rpm.frame)
                                            check(rpm.alignment == .center && abs(slot.minX - icon.frame.maxX - columnGap) <= pixel + 0.001,
                                                  "Both and RPM center the number in the same slot beside its badge")
                                        }
                                    }
                                    for (id, bar) in bars where !bar.isHidden {
                                        let icon = icons[id.replacingOccurrences(of: ".bar", with: ".title")]!
                                        if display == .bar {
                                            let gap = bar.frame.minX - icon.frame.maxX
                                            check(abs(gap - 2 * columnGap) <= pixel + 0.001,
                                                  "Bar alone uses the wider label-to-reading gap")
                                        } else {
                                            guard let rpm = labels[id.replacingOccurrences(of: ".bar", with: ".rpm")] else {
                                                fatalError("Both needs RPM beside its bar")
                                            }
                                            let textRect = rpm.alignmentRect(forFrame: rpm.frame)
                                            let halfTextWidth = rpm.intrinsicContentSize.width / 2
                                            let leftGap = textRect.midX - halfTextWidth - icon.frame.maxX
                                            let rightGap = bar.frame.minX - textRect.midX - halfTextWidth
                                            check(rpm.alignment == .center && leftGap > 0 && abs(leftGap - rightGap) <= pixel + 0.001,
                                                  "Both centres RPM with equal visible spacing to its icon and bar")
                                        }
                                        let graph: HUDMemoryPressureHistoryView = member(hud, "ramPressureHistory")
                                        check(abs(bar.frame.width - (graph.intrinsicContentSize.width - 4)) <= pixel / 2 + 0.001,
                                              "Horizontal and vertical bars share the pressure graph width")
                                    }
                                    if count == 1 { check(icons.values.first?.accessibilityLabel() == "FAN 1", "Single fan keeps an accessible label") }
                                    if count == 0, let status = labels["fan.status"] {
                                        check(status.font == HUDStyle.smallLabelFont(), "No fan status uses the small Label font")
                                    }
                                    let dividers: [NSView] = member(horizontal, "dividers")
                                    let visible = dividers.filter { !$0.isHidden }
                                    let faintWidth = max(0.5, pixel)
                                    check(visible.count == max(0, (expectedFans + 1) / 2 - 1) && visible.allSatisfy {
                                        abs($0.frame.width - faintWidth) < 0.001 && ($0.layer?.backgroundColor?.alpha ?? 1) < 0.2
                                    }, "Only faint, pixel-aligned dividers within FAN")
                                }
                                if count == 0 {
                                    for status in [FanSample.checking, .noFans, .unavailable] {
                                        context = "\(configuration), status=\(status.status)"
                                        hud.updateFans(status)
                                        check(panel.frame.size == size, "Status message changes do not resize the window")
                                    }
                                    continue
                                }
                                for rpm: Double? in [0, 1, 2720, 9999, 99_999, nil] {
                                    context = "\(configuration), rpm=\(String(describing: rpm))"
                                    let update = FanSample(status: .ready, fans: sample.fans.map { FanReading(id: $0.id, rpm: rpm, maximumRPM: 6000) })
                                    hud.updateFans(update)
                                    check(panel.frame.size == size, "RPM changes never resize the window")
                                }
                                context = "\(configuration), read failure"
                                hud.updateFans(.unavailable.preservingTopology(from: sample))
                                check(panel.frame.size == size, "Read failures never resize the window")
                            }
                        }
                    }
                }
            }
        }
        // Adding FAN must not enlarge the established vertical MEM layout.
        hud.setAlignment(.vertical)
        for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: false) }
        hud.setMetricEnabled(.ramTotal, enabled: true)
        for scale in HUDScale.allCases {
            hud.setHUDScale(scale)
            hud.setFanOptions(.init(enabled: false))
            let widthWithoutFans = panel.frame.width
            var totalBarWidth: CGFloat?
            for mode in HUDFanMode.allCases {
                context = "vertical MEM and FAN, scale=\(scale.rawValue), mode=\(mode)"
                hud.setFanOptions(.init(mode: mode, average: false))
                hud.updateFans(two)
                panel.contentView?.layoutSubtreeIfNeeded()
                check(panel.frame.width == widthWithoutFans, "Showing FAN does not widen the vertical HUD")
                if mode == .bar { totalBarWidth = fanView.barWidth }
                else if let totalBarWidth { check(fanView.barWidth == totalBarWidth, "Total-only and Both keep exactly the same bar width") }
            }
        }
        hud.setResourceOptions(.init(enabled: true, temperature: false, totalUse: true, focusedApp: false,
                                     details: true, pressure: true, pressureMode: .colorHistory), for: .ram)
        let history: HUDMemoryPressureHistoryView = member(hud, "ramPressureHistory")
        let titles: [HUDMetric: NSTextField] = member(hud, "titleLabels")
        let memoryTitle = titles[.ramTotal]!
        let swap: NSTextField = member(hud, "ramSwapValueLabel")
        for scale in [HUDScale.small, .init(rawValue: 0.81), .normal, .large] {
            hud.setHUDScale(scale)
            for mode in HUDFanMode.allCases {
                hud.setFanOptions(.init(mode: mode, average: false))
                hud.updateFans(two)
                panel.contentView?.layoutSubtreeIfNeeded()
                let plot = fanView.convert(history.plotBounds, from: history)
                let labelColumn = fanView.convert(memoryTitle.alignmentRect(forFrame: memoryTitle.frame),
                                                  from: memoryTitle.superview).minX
                let left = fanView.frames(forFanAt: 0), right = fanView.frames(forFanAt: 1)
                let height = HUDStyle.rowHeight + (mode.showsBar ? 10 : 0)
                check(abs(fanView.frame.height - ceil(height)) <= 0.5, "Paired bars have a separate line above their badges")
                for (cell, start) in [(left, labelColumn), (right, plot.minX)] {
                    let badge = cell.badge
                    let badgeStart = badge.minX + HUDFanIcon.inkInset
                    check(abs(badgeStart - start) <= 0.5 && badge.width == 20,
                          "The 20 pt badge outline starts at the label or plot edge in every mode")
                    if let rpm = cell.rpm {
                        check(abs(rpm.maxX - start - plot.width) <= 0.5 && rpm.midY == badge.midY,
                              "RPM shares the badge line and aligns to its bar's end")
                    }
                    if let bar = cell.bar {
                        check(abs(bar.minX - start) <= 0.5 && abs(bar.width - plot.width) <= 0.5, "Bars match the pressure plot")
                        if let rpm = cell.rpm {
                            check(abs(rpm.minY - bar.maxY - 4) < 0.001, "Both leaves a scaled 4 pt gap before the badge/RPM row")
                        }
                        check(badge.minY >= bar.maxY + 4, "Each paired badge sits below its bar in Bar and Both")
                    }
                }
            }
            hud.setFanOptions(.init(mode: .rpm, average: false))
            panel.contentView?.layoutSubtreeIfNeeded()
            let leftBadge = fanView.convert(fanView.frames(forFanAt: 0).badge, to: nil)
            let rightRPM = fanView.convert(fanView.frames(forFanAt: 1).rpm!, to: nil)
            hud.setFanOptions(.init(mode: .both, averageMode: .vertical))
            check(fanView.rowCount == 1 && fanView.frames(forFanAt: 0).bar!.midY == fanView.frames(forFanAt: 0).badge.midY,
                  "Average brings the badge, RPM, and bar back to the inline row")
            let swapEnd = swap.superview!.convert(swap.alignmentRect(forFrame: swap.frame), to: nil).maxX
            for sample in [single, two] {
                hud.updateFans(sample)
                for mode in HUDFanMode.allCases {
                    hud.setFanOptions(.init(mode: mode, averageMode: .vertical))
                    for showMemory in [true, false, true] {
                        hud.setMetricEnabled(.ramTotal, enabled: showMemory)
                        panel.contentView?.layoutSubtreeIfNeeded()
                        let cell = fanView.frames(forFanAt: 0)
                        let badgeStart = fanView.convert(cell.badge, to: nil).minX
                        check(badgeStart == leftBadge.minX, "Single and average badges keep the left fan's position")
                        if let bar = cell.bar {
                            check(cell.badge.midY == bar.midY && cell.badge.maxX < bar.minX,
                                  "Single and average badges share the bar's line without overlap")
                        }
                        if let rpm = cell.rpm {
                            let rpmEnd = fanView.convert(rpm, to: nil).maxX
                            let expectedEnd = mode == .rpm ? rightRPM.maxX : swapEnd
                            check(abs(rpmEnd - expectedEnd) <= 0.5,
                                  "Single and average RPM align with the right fan in RPM mode and Swap in Both: mode=\(mode), RPM=\(rpmEnd), expected=\(expectedEnd)")
                        }
                    }
                }
            }
        }
        // A two-fan column has only the category dividers on its sides.
        hud.setAlignment(.horizontal)
        for metric in HUDMetric.allCases { hud.setMetricEnabled(metric, enabled: false) }
        hud.setHUDScale(.normal)
        hud.setMetricEnabled(.ramTotal, enabled: true)
        hud.setMetricEnabled(.battery, enabled: true)
        hud.setFanOptions(.init(average: false))
        hud.updateFans(two)
        context = "horizontal MEM, two fans, and BAT boundaries"
        let dividers: [NSView] = member(horizontal, "dividers")
        check(dividers.filter { !$0.isHidden }.map { $0.frame.width } == [1.5, 1.5], "The FAN column keeps both category dividers")
        for alignment in HUDAlignment.allCases {
            context = "RPM emphasis, alignment=\(alignment), scale=1, mode=both"
            hud.setAlignment(alignment)
            hud.setFanOptions(.init(mode: .both, average: false))
            let unhighlightedSize = panel.frame.size
            hud.setFanOptions(.init(mode: .both, average: false, rpmHighlighted: true))
            check(panel.frame.size == unhighlightedSize, "RPM emphasis does not resize the HUD")
            if alignment == .horizontal {
                let labels: [String: NSTextField] = member(horizontal, "labels")
                check(labels["fan.0.rpm"]?.font == HUDStyle.readingFont(highlighted: true), "RPM uses highlighted font")
            }
        }
        hud.setAlignment(.horizontal)
        hud.shutdown()
        print("PASS: fan formats/discovery, missing/zero/invalid readings, menu states, averages and defaults, aligned menu controls, both layouts at all scales and modes, stable window geometry")
        if CommandLine.arguments.contains("--probe") {
            let actual = SMCTemperatureReader().readFans()
            print("Actual hardware:", actual.status, "fans:", actual.fans.count)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--preview"), CommandLine.arguments.indices.contains(index + 1) {
            let path = CommandLine.arguments[index + 1]
            func snapshot(_ view: NSView, at path: String) {
                let canvas = NSView(frame: NSRect(x: 0, y: 0, width: view.frame.width + 40, height: view.frame.height + 40))
                canvas.wantsLayer = true; canvas.layer?.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1).cgColor
                canvas.appearance = NSAppearance(named: .darkAqua)
                view.frame.origin = NSPoint(x: 20, y: 20); canvas.addSubview(view)
                let window = NSWindow(contentRect: canvas.frame, styleMask: [], backing: .buffered, defer: false)
                window.contentView = canvas
                canvas.layoutSubtreeIfNeeded()
                let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
                canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
                try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
            }
            snapshot(menuCanvas, at: path + "-menu.png")
            for useAverage in [false, true] {
                hud.setFanOptions(.init(average: useAverage))
                hud.updateRAM(.ramTotal, usage: .init(percentage: 60, usedBytes: 16_000_000_000, swapUsedBytes: 0))
                hud.updateMemoryPressure("normal")
                hud.updateFans(two)
                snapshot(horizontal, at: path + (useAverage ? "-horizontal-average.png" : "-horizontal-individual.png"))
            }
            let view = HUDFanView(frame: NSRect(x: 0, y: 0, width: HUDStyle.verticalValueColumnRight(), height: 21))
            let history: HUDMemoryPressureHistoryView = member(hud, "ramPressureHistory")
            view.setMemoryColumns(barWidth: history.intrinsicContentSize.width - 4,
                                  swapValueTrailing: swap.alignmentRect(forFrame: swap.frame).maxX)
            view.update(sample: two, options: .init(averageMode: .both), background: .dark)
            snapshot(view, at: path + "-vertical-average.png")
            view.update(sample: two, options: .init(average: false), background: .dark)
            view.frame.size.height = view.height()
            snapshot(view, at: path + "-vertical-individual.png")
            view.frame.size.height = HUDStyle.rowHeight
            for mode in HUDFanMode.allCases {
                view.update(sample: single, options: .init(mode: mode, averageMode: .both), background: .dark)
                snapshot(view, at: path + "-vertical-single-" + mode.rawValue + ".png")
            }
            menu.update(sample: single)
            snapshot(menuCanvas, at: path + "-menu-single.png")
            rpmHighlight.performClick(nil)
            snapshot(menuCanvas, at: path + "-menu-highlighted.png")
            view.update(sample: single, options: .init(mode: .both, rpmHighlighted: true), background: .dark)
            snapshot(view, at: path + "-vertical-highlighted.png")

        }
    }
}
