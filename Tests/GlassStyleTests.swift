import AppKit

@main struct GlassStyleTests {
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }

    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "PerformanceHUD.GlassStyleTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        let originalArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        defer {
            UserDefaults.standard.setVolatileDomain(originalArguments, forName: UserDefaults.argumentDomain)
            NotificationCenter.default.post(name: HUDGlassStyle.didChangeNotification, object: nil)
        }
        let originalGlobal = HUDGlassStyle.systemStrength()
        var options = HUDPreferences.glassOptions(in: store)
        precondition(options == HUDGlassOptions(), "Fresh settings follow the system with no remembered strength")
        options.select(.strength, system: 0.836)
        precondition(options.strength == 0.836, "First selection starts at the actual system strength without a jump")
        options.strength = 0.42
        HUDPreferences.setGlassOptions(options, in: store)
        precondition(HUDPreferences.glassOptions(in: store) == options, "Strength survives loading saved preferences")
        options.select(.system, system: 0.8)
        HUDPreferences.setGlassOptions(options, in: store)
        options = HUDPreferences.glassOptions(in: store)
        precondition(options.resolvedStrength(system: 0.8) == 0.8 && options.strength == 0.42)
        options.select(.strength, system: 0.8)
        precondition(options.resolvedStrength(system: 0.8) == 0.42, "Returning to Strength restores its own value")
        HUDPreferences.resetOptions(in: store)
        precondition(HUDPreferences.glassOptions(in: store) == HUDGlassOptions(), "Reset All restores system control and clears strength")
        store.set("bad", forKey: "hud.glass.mode")
        store.set(Double.infinity, forKey: "hud.glass.strength")
        precondition(HUDPreferences.glassOptions(in: store) == HUDGlassOptions(), "Invalid settings fall back safely")
        precondition(HUDGlassOptions.clamped(-1) == 0 && HUDGlassOptions.clamped(2) == 1)

        let menu = HUDGlassMenuView(options: HUDGlassOptions(), systemStrength: 0.836)
        let selector: NSSegmentedControl = member(menu, "control")
        let slider: NSSlider = member(menu, "slider")
        let value: NSTextField = member(menu, "valueLabel")
        precondition(selector.selectedSegment == 1 && !slider.isEnabled && value.stringValue == "84%")
        var selected: HUDGlassOptions?
        menu.onChange = { selected = $0 }
        selector.selectedSegment = 0
        selector.sendAction(selector.action, to: selector.target)
        precondition(slider.isEnabled && selected?.strength == 0.836)
        slider.doubleValue = 37.4
        slider.sendAction(slider.action, to: slider.target)
        precondition(selected?.strength == 0.37 && value.stringValue == "37%")
        selector.selectedSegment = 1
        selector.sendAction(selector.action, to: selector.target)
        menu.update(options: selected!, systemStrength: 0.25)
        precondition(!slider.isEnabled && value.stringValue == "25%", "Following system displays the current system value")
        selector.selectedSegment = 0
        selector.sendAction(selector.action, to: selector.target)
        precondition(slider.isEnabled && value.stringValue == "37%")
        let menuWindow = NSWindow(contentRect: menu.frame, styleMask: [], backing: .buffered, defer: false)
        menuWindow.contentView = menu
        menu.layoutSubtreeIfNeeded()
        let selectorRect = selector.alignmentRect(forFrame: selector.frame)
        let sliderRect = slider.convert(slider.bounds, to: menu)
        precondition(menu.bounds.contains(selectorRect) && menu.bounds.contains(sliderRect))
        precondition(sliderRect.maxY < selectorRect.minY && sliderRect.width >= 100, "Slider has its own clear row")
        let sizeMenu = HUDSizeMenuView(selectedScale: .normal)
        let sizeWindow = NSWindow(contentRect: sizeMenu.frame, styleMask: [], backing: .buffered, defer: false)
        sizeWindow.contentView = sizeMenu
        sizeMenu.layoutSubtreeIfNeeded()
        let sizeSlider: NSSlider = member(sizeMenu, "slider")
        let sizeValue: NSTextField = member(sizeMenu, "valueLabel")
        let sizeTrack = sizeSlider.convert(sizeSlider.bounds, to: sizeMenu)
        let sizeNumber = sizeValue.convert(sizeValue.bounds, to: sizeMenu)
        precondition(sizeTrack.minX == sliderRect.minX && sizeTrack.width == sliderRect.width,
            "Size and glass slider tracks have identical widths and starting positions")
        precondition(sizeNumber.midX == value.frame.midX && sizeValue.alignment == value.alignment,
            "Size and glass numbers are centred in the same column")

        // Inspect the native material output, without changing or replacing its layers.
        func materialValues(in layer: CALayer?) -> [Double]? {
            guard let layer else { return nil }
            for filter in layer.filters ?? [] {
                guard let object = filter as? NSObject,
                      object.responds(to: NSSelectorFromString("inputKeys")),
                      let keys = object.value(forKey: "inputKeys") as? [String],
                      keys.contains("inputFaceColorMatrixFillColor") else { continue }
                let color = object.value(forKey: "inputFaceColorMatrixFillColor")
                let components = color.map { ($0 as! CGColor).components ?? [] } ?? [0, 0, 0, 0]
                let parameters = ["inputBlurRadius", "inputFaceColorMatrixWhite", "inputFaceColorMatrixBlack"]
                    .map { (object.value(forKey: $0) as? NSNumber)?.doubleValue ?? 0 }
                return parameters + components.map(Double.init)
            }
            for child in layer.sublayers ?? [] {
                if let values = materialValues(in: child) { return values }
            }
            return nil
        }

        let body = NSSize(width: 270, height: 220)
        let background = NativeGlassHUDBackground(frame: NSRect(origin: .zero,
            size: NativeGlassHUDBackground.sizeIncludingShadow(bodySize: body)))
        let window = NSWindow(contentRect: background.frame, styleMask: [], backing: .buffered, defer: false)
        window.contentView = background
        background.layoutSubtreeIfNeeded()
        let native: NSGlassEffectView = member(background, "glass")
        let size = window.frame.size
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        for dark in [false, true] {
            background.isDark = dark
            window.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            var samples: [[Double]] = []
            for strength in [0.0, 0.25, 0.5, 0.75, 1.0, 0.0] {
                HUDGlassStyle.apply(HUDGlassOptions(mode: .strength, strength: strength))
                window.displayIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.6))
                window.displayIfNeeded()
                guard let values = materialValues(in: background.layer) else {
                    preconditionFailure("Native glass material was not rendered")
                }
                samples.append(values)
                precondition(background.isDark == dark && window.frame.size == size, "Strength preserves colour and geometry")
                precondition(UserDefaults.standard.double(forKey: HUDGlassStyle.nativeKey) == strength)
                let same: NSGlassEffectView = member(background, "glass")
                precondition(same === native, "Live changes preserve the existing glass view")
            }
            precondition(samples[0] == samples[5], "Returning to Clear reproduces the same material")
            // macOS changes both tint colour and intensity, particularly in Dark appearance.
            // Verify distinct native recipes rather than imposing a custom linear alpha curve.
            for i in 1...4 { precondition(samples[i] != samples[i - 1], "Each tested strength updates the native material") }
            HUDGlassStyle.apply(HUDGlassOptions())
            window.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            window.displayIfNeeded()
            let systemValues = materialValues(in: background.layer)!
            HUDGlassStyle.apply(HUDGlassOptions(mode: .strength, strength: HUDGlassStyle.systemStrength()))
            window.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            window.displayIfNeeded()
            precondition(materialValues(in: background.layer)! == systemValues,
                "Follow macOS matches an override at the same amount")
        }
        HUDGlassStyle.apply(HUDGlassOptions())
        precondition(UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[HUDGlassStyle.nativeKey] == nil)
        precondition(HUDGlassStyle.systemStrength() == originalGlobal, "The macOS preference was not changed")
        for (key, value) in originalArguments where key != HUDGlassStyle.nativeKey {
            precondition(NSDictionary(dictionary: [key: value]).isEqual(to:
                [key: UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[key]!]),
                "Unrelated launch arguments survive glass changes")
        }
        print("PASS: saved strengths, system defaults/reset, menu layout, live native material in both appearances, intermediate values, unchanged window and macOS preference")
    }
}
