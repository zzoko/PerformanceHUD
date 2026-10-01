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
            ("", "Show or hide the HUD with Control + Option + Command + H. Category checkmarks keep their individual settings when hidden."),
            ("Reading controls", "A checkbox shows or hides a reading. Its attached strip independently switches between faint and bold values. A bright strip means bold; turning a reading off remembers that choice. Energy and the fan checkboxes have no attached strip; fan RPM has a separate highlight control described under FAN.")]),
        .init(title: "Reset", rows: [
            ("Position", "Return the HUD to its default position. To move it yourself, hold Control + Option + Command and drag. Release all three keys after dragging to prevent automatic grid snapping. Placement includes the areas near the Dock and menu bar."),
            ("Options", "Restore default categories, readings, emphasis, usage modes, size, alignment, and appearance after confirmation. This enables the HUD and preserves its position and permissions.")]),
        .init(title: "Size", rows: [("", "Adjust from 0.75× to 1.25× in 0.05× steps. The default is 1×.")]),
        .init(title: "Alignment", rows: [("", "Vertical stacks categories. Horizontal places them in one row, with stronger dividers between categories and faint dividers between Total and App or individual fans. FPS History and Chip & OS are available only in Vertical; their selections return when switching back.")]),
        .init(title: "Appearance", rows: [
            ("Clear / Light / Dark · Follow system", "Choose a fixed appearance, or use Follow system to switch automatically between Light and Dark with macOS. Follow system never selects Clear. It is the default for fresh settings and Options reset; saved manual choices are preserved."),
            ("Screen Capture", "All styles use Screen Capture permission to draw the scenery behind the HUD. If capture is unavailable, a checkerboard marks the background while metrics remain usable. Allow capture in System Settings, then use Retry Background if needed.")]),
        .init(title: "FPS", rows: [
            ("Value / History / Both", "Show the tracked app’s FPS number, its 60-second history, or both. History uses approximately one reading per second; it is not a frame-time graph. Readings depend on what macOS exposes for the app. FPS is enabled with Both selected by default. The FPS checkmark hides the category and remembers your selection. Horizontal uses Value only; your Vertical selection returns when switching back."),
            ("Presentation · Static / Dynamic", "Static keeps the selected FPS rows visible. Dynamic rolls them away after three seconds of unavailable readings and expands them when readings return. A faint arrow remains while collapsed: downward in Vertical, rightward in Horizontal. The divider stays between FPS and any following readings. The arrow also remains when FPS is the only selected category. The full expanded area stays reserved for glass capture, so the transition does not restart it. Dynamic is selected by default for both layouts. Horizontal collapses only the FPS value sideways; History remains available only in Vertical. Reduce Motion skips the animation.")]),
        .init(title: "GPU", rows: [
            ("Power & Temperature", "Estimated system GPU watts averaged over the sampling interval, and the average of available GPU temperature sensors in °C. These readings remain system-wide in every usage mode. Power requires the approved helper."),
            ("Usage · Total / App / Both", "Total shows whole-system usage. App shows the focused app’s tracked process and may exclude helper processes. Both shows the two readings together. The Usage checkbox controls visibility; its strip controls emphasis. Per-app GPU readings depend on macOS support.")]),
        .init(title: "CPU", rows: [
            ("Power & Temperature", "Estimated system CPU watts and the average of identified CPU temperature sensors in °C. Sensor coverage varies by chip. Power requires the approved helper; neither reading is per-app."),
            ("Usage · Total / App / Both", "Choose system usage, the focused app’s tracked process, or both. Total CPU ranges from 0–100% across all cores. App CPU uses 100% per fully used logical core and can exceed 100%; helper processes may be excluded.")]),
        .init(title: "ANE", rows: [("", "Apple Neural Engine power in watts, using the approved helper. Usage percentage, temperature, and per-app readings are not offered because reliable readings have not been established.")]),
        .init(title: "SoC Power", rows: [("", "SOC shows the combined CPU, GPU, and Neural Engine power estimate from the same sample. It excludes the display and other whole-Mac components. Its checkbox works independently of the individual Power options; its strip controls boldness.")]),
        .init(title: "MEM", rows: [
            ("Details & Usage", "MEM stands for Unified Memory. Details and Usage are independent: show either, both, or neither. Total / App / Both selects the source for both controls, including when Usage is off. Details has its own boldness strip, affecting values rather than labels."),
            ("Total details", "Physical is memory in use, including app, wired, and compressed memory. Swap is disk space used for swap; Pressure describes system memory pressure."),
            ("App details", "Physical memory used by the focused app’s tracked process. Swap and pressure are system-wide and appear only with Total."),
            ("Horizontal layout", "PHY and SWP shorten the detail labels. An outlined triangle after SWP means warning pressure; a filled triangle means critical pressure. Normal pressure has no triangle, and unavailable readings stay blank. The triangle keeps its space beside SWP even when Usage is hidden.")]),
        .init(title: "FAN", rows: [
            ("Fan badges", "Rounded-square badges identify the fans in both layouts: 1, 2, and so on for individual fans, or A for Average."),
            ("Average · Vertical / Horizontal / Both", "Combines all detected fans into one A badge and reading in the selected layouts. Average is enabled for Horizontal by default; Vertical shows individual fans. RPM is the mean speed, while the bar averages each fan’s speed relative to its own maximum. Averaging requires at least two fans. With one fan, Average is unchecked and unavailable, and the HUD shows the badge numbered 1."),
            ("Usage · Total / RPM / Both", "Usage shows or hides the readings. Total shows only the speed bar, RPM shows only the numeric speed, and Both shows both. Both is selected by default. The bar fills relative to the fan’s reported maximum speed, without percentage text. A stopped fan can correctly read 0 RPM."),
            ("RPM highlighting", "Click the thin line beneath RPM and Both to make RPM readings bold, including Average. A bright line means bold; a faint line means regular. Highlighting starts off and is unavailable while RPM is hidden. Your choice is remembered when switching modes."),
            ("Layout", "Vertical gives each fan its own row; Horizontal places them side by side with faint dividers between fans and stronger dividers around the category. Bars keep the same width in both layouts and in Total or Both mode. With Both selected, the bar sits evenly between the badge and RPM. In Vertical, Total alone moves the bar to the right without changing its size. Horizontal RPM aligns with the other values before the next divider. Changing readings do not resize the HUD."),
            ("Availability", "On fanless Macs, FAN defaults to off for fresh settings and Options reset. You can still enable it to show No fans detected; Usage and Average stay unchecked and unavailable. Manual category choices are remembered. Missing RPM stays blank; a missing speed or maximum leaves the bar unfilled. Averages require valid readings from every fan. Read failures are distinct from no fans or a valid 0 RPM and do not turn FAN off. Fan monitoring is read-only: it needs no Power Helper and does not change cooling settings.")]),
        .init(title: "Battery", rows: [
            ("Energy", "A dynamic charge icon. A bolt indicates external power; yellow indicates Low Power Mode. Standard and High Power Mode use the regular icon."),
            ("Temperature", "Average of available battery temperature sensors in °C, with the battery controller as a fallback. Available on supported MacBooks; unavailable readings stay blank."),
            ("Power Source", "Battery or Power Adapter. Horizontal shortens these to BAT or ADP and hides the Power Source heading.")]),
        .init(title: "Chip & OS", rows: [("", "Chip name and macOS version. Available in Vertical alignment only.")]),
        .init(title: "Power Helper", rows: [
            ("Setup & approval", "CPU, GPU, ANE, and SoC watts share the bundled helper. Setup may request administrator approval in macOS Login Items. Muted Power controls remain clickable to offer setup, approval, or repair."),
            ("Sampling", "Runs only while the HUD is enabled and a visible category or SoC Power needs watts. With Power off, an approved helper is idle. Unsupported readings stay blank; brief sampling gaps can retain the last valid value for up to five seconds."),
            ("Remove", "Remove Power Helper unregisters it. Other readings remain usable. Current errors are shown in the Power Helper menu.")]),
        .init(title: "Quit", rows: [("", "Close PerformanceHUD and stop its monitoring. Your display settings are saved for the next launch.")])
    ]

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 660),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Controls Guide"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 440, height: 360)
        super.init(window: window)
        let root = NSView()
        window.contentView = root
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.5"
        let intro = Self.text("PerformanceHUD · Version \(version) · In menu order", size: 12, color: .secondaryLabelColor)
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
                if title == "Reading controls", let image = NSImage(named: "ReadingControlsGuide") {
                    let illustration = NSImageView()
                    illustration.image = image
                    illustration.imageScaling = .scaleProportionallyUpOrDown
                    illustration.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                    illustration.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
                    illustration.setAccessibilityLabel("Normal and highlighted Power checkboxes. The checkbox shows or hides the reading; the attached side segment highlights it.")
                    content.addArrangedSubview(illustration)
                    NSLayoutConstraint.activate([
                        illustration.widthAnchor.constraint(equalTo: content.widthAnchor),
                        illustration.heightAnchor.constraint(equalTo: illustration.widthAnchor,
                            multiplier: image.size.height / image.size.width)
                    ])
                }
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
