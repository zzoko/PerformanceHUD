import AppKit

@MainActor
final class HUDWindowController {

    // MARK: - Window

    private let panel: HUDPanel

    private let container:
        NSView

    private let stackView = NSView()

    private let windowContentView = NSView()
    private let backgroundView = NativeGlassHUDBackground(frame: .zero)
    private let glassSession: NativeGlassSession
    private let scaledContentView = NSView()
    private let backgroundContentView = NSView()
    private var backgroundSelection = HUDPreferences.background
    private var hudBackground = HUDPreferences.background.resolved(isDark: HUDWindowController.systemIsDark)
    private var appearanceObservation: NSKeyValueObservation?

    private static var systemIsDark: Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    // MARK: - Metric Views

    private var metricRows:
        [HUDMetric: NSView] = [:]

    private var titleLabels:
        [HUDMetric: NSTextField] = [:]

    private var valueLabels:
        [HUDMetric: NSTextField] = [:]

    private let metricGroups: [[HUDMetric]] = [
        [.fps, .fpsGraph],
        [.gpuTotal, .gpuCores, .cpuTotal, .cpuCores, .aneTotal, .ramTotal],
        [.storage],
        [.fans],
        [.battery]
    ]

    private let verticalMetricGroups: [[HUDMetric]] = [
        [.fps, .fpsGraph],
        [.process],
        [.gpuTotal, .gpuCores, .cpuTotal, .cpuCores, .aneTotal],
        [.ramTotal],
        [.storage],
        [.fans],
        [.battery],
        [.misc]
    ]

    private var groupDividers: [Int: NSView] = [:]

    private var showsRAMDetails = HUDPreferences.resourceOptions(for: .ram).showsDetails
    private var showsRAMPressure = HUDPreferences.resourceOptions(for: .ram).showsPressure
    private var memoryClusterWidth: CGFloat = 0
    private var ramDetailLabels: [HUDMetric: NSTextField] = [:]
    private let fpsGraphView = HUDFPSGraphView()
    private let horizontalView = HUDHorizontalView(frame: .zero) { HUDReadingLabel(labelWithString: "") }
    private let storageView = HUDStorageView(horizontal: false)
    private var storageOptions = HUDPreferences.storageOptions()
    private var storageDrives: [StorageDrive] = []
    private var visibleDrives: [StorageDrive] {
        storageOptions.enabled ? storageDrives.filter { storageOptions.location.includes(internalDrive: $0.internalDrive) } : []
    }

    private let fanView = HUDFanView(frame: .zero)
    private var fanOptions = HUDPreferences.fanOptions
    private var fpsMeasure = HUDPreferences.fpsOptions.measure
    private var fpsHitchMarks = HUDPreferences.fpsOptions.hitchMarks
    private var latestFPS: Double?
    private var latestFrameTiming: MetalFrameTiming?
    private var fpsValueHighlighted = HUDPreferences.fpsOptions.valueHighlighted
    private var fpsValueSize = HUDPreferences.fpsOptions.valueSize
    private var fanSample = FanSample.checking
    private var alignment = HUDPreferences.alignment
    private var ramDetailTitleLabels: [HUDMetric: NSTextField] = [:]
    private var ramSwapTitleLabel: NSTextField?
    private var ramSwapValueLabel: NSTextField?
    private var ramPressureValueLabel: NSTextField?
    private var ramPressureTitleLabel: NSTextField?
    private let ramPressureMeter = HUDMemoryPressureMeterView()
    private let ramPressureHistory = HUDMemoryPressureHistoryView()
    private var memoryPressureMode = HUDPreferences.resourceOptions(for: .ram).pressureMode
    private let batteryIndicator = HUDBatteryIndicatorView(frame: .zero)
    private let processView = HUDProcessView(frame: .zero)
    private let cpuCoreView: HUDCoreDetailView
    private var processOptions = HUDPreferences.processOptions
    private var cpuCoreOptions = HUDPreferences.cpuCoreOptions
    private var cpuResourceOptions = HUDPreferences.resourceOptions(for: .cpu)
    private var cpuCoreSample = CPUCoreSample.unavailable
    private var cpuFrequencies = CPUFrequencySample.unavailable
    private let gpuCoreView = HUDCoreDetailView(frame: .zero, gpu: true)
    private var gpuCoreOptions = HUDPreferences.gpuCoreOptions
    private var gpuResourceOptions = HUDPreferences.resourceOptions(for: .gpu)
    private var gpuFrequency: Double?
    private let miscView: HUDMiscView
    private var miscOptions = HUDPreferences.miscOptions

    private var temperatureLabels: [HUDMetric: NSTextField] = [:]
    private var temperatures: [HUDMetric: Double] = [:]
    private var temperatureWarnings: [HUDMetric: HUDHeatWarningOptions] = Dictionary(uniqueKeysWithValues:
        [HUDResourceGroup.cpu, .gpu].map { ($0.totalMetric, HUDPreferences.resourceOptions(for: $0).heatWarning) })
    private var powerLabels: [HUDMetric: NSTextField] = [:]
    private var powerTrailing: [HUDMetric: CGFloat] = [:]
    private var readingColumnRight: CGFloat = 0
    private var powerMetrics: Set<HUDMetric> = []
    private var highlightedReadings: [HUDMetric: Set<HUDReadingKind>] = [:]
    private var packageTitleLabel: NSTextField?
    private var packageValueLabel: NSTextField?
    private var packageRow: NSView?
    private var packageOptions = HUDPreferences.packagePowerOptions
    private var packageRowHeight: CGFloat {
        HUDStyle.rowHeight
    }
    private var hasVisibleContent: Bool { !enabledMetrics.isEmpty || showsPackagePower }
    private var showsPackagePower: Bool {
        packageOptions.enabled
    }
    private var temperatureTrailing: [HUDMetric: CGFloat] = [:]
    private var temperatureMetrics: Set<HUDMetric> = []
    private var hiddenUtilizationMetrics: Set<HUDMetric> = []

    // MARK: - State

    private var hudEnabled = HUDPreferences.hudEnabled

    private var enabledMetrics = HUDPreferences.visibleMetrics.subtracting([.storage])

    private var hudScale =
        HUDPreferences.hudScale

    private var customTopLeft = HUDPreferences.hudPosition
    private var screenObserver: NSObjectProtocol?
    private var geometryObservers: [NSObjectProtocol] = []
    private var windowGeometryTask: Task<Void, Never>?
    private var displayLayoutPending = false
    private var resizingHUD = false

    // Keep expanded layout measurements separate from the animated native surface.
    private let autoHidePresentation = HUDAutoHidePresentation(enabled: HUDPreferences.autoHideMode == .all)
    private var lastAutoHideHidden = HUDPreferences.autoHideMode == .all
    var onAutoHideVisibilityChange: (() -> Void)?
    var onFPSAvailabilityChange: (() -> Void)?
    var hasRecentFPSReading: Bool { fpsAvailability.expanded }
    var presentationScreen: NSScreen? { panel.screen }
    var isAutomaticallyHidden: Bool { modeTransition == nil && autoHidePresentation.isHidden }
    private var autoHideMode = HUDPreferences.autoHideMode
    private var autoHideAnimated = HUDPreferences.autoHideAnimated
    // Mode changes interpolate both the rounded surface and the FPS content.
    // Keep this presentation independent of the newly selected mode until it
    // reaches that mode's resting shape, including a compact FPS arrow.
    private struct ModeTransition {
        var size: NSSize
        var fpsProgress: CGFloat
        var available: Bool
    }
    private var modeTransition: ModeTransition?
    private var modeAnimationTimer: Timer?
    private var fpsAvailability = HUDFPSAvailability() {
        didSet {
            if oldValue.expanded != fpsAvailability.expanded { onFPSAvailabilityChange?() }
        }
    }
    private var fpsAvailabilityTask: Task<Void, Never>?
    private var fpsAnimationTimer: Timer?
    private var fpsAnimationTarget: CGFloat?
    private var fpsProgress: CGFloat = 1
    private var fpsCollapseDistance: CGFloat = 0
    private weak var fpsPresentationAnchor: NSView?
    private var collapsedVerticalFPSHeight: CGFloat = 0
    private let collapsedFPSIndicator = NSImageView()
    private var collapsedFPSHeaderHeight: CGFloat { HUDStyle.ramDetailHeight() }
    // Fitting and presentation sizes stay in 1× points until they reach the window.
    private var expandedHUDSize = NSSize.zero
    private var dynamicFPSActive: Bool {
        autoHideMode == .fps && !enabledMetrics.isDisjoint(with: [.fps, .fpsGraph])
    }

    private var usesFPSPresentation: Bool {
        (dynamicFPSActive || modeTransition != nil)
            && !enabledMetrics.isDisjoint(with: [.fps, .fpsGraph])
    }

    private var presentedFPSProgress: CGFloat {
        modeTransition?.fpsProgress ?? (dynamicFPSActive ? fpsProgress : 1)
    }

    private var shouldAnimateAutoHide: Bool {
        autoHideAnimated && hudEnabled && hasVisibleContent
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var textBackground: HUDBackground { hudBackground }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        for observer in geometryObservers { NotificationCenter.default.removeObserver(observer) }
        windowGeometryTask?.cancel()
        fpsAvailabilityTask?.cancel()
        fpsAnimationTimer?.invalidate()
        modeAnimationTimer?.invalidate()
    }

    // MARK: - Init

