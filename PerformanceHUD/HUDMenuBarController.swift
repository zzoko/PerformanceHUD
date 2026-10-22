import AppKit

/// Uses the horizontal HUD's actual renderer at its base size. The status item
/// applies one coordinate transform, so typography, gaps, meters, and icons all
/// retain their existing proportions independently of the overlay's size.
@MainActor
enum HUDMenuBarPresentation {
    struct Style {
        var resources: [HUDResourceGroup: HUDResourceOptions]
        var fpsHighlighted: Bool
        var packageHighlighted: Bool
        var fans: HUDFanOptions
        var battery: HUDBatteryOptions

        static var current: Self {
            Self(resources: Dictionary(uniqueKeysWithValues: HUDResourceGroup.allCases.map {
                ($0, HUDPreferences.resourceOptions(for: $0))
            }), fpsHighlighted: HUDPreferences.fpsOptions.valueHighlighted,
                 packageHighlighted: HUDPreferences.packagePowerOptions.highlighted,
                 fans: HUDPreferences.fanOptions, battery: HUDPreferences.batteryOptions)
        }
    }

    static func scaleFactor(menuBarHeight: CGFloat) -> CGFloat {
        min(1, max(1, menuBarHeight - 4) / HUDStyle.rowHeight(scale: .normal))
    }

    static func scaledSize(_ size: NSSize, menuBarHeight: CGFloat) -> NSSize {
        let factor = scaleFactor(menuBarHeight: menuBarHeight)
        return NSSize(width: size.width * factor, height: size.height * factor)
    }

    static func widthLimit(availableWidth: CGFloat) -> CGFloat {
        // Reserve at least half the physical status-item area for other icons.
        // AppKit does not expose the space currently free between other items.
        max(40, min(360, floor(availableWidth / 2)))
    }

    static func batteryOptions(readings: Set<HUDMenuBarReading>, style: Style) -> HUDBatteryOptions {
        var options = style.battery
        options.enabled = !readings.isDisjoint(with: [.batteryPower, .batteryTemperature, .batteryEnergy])
        options.temperature = readings.contains(.batteryTemperature)
        options.charge = readings.contains(.batteryEnergy)
        options.flowMode = readings.contains(.batteryPower) ? options.flowMode : .off
        return options
    }

    static func sections(snapshot: HUDLogSnapshot, fanSample: FanSample,
                         readings: Set<HUDMenuBarReading>, style: Style,
                         background: HUDBackground) -> [[HUDHorizontalView.Reading]] {
        typealias Reading = HUDHorizontalView.Reading
        let scale = HUDScale.normal
        let valueColor = HUDStyle.readingColor(background: background)
        let labelColor = HUDStyle.TextStyle.label.color(background: background)
        var result: [[Reading]] = []

        func number(_ column: HUDLogColumn) -> Double? {
            snapshot.numbers[column]
        }
        func text(_ column: HUDLogColumn, places: Int = 0, suffix: String = "") -> String {
            guard let value = number(column) else { return "—" }
            return String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"),
                          places, places == 0 ? value.rounded() : value) + suffix
        }
        func title(_ metric: HUDMetric, group: HUDResourceGroup? = nil) -> Reading {
            Reading(id: "\(metric.rawValue).title", text: metric.hudTitle, reference: metric.hudTitle,
                    font: HUDStyle.titleFont(for: metric, scale: scale), color: labelColor,
                    help: nil, startsMetric: true, resourceGroup: group, metric: metric)
        }
        func value(_ metric: HUDMetric, role: String, text: String, reference: String,
                   group: HUDResourceGroup? = nil, highlighted: Bool = false,
                   color: NSColor? = nil) -> Reading {
            Reading(id: "\(metric.rawValue).\(role)", text: text, reference: reference,
                    font: HUDStyle.readingFont(scale: scale, highlighted: highlighted), color: color ?? valueColor,
                    help: nil, startsMetric: false, resourceGroup: group, metric: metric)
        }

