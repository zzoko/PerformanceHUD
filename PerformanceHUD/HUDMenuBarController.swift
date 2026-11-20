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

        var fpsMeasure: HUDFPSMeasure = .frameRate
        var cpuCores = HUDCoreOptions.cpuDefault
        var gpuCores = HUDCoreOptions.gpuDefault

        static var current: Self {
            Self(resources: Dictionary(uniqueKeysWithValues: HUDResourceGroup.allCases.map {
                ($0, HUDPreferences.resourceOptions(for: $0))
            }), fpsHighlighted: HUDPreferences.fpsOptions.valueHighlighted,
                 packageHighlighted: HUDPreferences.packagePowerOptions.highlighted,
                 fans: HUDPreferences.fanOptions, battery: HUDPreferences.batteryOptions, fpsMeasure: HUDPreferences.fpsOptions.measure,
                 cpuCores: HUDPreferences.cpuCoreOptions, gpuCores: HUDPreferences.gpuCoreOptions)
        }
    }

    static func scaleFactor(menuBarHeight: CGFloat) -> CGFloat {
        min(1, max(1, menuBarHeight - 4) / HUDStyle.rowHeight)
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
                         background: HUDBackground,
                         coreTypes: [HUDCPUCoreType] = HUDDeviceInfo.current.coreTypes,
                         topology: CPUCoreTopology = .current) -> [[HUDHorizontalView.Reading]] {
        typealias Reading = HUDHorizontalView.Reading
        let valueColor = HUDStyle.readingColor(background: background)
        let labelColor = HUDStyle.TextStyle.label.color(background: background)
        var result: [[Reading]] = []

        func number(_ column: HUDLogColumn) -> Double? {
            snapshot.numbers[column]
        }
        func text(_ column: HUDLogColumn, places: Int = 0, suffix: String = "") -> String {
            guard let value = number(column) else { return "" }
            return String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"),
                          places, places == 0 ? value.rounded() : value) + suffix
        }
        func title(_ metric: HUDMetric) -> Reading {
            let caption = metric.hudTitle(for: .horizontal)
            return Reading(id: "\(metric.rawValue).title", text: caption, reference: caption,
                    font: HUDStyle.titleFont(for: metric), color: labelColor,
                    help: nil, startsMetric: true, metric: metric)
        }
        func value(_ metric: HUDMetric, role: String, text: String, reference: String,
                   highlighted: Bool = false,
                   color: NSColor? = nil) -> Reading {
            Reading(id: "\(metric.rawValue).\(role)", text: text, reference: reference,
                    font: HUDStyle.readingFont(highlighted: highlighted), color: color ?? valueColor,
                    help: nil, startsMetric: false, metric: metric)
        }

        if readings.contains(.fps) {
            let measure = style.fpsMeasure
            // Reserve the wider caption and value so changing the measure keeps the pin width stable.
            result.append([Reading(id: "\(HUDMetric.fps.rawValue).title", text: measure.caption, reference: HUDFPSMeasure.frameRate.caption,
                font: HUDStyle.titleFont(for: .fps), color: labelColor,
                help: nil, startsMetric: true, metric: .fps),
                Reading(id: "fps.value", text: measure.reading(fps: number(.fps), averageMS: number(.frameTimeAverage)) ?? "",
                reference: HUDFPSMeasure.frameTime.valueWidthReference, font: HUDStyle.fpsValueFont(highlighted: style.fpsHighlighted),
                color: valueColor, help: measure.menuTitle, startsMetric: false, metric: .fps,
                sizingFont: HUDStyle.fpsValueFont(highlighted: true))])
        }

        var resources: [Reading] = []
        for group in [HUDResourceGroup.gpu, .cpu] {
            guard let options = style.resources[group] else { continue }
            let gpu = group == .gpu
            let usage = readings.contains(gpu ? .gpuUsage : .cpuUsage)
            let power = readings.contains(gpu ? .gpuPower : .cpuPower)
            let temperature = readings.contains(gpu ? .gpuTemperature : .cpuTemperature)
            let cores = readings.contains(gpu ? .gpuCores : .cpuCores)
            guard power || temperature || usage || cores else { continue }
            let metric = group.totalMetric
            resources.append(title(metric))
            if power {
                resources.append(value(metric, role: "power", text: text(gpu ? .gpuPower : .cpuPower, places: 1, suffix: " W"),
                    reference: HUDStyle.horizontalPowerReference, highlighted: options.highlighted.contains(.power)))
            }
            if temperature {
                let column: HUDLogColumn = gpu ? .gpuTemperature : .cpuTemperature
                resources.append(value(metric, role: "temperature", text: text(column, suffix: "°C"),
                    reference: HUDStyle.horizontalTemperatureReference,
                    highlighted: options.highlighted.contains(.temperature),
                    color: HUDStyle.temperatureColor(number(column), warning: options.heatWarning, background: background)))
            }
            if usage {
                resources.append(value(metric, role: "value", text: text(gpu ? .gpuUsage : .cpuUsage, suffix: "%"),
                    reference: HUDStyle.horizontalPercentageReference, highlighted: options.usageHighlighted))
            }
            if cores {
                let options = gpu ? style.gpuCores : style.cpuCores
                let rows: [HUDHorizontalView.CoreRow]
                if gpu {
                    rows = [.init(name: "Cores", frequency: text(.gpuFrequency, places: 1, suffix: " GHz"), activity: [])]
                } else {
                    let types = coreTypes.isEmpty ? [HUDCPUCoreType(name: "Cores", count: 0)] : coreTypes
                    rows = types.map { type in
                        let ids = topology.groups.first { $0.name == type.name }?.ids ?? []
                        let activity: [Double?] = options.mode.showsBars
                            ? (ids.isEmpty ? Array(repeating: nil, count: type.count) : ids.map { number(.cpuCoreUsage($0)) })
                            : []
                        return .init(name: type.name, frequency: options.mode.showsValue
                            ? text(.cpuTypeFrequency(type.name), places: 1, suffix: " GHz") : nil, activity: activity)
                    }
                }
                resources += HUDCoreDetailView.horizontalReadings(rows: rows, gpu: gpu, options: options,
                    background: background)
            }
        }
        if readings.contains(.anePower) {
            resources += [title(.aneTotal), value(.aneTotal, role: "power",
                text: text(.anePower, places: 1, suffix: " W"), reference: HUDStyle.horizontalPowerReference,
                highlighted: style.resources[.ane]?.highlighted.contains(.power) ?? false)]
        }
        if readings.contains(.socPower) {
            resources += [Reading(id: "package.title", text: "SOC", reference: "SOC",
                font: HUDStyle.titleFont(for: .gpuTotal), color: labelColor, help: nil, startsMetric: true),
                Reading(id: "package.power", text: text(.socPower, places: 1, suffix: " W"),
                    reference: HUDStyle.horizontalPowerReference,
                    font: HUDStyle.readingFont(highlighted: style.packageHighlighted), color: valueColor,
                    help: nil, startsMetric: false)]
        }
        if let options = style.resources[.ram] {
            let details = readings.contains(.memoryDetails)
            let usage = readings.contains(.memoryUsage)
            let pressure = readings.contains(.memoryPressure)
            if usage || details || pressure {
                resources.append(title(.ramTotal))
                if usage {
                    resources.append(value(.ramTotal, role: "value", text: text(.memoryUsage, suffix: "%"),
                        reference: HUDStyle.horizontalPercentageReference, highlighted: options.usageHighlighted))
                }
                if details {
                    resources += HUDHorizontalView.memoryDetails(swap: text(.memorySwap, places: 2, suffix: " GB"),
                        physical: text(.memoryPhysical, places: 2, suffix: " GB"), valueFont: HUDStyle.readingFont(highlighted: options.highlighted.contains(.details)),
                        background: background)
                }
                if pressure {
                    let mode = HUDMenuBarReading.pressureMode(options.pressureMode)
                    let pressureText = snapshot.values[.memoryPressure] ?? ""
                    let level = mode == .colorText ? MemoryPressureMonitor.Level(displayText: pressureText) : nil
                    resources.append(Reading(id: "ram.pressure", text: pressureText, reference: "warning",
                        font: HUDStyle.readingFont(highlighted: options.highlighted.contains(.pressure)),
                        color: HUDStyle.pressureColor(for: level, background: background), help: "Memory pressure: \(pressureText)", startsMetric: false,
                        metric: .ramTotal,
                        sizingFont: HUDStyle.readingFont(highlighted: true),
                        pressureMode: mode))
                }
            }
        }
        if !resources.isEmpty { result.append(resources) }

        if readings.contains(.fanUsage) {
            var pinnedFans = style.fans
            pinnedFans.mode = HUDMenuBarReading.fanMode
            result.append(HUDHorizontalView.fanReadings(sample: fanSample, options: pinnedFans,
                background: background))
        }
        return result
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
        horizontal.battery.reservesMissingPowerSpace = true
        measuringHorizontal.battery.reservesMissingPowerSpace = true
        bolt.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "PerformanceHUD")
        bolt.imageScaling = .scaleProportionallyUpOrDown
        collapse.title = ""
        collapse.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Show menu-bar readings")
        collapse.setAccessibilityLabel("Show menu-bar readings")
        collapse.imageScaling = .scaleProportionallyDown
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
    /// transform and padding. Auto Charge reserves its visible width
    /// and FPS keeps its full width even while rolled up, so readings returning
    /// cannot unexpectedly consume more menu-bar space than was allowed.
    func expandedWidth(for readings: Set<HUDMenuBarReading>) -> CGFloat {
        guard !readings.isEmpty else { return menuBarHeight }
        let height = menuBarHeight
        let style = HUDMenuBarPresentation.Style.current
        let size = configure(measuringHorizontal, readings: readings, style: style,
                             background: menuBarBackground, reserveAutoCharge: true)
        guard size.width > 0 else { return menuBarHeight }
        let factor = HUDMenuBarPresentation.scaleFactor(menuBarHeight: height)
        return HUDMenuBarPresentation.scaledSize(size, menuBarHeight: height).width
            + 2 * HUDStyle.horizontalPadding * factor
    }

    private var menuBarHeight: CGFloat {
        // A native bolt can change the button’s intrinsic height. Size readings
        // against the status bar so they return at the same scale after hiding.
        statusItem.statusBar?.thickness ?? NSStatusBar.system.thickness
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
            background: background, inMenuBar: true)
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
                installed = false
            }
            setStatusItemLength(NSStatusItem.squareLength)
            if button.image == nil { button.image = bolt.image }
            return
        }
        if !installed {
            button.addSubview(content)
            button.addSubview(bolt)
            button.addSubview(collapse)
            installed = true
        }
        let height = menuBarHeight
        let factor = HUDMenuBarPresentation.scaleFactor(menuBarHeight: height)
        let padding = HUDStyle.horizontalPadding * factor
        let background = menuBarBackground
        bolt.contentTintColor = .labelColor
        collapse.contentTintColor = .labelColor
        let exceedsLimit = !latestOptions.isCollapsed
            && expandedWidth(for: latestOptions.readings) > maximumExpandedWidth
        let isCollapsed = latestOptions.isCollapsed || exceedsLimit
        reportOverflow(exceedsLimit)
        collapsedFPSIndicator.isHidden = true
        collapse.isHidden = !isCollapsed
        bolt.isHidden = !isCollapsed
        button.setAccessibilityLabel("PerformanceHUD")
        if isCollapsed {
            content.isHidden = true
            button.image = nil
            collapse.frame = NSRect(x: 0, y: 0, width: 18, height: height)
            bolt.frame = NSRect(x: 23, y: (height - 15) / 2, width: 12, height: 15)
            setStatusItemLength(40)
            return
        }

        let style = HUDMenuBarPresentation.Style.current
        let size = configure(horizontal, readings: latestOptions.readings, style: style,
                             background: background)
        let fpsCollapsed = latestOptions.readings.contains(.fps)
            && latestAutoHideMode == .fps && !latestFPSExpanded
        // Auto Charge can leave a waiting FPS pin as the only section.
        let onlyWaitingFPS = fpsCollapsed && size.width == horizontal.fpsSectionWidth
        if size.width > 0 && !onlyWaitingFPS {
            content.isHidden = false
            let headerWidth = HUDStyle.ramDetailHeight()
            let fpsOffset = fpsCollapsed ? max(0, horizontal.fpsSectionWidth - headerWidth) : 0
            let visibleSize = NSSize(width: size.width - fpsOffset, height: size.height)
            content.clipsToBounds = fpsCollapsed
            horizontal.setFPSOpacity(fpsCollapsed ? 0 : 1)
            horizontal.frame = NSRect(x: -fpsOffset, y: 0, width: size.width, height: size.height)
            collapsedFPSIndicator.isHidden = !fpsCollapsed
            collapsedFPSIndicator.contentTintColor = HUDStyle.TextStyle.label.color(background: background)
            collapsedFPSIndicator.frame = NSRect(x: (headerWidth - 12) / 2,
                y: (size.height - 12) / 2, width: 12, height: 12)
            let scaled = HUDMenuBarPresentation.scaledSize(visibleSize, menuBarHeight: height)
            content.frame = NSRect(x: padding, y: (height - scaled.height) / 2,
                                   width: scaled.width, height: scaled.height)
            content.bounds = NSRect(origin: .zero, size: visibleSize)
            horizontal.alignReadingFrames()
            button.image = nil
            setStatusItemLength(scaled.width + 2 * padding)
        } else {
            content.isHidden = true
            if button.image == nil { button.image = bolt.image }
            setStatusItemLength(NSStatusItem.squareLength)
        }
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
