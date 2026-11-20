import AppKit

/// A single, ordered reference for the controls in the status menu.
@MainActor
final class HUDControlsGuide: NSWindowController {
    struct Section {
        let title: String
        let rows: [(String, String)]
    }

    // Keep entries brief and in menu order. Explain shared behavior once.
    static let sections: [Section] = [
        .init(title: "Enable / Disable", rows: [
            ("", "Show or hide the HUD. Visible menu-bar readings keep updating either way.")]),
        .init(title: "Show menu-bar readings", rows: [
            ("Pin a reading", "Click the icon beside B. A line connects the formats a pin supports. Its dot marks the format the pin will show."),
            ("Collapse / expand", "Uncheck Show menu-bar readings to hide all pins. Click the chevron beside the bolt to show them again.")]),
        .init(title: "Reset", rows: [
            ("Position / Size", "Position restores the HUD’s starting point. Option-drag moves it. Size restores 1×."),
            ("All", "Enables the HUD, restores Balanced and the default layout settings, and clears pins. Saved presets, hotkeys, and app settings are kept.")]),
        .init(title: "Auto hide", rows: [
            ("Off / FPS / All", "After three seconds without FPS, FPS (default) collapses that section and its pin. All hides the whole HUD and keeps pins visible. Both restore the HUD content when FPS resumes. Off keeps it visible."),
            ("Animation", "Animate transitions. Switch off for instant changes. Reduce Motion also skips animations.")]),
        .init(title: "Size", rows: [("", "Scale the HUD from 0.5× to 2×. The default is 1×. Pins keep their own size.")]),
        .init(title: "Layout", rows: [("", "Vertical stacks categories. Horizontal arranges them in a strip. APP and Misc are Vertical-only. Switching back restores your Vertical selections.")]),
        .init(title: "Appearance", rows: [("Light / Dark / Follow macOS", "Choose a HUD appearance. Follow macOS is the default. Pins always follow macOS.")]),
        .init(title: "Liquid Glass", rows: [
            ("Custom / Follow macOS", "Adjust the HUD from Clear (0%) to Tinted (100%), or follow the system setting (default)."),
            ("Retry Glass Compatibility", "Appears if glass compatibility needs attention. Retry if a game seems capped at 60 FPS.")]),
        .init(title: "Preset", rows: [
            ("FPS / Balanced / Detailed", "FPS shows frame rate alone. Balanced includes CPU core bars. Detailed adds CPU and GPU GHz, APP, and Misc. Built-in presets clear all pins."),
            ("Custom", "Appears when your category settings and pins no longer match a preset. Layout, size, position, appearance, and Auto hide are independent."),
            ("Save current as… / Manage presets…", "Save your current category settings and pins by name. Use Manage presets to rename or delete saved presets.")]),
        .init(title: "Category controls", rows: [
            ("Switches and checkboxes", "Switch a category off to hide it and keep its selections. Checkboxes choose individual readings."),
            ("B · Emphasis", "A filled B emphasizes the reading. Pins share the same formatting and heat warnings as the HUD.")]),
        .init(title: "FPS", rows: [
            ("Display", "Choose Value, 60-second History, or Both (default). Horizontal and pinned readings show the value only."),
            ("Measure", "In either layout, choose Frame rate (FPS, default) or Frame time (FT, in ms). The frame-time number and line show the average gap between displayed frames. Each bar shows that second’s longest gap."),
            ("Number size", "Choose 1× (default) or 2× for the HUD number. The pin stays at 1×."),
            ("Hitch marks", "Both graphs flag hitches by default at 25 ms or more and at least 2.5× that second’s average. Yellow turns red at 100 ms. In FPS history, line depth grows with duration, reaching the baseline at 200 ms.")]),
        .init(title: "APP", rows: [
            ("GPU / CPU / Memory", "Shows the frontmost app’s GPU use, CPU use, and memory in GB. CPU uses the whole Mac as 100%.")]),
        .init(title: "GPU", rows: [
            ("Power", "Estimated GPU watts."),
            ("Temperature / Heat warning", "Average GPU sensor temperature. The number turns red at the threshold, 95°C by default. Enter a whole degree from 1 to 149."),
            ("Use", "System-wide GPU usage, from 0–100%."),
            ("Cores", "GPU frequency in GHz. Horizontal and the menu bar label it C.")]),
        .init(title: "CPU", rows: [
            ("Power", "Estimated CPU watts."),
            ("Temperature / Heat warning", "Average CPU sensor temperature. Its warning defaults to 95°C."),
            ("Use", "Total CPU usage across all cores, from 0–100%."),
            ("Cores · GHz / Load / Both", "GHz shows frequency per core type. Load shows one usage bar per core. Vertical wraps at 12 bars. Horizontal stacks core types. The menu-bar pin shows them side by side."),
            ("GHz", "Average speed while cores are active. Clusters of the same type share one reading, weighted by active time. B emphasizes GHz.")]),
        .init(title: "ANE", rows: [("Power", "Estimated Apple Neural Engine watts.")]),
        .init(title: "SOC", rows: [("Combined power", "Adds CPU, GPU, and Neural Engine watts, even if their individual readings are hidden.")]),
        .init(title: "Memory", rows: [
            ("Use / Details", "Use shows the percentage of memory in use. Physical is memory in use (GB). Swap is disk space used for swap (GB)."),
            ("Pressure · Text / Meter / Graph", "Text names the state. Meter shows one to three segments. Graph shows 30 seconds of history in Vertical. The dotted line marks 100 and the dot marks now. Horizontal and the menu bar display Graph as Meter."),
            ("State color", "Green means normal, yellow warning, and red critical. Turn off for neutral readings. B emphasizes Text.")]),
        .init(title: "Storage", rows: [
            ("Disk · Internal / External / Both", "Shows free space per mounted drive. B emphasizes free space. Detailed enables Storage."),
            ("Details", "Shows read and write rates. B emphasizes both rates. Horizontal places drives side by side.")]),
        .init(title: HUDMetric.fans.menuTitle, rows: [
            ("Use · Bar / RPM / Both", "Each fan has a numbered badge. Show speed as a bar relative to maximum, an RPM value, or both. Menu bar pins show RPM. Fanless Macs show Not available."),
            ("Average", "Show up to four individual fans or one A badge for the average of all detected fans. Choose Vertical, Horizontal (default), or Both.")]),
        .init(title: "Battery", rows: [
            ("Charge · Always / Auto / Off", "Watts pulse green when switching to charging (+) and red when switching to draining (−). Always shows zero. Auto (default) hides near-zero watts after three seconds and collapses a Charge-only pin."),
            ("Temperature / Heat warning", "Battery temperature in °C. Its warning defaults to 45°C."),
            ("Energy", "Charge level turns red at 10% or below. Low Power Mode takes priority and uses yellow. A bolt means external power. BAT and ADP identify battery and adapter in Horizontal."),
            ("Availability", "Macs without an internal battery show Not available.")]),
        .init(title: "Misc", rows: [
            ("Resolution / Refresh rate", "Metal output dimensions and the display’s configured refresh rate or range. A dash means resolution is unavailable."),
            ("Game Mode / Thermal", "Game Mode shows macOS’s reported on/off state (experimental). Thermal shows system thermal pressure from nominal to critical."),
            ("OS / Chip", "OS shows the macOS version. Chip Tier shows the chip name. Full adds CPU and GPU core counts. B emphasizes all Misc values.")]),
        .init(title: "Start / Stop logging", rows: [
            ("Recording", "With the HUD enabled, record selected readings to CSV once per second. Columns are fixed at Start. Missing readings stay blank. Frame time adds average and worst frame times alongside FPS."),
            ("Saving", "Stop logging, disable the HUD, or quit to save to Desktop. Auto hide keeps recording. If saving fails, the alert identifies the recovery file.")]),
        .init(title: "Power Helper", rows: [
            ("Set Up Power Readings…", "Required for CPU, GPU, ANE, and SOC watts and CPU/GPU GHz. Follow the macOS approval prompt. Battery watts and CPU core bars work without setup."),
            ("Remove Power Helper", "Unregisters the helper. Other readings remain available.")]),
        .init(title: "Edit hotkeys", rows: [
            ("Defaults", "Option-H toggles the HUD. Option-L toggles logging. Option-A cycles appearance. Option-drag moves the HUD. Logging and appearance shortcuts briefly show their new state."),
            ("Change a shortcut", "Click an action and press a combination with Control, Option, or Command. Escape cancels. Delete or Clear removes it. You can also change the drag modifier.")]),
        .init(title: "Check for updates", rows: [("", "Check now and choose whether to install. First launch also checks once, even with automatic checks off.")]),
        .init(title: "Automatic update checks", rows: [("Off / Weekly / Monthly", "Off by default. Weekly checks every 7 days, Monthly every 30. Available updates appear in the menu for you to install.")]),
        .init(title: "Auto start on login", rows: [("Off / On", "Open PerformanceHUD when you log in. Off by default.")]),
        .init(title: "Quit", rows: [("", "Save any active log and close PerformanceHUD.")])
    ]

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 660),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Controls guide"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 440, height: 360)
        super.init(window: window)
        let root = NSView()
        window.contentView = root
        let intro = Self.text("PerformanceHUD · In menu order", size: 12, color: .secondaryLabelColor)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        for view in [intro, scroll] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            intro.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            intro.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            intro.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            scroll.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        let document = GuideDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24)
        ])
        for (index, section) in Self.sections.enumerated() {
            if index > 0 {
                let divider = NSBox()
                divider.boxType = .separator
                stack.addArrangedSubview(divider)
                divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            let content = NSStackView()
            content.orientation = .vertical
            content.alignment = .leading
            content.spacing = 10
            let heading = Self.text(section.title, size: 15, weight: .semibold)
            content.addArrangedSubview(heading)
            for (title, explanation) in section.rows {
                let row = NSTextField(wrappingLabelWithString: "")
                row.isSelectable = true
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = 3
                let text = NSMutableAttributedString()
                if !title.isEmpty {
                    text.append(NSAttributedString(string: title + "\n", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.labelColor]))
                }
                text.append(NSAttributedString(string: explanation, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor]))
                text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
                row.attributedStringValue = text
                row.setContentCompressionResistancePriority(.required, for: .vertical)
                content.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            }
            stack.addArrangedSubview(content)
            content.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private static func text(_ value: String, size: CGFloat, weight: NSFont.Weight = .regular,
                             color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }
}

private final class GuideDocumentView: NSView {
    override var isFlipped: Bool { true }
}