        if readings.contains(.fps) {
            result.append([title(.fps), Reading(id: "fps.value", text: text(.fps), reference: "9999",
                font: HUDStyle.fpsValueFont(scale: scale, highlighted: style.fpsHighlighted), color: valueColor,
                help: "Frame rate", startsMetric: false, metric: .fps,
                sizingFont: HUDStyle.fpsValueFont(scale: scale, highlighted: true))])
        }

        var resources: [Reading] = []
        for group in [HUDResourceGroup.gpu, .cpu] {
            guard let options = style.resources[group] else { continue }
            let gpu = group == .gpu
            let usage = readings.contains(gpu ? .gpuUsage : .cpuUsage)
            let power = readings.contains(gpu ? .gpuPower : .cpuPower)
            let temperature = readings.contains(gpu ? .gpuTemperature : .cpuTemperature)
            if usage, options.selectedUsageMode != .total, let metric = group.appMetric {
                resources.append(title(metric, group: group))
                resources.append(value(metric, role: "value", text: text(gpu ? .gpuAppUsage : .cpuAppUsage, suffix: "%"),
                    reference: gpu ? HUDStyle.horizontalPercentageReference : "\(ProcessInfo.processInfo.activeProcessorCount * 100)%",
                    group: group, highlighted: options.usageHighlighted))
            }
            let totalUsage = usage && options.selectedUsageMode != .app
            guard power || temperature || totalUsage else { continue }
            let metric = group.totalMetric
            resources.append(title(metric, group: group))
            if power {
                resources.append(value(metric, role: "power", text: text(gpu ? .gpuPower : .cpuPower, places: 1, suffix: " W"),
                    reference: HUDStyle.horizontalPowerReference, group: group, highlighted: options.highlighted.contains(.power)))
            }
            if temperature {
                let column: HUDLogColumn = gpu ? .gpuTemperature : .cpuTemperature
                resources.append(value(metric, role: "temperature", text: text(column, suffix: "°C"),
                    reference: HUDStyle.horizontalTemperatureReference, group: group,
                    highlighted: options.highlighted.contains(.temperature),
                    color: HUDStyle.temperatureColor(number(column), warning: options.heatWarning, background: background)))
            }
            if totalUsage {
                resources.append(value(metric, role: "value", text: text(gpu ? .gpuUsage : .cpuUsage, suffix: "%"),
                    reference: HUDStyle.horizontalPercentageReference, group: group, highlighted: options.usageHighlighted))
            }
        }
        if readings.contains(.anePower) {
            resources += [title(.aneTotal, group: .ane), value(.aneTotal, role: "power",
                text: text(.anePower, places: 1, suffix: " W"), reference: HUDStyle.horizontalPowerReference,
                group: .ane, highlighted: style.resources[.ane]?.highlighted.contains(.power) ?? false)]
        }
        if readings.contains(.socPower) {
            resources += [Reading(id: "package.title", text: "SOC", reference: "SOC",
                font: HUDStyle.titleFont(for: .gpuTotal, scale: scale), color: labelColor, help: nil, startsMetric: true),
                Reading(id: "package.power", text: text(.socPower, places: 1, suffix: " W"),
                    reference: HUDStyle.horizontalPowerReference,
                    font: HUDStyle.readingFont(scale: scale, highlighted: style.packageHighlighted), color: valueColor,
                    help: nil, startsMetric: false)]
        }
        if let options = style.resources[.ram] {
            let details = readings.contains(.memoryDetails)
            let usage = readings.contains(.memoryUsage)
            let pressure = readings.contains(.memoryPressure)
            func detail(_ metric: HUDMetric, abbreviation: String, column: HUDLogColumn) -> [Reading] {
                [Reading(id: "\(metric.rawValue).\(abbreviation).title", text: abbreviation, reference: abbreviation,
                    font: HUDStyle.smallLabelFont(scale: scale), color: labelColor, help: nil,
                    startsMetric: false, resourceGroup: .ram, metric: metric, leftAligned: true),
                 Reading(id: "\(metric.rawValue).\(abbreviation).value", text: text(column, places: 2, suffix: " GB"), reference: "999.99 GB",
                    font: HUDStyle.readingFont(scale: scale, highlighted: options.highlighted.contains(.details)),
                    color: valueColor, help: nil, startsMetric: false, resourceGroup: .ram, metric: metric,
                    tightLeading: true, leftAligned: true)]
            }
            if (usage || details) && options.selectedUsageMode != .total {
                resources.append(title(.ram, group: .ram))
                if usage {
                    resources.append(value(.ram, role: "value", text: text(.memoryAppUsage, suffix: "%"),
                        reference: HUDStyle.horizontalPercentageReference, group: .ram, highlighted: options.usageHighlighted))
                }
                if details { resources += detail(.ram, abbreviation: "PHY", column: .memoryAppPhysical) }
            }
            if ((usage || details) && options.selectedUsageMode != .app) || pressure {
                resources.append(title(.ramTotal, group: .ram))
                if details && options.selectedUsageMode != .app {
                    resources += detail(.ramTotal, abbreviation: "PHY", column: .memoryPhysical)
                    resources += detail(.ramTotal, abbreviation: "SWP", column: .memorySwap)
                }
                if pressure {
                    let pressureText = snapshot.values[.memoryPressure] ?? "—"
                    resources.append(Reading(id: "ram.pressure", text: pressureText, reference: "warning",
                        font: HUDStyle.readingFont(scale: scale, highlighted: options.highlighted.contains(.pressure)),
                        color: valueColor, help: "Memory pressure: \(pressureText)", startsMetric: false,
                        resourceGroup: .ram, metric: .ramTotal,
                        sizingFont: HUDStyle.readingFont(scale: scale, highlighted: true),
                        pressureMode: options.pressureMode.resolved(for: .horizontal)))
                }
                if usage && options.selectedUsageMode != .app {
                    resources.append(value(.ramTotal, role: "value", text: text(.memoryUsage, suffix: "%"),
                        reference: HUDStyle.horizontalPercentageReference, group: .ram, highlighted: options.usageHighlighted))
                }
            }
        }
        if !resources.isEmpty { result.append(resources) }

