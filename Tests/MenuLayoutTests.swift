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
            let chip = NSMenuItem(title: "Chip & OS", action: nil, keyEquivalent: "")
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
        print("PASS: native menu column stays aligned when Chip & OS is checked, unchecked, or disabled; no false checkmark")
    }
}
