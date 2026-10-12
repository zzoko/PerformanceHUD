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
        func warningParts(_ category: HUDResourceMenuView) -> (HUDHeatWarningMenuView, HUDReadingCheckbox, NSTextField) {
            let warning: HUDHeatWarningMenuView = member(category, "heatWarningControl") as HUDHeatWarningMenuView?
                ?? { fatalError("Missing heat warning controls") }()
            return (warning, member(warning, "checkbox"), member(warning, "thresholdField"))
        }
        for category in [gpu, cpu, battery] {
            let (warning, checkbox, field) = warningParts(category)
            let checkboxRect = checkbox.convert(checkbox.bounds, to: category)
            check(checkboxRect.minX == HUDCategoryLayout.modeLeading,
                  "Heat warning checkbox begins exactly at the segmented-control column")
            check(checkbox.frame.width >= checkbox.intrinsicContentSize.width && checkbox.frame.maxX < field.frame.minX,
                  "Heat warning label fits without touching its temperature field")
            check(warning.bounds.contains(field.frame), "Threshold field fits inside its shared mode column")
            check(checkbox.emphasisControl == nil && checkbox.state == .on && field.isEnabled,
                  "Heat warning starts enabled and has no separate emphasis button")
        }
        for category in [ane, memory] {
            let warning: HUDHeatWarningMenuView? = member(category, "heatWarningControl")
            check(warning == nil, "Heat warning belongs only to temperature readings")
        }
        let (gpuWarning, gpuWarningCheckbox, gpuThreshold) = warningParts(gpu)
        let gpuControls: [Int: NSButton] = member(gpu, "controls")
        var heatOptions = options
        gpu.onChange = { heatOptions = $0 }
        gpuWarning.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: gpuThreshold))
        gpuThreshold.stringValue = ""
        gpu.update(alignment: .vertical)
        check(gpuThreshold.stringValue.isEmpty, "Menu refresh preserves an empty, unfinished temperature edit")
        gpuThreshold.stringValue = "101"
        gpuWarning.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: gpuThreshold))
        check(heatOptions.heatWarning.thresholdCelsius == 101 && heatOptions.highlighted == options.highlighted,
              "Committing a temperature changes only the threshold")
        for invalid in ["", "abc", "99.5", "0", "150", "-5"] {
            gpuThreshold.stringValue = invalid
            gpuThreshold.sendAction(gpuThreshold.action, to: gpuThreshold.target)
            check(heatOptions.heatWarning.thresholdCelsius == 101 && gpuThreshold.stringValue == "101",
                  "Invalid temperature restores the last valid value: \(invalid)")
        }
        gpuWarning.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: gpuThreshold))
        gpuThreshold.stringValue = "102"
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: NSMenu())
        check(heatOptions.heatWarning.thresholdCelsius == 102, "Closing a menu commits its last typed threshold")
        gpuThreshold.stringValue = "103"
        gpuWarningCheckbox.performClick(nil)
        check(!heatOptions.heatWarning.enabled && heatOptions.heatWarning.thresholdCelsius == 103 && !gpuThreshold.isEnabled,
              "Turning a warning off retains the edited threshold and disables its field")
        gpuWarningCheckbox.performClick(nil)
        check(heatOptions.heatWarning.enabled && gpuThreshold.isEnabled, "Turning a warning on restores its field")
        gpuWarning.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: gpuThreshold))
        gpuThreshold.stringValue = "104"
        let handledEscape = gpuWarning.control(gpuThreshold, textView: NSTextView(frame: .zero),
                                               doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        check(handledEscape && heatOptions.heatWarning.thresholdCelsius == 103 && gpuThreshold.stringValue == "103",
              "Canceling an unfinished edit restores the last committed threshold")
        let thresholdEditor = gpuThreshold.cell!.fieldEditor(for: gpuThreshold)!
        check(thresholdEditor.isFieldEditor && !thresholdEditor.isRichText && thresholdEditor.allowsUndo,
              "Threshold uses a native plain-text field editor with undo available")
        thresholdEditor.string = "90"
        thresholdEditor.setSelectedRange(NSRange(location: 1, length: 0))
        let selectAll = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a",
            isARepeat: false, keyCode: 0)!
        check(thresholdEditor.performKeyEquivalent(with: selectAll) && thresholdEditor.selectedRange().length == 2,
              "Command-A selects the entire threshold without needing an application Edit menu")
        gpuThreshold.stringValue = "103"
        gpuControls[1]!.performClick(nil)
        check(!gpuWarningCheckbox.isEnabled && !gpuThreshold.isEnabled && heatOptions.heatWarning.enabled,
              "A hidden temperature disables warning controls without losing the warning preference")
        gpuControls[1]!.performClick(nil)
        gpuControls[0]!.performClick(nil)
        check(!gpuWarningCheckbox.isEnabled && !gpuThreshold.isEnabled, "A disabled category disables warning controls")
        gpuControls[0]!.performClick(nil)
        let highlightedBefore = heatOptions.highlighted.contains(.temperature)
        (gpuControls[1] as! HUDReadingCheckbox).emphasisControl!.performClick(nil)
        check(heatOptions.highlighted.contains(.temperature) != highlightedBefore && heatOptions.heatWarning.thresholdCelsius == 103,
              "Temperature emphasis stays independent of its warning settings")
        let (_, batteryWarningCheckbox, batteryThreshold) = warningParts(battery)
        var batteryOptions = HUDBatteryOptions(enabled: true, temperature: true, charge: true)
        battery.onBatteryChange = { batteryOptions = $0 }
        check(batteryThreshold.stringValue == "45", "Battery uses its own default threshold")
        batteryThreshold.stringValue = "48"
        batteryThreshold.sendAction(batteryThreshold.action, to: batteryThreshold.target)
        batteryWarningCheckbox.performClick(nil)
        let batteryControls: [Int: NSButton] = member(battery, "controls")
        (batteryControls[1] as! HUDReadingCheckbox).emphasisControl!.performClick(nil)
        let batteryFlow: NSSegmentedControl = member(battery, "flowControl") as NSSegmentedControl?
            ?? { fatalError("Missing battery Charge selector") }()
        batteryFlow.selectedSegment = 0
        batteryFlow.sendAction(batteryFlow.action, to: batteryFlow.target)
        check(batteryOptions.heatWarning.thresholdCelsius == 48 && !batteryOptions.heatWarning.enabled
              && batteryOptions.temperatureHighlighted && batteryOptions.flowMode == .always && batteryOptions.charge,
              "Battery callbacks retain threshold, enabled state, temperature emphasis, and other settings")
        let restoredBattery = HUDResourceMenuView(batteryOptions: batteryOptions)
        let (_, restoredWarningCheckbox, restoredThreshold) = warningParts(restoredBattery)
        check(restoredThreshold.stringValue == "48" && restoredWarningCheckbox.state == .off,
              "Recreating the battery menu preserves its warning settings")
        let pressureMode: NSSegmentedControl = member(memory, "pressureModeControl") as NSSegmentedControl?
            ?? { fatalError("Missing pressure selector") }()
        let pressureStyle: NSSegmentedControl = member(memory, "pressureStyleControl") as NSSegmentedControl?
            ?? { fatalError("Missing pressure style selector") }()
        let memoryControls: [Int: NSButton] = member(memory, "controls")
        check(memoryControls[8]!.frame.minY < memoryControls[5]!.frame.minY, "Pressure is above Details")
        check((memoryControls[8] as! HUDReadingCheckbox).emphasisControl?.isEnabled == false,
              "Default Colored graph mode disables Pressure emphasis")
        check(abs(pressureMode.frame.midY - memoryControls[8]!.frame.midY) < 1, "Pressure owns the style selector")
        var memoryOptions = options
        memory.onChange = { memoryOptions = $0 }
        check(pressureMode.selectedSegment == 1 && pressureStyle.selectedSegment == 3 && pressureMode.isEnabled,
              "Pressure starts in Graph, style B2")
        check(pressureStyle.frame.minY > pressureMode.frame.maxY && pressureStyle.frame.maxY < memoryControls[5]!.frame.minY,
              "Graph styles are below Text/Graph and above Details")
        check(abs(pressureMode.frame.width - pressureStyle.frame.width) < 0.5, "Pressure selectors share the same total width")
        pressureStyle.selectedSegment = 1
        pressureStyle.sendAction(pressureStyle.action, to: pressureStyle.target)
        check(memoryOptions.pressureMode == .colorMeter, "Pressure selector updates its preference")
        memory.update(alignment: .horizontal)
        check(pressureMode.isEnabled && pressureStyle.selectedSegment == 1
              && !pressureStyle.isEnabled(forSegment: 2) && !pressureStyle.isEnabled(forSegment: 3),
              "Horizontal supports meters and disables only the history styles")
        memory.update(alignment: .vertical)
        check(pressureMode.isEnabled && pressureStyle.selectedSegment == 1
              && pressureStyle.isEnabled(forSegment: 2) && pressureStyle.isEnabled(forSegment: 3), "Vertical restores all styles")
        memoryControls[5]!.performClick(nil)
        check(pressureMode.isEnabled && memoryOptions.pressureMode == .colorMeter, "Details off leaves Pressure enabled")
        memoryControls[8]!.performClick(nil)
        check(!pressureMode.isEnabled && !memoryOptions.pressure && !memoryOptions.details, "Pressure can turn off independently")
        memoryControls[8]!.performClick(nil)
        memoryControls[5]!.performClick(nil)
        let memoryUse: NSSegmentedControl = member(memory, "usageModeControl") as NSSegmentedControl?
            ?? { fatalError("Missing memory source") }()
        memoryUse.selectedSegment = 1
        memoryUse.sendAction(memoryUse.action, to: memoryUse.target)
        check(!pressureMode.isEnabled, "App-only memory has no system pressure display")
        memoryUse.selectedSegment = 2
        memoryUse.sendAction(memoryUse.action, to: memoryUse.target)
        check(pressureMode.isEnabled, "Total memory restores the pressure control")
        memoryControls[0]!.performClick(nil)
        check(!pressureMode.isEnabled, "Memory category off disables pressure mode")
        memoryControls[0]!.performClick(nil)
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
        if CommandLine.arguments.contains("--keyboard-probe") {
            let editorMenu = NSMenu()
            editorMenu.autoenablesItems = false
            let editorItem = NSMenuItem()
            let editorCategory = HUDResourceMenuView(group: .gpu, options: options)
            editorItem.view = editorCategory
            editorMenu.addItem(editorItem)
            let (warning, _, field) = warningParts(editorCategory)
            var editedThreshold = options.heatWarning.thresholdCelsius
            editorCategory.onChange = { editedThreshold = $0.heatWarning.thresholdCelsius }
            var step = 0
            var receivedCharacters = false
            func click(_ view: NSView) {
                let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
                for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                    let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: view.window!.windowNumber,
                        context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                    NSApp.postEvent(event, atStart: false)
                }
            }
            func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) {
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: field.window!.windowNumber,
                    context: nil, characters: characters, charactersIgnoringModifiers: characters,
                    isARepeat: false, keyCode: code)!
                NSApp.postEvent(event, atStart: false)
            }
            let tick: @MainActor (Timer) -> Void = { timer in
                defer { step += 1 }
                switch step {
                case 0:
                    check(field.window != nil, "Native menu attaches threshold field to its tracking window")
                    click(field)
                case 1:
                    check(field.currentEditor() != nil, "Clicking the threshold opens its native field editor")
                    key("a", code: 0, modifiers: .command)
                    key("8", code: 28)
                    key("7", code: 26)
                case 2:
                    receivedCharacters = (field.currentEditor() as? NSTextView)?.string == "87"
                    key("\r", code: 36)
                case 3:
                    check(editedThreshold == 87, "Return commits the number typed in the live menu")
                    click(field)
                case 4:
                    key("a", code: 0, modifiers: .command)
                    key("9", code: 25)
                    key("9", code: 25)
                    key("\u{1b}", code: 53)
                case 5:
                    check(editedThreshold == 87 && field.stringValue == "87", "Escape restores the committed temperature")
                    editorMenu.cancelTracking()
                    timer.invalidate()
                default:
                    editorMenu.cancelTracking()
                    timer.invalidate()
                    }
            }
            let timer = Timer(timeInterval: 0.05, repeats: true) { timer in MainActor.assumeIsolated { tick(timer) } }
            RunLoop.main.add(timer, forMode: .eventTracking)
            editorMenu.popUp(positioning: nil, at: NSPoint(x: 100, y: 100), in: nil)
            timer.invalidate()
            check(receivedCharacters, "A real menu tracking loop forwards typed digits to the threshold editor")
            check(editedThreshold == 87, "Escape dismissal keeps the value committed with Return")
            check(!(member(warning, "isEditing") as Bool), "Dismissing the menu leaves no active field editor")
        }
        if let directoryArgument = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("--") }) {
            let directory = URL(fileURLWithPath: directoryArgument, isDirectory: true)
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