    init(deviceInfo: HUDDeviceInfo = .current, cpuTopology: CPUCoreTopology = .current) {

        cpuCoreView = HUDCoreDetailView(frame: .zero, types: deviceInfo.coreTypes, topology: cpuTopology)
        miscView = HUDMiscView(frame: .zero, info: deviceInfo)

        panel = HUDPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width:
                    HUDStyle.width,
                height: 100
            ),
            styleMask: [
                .borderless,
                .nonactivatingPanel
            ],
            backing: .buffered,
            defer: false
        )

        container = backgroundView.contentView
        glassSession = NativeGlassSession(window: panel)

        configureWindow()
        configureContainer()
        configureStackView()
        createMetricRows()

        autoHidePresentation.onChange = { [weak self] in self?.applyHUDPresentation() }
        updateLayout()
        restorePosition()
        panel.onDragFinished = { [weak self] in
            guard let self else { return }
            customTopLeft = visibleTopLeft
            restorePosition()
            HUDPreferences.hudPosition = visibleTopLeft
            customTopLeft = HUDPreferences.hudPosition
        }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.didChangeScreenNotification, NSWindow.didChangeBackingPropertiesNotification] {
            geometryObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: panel, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if name == NSWindow.didChangeBackingPropertiesNotification
                        || name == NSWindow.didChangeScreenNotification {
                        self.scheduleWindowGeometryRefresh(displayChanged: true)
                    } else if name == NSWindow.didResizeNotification && !self.resizingHUD {
                        self.scheduleWindowGeometryRefresh()
                    }
                }
            })
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleWindowGeometryRefresh(displayChanged: true)
            }
        }
        // Observe the app, not the HUD container whose appearance we override.
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, backgroundSelection == .system,
                      hudBackground != HUDBackground.system.resolved(isDark: Self.systemIsDark) else { return }
                setBackground(.system)
            }
        }
    }

    // MARK: - Window Setup

    private func configureWindow() {

        panel.isOpaque =
            false

        panel.backgroundColor =
            .clear

        panel.hasShadow =
            false

        panel.isFloatingPanel =
            true

        panel.hidesOnDeactivate =
            false

        // Mouse input passes through the HUD.
        panel.ignoresMouseEvents =
            true

        panel.level =
            HUDStyle.windowLevel

        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
    }

    // MARK: - Container

    private func configureContainer() {

        container.wantsLayer =
            true

        container.layer?
            .backgroundColor =
                NSColor.clear.cgColor

        // Leave transparent room inside the window for the layer-rendered shadow.
        windowContentView.wantsLayer = true
        panel.contentView = windowContentView
        windowContentView.addSubview(backgroundView)
        // All metric views live in this one 1× coordinate system. The glass and
        // its clipped viewport remain in window coordinates outside it.
        scaledContentView.autoresizesSubviews = false
        container.addSubview(scaledContentView)
        scaledContentView.addSubview(backgroundContentView)
        glassSession.onStateChange = { [weak self] in self?.onGlassSessionChange?() }
        applyBackgroundAppearance()
    }

    // MARK: - HUD content

    private func configureStackView() {

        stackView.autoresizesSubviews = false
        backgroundContentView.autoresizesSubviews = false
        backgroundContentView.addSubview(stackView)
        backgroundContentView.addSubview(horizontalView)
        backgroundContentView.addSubview(collapsedFPSIndicator)
        collapsedFPSIndicator.imageScaling = .scaleProportionallyUpOrDown
    }

    // MARK: - Metric Creation

    private func createMetricRows() {

        for (index, metrics) in verticalMetricGroups.enumerated() {
            if index > 0 {
                let divider = HUDSampleDividerView()
                groupDividers[index] = divider
                stackView.addSubview(divider)
            }
            for metric in metrics {
                let row = createRow(for: metric)
                metricRows[metric] = row
                row.translatesAutoresizingMaskIntoConstraints = true
                stackView.addSubview(row)
                if metric == .aneTotal { createPackageRow() }
            }
        }
        // The halo and fade can extend outside the memory row.
        ramPressureHistory.translatesAutoresizingMaskIntoConstraints = true
        backgroundContentView.addSubview(ramPressureHistory)
    }

    private func updateDividers() -> (count: Int, height: CGFloat) {
        var lastVisibleGroup: Int?
        var visibleDividerCount = 0
        var totalDividerHeight: CGFloat = 0

        for (index, metrics) in verticalMetricGroups.enumerated() {
            let groupIsVisible = metrics.contains { enabledMetrics.contains($0) }
                || (metrics.contains(.aneTotal) && showsPackagePower)
            let showDivider = groupIsVisible && lastVisibleGroup != nil
            let height = HUDStyle.dividerHeight(afterFPS: lastVisibleGroup == 0)
            if let divider = groupDividers[index] {
                divider.isHidden = !showDivider
                divider.setFrameSize(NSSize(width: divider.frame.width, height: height))
                (divider as? HUDSampleDividerView)?.applyStyle(
                    background: textBackground,
                    afterFPS: lastVisibleGroup == 0,
                    connectsToHistory: lastVisibleGroup == 0 && enabledMetrics.contains(.fpsGraph))
                if showDivider {
                    visibleDividerCount += 1
                    totalDividerHeight += height
                }
            }
            if groupIsVisible { lastVisibleGroup = index }
        }

        // Only the last category needs its graph's own bottom edge. Earlier
        // graphs meet a section divider, so avoid stacking two faint lines.
        fpsGraphView.showsBaseline = lastVisibleGroup == 0
        ramPressureHistory.showsBaseline = lastVisibleGroup.map {
            verticalMetricGroups[$0].contains(.ramTotal)
        } ?? false

        return (visibleDividerCount, totalDividerHeight)
    }

    private func createRow(
        for metric: HUDMetric
    ) -> NSView {
        switch metric {
        case .process: return processView
        case .cpuCores: return cpuCoreView
        case .gpuCores: return gpuCoreView
        case .fpsGraph:
            fpsGraphView.configure(measure: fpsMeasure, hitchMarks: fpsHitchMarks)
            return fpsGraphView
        case .storage: return storageView
        case .fans: return fanView
        case .misc: return miscView
        case .battery: return batteryIndicator
        default: break
        }

        let row = HUDMetricRowView()

        row.autoresizesSubviews = false

        // MARK: Title

        let titleLabel =
            HUDReadingLabel(
                labelWithString:
                    metric == .fps ? fpsMeasure.caption : metric.hudTitle(for: alignment)
            )

        titleLabel.font =
            HUDStyle.titleFont(
                for: metric
            )

        titleLabel.textColor =
            HUDStyle.primaryTitleColor(for: metric, background: textBackground)

        titleLabel.wantsLayer = true

        titleLabel.alignment =
            .left

        // MARK: Value

        let valueLabel =
            HUDReadingLabel(
                labelWithString:
                    metric.placeholderValue
            )

        valueLabel.font =
            HUDStyle.valueFont(
                for: metric
            )

        valueLabel.textColor =
            HUDStyle.valueColor(background: textBackground)

        valueLabel.wantsLayer = true

        valueLabel.alignment =
            .right

        // MARK: Add Views

        row.addSubview(
            titleLabel
        )

        row.addSubview(
            valueLabel
        )

        row.layoutReadings = { [weak self, weak row] in
            guard let self, let row else { return }
            let headingHeight = metric == .ramTotal ? memoryHeadingHeight() : row.bounds.height
            var captionHeight = headingHeight
            var captionTop = row.bounds.height
            var valueTop = captionTop
            var valueHeight = headingHeight
            if metric == .fps {
                captionHeight = titleLabel.intrinsicContentSize.height
                valueHeight = valueLabel.intrinsicContentSize.height
                valueTop = (row.bounds.height + valueHeight) / 2
                // Align visible cap tops even when the number is independently enlarged.
                captionTop = valueTop - (valueLabel.firstBaselineOffsetFromTop - valueLabel.font!.capHeight)
                    + (titleLabel.firstBaselineOffsetFromTop - titleLabel.font!.capHeight)
            }
            row.place(titleLabel, top: captionTop, height: captionHeight)
            row.place(valueLabel, top: valueTop, height: valueHeight, trailing: readingColumnRight)
            if let field = temperatureLabels[metric], let edge = temperatureTrailing[metric] {
                row.place(field, top: valueTop, trailing: edge)
            }
            if let field = powerLabels[metric], let edge = powerTrailing[metric] {
                row.place(field, top: valueTop, trailing: edge)
            }
        }

        if metric == .gpuTotal || metric == .cpuTotal {
            let temperature = HUDReadingLabel(labelWithString: "")
            temperature.font = temperatureFont(for: metric)
            temperature.textColor = HUDStyle.readingColor(background: textBackground)
            temperature.alignment = .right
            temperature.isHidden = true
            row.addSubview(temperature)
            temperatureLabels[metric] = temperature
        }

        if [.gpuTotal, .cpuTotal, .aneTotal].contains(metric) {
            let power = HUDReadingLabel(labelWithString: "")
            power.font = powerFont(for: metric)
            power.textColor = HUDStyle.readingColor(background: textBackground)
            power.alignment = .right
            power.isHidden = true
            row.addSubview(power)
            powerLabels[metric] = power
        }

        if metric == .ramTotal {
            let detailLabel = HUDReadingLabel(labelWithString: "")
            detailLabel.font = HUDStyle.ramDetailFont()
            detailLabel.textColor = HUDStyle.readingColor(background: textBackground)
            detailLabel.alignment = .right
            row.addSubview(detailLabel)
            let physicalLabel = HUDReadingLabel(labelWithString: "Physical")
            physicalLabel.font = HUDStyle.smallLabelFont()
            physicalLabel.textColor = HUDStyle.TextStyle.label.color(background: textBackground)
            physicalLabel.setAccessibilityLabel("Physical memory")
            row.addSubview(physicalLabel)
            ramDetailLabels[metric] = detailLabel
            ramDetailTitleLabels[metric] = physicalLabel

            let swapTitle = HUDReadingLabel(labelWithString: "Swap")
            swapTitle.setAccessibilityLabel("Swap memory")
            let swapValue = HUDReadingLabel(labelWithString: "")
            let pressureValue = HUDReadingLabel(labelWithString: "")
            pressureValue.setAccessibilityLabel("Memory pressure")
            let pressureTitle = HUDReadingLabel(labelWithString: "Pressure")
            swapValue.alignment = .right
            pressureValue.alignment = .right
            for label in [swapTitle, swapValue, pressureValue, pressureTitle] {
                label.font = detailLabel.font
                label.textColor = detailLabel.textColor
                label.translatesAutoresizingMaskIntoConstraints = true
                row.addSubview(label)
            }
            for caption in [swapTitle, pressureTitle] {
                caption.font = HUDStyle.smallLabelFont()
                caption.textColor = HUDStyle.TextStyle.label.color(background: textBackground)
            }
            for reading in [swapValue, detailLabel] {
                reading.allowsDefaultTighteningForTruncation = true
            }
            // Capture the intrinsic caption sizes before the row enters a transformed window.
            let swapSize = swapTitle.intrinsicContentSize
            let physicalSize = physicalLabel.intrinsicContentSize
            row.layoutDetails = { [weak self, weak row] in
                guard let self, let row else { return }
                // Work in the same fixed reading columns as the fan RPM and pressure plot.
                let titleInset = titleLabel.alignmentRectInsets.left
                let trailing = readingColumnRight - valueLabel.alignmentRectInsets.right
                let physicalX = trailing - memoryClusterWidth
                let readingWidth = memoryClusterWidth - physicalSize.width
                let detailTop = row.bounds.height - memoryHeadingHeight()
                let height = HUDStyle.ramDetailHeight()
                let pressureTop = detailTop - (showsRAMDetails ? height : 0)
                row.place(pressureTitle, top: pressureTop)
                row.place(pressureValue, top: pressureTop, height: height, trailing: readingColumnRight)
                let meterSize = ramPressureMeter.intrinsicContentSize
                ramPressureMeter.frame = NSRect(x: trailing - meterSize.width,
                    y: pressureTitle.frame.midY - meterSize.height / 2, width: meterSize.width, height: meterSize.height)
                for (caption, reading, x, captionSize) in [(swapTitle, swapValue, titleInset, swapSize),
                                                          (physicalLabel, detailLabel, physicalX, physicalSize)] {
                    let captionRect = NSRect(x: x, y: detailTop - captionSize.height,
                                             width: captionSize.width, height: captionSize.height)
                    caption.frame = caption.frame(forAlignmentRect: captionRect)
                    reading.frame = reading.frame(forAlignmentRect: NSRect(x: captionRect.maxX, y: detailTop - height,
                                                                           width: readingWidth, height: height))
                }
            }
            ramSwapTitleLabel = swapTitle
            ramSwapValueLabel = swapValue
            ramPressureValueLabel = pressureValue
            ramPressureTitleLabel = pressureTitle
            ramPressureMeter.translatesAutoresizingMaskIntoConstraints = true
            row.addSubview(ramPressureMeter)
        }

        // MARK: Save References

        titleLabels[metric] =
            titleLabel

        valueLabels[metric] =
            valueLabel

        return row
    }

    // Keep the combined reading with its components, separated from RAM below.
    private func createPackageRow() {
        let row = HUDMetricRowView()
        row.autoresizesSubviews = false
        row.isHidden = true
        let title = HUDReadingLabel(labelWithString: "SOC")
        let value = HUDReadingLabel(labelWithString: "")
        value.alignment = .right
        for label in [title, value] {
            label.font = HUDStyle.ramDetailFont()
            label.textColor = HUDStyle.readingColor(background: textBackground)
            row.addSubview(label)
        }
        stackView.addSubview(row)
        row.layoutReadings = { [weak self, weak row] in
            guard let self, let row else { return }
            row.place(title, top: row.bounds.height, height: row.bounds.height)
            row.place(value, top: row.bounds.height, trailing: powerTrailing[.cpuTotal] ?? readingColumnRight)
        }
        packageRow = row
        packageTitleLabel = title
        packageValueLabel = value
    }

    // MARK: - HUD Visibility

    func show() {

        updateLayout()
        restorePosition()
        updateVisibility()
    }

    func setHUDEnabled(
        _ enabled: Bool
    ) {

        hudEnabled =
            enabled
        fpsAvailability.advance(to: ProcessInfo.processInfo.systemUptime)
        if !enabled {
            stopModeAnimation()
            autoHidePresentation.transition(visible: fpsAvailability.expanded, animated: false)
            fpsAnimationTimer?.invalidate()
            fpsAnimationTimer = nil
            fpsProgress = dynamicFPSActive && !fpsAvailability.expanded ? 0 : 1
            applyHUDPresentation()
        }

        if enabled && autoHidePresentation.enabled {
            autoHidePresentation.transition(visible: fpsAvailability.expanded, animated: false)
        }
        if enabled { updateLayout() }
        updateVisibility()
    }

    func setAutoHideMode(_ mode: HUDAutoHideMode) {
        guard autoHideMode != mode else { return }
        transitionToAutoHideMode(mode)
    }

    private func transitionToAutoHideMode(_ mode: HUDAutoHideMode) {
        let startSize = presentedHUDSize
        var startFPS = presentedFPSProgress
        let fullExtent = alignment == .horizontal ? expandedHUDSize.width : expandedHUDSize.height
        let startExtent = alignment == .horizontal ? startSize.width : startSize.height
        fpsAvailability.advance(to: ProcessInfo.processInfo.systemUptime)
        let available = fpsAvailability.expanded
        let targetFPS: CGFloat = mode == .fps && !available
            && !enabledMetrics.isDisjoint(with: [.fps, .fpsGraph]) ? 0 : 1
        // There is no visible FPS content to carry out of a fully hidden HUD.
        // Reveal the destination's rows (or arrow) from the very first frame.
        if startExtent == 0 { startFPS = targetFPS }
        let endFPS = mode == .all && !available ? startFPS : targetFPS
        stopModeAnimation()
        modeTransition = ModeTransition(size: startSize, fpsProgress: startFPS, available: available)
        autoHideMode = mode
        fpsAnimationTimer?.invalidate()
        fpsAnimationTimer = nil
        fpsAnimationTarget = nil
        autoHidePresentation.stop()
        // Settle the destination's availability state behind the temporary
        // presentation, so callbacks never expose an intermediate full HUD.
        autoHidePresentation.setEnabled(mode == .all, visible: available, animated: false)
        autoHidePresentation.transition(visible: available, animated: false)
        updateLayout(keepingModeTransition: true)
        let endSize = settledHUDSize
        let endExtent = alignment == .horizontal ? endSize.width : endSize.height
        let distance = max(abs(endFPS - startFPS), abs(endExtent - startExtent) / max(1, fullExtent))
        guard shouldAnimateAutoHide, distance > 0 else {
            stopModeAnimation()
            applyHUDPresentation()
            updateVisibility()
            return
        }
        updateVisibility()
        let started = ProcessInfo.processInfo.systemUptime
        let duration = HUDFPSAvailability.animationDuration * Double(distance)
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let t = min(1, (ProcessInfo.processInfo.systemUptime - started) / duration)
                let eased = CGFloat(t * t * (3 - 2 * t))
                let scale = self.panel.backingScaleFactor * self.windowScale
                self.modeTransition?.size = NSSize(
                    width: ((startSize.width + (endSize.width - startSize.width) * eased) * scale).rounded() / scale,
                    height: ((startSize.height + (endSize.height - startSize.height) * eased) * scale).rounded() / scale)
                self.modeTransition?.fpsProgress = startFPS + (endFPS - startFPS) * eased
                if t >= 1 { self.stopModeAnimation() }
                self.applyHUDPresentation()
            }
        }
        modeAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopModeAnimation() {
        modeAnimationTimer?.invalidate()
        modeAnimationTimer = nil
        modeTransition = nil
    }

    func setAutoHideAnimated(_ animated: Bool) {
        guard autoHideAnimated != animated else { return }
        autoHideAnimated = animated
        // Enabling animation affects the next transition. Disabling it finishes
        // an in-flight transition immediately without changing the hide mode.
        guard !animated else { return }
        fpsAvailability.advance(to: ProcessInfo.processInfo.systemUptime)
        if modeTransition != nil {
            transitionToAutoHideMode(autoHideMode)
        } else if autoHidePresentation.enabled {
            autoHidePresentation.transition(visible: fpsAvailability.expanded, animated: false)
        } else {
            animateFPS(to: fpsAvailability.expanded ? 1 : 0)
        }
    }

    private func applyAutoHidePresentation() {
        let hidden = isAutomaticallyHidden
        if lastAutoHideHidden != hidden {
            lastAutoHideHidden = hidden
            updateVisibility()
            onAutoHideVisibilityChange?()
        }
    }

    private func animateAutoHide(visible: Bool) {
        autoHidePresentation.transition(visible: visible, animated: shouldAnimateAutoHide)
    }

    func setAlignment(_ alignment: HUDAlignment) {
        self.alignment = alignment
        titleLabels[.ram]?.stringValue = HUDMetric.ram.hudTitle(for: alignment)
        if alignment == .horizontal { ramPressureHistory.clear() }
        enabledMetrics = HUDPreferences.visibleMetrics
        if visibleDrives.isEmpty { enabledMetrics.remove(.storage) }
        else { enabledMetrics.insert(.storage) }
        for (metric, row) in metricRows { row.isHidden = !enabledMetrics.contains(metric) }
        updateLayout()
        restorePosition()
        updateVisibility()
    }

    // MARK: - Metric Visibility

    func setStorageOptions(_ options: HUDStorageOptions) {
        storageOptions = options
        setMetricEnabled(.storage, enabled: options.enabled)
    }

    func updateStorage(_ drives: [StorageDrive]) {
        let oldCount = visibleDrives.count
        storageDrives = drives
        let visible = visibleDrives
        if oldCount != visible.count || enabledMetrics.contains(.storage) != !visible.isEmpty {
            setMetricEnabled(.storage, enabled: !visible.isEmpty)
        } else if hudEnabled && !isAutomaticallyHidden && !visible.isEmpty {
            if alignment == .horizontal { refreshHorizontalReadings() }
            else { storageView.configure(visible, options: storageOptions, background: textBackground) }
        }
    }

    func setFanOptions(_ options: HUDFanOptions) {
        fanOptions = options
        setMetricEnabled(.fans, enabled: options.enabled && alignment.allows(.fans))
    }

    func updateFans(_ sample: FanSample) {
        let previousHeight = fanView.height()
        fanSample = sample
        guard hudEnabled, !isAutomaticallyHidden else { return }
        fanView.update(sample: sample, options: fanOptions, background: textBackground)
        // RPM changes only redraw the existing view; keep window geometry stable.
        if alignment == .horizontal { refreshHorizontalReadings() }
        else if fanView.height() != previousHeight { updateLayout() }
    }

    func setPackagePowerOptions(_ options: HUDPackagePowerOptions) {
        packageOptions = options
        updateLayout()
        updateVisibility()
    }

    func setResourceOptions(_ options: HUDResourceOptions, for group: HUDResourceGroup) {
        let options = options.systemOnly
        if group == .cpu { cpuResourceOptions = options }
        if group == .gpu { gpuResourceOptions = options }
        if group.supportsTemperature { temperatureWarnings[group.totalMetric] = options.heatWarning }
        highlightedReadings[group.totalMetric] = options.highlighted
        if group == .ram {
            showsRAMDetails = options.showsDetails
            showsRAMPressure = options.showsPressure
            memoryPressureMode = options.pressureMode
            ramPressureValueLabel?.textColor = ramPressureColor
            if !showsRAMPressure || !memoryPressureMode.isHistory { ramPressureHistory.clear() }
            if options.usageVisible { hiddenUtilizationMetrics.remove(.ramTotal) }
            else { hiddenUtilizationMetrics.insert(.ramTotal) }
            valueLabels[.ramTotal]?.isHidden = !options.usageVisible
        }
        enabledMetrics.remove(group.totalMetric)
        enabledMetrics.formUnion(options.visibleMetrics(for: group))
        if group == .cpu {
            let visible = options.enabled && cpuCoreOptions.enabled
            if visible { enabledMetrics.formUnion([.cpuTotal, .cpuCores]) }
            else { enabledMetrics.remove(.cpuCores) }
            cpuCoreView.isHidden = !visible
        }
        if group == .gpu {
            let visible = options.enabled && gpuCoreOptions.enabled
            if visible { enabledMetrics.formUnion([.gpuTotal, .gpuCores]) }
            else { enabledMetrics.remove(.gpuCores) }
            gpuCoreView.isHidden = !visible
        }
        metricRows[group.totalMetric]?.isHidden = !enabledMetrics.contains(group.totalMetric)
        if group.supportsPower {
            let showPower = options.enabled && options.power
            if showPower {
                powerMetrics.insert(group.totalMetric)
            }
            else { powerMetrics.remove(group.totalMetric); powerLabels[group.totalMetric]?.stringValue = "" }
            powerLabels[group.totalMetric]?.isHidden = !showPower
            let showTemperature = group.supportsTemperature && options.enabled && options.temperature
            if showTemperature { temperatureMetrics.insert(group.totalMetric) }
            else {
                temperatureMetrics.remove(group.totalMetric)
                temperatures.removeValue(forKey: group.totalMetric)
                temperatureLabels[group.totalMetric]?.stringValue = ""
            }
            temperatureLabels[group.totalMetric]?.isHidden = !showTemperature
            if group.supportsTotalUse && options.totalUse { hiddenUtilizationMetrics.remove(group.totalMetric) }
            else { hiddenUtilizationMetrics.insert(group.totalMetric) }
            valueLabels[group.totalMetric]?.isHidden = !group.supportsTotalUse || !options.totalUse
            updateReadingAppearance()
        }
        updateLayout()
        updateVisibility()
    }

    func updateTemperatures(_ sample: TemperatureSample) {
        defer { refreshHorizontalReadings() }
        for (metric, value) in [(HUDMetric.cpuTotal, sample.cpu), (.gpuTotal, sample.gpu)] {
            guard temperatureMetrics.contains(metric) else { continue }
            if let value, value.isFinite, value > 0, value < 150 {
                temperatures[metric] = value
                temperatureLabels[metric]?.stringValue = "\(Int(value.rounded()))°C"
            } else {
                temperatures.removeValue(forKey: metric)
                temperatureLabels[metric]?.stringValue = ""
            }
            temperatureLabels[metric]?.textColor = readingColor(for: metric, kind: .temperature)
        }
    }

    func updatePower(_ sample: PowerSample) {
        updateCPUFrequencies(sample.cpuFrequencies)
        gpuFrequency = sample.gpuFrequency
        gpuCoreView.updateGPU(frequency: gpuFrequency)
        defer { refreshHorizontalReadings() }
        func text(_ value: Double?) -> String {
            guard let value, value.isFinite, value >= 0 else { return "" }
            return String(format: "%.1f W", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        for (metric, value) in [(HUDMetric.cpuTotal, sample.cpu), (.gpuTotal, sample.gpu), (.aneTotal, sample.ane)] {
            powerLabels[metric]?.stringValue = powerMetrics.contains(metric) ? text(value) : ""
        }
        packageValueLabel?.stringValue = showsPackagePower ? text(sample.package) : ""
    }

    func setFPSOptions(_ options: HUDFPSOptions) {
        let visible = options.visibleMetrics(alignment: alignment)
        let sizeChanged = fpsValueSize != options.valueSize
        fpsValueHighlighted = options.valueHighlighted
        fpsValueSize = options.valueSize
        fpsMeasure = options.measure
        fpsHitchMarks = options.hitchMarks
        titleLabels[.fps]?.stringValue = fpsMeasure.caption
        valueLabels[.fps]?.stringValue = fpsReading
        fpsGraphView.configure(measure: fpsMeasure, hitchMarks: fpsHitchMarks)
        if enabledMetrics.intersection([.fps, .fpsGraph]) == visible && !sizeChanged {
            // Preserve FPS history when only its presentation changes.
            updateReadingAppearance()
            refreshHorizontalReadings()
            return
        }
        enabledMetrics.subtract([.fps, .fpsGraph])
        enabledMetrics.formUnion(visible)
        for metric in [HUDMetric.fps, .fpsGraph] {
            metricRows[metric]?.isHidden = !visible.contains(metric)
        }
        if !visible.contains(.fpsGraph) { fpsGraphView.reset() }
        // Apply the pair together, avoiding an intermediate window resize.
        updateLayout()
        updateVisibility()
    }

    func setMetricEnabled(_ metric: HUDMetric, enabled: Bool) {
        guard let row = metricRows[metric] else { return }
        let enabled = enabled && (metric != .storage || !visibleDrives.isEmpty)
        if enabled { enabledMetrics.insert(metric) }
        else { enabledMetrics.remove(metric) }
        row.isHidden = !enabled

        if metric == .fpsGraph && !enabled { fpsGraphView.reset() }

        updateLayout()
        updateVisibility()
    }

    private func updateVisibility() {

        if hudEnabled && hasVisibleContent && !isAutomaticallyHidden {

            restorePosition()

            panel.orderFrontRegardless()
            panel.startModifierTracking()
            glassSession.setVisible(true)

        } else {

            panel.stopModifierTracking()
            glassSession.setVisible(false)
            panel.orderOut(nil)
        }
    }

    func setDragModifier(_ modifier: HUDDragModifier) {
        panel.dragModifier = modifier
    }

    // MARK: - HUD Scale

    func setHUDScale(_ scale: HUDScale) {
        guard hudScale != scale else { return }
        hudScale = scale
        applyWindowScale()
        restorePosition()
    }

    // MARK: - Background

    func setBackground(_ background: HUDBackground) {
        backgroundSelection = background
        hudBackground = background.resolved(isDark: Self.systemIsDark)
        applyBackgroundAppearance()
        updateMetricColors()
        updateLayout()
        restorePosition()
    }

    private func applyBackgroundAppearance() {
        backgroundView.isDark = hudBackground == .dark
        panel.hasShadow = false
    }

    var onGlassSessionChange: (() -> Void)?
    var glassSessionFailure: String? { glassSession.failure }

    func retryGlassSession() { glassSession.retry() }

    func shutdown() {
        stopModeAnimation()
        autoHidePresentation.stop()
        windowGeometryTask?.cancel()
        windowGeometryTask = nil
        fpsAvailabilityTask?.cancel()
        fpsAvailabilityTask = nil
        fpsAnimationTimer?.invalidate()
        fpsAnimationTimer = nil
        appearanceObservation?.invalidate()
        appearanceObservation = nil
        fpsGraphView.reset()
        panel.stopModifierTracking()
        glassSession.shutdown()
        panel.orderOut(nil)
    }

    // MARK: - Text Appearance

    private func readingFont(for metric: HUDMetric, kind: HUDReadingKind) -> NSFont {
        metric == .fps ? HUDStyle.fpsValueFont(highlighted: fpsValueHighlighted, size: fpsValueSize)
            : HUDStyle.readingFont(highlighted: highlightedReadings[metric, default: []].contains(kind))
    }

    private func readingColor(for metric: HUDMetric, kind: HUDReadingKind) -> NSColor {
        if kind == .temperature, let warning = temperatureWarnings[metric] {
            return HUDStyle.temperatureColor(temperatures[metric], warning: warning, background: textBackground)
        }
        if metric == .fps {
            return (fpsValueHighlighted ? HUDStyle.TextStyle.emphasizedReading : .reading).color(background: textBackground)
        }
        return HUDStyle.readingColor(background: textBackground)
    }

    private func temperatureFont(for metric: HUDMetric) -> NSFont {
        readingFont(for: metric, kind: .temperature)
    }

    private func powerFont(for metric: HUDMetric) -> NSFont {
        readingFont(for: metric, kind: .power)
    }

    private var ramDetailsFont: NSFont {
        readingFont(for: .ramTotal, kind: .details)
    }

    private var ramPressureColor: NSColor {
        HUDStyle.pressureColor(for: memoryPressureMode == .colorText ? ramPressureMeter.currentLevel : nil,
                               background: textBackground)
    }

    private var ramPressureFont: NSFont {
        readingFont(for: .ramTotal, kind: .pressure)
    }

    private func updateReadingAppearance() {
        processView.configure(options: processOptions, background: textBackground)
        cpuCoreView.configure(options: cpuCoreOptions, background: textBackground,
            powerTrailingInset: HUDStyle.verticalPowerTrailingInset(temperature: temperatureFont(for: .cpuTotal), usage: readingFont(for: .cpuTotal, kind: .totalUse)))
        let matchCPUFrequency = alignment == .vertical && cpuResourceOptions.enabled
            && cpuCoreOptions.enabled && cpuCoreOptions.mode.showsValue
        gpuCoreView.configure(options: gpuCoreOptions, background: textBackground,
            matchingFrequencyColumn: matchCPUFrequency ? cpuCoreView.frequencyColumn : nil)
        miscView.configure(options: miscOptions, background: textBackground)
        ramPressureMeter.configure(mode: memoryPressureMode, background: textBackground)
        memoryClusterWidth = fullCPUReadingWidth
        ramPressureHistory.configure(mode: memoryPressureMode, background: textBackground,
                                     width: pressureHistoryWidth)
        let detailValues = Array(ramDetailLabels.values)
            + [ramSwapValueLabel].compactMap { $0 }
        for label in detailValues { label.font = ramDetailsFont }
        ramPressureValueLabel?.font = ramPressureFont
        let detailTitles = Array(ramDetailTitleLabels.values)
            + [ramSwapTitleLabel, ramPressureTitleLabel].compactMap { $0 }
        for label in detailTitles { label.font = HUDStyle.smallLabelFont() }
        let clusterWidth = memoryClusterWidth
        if let swapTitle = ramSwapTitleLabel, let physicalTitle = ramDetailTitleLabels[.ramTotal] {
            // Both detail values have the width remaining after the Physical caption.
            // Use the same column even when the memory row is hidden or detached.
            let valueWidth = clusterWidth - physicalTitle.intrinsicContentSize.width
            let swapEnd = swapTitle.alignmentRectInsets.left + swapTitle.intrinsicContentSize.width + valueWidth
            fanView.setMemoryColumns(barWidth: pressureHistoryWidth - 4,
                                     swapValueTrailing: swapEnd)
        }

        for (metric, label) in temperatureLabels {
            label.font = temperatureFont(for: metric)
            label.textColor = readingColor(for: metric, kind: .temperature)
        }
        for (metric, label) in powerLabels {
            label.font = powerFont(for: metric)
            label.textColor = readingColor(for: metric, kind: .power)
        }
        for (metric, label) in valueLabels {
            label.font = readingFont(for: metric, kind: .totalUse)
            label.textColor = readingColor(for: metric, kind: .totalUse)
        }

        packageTitleLabel?.font = HUDStyle.titleFont(for: .gpuTotal)
        packageTitleLabel?.textColor = HUDStyle.primaryTitleColor(for: .gpuTotal, background: textBackground)
        packageValueLabel?.font = HUDStyle.readingFont(highlighted: packageOptions.highlighted)
        packageValueLabel?.textColor = HUDStyle.readingColor(background: textBackground)
    }

    private func updateMetricColors() {
        collapsedFPSIndicator.contentTintColor = HUDStyle.TextStyle.label.color(background: textBackground)
        fanView.update(sample: fanSample, options: fanOptions, background: textBackground)
        defer { updateReadingAppearance(); refreshHorizontalReadings() }
        fpsGraphView.applyStyle(background: textBackground)
        batteryIndicator.applyStyle(background: textBackground)
        ramSwapTitleLabel?.textColor = HUDStyle.TextStyle.label.color(background: textBackground)
        ramPressureTitleLabel?.textColor = HUDStyle.TextStyle.label.color(background: textBackground)
        ramSwapValueLabel?.textColor = HUDStyle.readingColor(background: textBackground)
        ramPressureValueLabel?.textColor = ramPressureColor

        for metric in HUDMetric.allCases {

            ramDetailLabels[metric]?.textColor = HUDStyle.readingColor(background: textBackground)
            ramDetailTitleLabels[metric]?.textColor = HUDStyle.TextStyle.label.color(background: textBackground)

            // Neutral text adapts to the selected background.
            titleLabels[metric]?
                .textColor =
                    HUDStyle.primaryTitleColor(for: metric, background: textBackground)

        }
    }

    // MARK: - Layout

    private var pressureHistoryBottomExtension: CGFloat {
        pressureHistoryBaseBottomExtension() + pressureHistoryExtraHeight()
    }

    private func pressureHistoryBaseBottomExtension() -> CGFloat {
        HUDStyle.pressureHistoryBottomExtension(expanded: false)
    }

    private func pressureHistoryExtraHeight() -> CGFloat {
        guard alignment == .vertical, showsRAMPressure, memoryPressureMode.isHistory else { return 0 }
        return HUDStyle.pressureHistoryBottomExtension()
            - HUDStyle.pressureHistoryBottomExtension(expanded: false)
    }

    private var fullCPUReadingWidth: CGFloat {
        HUDStyle.verticalReadingClusterWidth(power: powerFont(for: .cpuTotal),
            temperature: temperatureFont(for: .cpuTotal), usage: readingFont(for: .cpuTotal, kind: .totalUse))
    }

    private var pressureHistoryWidth: CGFloat {
        // Keep the watt-aligned left guide while extending the right guide to
        // the divider edge, with the halo safely inside the HUD's outer padding.
        let readingInset = valueLabels[.ramTotal]?.alignmentRectInsets.right ?? 0
        return memoryClusterWidth + readingInset + 4
    }

    private func updateReadingPositions() {
        guard readingColumnRight > 0 else { return }
        let metrics: [HUDMetric] = [.gpuTotal, .cpuTotal, .aneTotal]
        for metric in metrics {
            let hasTemperature = enabledMetrics.contains(metric) && temperatureMetrics.contains(metric)
            let hasUsage = enabledMetrics.contains(metric) && !hiddenUtilizationMetrics.contains(metric)
            // Keep a compact, stable cluster anchored at the right edge.
            // Reference widths prevent changing readings from shifting columns.
            let temperature = NSTextField(labelWithString: "149°C")
            temperature.font = temperatureFont(for: metric)
            let usage = NSTextField(labelWithString: "100%")
            usage.font = readingFont(for: metric, kind: .totalUse)
            let gap = HUDStyle.metricColumnSpacing
            var trailing = readingColumnRight
            if hasUsage { trailing -= usage.intrinsicContentSize.width + gap }
            temperatureTrailing[metric] = trailing
            if hasTemperature { trailing -= temperature.intrinsicContentSize.width + gap }
            powerTrailing[metric] = trailing
        }

        powerTrailing[.aneTotal] = powerTrailing[.cpuTotal]

        // Prefer CPU so battery flow also lines up with ANE and SOC. When a
        // complete reference row is hidden, retain compact local battery columns.
        let reference = [HUDMetric.cpuTotal, .gpuTotal].first {
            enabledMetrics.contains($0) && temperatureMetrics.contains($0) && !hiddenUtilizationMetrics.contains($0)
        }
        let readingInset = valueLabels[.cpuTotal]?.alignmentRectInsets.right ?? 0
        batteryIndicator.alignVerticalReadings(
            powerTrailingInset: reference.flatMap { powerTrailing[$0] }.map { readingColumnRight - $0 + readingInset },
            temperatureTrailingInset: reference.flatMap { temperatureTrailing[$0] }.map { readingColumnRight - $0 + readingInset })
    }

    private func refreshHorizontalReadings(forceLayout: Bool = false) {
        guard alignment == .horizontal else { return }
        guard forceLayout || (hudEnabled && !isAutomaticallyHidden) else { return }
        var sections: [[HUDHorizontalView.Reading]] = []
        for metrics in metricGroups {
            var readings: [HUDHorizontalView.Reading] = []
            for metric in metrics {
                if (metric == .cpuCores || metric == .gpuCores), enabledMetrics.contains(metric) {
                    readings.append(contentsOf: (metric == .cpuCores ? cpuCoreView : gpuCoreView).horizontalReadings(background: textBackground))
                    continue
                }
                if metric == .storage, enabledMetrics.contains(.storage) {
                    horizontalView.storage.configure(visibleDrives, options: storageOptions, background: textBackground)
                    readings.append(.init(id: "storage", text: "", reference: "", font: HUDStyle.titleFont(for: .storage),
                        color: HUDStyle.primaryTitleColor(for: .storage, background: textBackground), help: nil, startsMetric: true, metric: .storage))
                    continue
                }
                if metric == .fans, enabledMetrics.contains(.fans) {
                    readings += HUDHorizontalView.fanReadings(sample: fanSample, options: fanOptions,
                        background: textBackground,
                        barWidth: pressureHistoryWidth - 4)
                    continue
                }
                // Insert Package at ANE's position even when ANE itself is hidden.
                defer {
                    if metric == .aneTotal && showsPackagePower {
                        for (role, field, reference) in [("title", packageTitleLabel, "SOC"), ("power", packageValueLabel, "999.9 W")] {
                            if let field, let font = field.font, let color = field.textColor {
                                readings.append(.init(id: "package.\(role)", text: field.stringValue, reference: reference,
                                    font: font, color: color, help: field.toolTip, startsMetric: role == "title"))
                            }
                        }
                    }
                }
                guard enabledMetrics.contains(metric), alignment.allows(metric), metric != .battery,
                      let title = titleLabels[metric] else { continue }
                func append(_ field: NSTextField?, role: String, reference: String, title: Bool = false) {
                    guard let field, let font = field.font, let color = field.textColor else { return }
                    readings.append(.init(id: "\(metric.rawValue).\(role)", text: field.stringValue,
                        reference: reference, font: font, color: color, help: field.toolTip, startsMetric: title,
                        metric: metric, leadingGap: metric == .fps && !title ? HUDStyle.horizontalFPSLabelGap(for: fpsValueSize) : nil,
                        sizingFont: metric == .fps && !title
                            ? HUDStyle.fpsValueFont(highlighted: true, size: fpsValueSize) : nil))
                }
                append(title, role: "title", reference: title.stringValue, title: true)
                if powerMetrics.contains(metric) { append(powerLabels[metric], role: "power", reference: HUDStyle.horizontalPowerReference) }
                if temperatureMetrics.contains(metric) { append(temperatureLabels[metric], role: "temperature", reference: HUDStyle.horizontalTemperatureReference) }
                if !hiddenUtilizationMetrics.contains(metric) {
                    let reference = metric == .fps ? fpsMeasure.valueWidthReference : HUDStyle.horizontalPercentageReference
                    append(valueLabels[metric], role: "value", reference: reference)
                }
                if showsRAMDetails && metric == .ramTotal {
                    readings += HUDHorizontalView.memoryDetails(swap: ramSwapValueLabel?.stringValue ?? "",
                        physical: ramDetailLabels[metric]?.stringValue ?? "", valueFont: ramDetailsFont, background: textBackground)
                }
                if metric == .ramTotal && showsRAMPressure {
                    let pressure = ramPressureValueLabel?.stringValue ?? ""
                    // Text reserves the widest word; meters are centred in a
                    // normal-width slot. Neither changes with pressure state.
                    readings.append(.init(id: "ram.pressure", text: pressure, reference: "warning",
                        font: ramPressureFont,
                        color: ramPressureColor,
                        help: "Memory pressure: \(pressure).", startsMetric: false, metric: metric,
                        sizingFont: HUDStyle.readingFont(highlighted: true),
                        pressureMode: memoryPressureMode.resolved(for: .horizontal)))
                }
            }
            if !readings.isEmpty { sections.append(readings) }
        }
        let size = horizontalView.configure(sections: sections, showsBattery: enabledMetrics.contains(.battery),
                                            background: textBackground, fpsValueSize: fpsValueSize)
        let horizontalPadding = HUDStyle.horizontalPadding
        let verticalPadding = HUDStyle.verticalPadding
        let total = pixelAlignedSize(NSSize(width: size.width + 2 * horizontalPadding,
                                            height: size.height + 2 * verticalPadding))
        // Core and fan stacks may draw into the strip's vertical padding. Keep all
        // reading coordinates relative to the usual centered content row.
        horizontalView.frame = NSRect(x: horizontalPadding, y: 0, width: size.width, height: total.height)
        horizontalView.bounds = NSRect(x: 0, y: -verticalPadding, width: size.width, height: total.height)
        if forceLayout || expandedHUDSize != total {
            resizeHUD(width: total.width, height: total.height)
        } else {
            // Sampling must not undo the presentation offset or resize the window.
            applyHUDPresentation()
        }
        horizontalView.alignReadingFrames(on: container, fpsHeightRounding: total.height - size.height - 2 * verticalPadding)
    }

    private func metricRowHeight(_ metric: HUDMetric) -> CGFloat {
        if metric == .fpsGraph && !enabledMetrics.contains(.fps) {
            return HUDStyle.rowHeight(for: .fpsGraph) + HUDStyle.rowHeight
        }
        if metric == .fps { return HUDStyle.fpsRowHeight(size: fpsValueSize) }
        if metric == .cpuCores { return cpuCoreView.height() }
        if metric == .gpuCores { return gpuCoreView.height() }
        if (metric == .cpuTotal && enabledMetrics.contains(.cpuCores)) ||
            (metric == .gpuTotal && enabledMetrics.contains(.gpuCores)) {
            return HUDStyle.headingToDetailSpacing(.regular)
        }
        if metric == .misc { return miscView.height() }
        if metric == .storage { return storageView.contentSize.height }
        if metric == .fans { return fanView.height() }
        if metric == .ramTotal {
            let detailLines = showsRAMDetails ? 1 : 0
            let pressureLines = showsRAMPressure ? 1 : 0
            let height = memoryHeadingHeight() + CGFloat(detailLines + pressureLines) * HUDStyle.ramDetailHeight()
                + pressureHistoryExtraHeight()
            return pixelAlignedSize(NSSize(width: 0, height: height)).height
        }
        return HUDStyle.rowHeight(for: metric)
    }

    private func memoryHeadingHeight() -> CGFloat {
        showsRAMDetails || showsRAMPressure ? HUDStyle.headingToDetailSpacing(.tight) : HUDStyle.rowHeight
    }

    private func updateRAMDetailsVisibility() {
        titleLabels[.ramTotal]?.stringValue = HUDMetric.ramTotal.hudTitle(for: alignment)
        metricRows[.ramTotal]?.needsLayout = true
        let labels = Array(ramDetailLabels.values) + Array(ramDetailTitleLabels.values)
            + [ramSwapTitleLabel, ramSwapValueLabel].compactMap { $0 }
        for label in labels { label.isHidden = !showsRAMDetails }
        ramPressureTitleLabel?.isHidden = !showsRAMPressure
        ramPressureValueLabel?.isHidden = !showsRAMPressure || memoryPressureMode.display != .text
        ramPressureMeter.isHidden = !showsRAMPressure || alignment != .vertical || memoryPressureMode.display != .meter
        ramPressureHistory.isHidden = !showsRAMPressure || alignment != .vertical || !memoryPressureMode.isHistory
    }

    private func updateLayout(keepingModeTransition: Bool = false) {
        if !keepingModeTransition { stopModeAnimation() }
        fpsAnimationTimer?.invalidate()
        fpsAnimationTimer = nil
        // Measure the unchanged expanded stack before applying its presentation crop.
        for metric in [HUDMetric.fps, .fpsGraph] { metricRows[metric]?.alphaValue = 1 }
        fpsGraphView.showsHeading = !enabledMetrics.contains(.fps)
        updateReadingAppearance()
        updateRAMDetailsVisibility()
        storageView.configure(visibleDrives, options: storageOptions, background: textBackground)
        fanView.update(sample: fanSample, options: fanOptions, background: textBackground)
        if !showsPackagePower {
            packageValueLabel?.stringValue = ""
        }
        stackView.isHidden = alignment == .horizontal
        horizontalView.isHidden = alignment != .horizontal
        if alignment == .horizontal {
            refreshHorizontalReadings(forceLayout: true)
            return
        }

        packageRow?.isHidden = !showsPackagePower
        packageTitleLabel?.isHidden = !showsPackagePower
        packageValueLabel?.isHidden = !showsPackagePower
        let packageHeight = showsPackagePower
            ? (enabledMetrics.isEmpty ? 0 : HUDStyle.rowSpacing) + packageRowHeight : 0

        let dividers = updateDividers()
        let dividerCount = CGFloat(dividers.count)
        // The graph includes its bottom gap so the fade ends close to the divider.
        let graphUsesDividerGap = enabledMetrics.contains(.fpsGraph) && dividerCount > 0
        let rowSpacing = HUDStyle.rowSpacing
        var compactHeadings = Set<HUDMetric>()
        for (heading, detail) in [(HUDMetric.gpuTotal, HUDMetric.gpuCores), (.cpuTotal, .cpuCores)] {
            if enabledMetrics.contains(heading) && enabledMetrics.contains(detail) { compactHeadings.insert(heading) }
        }
        let coreDetailGapsRemoved = CGFloat(compactHeadings.count) * rowSpacing

        let visibleCount =
            CGFloat(
                enabledMetrics.count
            )

        let rowHeight = enabledMetrics.reduce(CGFloat.zero) {
            $0 + metricRowHeight($1)
        } + packageHeight

        let spacingCount =
            max(
                visibleCount + dividerCount - 1,
                0
            )

        let spacingHeight =
            (spacingCount - (graphUsesDividerGap ? 1 : 0))
            * rowSpacing - coreDetailGapsRemoved

        let verticalPadding =
            HUDStyle.verticalPadding

        let totalHeight =
            verticalPadding
            + rowHeight
            + dividers.height
            + spacingHeight
            + verticalPadding

        // Measure the collapsed layout directly from its visible body, replacing
        // any FPS mode with one arrow row. Subtracting from an already rounded
        // expanded height can otherwise leave a different half-pixel remainder.
        let bodyMetrics = enabledMetrics.subtracting([.fps, .fpsGraph])
        let bodyHeight = bodyMetrics.reduce(CGFloat.zero) { $0 + metricRowHeight($1) }
        collapsedVerticalFPSHeight = pixelAlignedSize(NSSize(width: 0,
            height: 2 * verticalPadding + collapsedFPSHeaderHeight + bodyHeight
                + packageHeight + dividers.height
                + (CGFloat(bodyMetrics.count) + dividerCount) * rowSpacing - coreDetailGapsRemoved)).height

        // FPS Value alone retains its compact width. All other configurations use the full panel.
        let fpsOnly = enabledMetrics == [.fps] && !showsPackagePower
        let valueColumnRight = fpsOnly
            ? HUDStyle.compactFPSValueColumnRight(valueSize: fpsValueSize)
            : HUDStyle.verticalValueColumnRight()
        readingColumnRight = valueColumnRight
        updateReadingPositions()

        let width = max(
            fpsOnly ? 0 : HUDStyle.width,
            valueColumnRight + 2 * HUDStyle.horizontalPadding
        )

        let rowWidth = width - 2 * HUDStyle.horizontalPadding
        let stackHeight = totalHeight - 2 * verticalPadding
        stackView.frame = NSRect(x: HUDStyle.horizontalPadding, y: verticalPadding,
                                 width: rowWidth, height: stackHeight)
        // Every row is placed once in untransformed points. In particular, a
        // zoom cannot cause AppKit to round each fan, caption or gap independently.
        var top = stackHeight
        func place(_ view: NSView, height: CGFloat, gap: CGFloat? = nil) {
            top -= height
            view.frame = view.frame(forAlignmentRect: NSRect(x: 0, y: top, width: rowWidth, height: height))
            view.needsLayout = true
            top -= gap ?? rowSpacing
        }
        for (index, metrics) in verticalMetricGroups.enumerated() {
            if let divider = groupDividers[index], !divider.isHidden {
                place(divider, height: divider.frame.height)
            }
            for metric in metrics {
                if enabledMetrics.contains(metric), let row = metricRows[metric] {
                    place(row, height: metricRowHeight(metric),
                          gap: metric == .fpsGraph || compactHeadings.contains(metric) ? 0 : rowSpacing)
                }
                if metric == .aneTotal, showsPackagePower, let row = packageRow { place(row, height: packageRowHeight) }
            }
        }
        positionPressureGraph()
        resizeHUD(width: width, height: totalHeight)
    }

    private func positionPressureGraph() {
        guard alignment == .vertical, let row = metricRows[.ramTotal] else { return }
        let detailOffset = showsRAMDetails ? HUDStyle.ramDetailHeight() : 0
        let top = stackView.frame.minY + row.frame.maxY - memoryHeadingHeight() - detailOffset
        let height = HUDStyle.ramDetailHeight() + pressureHistoryBottomExtension
        let frame = NSRect(x: stackView.frame.maxX + 3.5 - pressureHistoryWidth, y: top - height,
                           width: pressureHistoryWidth, height: height)
        ramPressureHistory.frame = container.backingAlignedRect(frame, options: [.alignAllEdgesNearest])
    }

    private func pixelAlignedSize(_ size: NSSize) -> NSSize {
        let scale = panel.backingScaleFactor
        return NSSize(width: ceil(size.width * scale) / scale, height: ceil(size.height * scale) / scale)
    }

    private func resizeHUD(width proposedWidth: CGFloat, height proposedHeight: CGFloat) {
        resizingHUD = true
        defer { resizingHUD = false }
        // Match AppKit’s backing-pixel grid for stable text and native glass edges.
        expandedHUDSize = pixelAlignedSize(NSSize(width: proposedWidth, height: proposedHeight))
        layoutNativeSurface(size: expandedHUDSize, anchor: visibleTopLeft)
        container.layoutSubtreeIfNeeded()

        configureDynamicFPSPresentation()
    }

    private func scheduleWindowGeometryRefresh(displayChanged: Bool = false) {
        displayLayoutPending = displayLayoutPending || displayChanged
        windowGeometryTask?.cancel()
        windowGeometryTask = Task { [weak self] in
            // Exclusive fullscreen can restore an older window frame AFTER the
            // backing-scale notification. Reconcile once the event burst settles.
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard let self else { return }
            windowGeometryTask = nil
            let displayChanged = displayLayoutPending
            displayLayoutPending = false
            let expected = nativeWindowSize(for: windowSize(for: presentedHUDSize))
            // AppKit may round the borderless frame outward to whole points.
            let wrongSize = abs(panel.frame.width - expected.width) > 1
                || abs(panel.frame.height - expected.height) > 1
            guard displayChanged || wrongSize else { return }
            updateLayout()
            restorePosition()
        }
    }

    // MARK: - Dynamic FPS

    private func configureDynamicFPSPresentation() {
        fpsCollapseDistance = 0
        fpsPresentationAnchor = nil
        fpsAvailability.advance(to: ProcessInfo.processInfo.systemUptime)
        if usesFPSPresentation && alignment == .horizontal {
            fpsCollapseDistance = max(0, horizontalView.fpsSectionWidth - collapsedFPSHeaderHeight)
        } else if usesFPSPresentation {
            let remaining = enabledMetrics.subtracting([.fps, .fpsGraph])
            if remaining.isEmpty && !showsPackagePower {
                fpsCollapseDistance = max(0, expandedHUDSize.height - collapsedFPSHeaderHeight
                    - 2 * HUDStyle.verticalPadding)
            } else {
                // Keep the existing section divider beneath the rolled-up indicator.
                let firstGroup = verticalMetricGroups.indices.dropFirst().first { index in
                    verticalMetricGroups[index].contains { remaining.contains($0) }
                        || (verticalMetricGroups[index].contains(.aneTotal) && showsPackagePower)
                }
                let divider = firstGroup.flatMap { groupDividers[$0] }
                let firstBody = stackView.subviews.first { view in
                    !view.isHidden && view !== metricRows[.fps] && view !== metricRows[.fpsGraph]
                        && !groupDividers.values.contains(where: { $0 === view })
                }
                if let first = divider ?? firstBody, let host = stackView.superview {
                    fpsPresentationAnchor = first
                    let rect = first.convert(first.bounds, to: host)
                    fpsCollapseDistance = max(0, host.bounds.maxY - rect.maxY - HUDStyle.verticalPadding
                        - collapsedFPSHeaderHeight - HUDStyle.rowSpacing)
                }
            }
        }
        fpsProgress = dynamicFPSActive && !fpsAvailability.expanded ? 0 : 1
        applyHUDPresentation()
    }

    private var presentedHUDSize: NSSize {
        modeTransition?.size ?? settledHUDSize
    }

    private var settledHUDSize: NSSize {
        let progress = dynamicFPSActive ? fpsProgress : 1
        let horizontal = alignment == .horizontal
        let reduction = autoHidePresentation.enabled
            ? (horizontal ? expandedHUDSize.width : expandedHUDSize.height) * (1 - autoHidePresentation.progress)
            : (horizontal ? fpsCollapseDistance
                : usesFPSPresentation ? max(0, expandedHUDSize.height - collapsedVerticalFPSHeight) : 0) * (1 - progress)
        let scale = panel.backingScaleFactor * windowScale
        return NSSize(
            width: max(0, (expandedHUDSize.width - (horizontal ? reduction : 0)) * scale).rounded() / scale,
            height: max(0, (expandedHUDSize.height - (horizontal ? 0 : reduction)) * scale).rounded() / scale)
    }

    private func applyHUDPresentation() {
        let progress = presentedFPSProgress
        let horizontal = alignment == .horizontal
        let wholeHUD = autoHidePresentation.enabled
        let clipsContent = usesFPSPresentation || wholeHUD
        let size = presentedHUDSize
        let width = size.width
        let height = size.height
        // FPS rolls its rows away; All options keeps the content anchored while
        // the rounded glass edge moves over it, including its rim and shadow.
        let fullExtent = horizontal ? expandedHUDSize.width : expandedHUDSize.height
        let backing = panel.backingScaleFactor * windowScale
        let fpsExtent = ((fullExtent - fpsCollapseDistance * (1 - progress)) * backing).rounded() / backing
        // Position the content from the measured divider edge, independently of
        // the rounded surface height, so the divider stays fixed across modes.
        let offset = progress == 1 ? 0 : (horizontal ? fullExtent - fpsExtent : fpsCollapseDistance * (1 - progress))
        // Keep the top-left anchor fixed while the native surface and window resize.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let anchor = visibleTopLeft
        let wasResizing = resizingHUD
        resizingHUD = true
        backgroundView.clipsContent = clipsContent
        layoutNativeSurface(size: size, anchor: anchor)
        resizingHUD = wasResizing
        if !horizontal {
            stackView.frame.origin.y = expandedHUDSize.height - HUDStyle.verticalPadding - stackView.frame.height + offset
            positionPressureGraph()
        }
        if horizontal {
            horizontalView.frame.origin.x = HUDStyle.horizontalPadding - offset
            horizontalView.setFPSOpacity(progress)
        }
        backgroundContentView.wantsLayer = true
        for metric in [HUDMetric.fps, .fpsGraph] { metricRows[metric]?.alphaValue = progress }
        for divider in groupDividers.values {
            (divider as? HUDSampleDividerView)?.setHistoryVisibility(progress)
        }
        // A quiet arrow points toward the space where FPS will return. Cross-fade
        // it near the end of collapse so it does not overlap the regular FPS row.
        collapsedFPSIndicator.image = NSImage(systemSymbolName: horizontal ? "arrow.right" : "arrow.down",
            accessibilityDescription: "FPS enabled; collapsed while waiting for readings")
        collapsedFPSIndicator.isHidden = !usesFPSPresentation || progress >= 0.4
        let headerFade = min(1, max(0, 1 - progress / 0.4))
        collapsedFPSIndicator.alphaValue = headerFade * headerFade * (3 - 2 * headerFade)
        collapsedFPSIndicator.contentTintColor = HUDStyle.TextStyle.label.color(background: textBackground)
        let indicatorSize: CGFloat = 12
        collapsedFPSIndicator.frame = NSRect(
            x: horizontal ? HUDStyle.horizontalPadding + (collapsedFPSHeaderHeight - indicatorSize) / 2
                : (width - indicatorSize) / 2,
            y: horizontal ? (height - indicatorSize) / 2
                : expandedHUDSize.height - HUDStyle.verticalPadding - (collapsedFPSHeaderHeight + indicatorSize) / 2,
            width: indicatorSize, height: indicatorSize)
        backgroundView.alphaValue = height < 1 || width < 1 ? 0 : 1
        panel.draggableContentRect = container.convert(container.bounds, to: nil)
        container.layoutSubtreeIfNeeded()
        if !horizontal, usesFPSPresentation, let first = fpsPresentationAnchor {
            // Align the moving boundary to the window's backing grid.
            let desired = HUDStyle.verticalPadding + collapsedFPSHeaderHeight
                + HUDStyle.rowSpacing + fpsCollapseDistance * progress
            let target = (desired * backing).rounded() / backing
            let actual = backgroundContentView.bounds.maxY - first.convert(first.bounds, to: backgroundContentView).maxY
            if abs(target - actual) > 0.01 {
                stackView.frame.origin.y += actual - target
                positionPressureGraph()
            }
        }
        CATransaction.commit()
        applyAutoHidePresentation()
    }

    private func animateFPS(to target: CGFloat) {
        if shouldAnimateAutoHide && fpsAnimationTimer != nil && fpsAnimationTarget == target { return }
        fpsAnimationTarget = target
        fpsAnimationTimer?.invalidate()
        fpsAnimationTimer = nil
        guard dynamicFPSActive, fpsProgress != target else { return }
        guard shouldAnimateAutoHide, panel.isVisible else {
            fpsProgress = target
            applyHUDPresentation()
            return
        }
        let start = fpsProgress
        let started = ProcessInfo.processInfo.systemUptime
        let duration = HUDFPSAvailability.animationDuration * Double(abs(target - start))
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let t = min(1, (ProcessInfo.processInfo.systemUptime - started) / duration)
                let eased = t * t * (3 - 2 * t)
                self.fpsProgress = start + (target - start) * CGFloat(eased)
                self.applyHUDPresentation()
                if t >= 1 { timer.invalidate(); self.fpsAnimationTimer = nil }
            }
        }
        fpsAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func fpsBecameAvailable() {
        fpsAvailabilityTask?.cancel()
        fpsAvailabilityTask = nil
        fpsAvailability.receivedReading()
        // Menu-bar FPS remains live with the overlay disabled. Cache its state
        // for the next reveal without animating the hidden window.
        guard hudEnabled else { return }
        // Do not restart an in-flight expansion for each arriving sample.
        if let transition = modeTransition {
            if !transition.available { transitionToAutoHideMode(autoHideMode) }
        } else if autoHidePresentation.enabled { animateAutoHide(visible: true) }
        else { animateFPS(to: 1) }
    }

    private func fpsBecameUnavailable() {
        fpsAvailability.unavailable(at: ProcessInfo.processInfo.systemUptime)
        guard fpsAvailabilityTask == nil, let since = fpsAvailability.unavailableSince else { return }
        let delay = max(0, HUDFPSAvailability.collapseDelay - (ProcessInfo.processInfo.systemUptime - since))
        fpsAvailabilityTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self else { return }
            fpsAvailabilityTask = nil
            fpsAvailability.advance(to: ProcessInfo.processInfo.systemUptime)
            guard hudEnabled else { return }
            if !fpsAvailability.expanded {
                if modeTransition != nil { transitionToAutoHideMode(autoHideMode) }
                else if autoHidePresentation.enabled { animateAutoHide(visible: false) }
                else { animateFPS(to: 0) }
            }
        }
    }

    private var shadowMargin: CGFloat {
        NativeGlassHUDBackground.shadowPadding
    }

    private var visibleTopLeft: NSPoint {
        panel.convertPoint(toScreen: container.convert(
            NSPoint(x: container.bounds.minX, y: container.bounds.maxY), to: nil))
    }

    private func nativeWindowSize(for body: NSSize) -> NSSize {
        let padded = NativeGlassHUDBackground.sizeIncludingShadow(bodySize: body)
        // AppKit rounds borderless windows outward to whole points. Keep that
        // extra fraction in the transparent margin, not in the glass or text.
        return NSSize(width: ceil(padded.width), height: ceil(padded.height))
    }

    private var windowScale: CGFloat { CGFloat(hudScale.rawValue) }

    private func windowSize(for logical: NSSize) -> NSSize {
        let backing = panel.backingScaleFactor
        return NSSize(width: (logical.width * windowScale * backing).rounded() / backing,
                      height: (logical.height * windowScale * backing).rounded() / backing)
    }

    private func applyWindowScale() {
        let wasResizing = resizingHUD
        resizingHUD = true
        defer { resizingHUD = wasResizing }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutNativeSurface(size: presentedHUDSize, anchor: visibleTopLeft)
        for divider in groupDividers.values {
            (divider as? HUDSampleDividerView)?.updateLine()
        }
        horizontalView.updateHairlines()
        ramPressureHistory.needsDisplay = true
        fpsGraphView.needsDisplay = true
        panel.draggableContentRect = container.convert(container.bounds, to: nil)
        CATransaction.commit()
    }

    private func layoutNativeSurface(size logicalSize: NSSize, anchor: NSPoint) {
        let size = windowSize(for: logicalSize)
        let windowSize = nativeWindowSize(for: size)
        let frame = NSRect(x: anchor.x - shadowMargin,
                           y: anchor.y + shadowMargin - windowSize.height,
                           width: windowSize.width, height: windowSize.height)
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        let padded = NativeGlassHUDBackground.sizeIncludingShadow(bodySize: size)
        backgroundView.frame = NSRect(x: 0, y: panel.contentLayoutRect.height - padded.height,
                                      width: padded.width, height: padded.height)
        let radius = 16 * windowScale
        if backgroundView.cornerRadius != radius { backgroundView.cornerRadius = radius }
        backgroundView.layoutSurface()
        let full = NSSize(width: expandedHUDSize.width * windowScale, height: expandedHUDSize.height * windowScale)
        let contentFrame = NSRect(x: 0, y: size.height - full.height, width: full.width, height: full.height)
        if scaledContentView.frame != contentFrame { scaledContentView.frame = contentFrame }
        let contentBounds = NSRect(origin: .zero, size: expandedHUDSize)
        if scaledContentView.bounds != contentBounds { scaledContentView.bounds = contentBounds }
        if backgroundContentView.frame != contentBounds { backgroundContentView.frame = contentBounds }
    }

    // MARK: - Screen Position

    func resetPosition() {
        customTopLeft = nil
        HUDPreferences.hudPosition = nil
        restorePosition()
    }

    private func restorePosition() {
        let positioningSize = dynamicFPSActive || autoHidePresentation.enabled || modeTransition != nil
            ? windowSize(for: expandedHUDSize) : container.frame.size
        if let customTopLeft, !NSScreen.screens.isEmpty {
            // Choose the nearest remaining display if the saved display was disconnected.
            let screen = NSScreen.screens.min { left, right in
                HUDPositioning.distanceSquared(from: customTopLeft, to: left.frame)
                    < HUDPositioning.distanceSquared(from: customTopLeft, to: right.frame)
            }!
            let contentOrigin = HUDPositioning.origin(
                for: customTopLeft,
                size: positioningSize,
                in: screen.frame
            )
            panel.setFrameOrigin(NSPoint(x: contentOrigin.x - shadowMargin,
                                        y: contentOrigin.y + positioningSize.height + shadowMargin - panel.frame.height))
            return
        }

        guard
            let screen =
                NSScreen.main
        else {
            return
        }

        let usableFrame =
            HUDStyle.gameContentFrame(in: screen.frame)
                .intersection(screen.visibleFrame)

        let inset =
            HUDStyle.screenEdgeInset

        let x =
            usableFrame.minX
            + inset
            - shadowMargin

        let y =
            usableFrame.maxY
            - panel.frame.height
            - inset
            + shadowMargin

        panel.setFrameOrigin(
            NSPoint(
                x: x,
                y: y
            )
        )
    }

    func updateBattery(_ sample: BatterySample?, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        horizontalView.battery.update(percentage: sample?.percentage, source: sample?.source,
            temperature: sample?.temperature, power: sample?.power, now: now)
        batteryIndicator.update(percentage: sample?.percentage, source: sample?.source,
            temperature: sample?.temperature, power: sample?.power, now: now)
        if alignment == .horizontal, enabledMetrics.contains(.battery),
           horizontalView.battery.frame.width != ceil(horizontalView.battery.minimumRowWidth) {
            // Fit the visible battery readings, including Auto transitions and
            // battery-only HUDs with no other updates to refresh their layout.
            refreshHorizontalReadings()
        }
    }

    func setBatteryOptions(_ options: HUDBatteryOptions) {
        batteryIndicator.setOptions(options)
        horizontalView.battery.setOptions(options)
        setMetricEnabled(.battery, enabled: options.enabled)
    }

    // MARK: - Generic Metric Updating

    func updateMetric(
        _ metric: HUDMetric,
        value: String
    ) {
        switch metric {
        case .gpu:
            processView.setValue(value, for: .gpu)
            return
        case .cpu:
            processView.setValue(value, for: .cpu)
            return
        case .battery:
            if value.isEmpty { updateBattery(nil) }
            return
        default: break
        }
        defer { refreshHorizontalReadings() }
        valueLabels[metric]?
            .stringValue =
                value
        if value.isEmpty {
            ramDetailLabels[metric]?.stringValue = ""
            if metric == .ramTotal { ramSwapValueLabel?.stringValue = "" }
        }
    }

    func updateMemoryPressure(_ value: String) {
        ramPressureValueLabel?.stringValue = value
        ramPressureMeter.update(value)
        ramPressureValueLabel?.textColor = ramPressureColor
        refreshHorizontalReadings()
    }

    func updateMemoryPressureHistory(_ sample: MemoryPressureMonitor.Sample) {
        guard showsRAMPressure, alignment == .vertical, memoryPressureMode.isHistory else { return }
        ramPressureHistory.append(sample)
    }

    func clearMemoryPressureHistory() { ramPressureHistory.clear() }

    func updateRAM(_ metric: HUDMetric, usage: RAMUsageSample?) {
        if metric == .ram {
            processView.setValue(usage?.gigabytesText, for: .memory)
            return
        }
        guard metric == .ramTotal else { return }
        defer { refreshHorizontalReadings() }
        valueLabels[metric]?.stringValue = usage.map { "\(Int($0.percentage.rounded()))%" } ?? ""
        ramDetailLabels[metric]?.stringValue = usage?.gigabytesText ?? ""
        ramSwapValueLabel?.stringValue = usage?.swapGigabytesText ?? ""
    }

    // MARK: - Process and core detail rows

    func setProcessOptions(_ options: HUDProcessOptions) {
        processOptions = options
        processView.configure(options: options, background: textBackground)
        setMetricEnabled(.process, enabled: options.enabled && alignment == .vertical)
    }

    func setProcessName(_ name: String?) { processView.setName(name) }

    func setCPUCoreOptions(_ options: HUDCoreOptions) {
        cpuCoreOptions = options
        setResourceOptions(cpuResourceOptions, for: .cpu)
    }

    func setGPUCoreOptions(_ options: HUDCoreOptions) {
        gpuCoreOptions = options.gpuFrequencyOnly
        setResourceOptions(gpuResourceOptions, for: .gpu)
    }

    func updateCPUCores(_ sample: CPUCoreSample) {
        cpuCoreSample = sample
        cpuCoreView.update(sample: sample, frequencies: cpuFrequencies)
        if alignment == .horizontal && enabledMetrics.contains(.cpuCores) && cpuCoreOptions.mode.showsBars {
            refreshHorizontalReadings()
        }
    }

    func updateCPUFrequencies(_ frequencies: CPUFrequencySample) {
        cpuFrequencies = frequencies
        cpuCoreView.update(sample: cpuCoreSample, frequencies: frequencies)
    }

    // MARK: - Misc

    func setMiscOptions(_ options: HUDMiscOptions) {
        miscOptions = options
        miscView.configure(options: options, background: textBackground)
        setMetricEnabled(.misc, enabled: alignment.allows(.misc) && !options.visibleReadings.isEmpty)
    }

    func updateMisc(_ sample: HUDMiscSample) {
        miscView.update(sample)
    }

    // MARK: - FPS

    private var fpsReading: String {
        fpsMeasure.reading(fps: latestFPS, averageMS: latestFrameTiming?.averageMS) ?? ""
    }

    func updateFPS(_ fps: Double, timing: MetalFrameTiming? = nil) {
        guard fps.isFinite, fps >= 0, fps < Double(Int.max) else {
            markFPSUnavailable()
            return
        }
        latestFPS = fps
        latestFrameTiming = timing
        fpsBecameAvailable()
        updateMetric(.fps, value: fpsReading)
        if hudEnabled && enabledMetrics.contains(.fpsGraph) {
            fpsGraphView.append(fps, timing: timing)
        }
    }

    func markFPSUnavailable() {
        latestFPS = nil
        latestFrameTiming = nil
        fpsBecameUnavailable()
        updateMetric(.fps, value: "")
        if hudEnabled && enabledMetrics.contains(.fpsGraph) {
            fpsGraphView.markUnavailable()
        }
    }

    func resetFPS() {
        latestFPS = nil
        latestFrameTiming = nil
        fpsBecameUnavailable()
        fpsGraphView.reset()
        updateMetric(.fps, value: "")
    }
}

