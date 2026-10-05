import AppKit

@main struct AutoHideTests {
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }
    @MainActor static func main() async {
        _ = NSApplication.shared
        let suiteName = "AutoHide.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        precondition(HUDPreferences.autoHideMode(in: suite) == .fps, "Fresh settings default to FPS")
        suite.set(false, forKey: "hud.fps.dynamic")
        precondition(HUDPreferences.autoHideMode(in: suite) == .off, "Legacy Static migrates to Off")
        suite.set(true, forKey: "hud.autoHide")
        precondition(HUDPreferences.autoHideMode(in: suite) == .all, "Existing whole-HUD choice migrates")
        for mode in HUDAutoHideMode.allCases {
            HUDPreferences.setAutoHideMode(mode, in: suite)
            precondition(HUDPreferences.autoHideMode(in: suite) == mode)
            precondition(suite.object(forKey: "hud.autoHide") == nil && suite.object(forKey: "hud.fps.dynamic") == nil)
        }
        // Reset display choices without changing either dialog's independent consent.
        let autoHideDismissedKey = "hud.autoHide.explanationDismissed"
        let resetDismissedKey = "hud.resetOptions.confirmationDismissed"
        for autoHideDismissed: Bool? in [nil, false, true] {
            for resetDismissed: Bool? in [nil, false, true] {
                suite.set(autoHideDismissed, forKey: autoHideDismissedKey)
                suite.set(resetDismissed, forKey: resetDismissedKey)
                for _ in 0..<2 {
                    HUDPreferences.setAutoHideMode(.all, in: suite)
                    suite.set(1.75, forKey: "hud.scale")
                    HUDPreferences.resetOptions(in: suite)
                    precondition(HUDPreferences.autoHideMode(in: suite) == .fps,
                                 "Reset still restores the default Auto hide mode")
                    precondition(suite.object(forKey: "hud.scale") == nil,
                                 "Reset still restores the default size")
                    // Reopen the saved preferences as on a later launch.
                    let reopened = UserDefaults(suiteName: suiteName)!
                    precondition((reopened.object(forKey: autoHideDismissedKey) as? Bool) == autoHideDismissed,
                                 "Auto hide remembers its own choice across resets and launches")
                    precondition((reopened.object(forKey: resetDismissedKey) as? Bool) == resetDismissed,
                                 "Reset confirmation remembers its own choice independently")
                }
            }
        }
        suite.removePersistentDomain(forName: suiteName)
        if CommandLine.arguments.contains("--preferences-only") {
            print("PASS: Auto hide migration/defaults; independent dialog choices survive repeated resets and preference reloads")
            return
        }

        UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "fps",
            "hud.alignment": "vertical"], forName: UserDefaults.argumentDomain)
        precondition(HUDPreferences.autoHideMode == .fps)

        let menu = HUDAutoHideMenuView(selected: .fps)
        let control: NSSegmentedControl = member(menu, "control")
        let all: NSSegmentedControl = member(menu, "allControl")
        let menuWindow = NSWindow(contentRect: menu.frame, styleMask: [], backing: .buffered, defer: false)
        menuWindow.contentView = menu
        menu.layoutSubtreeIfNeeded()
        precondition(control.frame.minX == HUDMenuLayout.labelLeading + HUDMenuLayout.labelWidth + HUDMenuLayout.spacing)
        precondition(control.frame.width == all.frame.width && control.frame.minX == all.frame.minX)
        precondition(menu.subviews.compactMap { ($0 as? NSTextField)?.stringValue }.contains("Auto hide"))
        precondition(control.selectedSegment == 0 && all.selectedSegment == -1)
        var requested: HUDAutoHideMode?
        menu.onChange = { requested = $0 }
        all.selectedSegment = 0
        _ = all.sendAction(all.action, to: all.target)
        precondition(requested == .all && control.selectedSegment == 0 && all.selectedSegment == -1,
                     "Cancelling the explanation must leave FPS selected")
        menu.select(.all)
        precondition(control.selectedSegment == -1 && all.selectedSegment == 0)
        control.selectedSegment = 1
        _ = control.sendAction(control.action, to: control.target)
        precondition(requested == .off)
        menu.select(.off)
        precondition(control.selectedSegment == 1 && all.selectedSegment == -1)
        let fpsMenu = HUDFPSMenuView(options: .init(enabled: true, mode: .both), alignment: .vertical)
        precondition(fpsMenu.subviews.compactMap { $0 as? NSSegmentedControl }.count == 1,
                     "The FPS category must contain only Value / History / Both")
        if CommandLine.arguments.contains("--preview") {
            menu.appearance = NSAppearance(named: .darkAqua)
            menu.wantsLayer = true
            menu.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
            menu.select(.fps)
            let bitmap = menu.bitmapImageRepForCachingDisplay(in: menu.bounds)!
            menu.cacheDisplay(in: menu.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/phud-auto-hide-menu.png"))
        }

        let reveal = HUDAutoHidePresentation(enabled: true)
        precondition(reveal.isHidden && reveal.progress == 0)
        reveal.transition(visible: true, animated: true)
        precondition(!reveal.isHidden, "The panel must be available before expansion's first frame")
        try? await Task.sleep(for: .milliseconds(160))
        precondition(reveal.progress > 0 && reveal.progress < 1)
        let reversal = reveal.progress
        reveal.transition(visible: false, animated: true)
        precondition(reveal.progress == reversal, "Reversal must not snap")
        try? await Task.sleep(for: .milliseconds(300))
        precondition(reveal.isHidden && reveal.progress == 0)
        reveal.transition(visible: true, animated: true)
        reveal.transition(visible: true, animated: false)
        precondition(reveal.progress == 1, "Instant transitions must cancel an existing animation")
        reveal.transition(visible: false, animated: false)
        precondition(reveal.isHidden, "Reduce Motion path must finish immediately")
        reveal.setEnabled(false, visible: false, animated: false)
        precondition(!reveal.isHidden && reveal.progress == 1)

        // Exercise native glass geometry at intermediate animation frames.
        // The whole HUD stays disabled while its presentation timer runs offscreen.
        for alignment in [HUDAlignment.vertical, .horizontal] {
            for scale in [HUDScale.small, .normal, .large] {
                let rounded = HUDWindowController()
                rounded.setBackground(.dark)
                rounded.setAlignment(alignment)
                rounded.setHUDScale(scale)
                rounded.setAutoHideMode(.all)
                let animation: HUDAutoHidePresentation = member(rounded, "autoHidePresentation")
                let glass: NativeGlassHUDBackground = member(rounded, "backgroundView")
                let container: NSView = member(rounded, "container")
                let panel: HUDPanel = member(rounded, "panel")
                let fullSize: NSSize = member(rounded, "expandedHUDSize")
                let anchor = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
                animation.transition(visible: true, animated: true)
                try? await Task.sleep(for: .milliseconds(160))
                animation.stop()
                precondition(animation.progress > 0 && animation.progress < 1)
                precondition(container.layer?.masksToBounds == true && container.layer?.cornerCurve == .continuous)
                precondition(glass.bodyFrame.size == container.bounds.size)
                precondition(alignment == .vertical ? container.bounds.height < fullSize.height : container.bounds.width < fullSize.width)
                let native: NSGlassEffectView = member(glass, "glass")
                precondition(native.cornerRadius == min(16 * CGFloat(scale.rawValue), min(container.bounds.width, container.bounds.height) / 2))
                precondition(panel.frame.minX == anchor.x && panel.frame.maxY == anchor.y,
                             "Native reveal must preserve its top-left anchor")
                precondition(abs(panel.frame.width - container.bounds.width - 48) < 1 && abs(panel.frame.height - container.bounds.height - 48) < 1,
                             "Window follows the visible native glass, without a reserved capture area")
                let shadow: CALayer = member(glass, "outsideShadow")
                precondition(shadow.shadowPath?.boundingBoxOfPath == glass.bodyFrame,
                             "Shadow follows the moving body")
                if CommandLine.arguments.contains("--preview") && scale == .normal {
                    let root: NSView = member(rounded, "windowContentView")
                    let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
                    root.cacheDisplay(in: root.bounds, to: bitmap)
                    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/phud-rounded-hide-\(alignment.rawValue).png"))
                }
                animation.transition(visible: true, animated: false)
                precondition(glass.bodyFrame.size == fullSize, "Full native body mismatch: layout=\(alignment), scale=\(scale), expected=\(fullSize), actual=\(glass.bodyFrame.size), progress=\(animation.progress), window=\(panel.frame)")
                if alignment == .horizontal {
                    animation.transition(visible: false, animated: false)
                    precondition(container.bounds.width == 0)
                    // Appearance changes must preserve a collapsed horizontal layout.
                    for appearance in [HUDBackground.light, .dark] {
                        rounded.setBackground(appearance)
                        let trailing: NSLayoutConstraint? = member(rounded, "stackTrailingConstraint")
                        precondition(trailing?.isActive == false,
                                     "Hidden vertical rows must not be constrained to the zero-width viewport")
                    }
                    rounded.setAlignment(.vertical)
                    let stack: NSStackView = member(rounded, "stackView")
                    let trailing: NSLayoutConstraint? = member(rounded, "stackTrailingConstraint")
                    precondition(trailing?.isActive == true && !stack.isHidden)
                    precondition(abs(stack.frame.width - (container.bounds.width - 2 * HUDStyle.horizontalPadding(scale: scale))) <= 1,
                                 "Returning to Vertical must restore the full label/value layout width")
                }
                rounded.shutdown()
            }
        }

        let hud = HUDWindowController()
        hud.setBackground(.dark)
        hud.setHUDEnabled(true)
        hud.setAutoHideMode(.all)
        let panel: HUDPanel = member(hud, "panel")
        let root: NSView = member(hud, "windowContentView")
        let container: NSView = member(hud, "container")
        let presentation: HUDAutoHidePresentation = member(hud, "autoHidePresentation")
        let session: NativeGlassSession = member(hud, "glassSession")
        try? await Task.sleep(for: .milliseconds(650))
        precondition(hud.isAutomaticallyHidden && !panel.isVisible && !session.isActive)
        for alignment in [HUDAlignment.vertical, .horizontal] {
            hud.setAlignment(alignment)
            hud.setFPSOptions(.init(enabled: false, mode: .both))
            let frame = panel.frame
            hud.updateFPS(60)
            precondition(panel.isVisible && (session.isActive || session.failure != nil), "FPS must reveal the HUD and attempt its listener even when its category is unchecked")
            try? await Task.sleep(for: .milliseconds(150))
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                precondition(root.layer?.mask == nil && presentation.progress > 0 && presentation.progress < 1)
                precondition(container.layer?.masksToBounds == true && container.layer?.cornerCurve == .continuous,
                             "The moving visible edge must stay rounded, without clipping the entire window")
            }
            precondition(panel.frame.maxY == frame.maxY && panel.frame.minX == frame.minX, "Reveal preserves the top-left anchor")
            try? await Task.sleep(for: .milliseconds(500))
            precondition(presentation.progress == 1 && root.layer?.mask == nil)
            hud.markFPSUnavailable()
            try? await Task.sleep(for: .milliseconds(2400))
            precondition(panel.isVisible, "Brief FPS gaps must not hide the HUD")
            hud.markFPSUnavailable() // Must not postpone the original three-second deadline.
            try? await Task.sleep(for: .milliseconds(1700))
            let state: HUDFPSAvailability = member(hud, "fpsAvailability")
            precondition(hud.isAutomaticallyHidden && !panel.isVisible,
                         "Hide incomplete: layout=\(alignment) progress=\(presentation.progress) hidden=\(hud.isAutomaticallyHidden) visible=\(panel.isVisible) availability=\(state)")
            precondition(panel.frame == frame, "Hiding returns the native window to its collapsed size")
        }
        hud.setHUDEnabled(false)
        hud.updateFPS(60)
        precondition(!panel.isVisible && !session.isActive, "Master disable stops the listener and wins over automatic FPS availability")
        hud.setHUDEnabled(true)
        precondition(panel.isVisible)
        hud.setFPSOptions(.init(enabled: true, mode: .both))
        hud.setAutoHideMode(.fps)
        hud.markFPSUnavailable()
        try? await Task.sleep(for: .milliseconds(3700))
        precondition(panel.isVisible && !hud.isAutomaticallyHidden, "FPS mode keeps the remaining HUD visible")
        let fpsProgress: CGFloat = member(hud, "fpsProgress")
        precondition(fpsProgress == 0 && root.layer?.mask == nil, "FPS mode collapses only the FPS section")
        hud.setAutoHideMode(.off)
        precondition(panel.isVisible && !hud.isAutomaticallyHidden)
        let staticProgress: CGFloat = member(hud, "fpsProgress")
        precondition(staticProgress == 1 && root.layer?.mask == nil, "Off restores all selected rows immediately")
        hud.updateFPS(60)
        hud.markFPSUnavailable()
        try? await Task.sleep(for: .milliseconds(3700))
        let afterGap: CGFloat = member(hud, "fpsProgress")
        precondition(afterGap == 1 && panel.isVisible, "Off stays static through FPS loss")
        hud.setAutoHideMode(.all)
        try? await Task.sleep(for: .milliseconds(600))
        precondition(hud.isAutomaticallyHidden)
        hud.setAutoHideMode(.off)
        precondition(panel.isVisible && root.layer?.mask == nil, "Off must also restore a fully hidden HUD")
        hud.shutdown()
        precondition(!session.isActive, "HUD shutdown must synchronously unregister its listener")
        print("PASS: three-mode defaults/migration/reset, selector/cancel behavior, three-second grace, rounded glass/shadows at 0.5×–2× with native window resizing, both reveal directions, FPS category off, reversal, master disable, FPS-only collapse, and static Off")
    }
}
