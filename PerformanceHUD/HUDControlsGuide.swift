import AppKit

/// A single, ordered reference for the controls in the status menu.
@MainActor
final class HUDControlsGuide: NSWindowController {
    struct Section {
        let title: String
        let rows: [(String, String)]
    }

    static let sections: [Section] = [
        .init(title: "Enable / Disable", rows: [
            ("", "Show or hide the HUD. Option + H is the default shortcut. Your selections are remembered; visible menu-bar readings keep updating while the HUD is disabled.")]),
        .init(title: "Show menu-bar readings", rows: [
            ("Selection", "Click the small menu-bar symbol to the right of B beside a reading to show it in the macOS menu bar, independently of the HUD. All start off. The first use asks for confirmation: Yes enables the reading and remembers your approval; No leaves it off. Keep to a couple of readings: selections that exceed the width limit stay off and show a warning."),
            ("Display", "Uses a scaled-down horizontal layout with shared modes, emphasis, and heat warnings. FPS shows Value only; pressure B1/B2 uses A1/A2; fan averaging follows Horizontal. Misc and Chip & OS are unavailable."),
            ("Collapse / expand", "Use Show menu-bar readings or the chevron beside the bolt to hide or reveal all selections without clearing them. If a saved preset, reading mode, or display change exceeds the width limit, readings collapse until you reduce them. The HUD is unaffected. Click the bolt or readings to open the controls.")]),
        .init(title: "Reset", rows: [
            ("Position", "Return to the default position. To move the HUD, hold Option and drag with the left mouse button; release Option after dragging to avoid snapping. Edit hotkeys lets you change this modifier."),
            ("Size", "Return to 1× without changing other settings."),
            ("All", "Restore default HUD settings, including Balanced selections, position, size, appearance, and Auto hide. Enables the HUD and clears menu-bar selections. Saved presets, permissions, hotkeys, update schedule, login settings, and dismissed warnings are kept.")]),
        .init(title: "Auto hide", rows: [
            ("Off", "Keep selected readings visible even when FPS is unavailable."),
            ("FPS · default", "Collapse the FPS area to an arrow after three seconds without readings, in both the HUD and menu bar. It expands when readings return; other readings stay visible. With only FPS selected in the menu bar, just the app controls remain."),
            ("All", "Hide the whole HUD after three seconds without FPS readings and reveal it when they return. Apps without detectable FPS keep it hidden. This mode does not hide menu-bar readings. Logging continues."),
            ("Animation", "Animate HUD hiding, showing, and mode changes. On by default; turn it off for instant transitions. macOS Reduce Motion also skips animations.")]),
        .init(title: "Size", rows: [("", "Scale the HUD from 0.5× to 2×. Default: 1×. Menu-bar readings keep their own fixed scale.")]),
        .init(title: "Alignment", rows: [("", "Vertical stacks categories; Horizontal places them in one row. Horizontal uses FPS Value only and pressure meters. Misc and Chip & OS are Vertical-only. Your Vertical choices return when switching back.")]),
        .init(title: "Appearance", rows: [("Light / Dark / Follow macOS", "Choose a fixed appearance or follow macOS, the default. Option + A cycles these choices; change the shortcut in Edit hotkeys. Menu-bar readings always follow macOS appearance.")]),
        .init(title: "Liquid Glass", rows: [
            ("Strength", "Adjust from Clear (0%) to Frosted (100%) for the HUD only. Starts at your current macOS strength and remembers later adjustments. Light and Dark are separate choices."),
            ("Follow macOS · default", "Follow System Settings → Appearance. The inactive slider shows the system strength. Accessibility settings such as Reduce transparency can affect either mode."),
            ("Retry Glass Compatibility", "If this appears, retry it to restore compatibility with games that may otherwise be capped at 60 FPS.")]),
        .init(title: "Preset", rows: [
            ("FPS / Balanced / Detailed", "FPS shows only Frame rate in Value mode. Balanced uses the default readings. Detailed adds Misc and Chip & OS and sets GPU, CPU, and memory Use to Both. Built-in presets turn menu-bar selections off."),
            ("Custom", "Changing categories, readings, modes, emphasis, heat warnings, or menu-bar selections shows Custom unless the choices match a preset. Size, position, alignment, appearance, Liquid Glass, Auto hide, and app settings stay independent."),
            ("Save current as… / Manage presets…", "Save your selections by name, then rename or delete saved presets. Presets include menu-bar selections, but not their global collapse state. Built-in presets cannot be edited or deleted.")]),
        .init(title: "Category controls", rows: [
            ("Switches and checkboxes", "A category switch shows or hides its readings without clearing choices. Checkboxes control individual readings; adjacent buttons choose their mode. Scroll to reach more categories."),
            ("B · Emphasis", "Highlight a reading without changing its size. A filled B means on. Formatting controls remain available for readings selected in the menu bar, even when hidden in the HUD.")]),
        .init(title: "FPS", rows: [("Value / History / Both", "Show the focused app’s FPS number, its last 60 seconds of history, or both. History is sampled about once per second, not per frame. Availability depends on the app and macOS. Both is the default; B emphasizes the number.")]),
        .init(title: "GPU", rows: [
            ("Power", "Estimated system GPU watts. Requires Power Helper."),
            ("Temperature / Heat warning", "Average of available GPU temperature sensors. Heat warning turns the number red at or above the chosen temperature; enabled at 95°C by default. Accepts whole degrees from 1–149°C and follows the rounded displayed value. B controls emphasis independently."),
            ("Use · Total / App / Both", "Choose whole-system usage, the focused app’s tracked process, or both. App readings depend on macOS support and may exclude helper processes. Power and temperature always remain system-wide.")]),
        .init(title: "CPU", rows: [
            ("Power", "Estimated system CPU watts. Requires Power Helper."),
            ("Temperature / Heat warning", "Average of available CPU temperature sensors; coverage varies by chip. Heat warning changes only the number’s colour, with a separate threshold enabled at 95°C by default."),
            ("Use · Total / App / Both", "Total ranges from 0–100% across all cores. App uses 100% per fully used logical core, so it can exceed 100%; helper processes may be excluded. Power and temperature remain system-wide.")]),
        .init(title: "ANE", rows: [("Power", "Apple Neural Engine watts. The category switch controls this single reading; Power Helper is required.")]),
        .init(title: "SOC", rows: [("Combined power", "Combined CPU, GPU, and Neural Engine watts, independent of their individual Power switches. Excludes the display and other whole-Mac components. Requires Power Helper.")]),
        .init(title: "MEM", rows: [
            ("Pressure · Text / Graph", "Show system memory pressure independently of Details. Text displays the state; B emphasizes only the text. HUD pressure requires Total or Both; menu-bar pressure remains system-wide in any usage mode."),
            ("A1 / A2 · Meters", "One filled segment means normal, two warning, three critical. A1 is neutral; A2 uses green, yellow, or red for the current state."),
            ("B1 / B2 · History", "Show 30 seconds of numeric pressure on a fixed 0–100 scale, not memory usage percentage. Dots across the top mark 100; the rightmost dot marks now. B1 is neutral; B2 uses macOS pressure colours and is the default. Vertical-only: Horizontal and the menu bar use the matching A1/A2 meter."),
            ("Details", "Physical is memory in use; Swap is disk space used for swap. App details show the tracked process’s physical memory only. B emphasizes these values, not the pressure graph. Horizontal labels are PHY and SWP."),
            ("Use · Total / App / Both", "Choose system memory, the focused app’s tracked process, or both. This also selects the source for Details, even when the Use percentage is hidden.")]),
        .init(title: "FAN", rows: [
            ("Average · Vertical / Horizontal / Both", "Combine two or more fans in the chosen layouts. A marks an average; numbered badges identify individual fans. Horizontal averaging is on by default."),
            ("Use · Total / RPM / Both", "Total shows a bar relative to the fan’s maximum speed; RPM shows its speed as a number. Both shows both. Total is the default; B emphasizes RPM only. A stopped fan can correctly show 0 RPM."),
            ("Availability", "Fanless Macs show Not available with FAN off and greyed out. Readings are for monitoring only: these controls do not change fan speed or require Power Helper.")]),
        .init(title: "Battery", rows: [
            ("Charge · Always / Auto / Off", "Net battery watts: positive means charging, negative discharging. Always includes zero; Auto, the default, hides near-zero flow after three seconds; Off hides it. Auto reclaims the space in Horizontal. If Charge is the only battery reading selected in the menu bar, hiding it also hides its category. Auto restores it when flow returns."),
            ("Temperature / Heat warning", "Battery temperature in °C on supported MacBooks. Heat warning turns only the number red at your threshold; enabled at 45°C by default. Unavailable readings stay blank."),
            ("Energy", "Battery charge icon: red at 10% or below; otherwise yellow in Low Power Mode. A bolt indicates external power. Power Source identifies Battery or Adapter, shortened to BAT or ADP in Horizontal.")]),
        .init(title: "Misc", rows: [
            ("", "Vertical-only and off by default. Its buttons toggle each reading independently."),
            ("Process", "The focused app being tracked."),
            ("Resolution", "Reported Metal output dimensions, which may differ from internal rendering resolution with upscaling."),
            ("Refresh rate", "The display’s configured rate or variable-refresh range, not its instantaneous rate."),
            ("Game Mode", "Experimental macOS on/off status. Unavailable readings stay blank."),
            ("Thermal", "System thermal pressure: nominal, fair, serious, or critical. This is not a temperature reading.")]),
        .init(title: "Chip & OS", rows: [("", "Chip name and macOS version. Vertical-only and off by default.")]),
        .init(title: "Start / Stop logging", rows: [
            ("Recording", "Record selected HUD readings once per second to CSV. The HUD must be enabled. Option + L is the default shortcut. Columns are fixed when recording starts; start a new log to include newly selected readings. Missing readings stay blank."),
            ("Saving", "Stopping, disabling the HUD, or quitting saves the CSV to your Desktop. Auto hide keeps recording. If saving fails, an alert identifies the recovery file. Logging always starts manually.")]),
        .init(title: "Power Helper", rows: [
            ("Setup & approval", "Required for CPU, GPU, ANE, and SOC watts. Click a Power control or Set Up Power Readings and follow macOS approval prompts. Battery watts and other sensors do not need it."),
            ("Remove Power Helper", "Unregister the helper while keeping other readings available. An approved helper only samples when the HUD, visible menu-bar readings, or logging needs watts.")]),
        .init(title: "Edit hotkeys", rows: [
            ("Shortcuts", "Click an action and record a combination containing Control, Option, or Command. Escape cancels; Delete or Clear removes it. Defaults: Option + H for the HUD, Option + L for logging, Option + A for appearance, and Option + drag to move."),
            ("Availability", "Shortcuts work across apps while PerformanceHUD is running and pause while the editor is open. Conflicting shortcuts need a different combination. Changes save immediately and survive Reset → All.")]),
        .init(title: "Check for updates", rows: [
            ("", "Check for an official update, then choose whether to download and restart. HUD settings are kept. A one-time first-launch check also offers newer versions, even when automatic checks are off; it stays quiet if current or offline."),
            ("Privacy", "Checks contact the PerformanceHUD update service. No HUD readings, app names, CSV logs, or screen content are sent.")]),
        .init(title: "Automatic update checks", rows: [("Off / Weekly / Monthly", "Off by default. Weekly checks every seven days; Monthly every thirty. Overdue checks run when the app next opens. An available update appears in the menu; scheduled checks do not interrupt you, download, or restart automatically.")]),
        .init(title: "Auto start on login", rows: [("Off / On", "Off by default. On opens PerformanceHUD with your saved settings when you log in. Follow any macOS Login Items approval prompt. Off stops future automatic launches without closing the app.")]),
        .init(title: "Quit", rows: [("", "Close PerformanceHUD, stop monitoring, and save any active CSV log. Your settings are kept for next launch.")])
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