@MainActor
private final class HUDMetricRowView: NSView {
    var layoutReadings: (() -> Void)?
    var layoutDetails: (() -> Void)?
    func place(_ label: NSTextField, top: CGFloat, height: CGFloat? = nil, trailing: CGFloat? = nil) {
        let size = label.intrinsicContentSize
        let h = height ?? size.height
        let width = size.width + label.alignmentRectInsets.left + label.alignmentRectInsets.right
        label.frame = NSRect(x: trailing.map { $0 - width } ?? 0, y: top - h, width: width, height: h)
    }

    override func layout() {
        super.layout()
        layoutReadings?()
        layoutDetails?()
    }
}

// The sample uses a quiet 0.5pt line, with 4.5pt of space below it before stack spacing.
@MainActor
private final class HUDSampleDividerView: NSView {
    private let line = NSView()
    private var normalLineOffset: CGFloat = 2
    private var connectsToHistory = false
    private var historyVisibility: CGFloat = 1
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        line.wantsLayer = true
        addSubview(line)
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    func applyStyle(background: HUDBackground, afterFPS: Bool = true, connectsToHistory: Bool = false) {
        normalLineOffset = HUDStyle.dividerHeight(afterFPS: afterFPS) - 5
        self.connectsToHistory = connectsToHistory
        line.layer?.backgroundColor = HUDStyle.separatorColor(background: background).cgColor
        needsLayout = true
    }

    func setHistoryVisibility(_ progress: CGFloat) {
        guard historyVisibility != progress else { return }
        historyVisibility = progress
        needsLayout = true
    }

    override func layout() {
        super.layout()
        updateLine()
    }

    func updateLine() {
        // The graph's fade meets the divider only while the graph is visible.
        // A collapsed arrow uses the same divider position in every FPS mode.
        line.frame = NSRect(x: 0, y: normalLineOffset * (connectsToHistory ? 1 - historyVisibility : 1),
                            width: bounds.width, height: hudHairline)
    }
}
