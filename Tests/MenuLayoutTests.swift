import AppKit

@main struct MenuLayoutTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        func makeMenu(checked: Bool, enabled: Bool, reserve: Bool) -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for title in ["Disable", "Power Helper", "Controls guide…", "Quit"] {
                menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
            }
            let chip = NSMenuItem(title: "Misc", action: nil, keyEquivalent: "")
            chip.state = checked ? .on : .off
            chip.isEnabled = enabled
            if reserve { HUDMenuLayout.reserveStateColumn(for: chip) }
            menu.addItem(chip)
            return menu
        }
        let checkedWidth = makeMenu(checked: true, enabled: true, reserve: false).size.width
        for checked in [false, true] {
            for enabled in [false, true] {
                // Use fresh menus: AppKit can cache the previous column width.
                let menu = makeMenu(checked: checked, enabled: enabled, reserve: true)
                precondition(menu.size.width == checkedWidth,
                             "Native checkmark column changed for checked=\(checked), enabled=\(enabled)")
                let chip = menu.items.last!
                precondition(chip.state == (checked ? .on : .off), "Spacing must not fake selection")
                precondition(chip.isEnabled == enabled, "Spacing must preserve availability")
                let blank = chip.offStateImage!
                let bitmap = NSBitmapImageRep(data: blank.tiffRepresentation!)!
                for x in 0..<bitmap.pixelsWide {
                    for y in 0..<bitmap.pixelsHigh {
                        precondition(bitmap.colorAt(x: x, y: y)!.alphaComponent == 0,
                                     "Unchecked state must stay invisible")
                    }
                }
            }
        }
        checkMenuTransparency()
        print("PASS: native menu transparency and restoration; menu column stays aligned when Misc is checked, unchecked, or disabled; no false checkmark")
    }

    @MainActor private static func checkMenuTransparency() {
        let transparency = HUDMenuTransparency()
        func makeWindow(level: NSWindow.Level) -> NSWindow {
            let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 80, height: 40),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.level = level
            window.backgroundColor = .clear
            window.contentView!.addSubview(NSScrollView(frame: window.contentView!.bounds))
            return window
        }
        let root = makeWindow(level: .popUpMenu)
        let ordinary = makeWindow(level: .normal)
        transparency.setReduced(true)
        precondition(root.backgroundColor == .windowBackgroundColor && ordinary.backgroundColor == .clear)

        let submenu = makeWindow(level: .popUpMenu)
        submenu.orderFront(nil)
        let companion = makeWindow(level: .popUpMenu)
        companion.contentView = NSGlassEffectView()
        submenu.addChildWindow(companion, ordered: .below)
        companion.orderFront(nil)
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: companion)
        precondition(submenu.backgroundColor == .windowBackgroundColor && companion.backgroundColor == .clear)
        transparency.setReduced(false)
        precondition(root.backgroundColor == .clear && submenu.backgroundColor == .clear)
        submenu.removeChildWindow(companion)
        companion.orderOut(nil)
        submenu.orderOut(nil)
    }
}