        if readings.contains(.fanUsage) {
            let options = style.fans
            let fans = fanSample.displayReadings(averaged: options.averages(in: .horizontal))
            let fanColor = HUDStyle.titleColor(for: .fans, background: background)
            let fanReadings = fans.flatMap { fan -> [Reading] in
                var values = [Reading(id: "fan.\(fan.id).title", text: fan.title, reference: fan.title,
                    font: HUDStyle.titleFont(for: .fans, scale: scale), color: fanColor,
                    help: fan.title, startsMetric: true, metric: .fans, fanMarker: fan.iconMarker)]
                if options.mode.showsRPM {
                    values.append(Reading(id: "fan.\(fan.id).rpm", text: fan.rpmText.isEmpty ? "—" : fan.rpmText,
                        reference: "99999 RPM", font: HUDStyle.readingFont(scale: scale, highlighted: options.rpmHighlighted),
                        color: valueColor, help: nil, startsMetric: false, metric: .fans,
                        sizingFont: HUDStyle.readingFont(scale: scale, highlighted: true)))
                }
                if options.mode.showsBar {
                    values.append(Reading(id: "fan.\(fan.id).bar", text: "", reference: "",
                        font: HUDStyle.readingFont(scale: scale, highlighted: false), color: fanColor,
                        help: "\(fan.title) speed relative to maximum", startsMetric: false, metric: .fans,
                        barWidth: fanBarWidth(style: style), barFraction: fan.fraction))
                }
                return values
            }
            if fanReadings.isEmpty {
                result.append([Reading(id: "fan.status", text: fanSample.message ?? "Fan readings unavailable",
                    reference: "Fan readings unavailable", font: HUDStyle.smallLabelFont(scale: scale),
                    color: labelColor, help: nil, startsMetric: true, metric: .fans)])
            } else { result.append(fanReadings) }
        }
        return result
    }

    // The existing horizontal fan bar spans the same three reading columns as
    // the vertical pressure plot, even when some overlay readings are disabled.
    private static func fanBarWidth(style: Style) -> CGFloat {
        let options = style.resources[.cpu]
        let references: [(String, Bool)] = [("0.0 W", options?.highlighted.contains(.power) ?? false),
            ("149°C", options?.highlighted.contains(.temperature) ?? false),
            ("100%", options?.usageHighlighted ?? false)]
        let width = references.reduce(CGFloat.zero) { result, reference in
            let label = NSTextField(labelWithString: reference.0)
            label.font = HUDStyle.readingFont(scale: .normal, highlighted: reference.1)
            return result + label.intrinsicContentSize.width
        }
        return width + 2 * HUDStyle.metricColumnSpacing(scale: .normal)
            + NSTextField(labelWithString: "").alignmentRectInsets.right
    }
}

