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
            ("", "Show or hide the HUD with Option + H by default. Change or clear the shortcut in Edit hotkeys. Category switches keep their individual settings when hidden."),
            ("Category switches", "The switch to the left of each category shows or hides it while remembering its selections. Clicking the category name also toggles it. Frame rate, Combined power, and Name and version are labels: FPS, SOC, and Chip & OS each use only their category switch. Unavailable categories are greyed out. Scroll the category list when it does not fit on screen."),
            ("Reading controls", "Checkboxes show or hide individual readings. The adjacent mode buttons choose what those readings display. Battery Charge uses Always / Auto / Off directly, while Misc has separate on/off buttons for its readings. Turning a category off dims its controls without clearing your choices."),
            ("Emphasis", "A B button at the right of a reading switches its values between Reading and Emphasized Reading styles without changing their size or labels. A brighter, filled B means emphasis is on. The button dims when the value is switched off, excluded by its display mode, or needs Power Helper setup. Your choice is remembered. Energy, fan Average, Misc, and Chip & OS do not have emphasis controls.")]),
        .init(title: "Reset", rows: [
            ("Position", "Return the HUD to its default position. To move it yourself, hold Option by default and drag with the left mouse button. Choose Option, Control, Shift, or Command for Move HUD in Edit hotkeys; the hint beside Reset shows your selected key. Release the key after dragging to prevent automatic grid snapping. Placement includes the areas near the Dock and menu bar."),
            ("Size", "Return the HUD to its default 1× size without changing other options."),
            ("All", "Restore default categories, readings, emphasis, usage modes, size, position, alignment, and appearance. This enables the HUD and preserves its permissions, custom hotkeys, update schedule, and login setting. Select “Don’t show this again” when confirming to skip future reset confirmations; this choice is remembered across resets, independently of the Auto hide explanation.")]),
        .init(title: "Auto hide", rows: [
            ("Off", "Keep the HUD and its selected FPS rows visible, even without FPS readings. Nothing collapses automatically."),
            ("FPS · default", "Collapse only the FPS area after three seconds without readings; show it again when readings return. Other selected categories remain visible. A faint arrow points down in Vertical or right in Horizontal while FPS is collapsed."),
            ("All", "Reveal the whole HUD when FPS readings are available and hide it after three seconds without them. Games or apps without detectable FPS keep it hidden. FPS detection continues even if the FPS category switch is off; other readings pause once hidden unless logging is active. Enable/Disable and the shortcut remain the master switch. An explanation appears when selecting this mode. Confirm with “Don’t show this again” checked to skip it in future; this choice is remembered independently of the reset confirmation, including after resetting all options."),
            ("Animation · on by default", "Animate hiding, showing, and switching between Off, FPS, and All: downward in Vertical and sideways in Horizontal. Uncheck Animation for instant changes: FPS switches between its selected readings and the arrow, while All shows or hides the whole HUD. The three-second wait before hiding is unchanged. Off never auto-hides anything, regardless of this checkbox. The choice is saved independently of the hide mode; Reset → All turns animation back on. Turning animation off mid-transition finishes it immediately. Reduce Motion also skips animations.")]),
        .init(title: "Size", rows: [("", "Adjust from 0.5× to 2× in 0.01× steps. The default is 1×; use Reset → Size to return to it.")]),
        .init(title: "Alignment", rows: [("", "Vertical stacks categories. Horizontal places them in one row, with stronger dividers between categories and faint dividers between Total and App or individual fans. FPS History, Misc, and Chip & OS are available only in Vertical; their selections return when switching back.")]),
        .init(title: "Appearance", rows: [
            ("Light / Dark · Follow macOS", "Choose a fixed appearance, or use Follow macOS to switch automatically between Light and Dark with macOS. It is the default for fresh settings and Reset → All; saved Light/Dark choices are preserved. Option + A cycles Light → Dark → Follow macOS by default, including while the HUD is hidden. Change the shortcut in Edit hotkeys."),
            ("Native glass", "Apple’s regular Liquid Glass draws the HUD appearance without screen capture permission. A compatibility workaround runs while the HUD is visible to address the observed game FPS cap. If it cannot start, Retry Glass Compatibility appears in the menu; the glass still works, but some games may be limited to 60 FPS.")]),
        .init(title: "Liquid Glass", rows: [
            ("Strength", "Move left toward Clear (0%) or right toward Frosted (100%). Changes apply immediately to PerformanceHUD’s native glass without changing macOS settings. On first use it starts at your current system strength; after that it remembers your own setting. Light and Dark remain independent of this slider."),
            ("Follow macOS · default", "Use the Liquid Glass setting in System Settings → Appearance. The disabled slider shows the current system strength. Returning to Follow macOS keeps your chosen strength for next time; Reset → All restores Follow macOS and clears the remembered strength."),
            ("Accessibility", "Reduce transparency and Increase contrast in macOS Accessibility settings can also affect the glass in either mode.")]),
        .init(title: "FPS", rows: [
            ("Value / History / Both", "Show the tracked app’s FPS number, its 60-second history, or both. History uses approximately one reading per second; it is not a frame-time graph. Readings depend on what macOS exposes for the app. FPS is enabled with Both selected by default. The FPS switch hides the category and remembers your selection. Horizontal uses Value only; your Vertical selection returns when switching back."),
            ("Value emphasis", "Click the B button beside the FPS display modes to switch the FPS number between Reading and Emphasized Reading styles. Emphasis is on by default and also applies in Both mode. The button is unavailable when FPS is switched off or only History is selected; your choice is remembered."),
            ("Visibility", "Use Auto hide near the top of the menu to choose whether only FPS collapses, the whole HUD hides, or everything stays visible. In FPS mode, a faint arrow remains while collapsed, including when FPS is the only selected category. The divider remains when another category follows.")]),
        .init(title: "GPU", rows: [
            ("Power & Temperature", "Estimated system GPU watts averaged over the sampling interval, and the average of available GPU temperature sensors in °C. These readings remain system-wide in every usage mode. Power requires the approved helper."),
            ("Use · Total / App / Both", "Total shows whole-system usage. App shows the focused app’s tracked process and may exclude helper processes. Both shows the two readings together. The Use checkbox controls visibility; its B button controls emphasis, which starts off. Per-app GPU readings depend on macOS support.")]),
        .init(title: "CPU", rows: [
            ("Power & Temperature", "Estimated system CPU watts and the average of identified CPU temperature sensors in °C. Sensor coverage varies by chip. Power requires the approved helper; neither reading is per-app."),
            ("Use · Total / App / Both", "Choose system usage, the focused app’s tracked process, or both. Emphasis starts off. Total CPU ranges from 0–100% across all cores. App CPU uses 100% per fully used logical core and can exceed 100%; helper processes may be excluded.")]),
        .init(title: "ANE", rows: [("", "Apple Neural Engine power in watts, using the approved helper. Usage percentage, temperature, and per-app readings are not offered because reliable readings have not been established.")]),
        .init(title: "SOC", rows: [("Combined power", "SOC shows the combined CPU, GPU, and Neural Engine power estimate from the same sample. It excludes the display and other whole-Mac components. The SOC category switch controls this reading independently of the individual Power options; its B button controls emphasis, which is off by default. There is no separate reading checkbox. Power requires the approved helper; click the SOC switch to request setup when needed.")]),
        .init(title: "MEM", rows: [
            ("Pressure, Details & Use", "MEM stands for Unified Memory. Pressure, Details, and Use have independent checkboxes. Details controls Physical and Swap; its B button emphasizes only those text values. Total / App / Both selects the memory source, including when Use is off. System pressure is available with Total or Both. Emphasis starts off."),
            ("Total details", "Physical is memory in use, including app, wired, and compressed memory. Swap is disk space used for swap."),
            ("Pressure · Text / Meter / Color meter", "The Pressure checkbox shows or hides system memory pressure independently of Details. Pressure starts enabled with Color meter selected. Choose the pressure word or a three-segment meter. Its B button emphasizes the pressure word in Text mode and is unavailable for meters. One filled segment means normal, two warning, and three critical. Meter uses neutral colours. Color meter fills all active bars with the current state's colour: green for normal, yellow for warning, and red for critical. Inactive segments stay grey. Vertical places them side by side; Horizontal fills them from bottom to top. Unavailable readings stay blank. The selector is unavailable with Pressure off or App-only memory selected. Your choices are remembered."),
            ("App details", "Physical memory used by the focused app’s tracked process. Swap and pressure are system-wide and appear only with Total."),
            ("Horizontal layout", "PHY and SWP shorten the detail labels. Pressure follows these details when both are enabled, and also works with Details off. Meter styles use less space than Text. Each style keeps its space reserved as pressure changes, even when Use is hidden.")]),
        .init(title: "FAN", rows: [
            ("Fan badges", "Rounded-square badges identify the fans in both layouts: 1, 2, and so on for individual fans, or A for Average."),
            ("Average · Vertical / Horizontal / Both", "Combines all detected fans into one A badge and reading in the selected layouts. Average is enabled for Horizontal by default; Vertical shows individual fans. RPM is the mean speed, while the bar averages each fan’s speed relative to its own maximum. Averaging requires at least two fans. With one fan, Average is unchecked and unavailable, and the HUD shows the badge numbered 1."),
            ("Use · Total / RPM / Both", "Use shows or hides the readings. Total shows only the speed bar, RPM shows only the numeric speed, and Both shows both. Both is selected by default. The bar fills relative to the fan’s reported maximum speed, without percentage text. A stopped fan can correctly read 0 RPM."),
            ("RPM emphasis", "Click the B button beside Use and its Total / RPM / Both modes to switch RPM values between Reading and Emphasized Reading styles, including averaged RPM. This applies in both RPM and Both modes. Emphasis starts off and is unavailable while RPM is hidden. Your choice is remembered when switching modes."),
            ("Layout", "Vertical gives each fan its own row; Horizontal places them side by side with faint dividers between fans and stronger dividers around the category. Bars keep the same width in both layouts and in Total or Both mode. With Both selected, the bar sits evenly between the badge and RPM. In Vertical, Total alone moves the bar to the right without changing its size. Horizontal RPM aligns with the other values before the next divider. Changing readings do not resize the HUD."),
            ("Availability", "On fanless Macs, FAN is forced off and greyed out, with Not available shown in the menu. Macs with fans retain the normal controls. Missing RPM stays blank; a missing speed or maximum leaves the bar unfilled. Averages require valid readings from every fan. Read failures are distinct from no fans or a valid 0 RPM and do not turn FAN off. Fan monitoring is read-only: it needs no Power Helper and does not change cooling settings.")]),
        .init(title: "Battery", rows: [
            ("Charge · Always / Auto / Off", "Net battery power in watts: positive means charging, negative means discharging, and zero means no measured net flow. Choose a mode directly using the three inline buttons. Auto is the default: it shows flow at 0.2 W or more in either direction and hides it after three seconds at 0.1 W or less. Always includes zero; Off hides it entirely. Auto keeps its space in Vertical. In Horizontal, the HUD shrinks when Auto hides Charge and expands when the reading returns. Logging continues to include actual values, including zeros. The B button to the right of the Charge modes independently emphasizes the reading and remembers its choice when Off. Reads live battery voltage and signed current once per second, without the power helper. If those sensors are unavailable, macOS’s published battery-controller readings provide a fallback that can update more slowly. Unavailable values stay blank. Discharge on an adapter can mean the battery is supplementing it, but charging management can also allow discharge; this reading alone does not identify throttling or a charger problem."),
            ("Temperature", "Average of available battery temperature sensors in °C, with the battery controller as a fallback. Vertical places flow, temperature, and the battery icon on one row, aligned with the power and temperature columns above when all three are enabled. Turning off readings packs those remaining toward the right without resizing the HUD. Horizontal places temperature before flow. Available on supported MacBooks; unavailable readings stay blank."),
            ("Energy", "A dynamic charge icon. A bolt indicates external power; yellow indicates Low Power Mode. Standard and High Power Mode use the regular icon."),
            ("Power Source", "Battery or Adapter. Horizontal shortens these to BAT or ADP and hides the Power Source heading.")]),
        .init(title: "Misc", rows: [
            ("Reading buttons", "Misc is off by default, with all five readings selected. Enable it in Vertical alignment, then click Process, Resolution, Refresh rate, Game Mode, or Thermal to toggle that reading independently. Brighter, filled buttons are selected; several can be on together. Misc is unavailable in Horizontal; your choices return in Vertical. Names use Label style and values use Reading style. Unavailable values stay blank."),
            ("Process", "The focused app being tracked. Long names are shortened to keep the HUD steady."),
            ("Resolution", "The pixel dimensions of the largest active Metal layer reported by the FPS sampler. This is output resolution, which may differ from internal rendering resolution when a game uses upscaling."),
            ("Refresh rate", "The configured rate of the display containing the focused app’s frontmost visible window. Variable-refresh modes show their supported range, not instantaneous panel refresh. If the display cannot be identified, the value stays blank."),
            ("Game Mode", "Experimental on/off status from a macOS system notification. Paused counts as off because Game Mode is inactive. It needs no Xcode, administrator access, screen capture, or injection. The system notification is undocumented; unavailable or unrecognized states stay blank."),
            ("Thermal", "macOS’s system-wide thermal state: nominal, fair, serious, or critical. This describes thermal pressure, not a temperature or an exact amount of throttling.")]),
        .init(title: "Chip & OS", rows: [("", "Chip name and macOS version. Available in Vertical alignment only.")]),
        .init(title: "Start / Stop logging", rows: [
            ("Shortcut", "Option + L starts or stops logging by default; change or clear it in Edit hotkeys. Starting requires the HUD to be enabled and uses the same first-use explanation as the menu control."),
            ("Recording", "Available while the HUD is enabled. Record the latest selected readings once per second to a CSV, with a timestamp in the first column and units in the headings. FPS, watts, and memory sizes use two decimal places; temperatures and percentages use one. RPM is rounded to whole numbers, and timestamps omit milliseconds. Sensors keep their normal update rates; logging is not per-frame profiling. FPS Value and History share one FPS column. Missing readings are blank; real zero readings remain zero."),
            ("Selected readings", "Columns follow menu order and are fixed when logging starts. Turning a reading off leaves its cells blank. Start a new log to include newly selected readings or a different fan-average layout. Memory uses GiB (1024-based GB), matching the HUD; fan usage is a percentage of reported maximum speed. App readings follow the focused app."),
            ("Saving", "Stop logging saves a timestamped PerformanceHUD CSV to your Desktop. Disabling the HUD, using its shortcut to disable it, or quitting also stops and saves. Auto hide keeps logging and selected monitors running while the HUD is hidden. macOS may ask for Desktop folder access. If saving fails, an alert shows the local recovery file."),
            ("First-use explanation", "Confirm with “Don’t show this again” to remember this choice independently of Auto hide and Reset all options. Logging always starts manually and never resumes automatically on launch.")]),
        .init(title: "Power Helper", rows: [
            ("Setup & approval", "CPU, GPU, ANE, and SOC watts share the bundled helper. Setup may request administrator approval in macOS Login Items. Muted Power checkboxes remain clickable while their category is on to offer setup, approval, or repair. SOC uses its category switch for the same purpose."),
            ("Sampling", "Runs while the HUD is enabled and a selected category or SOC Combined power needs watts. Sampling pauses when Auto hide → All fully hides the HUD, unless logging is active. With Power off, an approved helper is idle. Unsupported readings stay blank; brief sampling gaps can retain the last valid value for up to five seconds."),
            ("Remove", "Remove Power Helper unregisters it. Other readings remain usable. Current errors are shown in the Power Helper menu.")]),
        .init(title: "Edit hotkeys", rows: [
            ("Custom shortcuts", "Click an action’s shortcut and press a combination containing Control, Option, or Command. Escape cancels recording; Delete or Clear removes a shortcut. Move HUD lets you choose Option, Control, Shift, or Command to hold with a left mouse drag. All choices save immediately and survive Reset → All. Restore defaults returns to Option + H for the HUD, Option + L for logging, Option + A for appearance, and Option + drag for moving."),
            ("Availability", "Shortcuts work across apps while PerformanceHUD is running, and pause while the editor is open. Close it to resume. Option-letter shortcuts replace their usual typing symbols. Duplicate assignments and shortcuts reported as reserved by macOS are rejected; if another app uses the same combination, choose another. Shortcuts use physical keys, with labels following the current keyboard layout. No Accessibility or Input Monitoring permission is needed.")]),
        .init(title: "Updates", rows: [
            ("Check for updates", "Check for an official PerformanceHUD update. Choose whether to download it and restart the app. Your HUD settings are retained; quitting for an update saves any active CSV log. An updated Power Helper may need approval afterwards. Updates are available to both purchased copies and source builds; installing one replaces the app with the official build. Custom changes compiled into the app are not retained, but your source project is unaffected."),
            ("Automatic update checks", "Off by default. Weekly checks every seven days; Monthly checks every thirty days while PerformanceHUD is running. An overdue check runs after the app is launched again. When an update is found, the menu shows Update to followed by its version. Scheduled checks do not interrupt a game or download or restart the app automatically. This choice is remembered independently of Reset → All."),
            ("Privacy", "Update checks contact the PerformanceHUD update service hosted by Cloudflare. No HUD readings, game names, CSV logs, or screen content are sent. Updates and their information are verified before installation.")]),
        .init(title: "Auto start on login", rows: [
            ("Off / On", "Off by default. On asks macOS to open PerformanceHUD when you log in, using your saved HUD settings. Off stops future automatic launches without closing the app. If macOS requires approval, the app offers to open Login Items in System Settings. This setting follows changes made there and is preserved by Reset → All. It is separate from the power helper’s background activity approval.")]),
        .init(title: "Quit", rows: [("", "Close PerformanceHUD and stop its monitoring. Your display settings are saved for the next launch.")])
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
