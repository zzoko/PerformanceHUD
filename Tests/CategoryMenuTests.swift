import AppKit

@main struct CategoryMenuTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let options = HUDResourceOptions(enabled: true, temperature: true, totalUse: true, focusedApp: true,
                                         power: true, highlighted: [.power, .totalUse, .focusedApp])
        let fps = HUDFPSMenuView(options: .init(enabled: true, mode: .both), alignment: .vertical)
        let gpu = HUDResourceMenuView(group: .gpu, options: options)
        let cpu = HUDResourceMenuView(group: .cpu, options: options)
        let ane = HUDResourceMenuView(group: .ane, options: options)
        let memory = HUDResourceMenuView(group: .ram, options: options)
        let soc = HUDPackagePowerMenuView(options: .init())
        soc.setState(options: .init(), helper: .ready)
        let fanSample = FanSample(status: .ready, fans: [.init(id: 0, rpm: 2200, maximumRPM: 5000),
                                                       .init(id: 1, rpm: 2400, maximumRPM: 5000)])
        let fan = HUDFanMenuView(options: .init(), sample: fanSample)
        let battery = HUDResourceMenuView(batteryOptions: .init(enabled: true, temperature: true, charge: true))
        let misc = HUDMiscMenuView(options: .init(enabled: true))
        let chip = HUDDeviceInfoMenuView(selected: true, enabled: true)
        let categories: [HUDCategoryMenuView] = [fps, gpu, cpu, ane, soc, memory, fan, battery, misc, chip]
        let list = HUDCategoryListView(categories: categories)
        list.fit(availableHeight: 1000)
        let window = NSWindow(contentRect: list.frame, styleMask: [], backing: .buffered, defer: false)
        window.contentView = list
        list.layoutSubtreeIfNeeded()
        func verifyGeometry() {
            list.layoutSubtreeIfNeeded()
            var previousBottom: CGFloat = 0
            for category in categories {
                check(category.superview === list.documentView, "Only the category list owns each row")
                check(category.frame.minY == previousBottom, "Categories must remain ordered without overlaps or gaps")
                previousBottom = category.frame.maxY
                check(category.frame.width == list.frame.width, "All categories use the same width")
                for view in category.subviews {
                    check(category.bounds.contains(view.frame), "Control outside category: \(type(of: category)) \(view.frame)")
                    if let checkbox = view as? HUDReadingCheckbox {
                        check(checkbox.frame.width >= checkbox.intrinsicContentSize.width,
                              "Reading label must not truncate: \(checkbox.title)")
                    }
                    if let selector = view as? NSSegmentedControl {
                        check(selector.frame.width >= selector.intrinsicContentSize.width, "Mode labels must fit")
                    }
                }
                let emphasis = category.subviews.compactMap { $0 as? HUDEmphasisButton }
                for button in emphasis {
                    check(button.frame.minX == HUDCategoryLayout.emphasisLeading, "Emphasis column must align")
                    for sibling in category.subviews where sibling !== button {
                        check(!button.frame.intersects(sibling.frame), "Emphasis target overlaps another control")
                    }
                }
            }
        }
        verifyGeometry()
        let menu = NSMenu()
        let item = NSMenuItem()
        item.view = list
        menu.addItem(item)
        for height: CGFloat in [240, 620, 320, 1000] {
            _ = menu.size
            list.fit(availableHeight: height)
            list.needsLayout = true
            verifyGeometry()
            check(chip.frame.minY >= misc.frame.maxY && !chip.frame.intersects(fps.frame),
                  "Chip & OS stays below Misc when a native menu measures and resizes the list")
        }
        let controls: [Int: NSButton] = member(gpu, "controls")
        let use = controls[7] as! HUDReadingCheckbox
        let mode: NSSegmentedControl = member(gpu, "usageModeControl") as NSSegmentedControl?
            ?? { fatalError("Missing usage selector") }()
        var changed = options
        gpu.onChange = { changed = $0 }
        use.performClick(nil)
        check(!changed.usageVisible && changed.selectedUsageMode == .both && changed.usageHighlighted,
              "Hiding Use preserves mode and emphasis")
        check(use.emphasisControl?.isEnabled == false, "Hidden reading disables only emphasis")
        mode.selectedSegment = 1
        mode.sendAction(mode.action, to: mode.target)
        check(!changed.usageVisible && changed.selectedUsageMode == .app, "Changing mode cannot enable a hidden reading")
        use.performClick(nil)
        check(changed.focusedApp && !changed.totalUse && changed.usageHighlighted, "Use restores saved mode and emphasis")
        use.emphasisControl!.performClick(nil)
        check(!changed.usageHighlighted && changed.focusedApp && changed.power, "Emphasis is independent of visibility and other readings")
        controls[0]!.performClick(nil)
        check(!changed.enabled && !mode.isEnabled && !use.isEnabled, "Category switch disables subordinate controls")
        controls[0]!.performClick(nil)
        check(changed.enabled && changed.focusedApp && changed.power && mode.isEnabled, "Category returns with its selections")
        let socMaster: NSButton = member(soc, "master")
        let socHighlight: HUDEmphasisButton = member(soc, "highlight")
        var socOptions = HUDPackagePowerOptions(enabled: true, highlighted: true)
        soc.setState(options: socOptions, helper: .ready)
        soc.onChange = { socOptions = $0 }
        socMaster.performClick(nil)
        check(!socOptions.enabled && !socHighlight.isEnabled && socOptions.highlighted,
              "SOC category toggle switches the reading off without losing emphasis")
        socMaster.performClick(nil)
        check(socOptions.enabled && socHighlight.isEnabled && socHighlight.state == .on,
              "SOC switch restores the category and saved emphasis")
        socHighlight.performClick(nil)
        check(!socOptions.highlighted && socOptions.enabled && socMaster.state == .on,
              "SOC emphasis changes without toggling the category")
        var socSetupCount = 0
        soc.onPowerSetup = { socSetupCount += 1 }
        soc.setState(options: .init(enabled: false), helper: .setupRequired)
        socMaster.performClick(nil)
        check(socSetupCount == 1 && socMaster.state == .off && !socHighlight.isEnabled,
              "SOC category toggle offers helper setup without enabling unavailable power")
        soc.setState(options: socOptions, helper: .ready)
        var setupCount = 0
        gpu.onPowerSetup = { setupCount += 1 }
        gpu.setPowerState(.setupRequired, selected: false)
        controls[4]!.performClick(nil)
        check(setupCount == 1 && controls[4]!.state == .off, "Unavailable watts still offer helper setup")
        check((controls[4] as! HUDReadingCheckbox).emphasisControl?.isEnabled == false, "Unavailable power cannot be emphasized")
        gpu.setPowerState(.ready, selected: true)
        let chipMaster: NSButton = member(chip, "master")
        let chipReading: NSTextField = member(chip, "reading")
        var chipSelected = true
        chip.onChange = {
            chipSelected.toggle()
            chip.update(selected: chipSelected, enabled: true)
        }
        chipMaster.performClick(nil)
        check(!chipSelected && chipMaster.state == .off, "Chip category switch hides the reading")
        chipMaster.performClick(nil)
        check(chipSelected && chipReading.textColor == .labelColor, "Chip category switch restores the reading")
        chip.update(selected: true, enabled: false)
        check(chipReading.textColor == .disabledControlTextColor && !chipMaster.isEnabled && chipMaster.state == .off,
              "Horizontal disables Chip & OS without changing its saved selection")
        chip.update(selected: true, enabled: true)
        check(chipReading.textColor == .labelColor && chipMaster.state == .on, "Vertical restores Chip & OS")
        // Short displays retain an actual scrollable document, including the final row.
        list.fit(availableHeight: 240)
        check(list.frame.height == 240 && list.documentView!.frame.height > 240, "Category section fits a small display")
        let last = chip.frame
        list.documentView!.scrollToVisible(last)
        check(list.documentVisibleRect.intersects(last), "Chip & OS stays reachable by scrolling")
        list.fit(availableHeight: 1000)
        fan.update(sample: .noFans)
        list.layoutSubtreeIfNeeded()
        check(fan.frame.height < memory.frame.height, "Fanless category uses one concise status row")
        check(battery.frame.minY == fan.frame.maxY, "Fan status changes reflow the following categories")
        fan.update(sample: fanSample)
        verifyGeometry()
        if CommandLine.arguments.count > 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            for light in [false, true] {
                // The native menu may have reparented the list away from the test window.
                list.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
                let canvas = list.documentView!
                canvas.wantsLayer = true
                canvas.layer?.backgroundColor = NSColor(white: light ? 0.95 : 0.15, alpha: 1).cgColor
                canvas.layoutSubtreeIfNeeded()
                let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
                list.effectiveAppearance.performAsCurrentDrawingAppearance {
                    canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
                }
                try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(light ? "menu-light.png" : "menu-dark.png"))
            }
        }
        print("PASS: category geometry, independent visibility/mode/emphasis, helper setup, scrolling, and fan status reflow")
    }
}