@MainActor
final class HUDMenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onToggleCollapsed: () -> Void
    private let widthLimitProvider: (() -> CGFloat)?
    private let content = HUDMenuBarPassiveView(frame: .zero)
    private let horizontal = HUDHorizontalView(frame: .zero)
    private let measuringHorizontal = HUDHorizontalView(frame: .zero)
    private let collapsedFPSIndicator = HUDMenuBarPassiveImageView(frame: .zero)
    private let bolt = HUDMenuBarPassiveImageView(frame: .zero)
    private let collapse = HUDMenuBarCollapseButton(frame: .zero)
    private var latestSnapshot = HUDLogSnapshot()
    private var latestFans = FanSample.checking
    private var latestBattery: BatterySample?
    private var latestOptions = HUDMenuBarOptions()
    private var latestFPSExpanded = true
    private var latestAutoHideMode: HUDAutoHideMode = .off
    private var installed = false
    private var updating = false
    private var overflowing = false
    private var overflowSequence = 0

    var onWidthOverflow: (() -> Void)?

    var maximumExpandedWidth: CGFloat {
        if let widthLimitProvider { return max(40, widthLimitProvider()) }
        return NSScreen.screens.map { screen in
            HUDMenuBarPresentation.widthLimit(availableWidth:
                screen.auxiliaryTopRightArea?.width ?? screen.frame.width / 2)
        }.min() ?? 360
    }

    init(statusItem: NSStatusItem, widthLimitProvider: (() -> CGFloat)? = nil,
         onToggleCollapsed: @escaping () -> Void) {
        self.statusItem = statusItem
        self.onToggleCollapsed = onToggleCollapsed
        self.widthLimitProvider = widthLimitProvider
        super.init()
        content.addSubview(horizontal)
        content.addSubview(collapsedFPSIndicator)
        collapsedFPSIndicator.image = NSImage(systemSymbolName: "arrow.right",
            accessibilityDescription: "FPS enabled; collapsed while waiting for readings")
        collapsedFPSIndicator.imageScaling = .scaleProportionallyUpOrDown
        collapsedFPSIndicator.isHidden = true
        horizontal.isHidden = false
        horizontal.battery.showsUnavailableReadings = true
        measuringHorizontal.battery.showsUnavailableReadings = true
        bolt.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "PerformanceHUD")
        bolt.imageScaling = .scaleProportionallyUpOrDown
        collapse.title = ""
        collapse.imagePosition = .imageOnly
        collapse.isBordered = false
        collapse.setButtonType(.momentaryChange)
        collapse.target = self
        collapse.action = #selector(toggleCollapsed)
        collapse.sendAction(on: .leftMouseDown)
        content.onAppearanceChange = { [weak self] in self?.refreshAppearance() }
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func refresh(snapshot: HUDLogSnapshot, fanSample: FanSample,
                 batterySample: BatterySample?, options: HUDMenuBarOptions,
                 fpsExpanded: Bool = true, autoHideMode: HUDAutoHideMode = .off) {
        latestSnapshot = snapshot
        latestFans = fanSample
        latestBattery = batterySample
        latestOptions = options
        latestFPSExpanded = fpsExpanded
        latestAutoHideMode = autoHideMode
        updatePresentation()
    }

    private func refreshAppearance() {
        guard installed, !updating else { return }
        updatePresentation()
    }

    @objc private func toggleCollapsed() { onToggleCollapsed() }

    @objc private func screenParametersChanged() { updatePresentation() }

    /// Measures the same renderer used by the status item, including its scale
    /// transform, padding, and controls. Auto Charge reserves its visible width
    /// and FPS keeps its full width even while rolled up, so readings returning
    /// cannot unexpectedly consume more menu-bar space than was allowed.
    func expandedWidth(for readings: Set<HUDMenuBarReading>) -> CGFloat {
        guard !readings.isEmpty else { return 40 }
        let height = menuBarHeight
        let style = HUDMenuBarPresentation.Style.current
        let size = configure(measuringHorizontal, readings: readings, style: style,
                             background: menuBarBackground, reserveAutoCharge: true)
        guard size.width > 0 else { return 40 }
        let factor = HUDMenuBarPresentation.scaleFactor(menuBarHeight: height)
        return HUDMenuBarPresentation.scaledSize(size, menuBarHeight: height).width
            + 2 * HUDStyle.horizontalPadding(scale: .normal) * factor + 40
    }

    private var menuBarHeight: CGFloat {
        let height = statusItem.button?.bounds.height ?? 0
        return height > 0 ? height : NSStatusBar.system.thickness
    }

    private var menuBarBackground: HUDBackground {
        statusItem.button?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    private func configure(_ view: HUDHorizontalView, readings: Set<HUDMenuBarReading>,
                           style: HUDMenuBarPresentation.Style, background: HUDBackground,
                           reserveAutoCharge: Bool = false) -> NSSize {
        var batteryOptions = HUDMenuBarPresentation.batteryOptions(readings: readings, style: style)
        if reserveAutoCharge, batteryOptions.flowMode == .auto { batteryOptions.flowMode = .always }
        view.battery.setOptions(batteryOptions)
        view.battery.update(percentage: latestBattery?.percentage, source: latestBattery?.source,
            temperature: latestBattery?.temperature, power: latestBattery?.power)
        // Charge alone has no useful category label when Auto has no flow or
        // Off is selected. Keep updating the view above so Auto can return.
        let chargeOnly = readings.contains(.batteryPower) && !batteryOptions.temperature && !batteryOptions.charge
        let showsBattery = batteryOptions.enabled && (!chargeOnly || view.battery.hasVisiblePowerFlow)
        let sections = HUDMenuBarPresentation.sections(snapshot: latestSnapshot, fanSample: latestFans,
            readings: readings, style: style, background: background)
        return view.configure(sections: sections, showsBattery: showsBattery,
            scale: .normal, background: background)
    }

    private func reportOverflow(_ value: Bool) {
        guard value else {
            overflowing = false
            return
        }
        guard !overflowing else { return }
        overflowing = true
        overflowSequence += 1
        let sequence = overflowSequence
        DispatchQueue.main.async { [weak self] in
            guard let self, self.overflowing, self.overflowSequence == sequence else { return }
            self.onWidthOverflow?()
        }
    }

    private func setStatusItemLength(_ length: CGFloat) {
        if statusItem.length != length { statusItem.length = length }
    }

    private func updatePresentation() {
        guard let button = statusItem.button, !updating else { return }
        updating = true
        defer { updating = false }
        guard !latestOptions.readings.isEmpty else {
            reportOverflow(false)
            collapsedFPSIndicator.isHidden = true
            if installed {
                content.removeFromSuperview()
                bolt.removeFromSuperview()
                collapse.removeFromSuperview()
                setStatusItemLength(NSStatusItem.squareLength)
                button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "PerformanceHUD")
                installed = false
            }
            return
        }
        if !installed {
            button.addSubview(content)
            button.addSubview(bolt)
            button.addSubview(collapse)
            installed = true
        }
        // Rebuilding the settings menu may restore the original bolt image.
        // This view supplies the bolt while readings or their chevron are shown.
        button.image = nil
        let height = menuBarHeight
        let buttonWidth: CGFloat = 22
        let chevronWidth: CGFloat = 18
        let factor = HUDMenuBarPresentation.scaleFactor(menuBarHeight: height)
        let padding = HUDStyle.horizontalPadding(scale: .normal) * factor
        let background = menuBarBackground
        bolt.contentTintColor = .labelColor
        collapse.contentTintColor = .labelColor
        let exceedsLimit = !latestOptions.isCollapsed
            && expandedWidth(for: latestOptions.readings) > maximumExpandedWidth
        let isCollapsed = latestOptions.isCollapsed || exceedsLimit
        reportOverflow(exceedsLimit)
        content.isHidden = isCollapsed
        collapsedFPSIndicator.isHidden = true
        var contentWidth: CGFloat = 0
        if !isCollapsed {
            let style = HUDMenuBarPresentation.Style.current
            let size = configure(horizontal, readings: latestOptions.readings, style: style,
                                 background: background)
            let fpsCollapsed = latestOptions.readings.contains(.fps)
                && latestAutoHideMode == .fps && !latestFPSExpanded
            // Empty Auto Charge may leave FPS as the only rendered section.
            // Keep one global chevron instead of an adjacent passive arrow.
            let onlyWaitingFPS = fpsCollapsed && size.width == horizontal.fpsSectionWidth
            if size.width > 0 && !onlyWaitingFPS {
                let headerWidth = HUDStyle.ramDetailHeight(scale: .normal)
                let fpsOffset = fpsCollapsed ? max(0, horizontal.fpsSectionWidth - headerWidth) : 0
                let visibleSize = NSSize(width: size.width - fpsOffset, height: size.height)
                content.clipsToBounds = fpsCollapsed
                horizontal.setFPSOpacity(fpsCollapsed ? 0 : 1)
                horizontal.frame = NSRect(x: -fpsOffset, y: 0, width: size.width, height: size.height)
                collapsedFPSIndicator.isHidden = !fpsCollapsed
                collapsedFPSIndicator.contentTintColor = HUDStyle.titleColor(for: .deviceInfo, background: background)
                collapsedFPSIndicator.frame = NSRect(x: (headerWidth - 12) / 2,
                    y: (size.height - 12) / 2, width: 12, height: 12)
                let scaled = HUDMenuBarPresentation.scaledSize(visibleSize, menuBarHeight: height)
                content.frame = NSRect(x: padding, y: (height - scaled.height) / 2,
                                       width: scaled.width, height: scaled.height)
                content.bounds = NSRect(origin: .zero, size: visibleSize)
                contentWidth = scaled.width + 2 * padding
            } else {
                // Retain a valid bounds transform while temporarily empty.
                content.isHidden = true
            }
        }
        let title = isCollapsed ? "Show menu-bar readings" : "Hide menu-bar readings"
        collapse.image = NSImage(systemSymbolName: isCollapsed ? "chevron.left" : "chevron.right",
                                  accessibilityDescription: title)
        collapse.setAccessibilityLabel(title)
        collapse.imageScaling = .scaleProportionallyDown
        // Keep both controls together at the anchored right edge, so collapsing
        // the readings to their left does not move the next click target.
        collapse.frame = NSRect(x: contentWidth, y: 0, width: chevronWidth, height: height)
        bolt.frame = NSRect(x: contentWidth + chevronWidth + 5, y: (height - 15) / 2, width: 12, height: 15)
        setStatusItemLength(buttonWidth + contentWidth + chevronWidth)
        button.setAccessibilityLabel("PerformanceHUD")
    }
}

/// Labels and drawings leave native status-button tracking intact; the separate
/// chevron button remains the only child that consumes a click.
@MainActor
private final class HUDMenuBarPassiveView: NSView {
    var onAppearanceChange: (() -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

@MainActor
private final class HUDMenuBarPassiveImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The standard button cell reserves more interior padding than this compact
/// status-item control has. Draw the system symbol directly while retaining
/// NSButton's tracking, target/action, and accessibility behavior.
@MainActor
private final class HUDMenuBarCollapseButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        guard let image = image?.withSymbolConfiguration(.init(paletteColors: [.labelColor])) else { return }
        let size = image.size
        image.draw(in: NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                             width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: isHighlighted ? 0.6 : 1,
                   respectFlipped: true, hints: nil)
    }
}
