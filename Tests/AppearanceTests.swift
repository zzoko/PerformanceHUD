import AppKit

@main struct AppearanceTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }
    @MainActor static func main() async {
        let app = NSApplication.shared
        let originalAppearance = app.appearance
        defer { app.appearance = originalAppearance }
        UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "fps", "hud.background": ""], forName: UserDefaults.argumentDomain)
        check(HUDPreferences.background == .system, "Unconfigured appearance defaults to Follow system")
        for fixed in HUDBackground.menuOptions {
            UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "fps", "hud.background": fixed.rawValue], forName: UserDefaults.argumentDomain)
            check(HUDPreferences.background == fixed, "Existing manual appearance choices are preserved")
        }
        UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "fps", "hud.background": "system"], forName: UserDefaults.argumentDomain)
        check(HUDPreferences.background == .system, "Saved Follow system choice is restored")
        check(HUDBackground.system.resolved(isDark: false) == .light && HUDBackground.system.resolved(isDark: true) == .dark, "Follow system resolves only to Light/Dark")
        for fixed in HUDBackground.menuOptions {
            check(fixed.resolved(isDark: false) == fixed && fixed.resolved(isDark: true) == fixed, "Fixed choices do not follow system")
        }

        for legacy in ["transparent", "off", "invalid"] {
            UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.background": legacy], forName: UserDefaults.argumentDomain)
            check(HUDPreferences.background == .system, "Retired/unknown appearances migrate to Follow system")
        }
        let menu = HUDBackgroundMenuView(selectedBackground: .system)
        let manual: NSSegmentedControl = member(menu, "control")
        let follow: NSSegmentedControl = member(menu, "systemControl")
        check(manual.segmentCount == 2 && manual.selectedSegment == -1 && follow.selectedSegment == 0, "Follow system is separate from the two fixed choices")
        var chosen: HUDBackground?
        menu.onBackgroundSelected = { chosen = $0 }
        manual.selectedSegment = 0
        manual.sendAction(manual.action, to: manual.target)
        check(chosen == .light && follow.selectedSegment == -1, "Selecting Light clears Follow system")
        follow.selectedSegment = 0
        follow.sendAction(follow.action, to: follow.target)
        check(chosen == .system && manual.selectedSegment == -1, "Selecting Follow system clears fixed choices")
        let menuWindow = NSWindow(contentRect: menu.frame, styleMask: [], backing: .buffered, defer: false)
        menuWindow.contentView = menu
        menu.layoutSubtreeIfNeeded()
        let manualRect = manual.alignmentRect(forFrame: manual.frame)
        let followRect = follow.alignmentRect(forFrame: follow.frame)
        check(abs(manualRect.minX - followRect.minX) < 0.01 && abs(manualRect.width - followRect.width) < 0.01, "Follow system spans the same width as the two choices")
        check(followRect.maxY < manualRect.minY && followRect.minY >= 0, "Follow system sits below fixed choices inside the row")

        app.appearance = NSAppearance(named: .aqua)
        let hud = HUDWindowController()
        hud.setHUDEnabled(false)
        defer { hud.shutdown() }
        let panel: HUDPanel = member(hud, "panel")
        let glass: NativeGlassHUDBackground = member(hud, "backgroundView")
        check(!glass.isDark, "Saved system choice uses Light at startup")
        let size = panel.frame.size
        func waitFor(_ background: HUDBackground) async {
            for _ in 0..<100 {
                let actual: HUDBackground = member(hud, "hudBackground")
                if actual == background { return }
                try? await Task.sleep(for: .milliseconds(10))
            }
            preconditionFailure("Live appearance did not update to \(background)")
        }
        app.appearance = NSAppearance(named: .darkAqua)
        await waitFor(.dark)
        check(glass.isDark && panel.frame.size == size, "Dark appearance updates the existing glass without resizing")
        app.appearance = NSAppearance(named: .aqua)
        await waitFor(.light)
        check(!glass.isDark && panel.frame.size == size, "Light appearance updates the existing glass without resizing")
        for fixed in HUDBackground.menuOptions {
            hud.setBackground(fixed)
            app.appearance = NSAppearance(named: .darkAqua)
            try? await Task.sleep(for: .milliseconds(20))
            app.appearance = NSAppearance(named: .aqua)
            try? await Task.sleep(for: .milliseconds(20))
            let actual: HUDBackground = member(hud, "hudBackground")
            check(actual == fixed, "Manual choice ignores appearance changes")
        }
        hud.setBackground(.system)
        check(!glass.isDark, "Re-enabling Follow system immediately matches macOS")
        print("PASS: appearance selection, saved system choice, menu geometry, live Light/Dark changes, fixed-choice independence, stable HUD size")

        if let index = CommandLine.arguments.firstIndex(of: "--preview"), CommandLine.arguments.indices.contains(index + 1) {
            let path = CommandLine.arguments[index + 1]
            menu.appearance = NSAppearance(named: .darkAqua)
            menu.wantsLayer = true
            menu.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1).cgColor
            let bitmap = menu.bitmapImageRepForCachingDisplay(in: menu.bounds)!
            menu.cacheDisplay(in: menu.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        }
    }
}
