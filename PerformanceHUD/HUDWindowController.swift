import AppKit

@MainActor
final class HUDWindowController {

    // MARK: - Background Preset

    private enum BackgroundPreset {
        case customGlass
        case clearGlass
    }

    // Keep exactly one preset line uncommented, then rebuild the app.
    private static let backgroundPreset: BackgroundPreset = .customGlass
    // Disabled: Liquid Glass capped game FPS at 60 in testing.
    // private static let backgroundPreset: BackgroundPreset = .clearGlass

    // MARK: - Window

    private let panel: HUDPanel

    private let container:
        NSView

    private let stackView:
        NSStackView

    private let windowContentView = NSView()
    private let backgroundView: NSView = {
        switch HUDWindowController.backgroundPreset {
        case .customGlass: return PerformanceHUDGlassBackground(frame: .zero, style: .transparent)
        case .clearGlass: return NSGlassEffectView()
        }
    }()
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
        [.gpu, .gpuTotal, .cpu, .cpuTotal, .aneTotal, .ram, .ramTotal],
        [.fans],
        [.battery],
        [.deviceInfo]
    ]

    private let verticalMetricGroups: [[HUDMetric]] = [
        [.fps, .fpsGraph],
        [.gpu, .gpuTotal, .cpu, .cpuTotal, .aneTotal],
        [.ram, .ramTotal],
        [.fans],
        [.battery],
        [.deviceInfo]
    ]


    private var groupDividers: [Int: NSView] = [:]
    private var dividerHeightConstraints: [Int: NSLayoutConstraint] = [:]

    private var bottomDivider: NSView?
    private var bottomDividerHeightConstraint: NSLayoutConstraint?

    private var showsRAMDetails = HUDPreferences.resourceOptions(for: .ram).showsDetails
    private var ramDetailBottomConstraints: [HUDMetric: NSLayoutConstraint] = [:]
    private var ramDetailLabels: [HUDMetric: NSTextField] = [:]
    private var ramDetailGroupSpacingConstraints: [HUDMetric: NSLayoutConstraint] = [:]
    private let fpsGraphView = HUDFPSGraphView()
    private let horizontalView = HUDHorizontalView(frame: .zero)
    private let fanView = HUDFanView(frame: .zero)
    private var fanOptions = HUDPreferences.fanOptions
    private var fpsValueHighlighted = HUDPreferences.fpsOptions.valueHighlighted
    private var fanSample = FanSample.checking
    private var alignment = HUDPreferences.alignment
    private var ramDetailTitleLabels: [HUDMetric: NSTextField] = [:]
    private var ramSwapTitleLabel: NSTextField?
    private var ramSwapValueLabel: NSTextField?
    private var ramPressureValueLabel: NSTextField?
    private var ramPressureTitleLabel: NSTextField?
    private let batteryIndicator = HUDBatteryIndicatorView(frame: .zero)

    private var deviceInfoLabels: [NSTextField] = []
    private var primaryLabelHeightConstraints: [HUDMetric: NSLayoutConstraint] = [:]

    // MARK: - Dynamic Constraints

    private var rowHeightConstraints:
        [HUDMetric: NSLayoutConstraint] = [:]

    private var valueSpacingConstraints:
        [HUDMetric: NSLayoutConstraint] = [:]
    
    private var valueColumnConstraints:
        [HUDMetric: NSLayoutConstraint] = [:]

    private var temperatureLabels: [HUDMetric: NSTextField] = [:]
    private var powerLabels: [HUDMetric: NSTextField] = [:]
    private var powerTrailingConstraints: [HUDMetric: NSLayoutConstraint] = [:]
    private var readingColumnRight: CGFloat = 0
    private var powerMetrics: Set<HUDMetric> = []
    private var highlightedReadings: [HUDMetric: Set<HUDReadingKind>] = [:]
    private var packageTitleLabel: NSTextField?
    private var packageValueLabel: NSTextField?
    private var packageRow: NSView?
    private var packageHeightConstraint: NSLayoutConstraint?
    private var packageTrailingConstraint: NSLayoutConstraint?
    private var packageOptions = HUDPreferences.packagePowerOptions
    private var packageRowHeight: CGFloat {
        HUDStyle.rowHeight(scale: hudScale)
    }
    private var hasVisibleContent: Bool { !enabledMetrics.isEmpty || showsPackagePower }
    private var showsPackagePower: Bool {
        packageOptions.enabled
    }
    private var temperatureTrailingConstraints: [HUDMetric: NSLayoutConstraint] = [:]
    private var temperatureMetrics: Set<HUDMetric> = []
    private var hiddenUtilizationMetrics: Set<HUDMetric> = []

    private var stackLeadingConstraint:
        NSLayoutConstraint?

    private var stackTrailingConstraint:
        NSLayoutConstraint?

    private var stackTopConstraint:
        NSLayoutConstraint?

    // MARK: - State

    private var hudEnabled = HUDPreferences.hudEnabled

    private var enabledMetrics = HUDPreferences.visibleMetrics

    private var hudScale =
        HUDPreferences.hudScale

    private var customTopLeft = HUDPreferences.hudPosition
    private var screenObserver: NSObjectProtocol?
    private var geometryObservers: [NSObjectProtocol] = []
    private var captureRefreshTask: Task<Void, Never>?
    private let glassRevealGate = HUDGlassRevealGate()
    private var windowGeometryTask: Task<Void, Never>?
    private var displayLayoutPending = false
    private var resizingHUD = false

    // Dynamic FPS changes the visible surface, never the reserved window/capture area.
    private let autoHidePresentation = HUDAutoHidePresentation(enabled: HUDPreferences.autoHideMode == .all)
    private var lastAutoHideHidden = HUDPreferences.autoHideMode == .all
    var onAutoHideVisibilityChange: (() -> Void)?
    var isAutomaticallyHidden: Bool { autoHidePresentation.isHidden }
    private var autoHideMode = HUDPreferences.autoHideMode
    private var fpsAvailability = HUDFPSAvailability()
    private var fpsAvailabilityTask: Task<Void, Never>?
    private var fpsAnimationTimer: Timer?
    private var fpsAnimationTarget: CGFloat?
    private var fpsProgress: CGFloat = 1
    private var fpsCollapseDistance: CGFloat = 0
    private let collapsedFPSIndicator = NSImageView()
    private var collapsedFPSHeaderHeight: CGFloat { HUDStyle.ramDetailHeight(scale: hudScale) }
    private var expandedHUDSize = NSSize.zero
    private var dynamicFPSActive: Bool {
        autoHideMode == .fps && !enabledMetrics.isDisjoint(with: [.fps, .fpsGraph])
    }

    private var customGlass: PerformanceHUDGlassBackground? {
        backgroundView as? PerformanceHUDGlassBackground
    }

    private var textBackground: HUDBackground {
        // Match a held frame's appearance until its replacement arrives, and
        // retain a legible light foreground over the dark fallback.
        guard hudBackground != .off, let glass = customGlass else { return hudBackground }
        if glass.isShowingFallback { return hudBackground == .light ? .dark : hudBackground }
        switch glass.displayedStyle {
        case .light: return .light
        case .dark: return .dark
        case .transparent: return .transparent
        case nil: return hudBackground
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        for observer in geometryObservers { NotificationCenter.default.removeObserver(observer) }
        captureRefreshTask?.cancel()
        windowGeometryTask?.cancel()
        fpsAvailabilityTask?.cancel()
        fpsAnimationTimer?.invalidate()
    }

    // MARK: - Init

    init() {

        panel = HUDPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width:
                    HUDStyle.width(
                        scale:
                            HUDPreferences.hudScale
                    ),
                height: 100
            ),
            styleMask: [
                .borderless,
                .nonactivatingPanel
            ],
            backing: .buffered,
            defer: false
        )

        container = NSView(frame: panel.contentLayoutRect)

        stackView =
            NSStackView()

        configureWindow()
        configureContainer()
        configureStackView()
        createMetricRows()

        autoHidePresentation.onChange = { [weak self] in self?.applyHUDPresentation() }
        glassRevealGate.onWait = { [weak self] in
            guard let self else { return }
            setGlassRevealOpacity(0)
            autoHidePresentation.setRevealSuspended(true)
            fpsAnimationTimer?.invalidate()
            fpsAnimationTimer = nil
            customGlass?.preparingForReveal = true
        }
        glassRevealGate.onFinish = { [weak self] cancelled in
            guard let self else { return }
            customGlass?.preparingForReveal = false
            setGlassRevealOpacity(1)
            autoHidePresentation.setRevealSuspended(false, resume: !cancelled)
            if !cancelled && dynamicFPSActive { animateFPS(to: fpsAvailability.expanded ? 1 : 0) }
        }
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
                    self.scheduleCaptureRefresh()
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
        windowContentView.addSubview(container)
        container.layer?.masksToBounds = false

        backgroundView.wantsLayer = true
        if let glassView = backgroundView as? NSGlassEffectView {
            glassView.style = .clear
            glassView.contentView = backgroundContentView
        } else {
            // Custom glass supplies its own rounded surface, rim, and layer shadow.
            backgroundContentView.translatesAutoresizingMaskIntoConstraints = false
            backgroundView.addSubview(backgroundContentView)
            NSLayoutConstraint.activate([
                backgroundContentView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
                backgroundContentView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
                backgroundContentView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
                backgroundContentView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor)
            ])
        }
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(backgroundView)
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: container.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        customGlass?.onFallbackChange = { [weak self] in
            self?.updateMetricColors()
            _ = self?.updateDividers()
            self?.updateGlassRevealReadiness()
        }
        customGlass?.onCaptureStateChange = { [weak self] state in
            guard let self else { return }
            updateGlassRevealReadiness()
            onCaptureStateChange?(state)
        }
        applyBackgroundAppearance()
    }

    // MARK: - Stack View

    private func configureStackView() {

        stackView.orientation =
            .vertical

        /*
         All rows fill the same width.
         This keeps the values aligned
         to the same right-hand edge.
        */
        stackView.alignment =
            .width

        stackView.spacing =
            HUDStyle.rowSpacing(
                scale: hudScale
            )

        stackView.distribution =
            .fill

        stackView.detachesHiddenViews = true

        stackView.translatesAutoresizingMaskIntoConstraints =
            false

        attachStackView()
    }

    private func attachStackView() {
        let host: NSView = hudBackground == .off ? container : backgroundContentView
        NSLayoutConstraint.deactivate(
            [stackLeadingConstraint, stackTrailingConstraint, stackTopConstraint].compactMap { $0 }
        )
        host.addSubview(stackView)
        host.addSubview(horizontalView)
        host.addSubview(collapsedFPSIndicator)
        collapsedFPSIndicator.image = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: "FPS enabled; rolled up while waiting for readings")
        collapsedFPSIndicator.imageScaling = .scaleProportionallyUpOrDown

        let leading =
            stackView.leadingAnchor.constraint(
                equalTo:
                    host.leadingAnchor,
                constant:
                    HUDStyle.horizontalPadding(scale: hudScale)
            )

        let trailing =
            stackView.trailingAnchor.constraint(
                equalTo:
                    host.trailingAnchor,
                constant:
                    -HUDStyle.horizontalPadding(scale: hudScale)
            )

        let top =
            stackView.topAnchor.constraint(
                equalTo:
                    host.topAnchor,
                constant:
                    HUDStyle.verticalPadding(scale: hudScale)
            )

        stackLeadingConstraint =
            leading

        stackTrailingConstraint =
            trailing

        stackTopConstraint =
            top

        NSLayoutConstraint.activate([leading, top])
        // The hidden vertical stack must not inherit the narrowing horizontal
        // viewport. Restore its trailing edge after the expanded width is ready.
        trailing.isActive = alignment == .vertical && expandedHUDSize.width > 0
    }

    // MARK: - Metric Creation

    private func createMetricRows() {

        for (index, metrics) in verticalMetricGroups.enumerated() {
            if index > 0 {
                let divider = createDivider()
                groupDividers[index] = divider.view
                dividerHeightConstraints[index] = divider.height
            }

            for metric in metrics {
                let row = createRow(for: metric)
                metricRows[metric] = row
                stackView.addArrangedSubview(row)
                if metric == .aneTotal { createPackageRow() }
                if metric == .fpsGraph || metric == .battery || metric == .fans {
                    NSLayoutConstraint.activate([
                        row.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
                        row.trailingAnchor.constraint(equalTo: stackView.trailingAnchor)
                    ])
                }
            }
        }

        let divider = createDivider()
        bottomDivider = divider.view
        bottomDividerHeightConstraint = divider.height
        divider.view.isHidden = true
    }

    private func createDivider() -> (view: NSView, height: NSLayoutConstraint) {
        let divider = HUDSampleDividerView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.applyStyle(scale: hudScale, background: textBackground)
        let height = divider.heightAnchor.constraint(
            equalToConstant: HUDStyle.dividerHeight(scale: hudScale)
        )
        stackView.addArrangedSubview(divider)
        NSLayoutConstraint.activate([
            height,
            divider.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: stackView.trailingAnchor)
        ])
        return (divider, height)
    }

    private func updateDividers() -> (count: Int, height: CGFloat) {
        var lastVisibleGroup: Int?
        var visibleDividerCount = 0
        var totalDividerHeight: CGFloat = 0

        for (index, metrics) in verticalMetricGroups.enumerated() {
            let groupIsVisible = metrics.contains { enabledMetrics.contains($0) }
                || (metrics.contains(.aneTotal) && showsPackagePower)
            let showDivider = groupIsVisible
                && (lastVisibleGroup != nil || metrics == [.deviceInfo] || metrics == [.ram, .ramTotal] || metrics == [.fans])
            let height = HUDStyle.dividerHeight(scale: hudScale, afterFPS: lastVisibleGroup == 0)
            if let divider = groupDividers[index] {
                divider.isHidden = !showDivider
                dividerHeightConstraints[index]?.constant = height
                (divider as? HUDSampleDividerView)?.applyStyle(
                    scale: hudScale, background: textBackground,
                    connectsToHistory: lastVisibleGroup == 0 && enabledMetrics.contains(.fpsGraph))
                if showDivider {
                    visibleDividerCount += 1
                    totalDividerHeight += height
                }
            }
            if groupIsVisible { lastVisibleGroup = index }
        }

        let fansAreLast = lastVisibleGroup.map { verticalMetricGroups[$0] == [.fans] } ?? false
        let showBottomDivider = fansAreLast || (hudBackground == .off
            && hasVisibleContent && visibleDividerCount == 0)
        bottomDivider?.isHidden = !showBottomDivider
        let bottomHeight = HUDStyle.dividerHeight(scale: hudScale, afterFPS: lastVisibleGroup == 0)
        bottomDividerHeightConstraint?.constant = bottomHeight
        (bottomDivider as? HUDSampleDividerView)?.applyStyle(
            scale: hudScale, background: textBackground,
            connectsToHistory: lastVisibleGroup == 0 && enabledMetrics.contains(.fpsGraph))
        return (visibleDividerCount + (showBottomDivider ? 1 : 0),
                totalDividerHeight + (showBottomDivider ? bottomHeight : 0))
    }

    private func createRow(
        for metric: HUDMetric
    ) -> NSView {
        if metric == .fpsGraph {
            fpsGraphView.translatesAutoresizingMaskIntoConstraints = false
            fpsGraphView.applyStyle(scale: hudScale, background: textBackground)
            let height = fpsGraphView.heightAnchor.constraint(
                equalToConstant: HUDStyle.rowHeight(for: .fpsGraph, scale: hudScale)
            )
            rowHeightConstraints[.fpsGraph] = height
            height.isActive = true
            return fpsGraphView
        }
        if metric == .fans {
            fanView.translatesAutoresizingMaskIntoConstraints = false
            let height = fanView.heightAnchor.constraint(equalToConstant: fanView.height(scale: hudScale))
            rowHeightConstraints[.fans] = height
            height.isActive = true
            return fanView
        }
        if metric == .deviceInfo { return createDeviceInfoRow() }
        if metric == .battery {
            batteryIndicator.translatesAutoresizingMaskIntoConstraints = false
            batteryIndicator.applyStyle(scale: hudScale, background: textBackground)
            let height = batteryIndicator.heightAnchor.constraint(
                equalToConstant: HUDStyle.rowHeight(for: .battery, scale: hudScale))
            rowHeightConstraints[.battery] = height
            height.isActive = true
            return batteryIndicator
        }

        let row =
            NSView(
                frame: .zero
            )

        row.translatesAutoresizingMaskIntoConstraints =
            false

        // MARK: Title

        let titleLabel =
            NSTextField(
                labelWithString:
                    metric.hudTitle
            )

        titleLabel.font =
            HUDStyle.titleFont(
                for: metric,
                scale: hudScale
            )

        titleLabel.textColor =
            HUDStyle.primaryTitleColor(for: metric, background: textBackground)

        titleLabel.wantsLayer = true

        titleLabel.alignment =
            .left

        titleLabel.translatesAutoresizingMaskIntoConstraints =
            false

        // MARK: Value

        let valueLabel =
            NSTextField(
                labelWithString:
                    metric.placeholderValue
            )

        valueLabel.font =
            HUDStyle.valueFont(
                for: metric,
                scale: hudScale
            )

        valueLabel.textColor =
            HUDStyle.valueColor(background: textBackground)

        valueLabel.wantsLayer = true

        valueLabel.alignment =
            .right

        valueLabel.translatesAutoresizingMaskIntoConstraints =
            false

        // MARK: Add Views

        row.addSubview(
            titleLabel
        )

        row.addSubview(
            valueLabel
        )

        // MARK: Dynamic Constraints

        let rowHeightConstraint =
            row.heightAnchor.constraint(
                equalToConstant:
                    HUDStyle.rowHeight(
                        for: metric, scale: hudScale
                    )
            )

        let valueSpacingConstraint =
            valueLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo:
                    titleLabel.trailingAnchor,
                constant:
                    HUDStyle.metricColumnSpacing(
                        scale: hudScale
                    )
            )

        let valueColumnConstraint =
            valueLabel.trailingAnchor.constraint(
                equalTo:
                    row.leadingAnchor,
                constant:
                    HUDStyle.valueColumnRight(
                        scale: hudScale
                    )
            )

        rowHeightConstraints[metric] =
            rowHeightConstraint

        valueSpacingConstraints[metric] =
            valueSpacingConstraint

        valueColumnConstraints[metric] =
            valueColumnConstraint

        let primaryLabelHeightConstraint = titleLabel.heightAnchor.constraint(
            equalToConstant: HUDStyle.primaryLabelHeight(for: metric, scale: hudScale)
        )
        primaryLabelHeightConstraints[metric] = primaryLabelHeightConstraint

        // MARK: Constraints

        NSLayoutConstraint.activate([

            rowHeightConstraint,
            primaryLabelHeightConstraint,
            valueLabel.heightAnchor.constraint(equalTo: titleLabel.heightAnchor),

            titleLabel.leadingAnchor.constraint(
                equalTo: row.leadingAnchor,
                constant: titleLabel.alignmentRectInsets.left
            ),

            // Center the FPS label and value within their shared row.
            metric == .fps
                ? titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor)
                : titleLabel.topAnchor.constraint(equalTo: row.topAnchor),

            valueSpacingConstraint,

            valueColumnConstraint,

            valueLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor)
        ])

        if metric == .gpuTotal || metric == .cpuTotal {
            let temperature = NSTextField(labelWithString: "")
            temperature.font = temperatureFont(for: metric)
            temperature.textColor = HUDStyle.readingColor(background: textBackground)
            temperature.alignment = .right
            temperature.isHidden = true
            temperature.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(temperature)
            let trailing = temperature.trailingAnchor.constraint(equalTo: row.leadingAnchor,
                                                                 constant: HUDStyle.valueColumnRight(scale: hudScale))
            NSLayoutConstraint.activate([
                trailing,
                temperature.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor,
                                                     constant: HUDStyle.metricColumnSpacing(scale: hudScale)),
                temperature.firstBaselineAnchor.constraint(equalTo: valueLabel.firstBaselineAnchor)
            ])
            temperatureLabels[metric] = temperature
            temperatureTrailingConstraints[metric] = trailing
        }

        if [.gpuTotal, .cpuTotal, .aneTotal].contains(metric) {
            let power = NSTextField(labelWithString: "")
            power.font = powerFont(for: metric)
            power.textColor = HUDStyle.readingColor(background: textBackground)
            power.alignment = .right
            power.isHidden = true
            power.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(power)
            let powerTrailing = power.trailingAnchor.constraint(equalTo: row.leadingAnchor,
                constant: HUDStyle.valueColumnRight(scale: hudScale))
            NSLayoutConstraint.activate([
                powerTrailing,
                power.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor,
                    constant: HUDStyle.metricColumnSpacing(scale: hudScale)),
                power.firstBaselineAnchor.constraint(equalTo: valueLabel.firstBaselineAnchor)
            ])
            powerLabels[metric] = power
            powerTrailingConstraints[metric] = powerTrailing

        }

        if metric == .ram || metric == .ramTotal {
            let detailLabel = NSTextField(labelWithString: "")
            detailLabel.font = HUDStyle.ramDetailFont(scale: hudScale)
            detailLabel.textColor = HUDStyle.readingColor(background: textBackground)
            detailLabel.alignment = .right
            detailLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(detailLabel)
            let physicalLabel = NSTextField(labelWithString: "Physical")
            physicalLabel.font = HUDStyle.smallLabelFont(scale: hudScale)
            physicalLabel.textColor = HUDStyle.TextStyle.label.color(background: textBackground)
            physicalLabel.setAccessibilityLabel("Physical memory")
            physicalLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(physicalLabel)
            let detailTop = detailLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor)
            ramDetailGroupSpacingConstraints[metric] = detailTop
            NSLayoutConstraint.activate([
                detailTop,
                physicalLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                physicalLabel.firstBaselineAnchor.constraint(equalTo: detailLabel.firstBaselineAnchor),
                detailLabel.leadingAnchor.constraint(greaterThanOrEqualTo: physicalLabel.trailingAnchor),
                detailLabel.trailingAnchor.constraint(equalTo: valueLabel.trailingAnchor)
            ])
            ramDetailLabels[metric] = detailLabel
            ramDetailTitleLabels[metric] = physicalLabel

            if metric == .ramTotal {
                let swapTitle = NSTextField(labelWithString: "Swap")
                swapTitle.setAccessibilityLabel("Swap memory")
                let swapValue = NSTextField(labelWithString: "")
                let pressureValue = NSTextField(labelWithString: "")
                pressureValue.setAccessibilityLabel("Memory pressure")
                let pressureTitle = NSTextField(labelWithString: "Pressure")
                swapValue.alignment = .right
                pressureValue.alignment = .right
                for label in [swapTitle, swapValue, pressureValue, pressureTitle] {
                    label.font = detailLabel.font
                    label.textColor = detailLabel.textColor
                    label.translatesAutoresizingMaskIntoConstraints = false
                    row.addSubview(label)
                }
                for caption in [swapTitle, pressureTitle] {
                    caption.font = HUDStyle.smallLabelFont(scale: hudScale)
                    caption.textColor = HUDStyle.TextStyle.label.color(background: textBackground)
                }
                let bottom = pressureValue.bottomAnchor.constraint(equalTo: row.bottomAnchor)
                ramDetailBottomConstraints[metric] = bottom
                NSLayoutConstraint.activate([
                    swapTitle.leadingAnchor.constraint(equalTo: physicalLabel.leadingAnchor),
                    swapTitle.firstBaselineAnchor.constraint(equalTo: swapValue.firstBaselineAnchor),
                    swapValue.topAnchor.constraint(equalTo: detailLabel.bottomAnchor),
                    swapValue.heightAnchor.constraint(equalTo: detailLabel.heightAnchor),
                    swapValue.leadingAnchor.constraint(greaterThanOrEqualTo: swapTitle.trailingAnchor),
                    swapValue.trailingAnchor.constraint(equalTo: valueLabel.trailingAnchor),
                    pressureValue.topAnchor.constraint(equalTo: swapValue.bottomAnchor),
                    pressureValue.heightAnchor.constraint(equalTo: detailLabel.heightAnchor),
                    pressureTitle.leadingAnchor.constraint(equalTo: physicalLabel.leadingAnchor),
                    pressureTitle.firstBaselineAnchor.constraint(equalTo: pressureValue.firstBaselineAnchor),
                    pressureValue.leadingAnchor.constraint(greaterThanOrEqualTo: pressureTitle.trailingAnchor),
                    pressureValue.trailingAnchor.constraint(equalTo: valueLabel.trailingAnchor),
                    bottom
                ])
                ramSwapTitleLabel = swapTitle
                ramSwapValueLabel = swapValue
                ramPressureValueLabel = pressureValue
                ramPressureTitleLabel = pressureTitle
            } else {
                let bottom = detailLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor)
                ramDetailBottomConstraints[metric] = bottom
                bottom.isActive = true
            }
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
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isHidden = true
        let title = NSTextField(labelWithString: "SOC")
        let value = NSTextField(labelWithString: "")
        value.alignment = .right
        for label in [title, value] {
            label.font = HUDStyle.ramDetailFont(scale: hudScale)
            label.textColor = HUDStyle.readingColor(background: textBackground)
            label.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(label)
        }
        stackView.addArrangedSubview(row)
        let height = row.heightAnchor.constraint(equalToConstant: packageRowHeight)
        let trailing = value.trailingAnchor.constraint(equalTo: row.leadingAnchor,
            constant: HUDStyle.valueColumnRight(scale: hudScale))
        NSLayoutConstraint.activate([
            height, trailing,
            row.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
            title.topAnchor.constraint(equalTo: row.topAnchor),
            title.heightAnchor.constraint(equalTo: row.heightAnchor),
            title.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: title.alignmentRectInsets.left),
            value.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: value.leadingAnchor,
                constant: -HUDStyle.metricColumnSpacing(scale: hudScale))
        ])
        packageRow = row
        packageTitleLabel = title
        packageValueLabel = value
        packageHeightConstraint = height
        packageTrailingConstraint = trailing
    }

    private func createDeviceInfoRow() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let info = HUDDeviceInfo.current
        let chipLabel = NSTextField(labelWithString: info.chipName)
        let versionLabel = NSTextField(labelWithString: info.macOSVersion)
        deviceInfoLabels = [chipLabel, versionLabel]
        chipLabel.alignment = .left
        versionLabel.alignment = .right
        for label in deviceInfoLabels {
            label.font = HUDStyle.smallLabelFont(scale: hudScale)
            label.textColor = HUDStyle.TextStyle.label.color(background: textBackground)
            label.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: row.topAnchor),
                label.bottomAnchor.constraint(equalTo: row.bottomAnchor)
            ])
        }
        let height = row.heightAnchor.constraint(equalToConstant: HUDStyle.rowHeight(for: .deviceInfo, scale: hudScale))
        let spacing = versionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: chipLabel.trailingAnchor,
                                                            constant: HUDStyle.metricColumnSpacing(scale: hudScale))
        rowHeightConstraints[.deviceInfo] = height
        valueSpacingConstraints[.deviceInfo] = spacing
        NSLayoutConstraint.activate([
            height, spacing,
            chipLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: chipLabel.alignmentRectInsets.left),
            versionLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -versionLabel.alignmentRectInsets.right)
        ])
        return row
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
            autoHidePresentation.transition(visible: fpsAvailability.expanded, animated: false)
            fpsAnimationTimer?.invalidate()
            fpsAnimationTimer = nil
            fpsProgress = dynamicFPSActive && !fpsAvailability.expanded ? 0 : 1
            applyHUDPresentation()
        }

        if enabled && autoHidePresentation.enabled {
            autoHidePresentation.transition(visible: fpsAvailability.expanded, animated: false)
        }
        updateVisibility()
    }

    func setAutoHideMode(_ mode: HUDAutoHideMode) {
        guard autoHideMode != mode else { return }
        let previousFPSProgress = autoHideMode == .fps ? fpsProgress : 1
        autoHideMode = mode
        fpsAnimationTimer?.invalidate()
        fpsAnimationTimer = nil
        fpsAnimationTarget = nil
        fpsAvailability.advance(to: ProcessInfo.processInfo.systemUptime)
        autoHidePresentation.setEnabled(mode == .all, visible: fpsAvailability.expanded,
            animated: hudEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        updateLayout()
        updateVisibility()
        if dynamicFPSActive {
            let target = fpsProgress
            fpsProgress = previousFPSProgress
            applyHUDPresentation()
            animateFPS(to: target)
        }
        restorePosition()
    }

    private func applyAutoHidePresentation() {
        let hidden = autoHidePresentation.isHidden
        if lastAutoHideHidden != hidden {
            lastAutoHideHidden = hidden
            updateVisibility()
            onAutoHideVisibilityChange?()
        }
    }

    private func animateAutoHide(visible: Bool) {
        autoHidePresentation.transition(visible: visible,
            animated: hudEnabled && hasVisibleContent && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func setAlignment(_ alignment: HUDAlignment) {
        self.alignment = alignment
        enabledMetrics = HUDPreferences.visibleMetrics
        for (metric, row) in metricRows { row.isHidden = !enabledMetrics.contains(metric) }
        updateLayout()
        restorePosition()
        updateVisibility()
    }

    // MARK: - Metric Visibility

    func setFanOptions(_ options: HUDFanOptions) {
        fanOptions = options
        setMetricEnabled(.fans, enabled: options.enabled && alignment.allows(.fans))
    }

    func updateFans(_ sample: FanSample) {
        let previousRows = fanView.rowCount
        fanSample = sample
        fanView.update(sample: sample, options: fanOptions, scale: hudScale, background: textBackground)
        // RPM changes only redraw the existing view; do not restart capture.
        if alignment == .horizontal { refreshHorizontalReadings() }
        else if fanView.rowCount != previousRows { updateLayout() }
    }

    func setPackagePowerOptions(_ options: HUDPackagePowerOptions) {
        packageOptions = options
        updateLayout()
        updateVisibility()
    }

    func setResourceOptions(_ options: HUDResourceOptions, for group: HUDResourceGroup) {
        highlightedReadings[group.totalMetric] = options.highlighted
        if let appMetric = group.appMetric {
            highlightedReadings[appMetric] = options.highlighted.contains(.focusedApp) ? [.totalUse] : []
        }
        if group == .ram {
            showsRAMDetails = options.showsDetails
            for metric in [HUDMetric.ram, .ramTotal] {
                if options.usageVisible { hiddenUtilizationMetrics.remove(metric) }
                else { hiddenUtilizationMetrics.insert(metric) }
                valueLabels[metric]?.isHidden = !options.usageVisible
            }
        }
        if let appMetric = group.appMetric { enabledMetrics.remove(appMetric) }
        enabledMetrics.remove(group.totalMetric)
        enabledMetrics.formUnion(options.visibleMetrics(for: group))
        for metric in [group.appMetric, group.totalMetric].compactMap({ $0 }) {
            metricRows[metric]?.isHidden = !enabledMetrics.contains(metric)
        }
        if group.supportsPower {
            let showPower = options.enabled && options.power
            if showPower { powerMetrics.insert(group.totalMetric) }
            else { powerMetrics.remove(group.totalMetric); powerLabels[group.totalMetric]?.stringValue = "" }
            powerLabels[group.totalMetric]?.isHidden = !showPower
            let showTemperature = group.supportsTemperature && options.enabled && options.temperature
            if showTemperature { temperatureMetrics.insert(group.totalMetric) }
            else { temperatureMetrics.remove(group.totalMetric); temperatureLabels[group.totalMetric]?.stringValue = "" }
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
                temperatureLabels[metric]?.stringValue = "\(Int(value.rounded()))°C"
            } else {
                temperatureLabels[metric]?.stringValue = ""
            }
        }
    }

    func updatePower(_ sample: PowerSample) {
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
        fpsValueHighlighted = options.valueHighlighted
        if enabledMetrics.intersection([.fps, .fpsGraph]) == visible {
            // A text-only change preserves FPS history, animation and capture.
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
        // Apply the pair together, avoiding an intermediate capture resize.
        updateLayout()
        updateVisibility()
    }

    func setMetricEnabled(
        _ metric: HUDMetric,
        enabled: Bool
    ) {

        if enabled {

            enabledMetrics.insert(
                metric
            )

        } else {

            enabledMetrics.remove(
                metric
            )
        }

        metricRows[metric]?
            .isHidden =
                !enabled

        if metric == .fpsGraph && !enabled { fpsGraphView.reset() }

        updateLayout()
        updateVisibility()
    }

    private func updateVisibility() {

        if hudEnabled && hasVisibleContent && !autoHidePresentation.isHidden {

            restorePosition()

            if !panel.isVisible, hudBackground != .off, let glass = customGlass {
                // Keep a WindowServer-visible window for capture discovery, but
                // do not show its contents before the first usable frame.
                glassRevealGate.begin(hasFrame: !glass.isShowingFallback,
                                      needsAttention: glass.captureState.needsAttention)
            }
            panel.orderFrontRegardless()
            panel.startModifierTracking()
            updateCaptureLifecycle()

        } else {

            panel.stopModifierTracking()
            panel.orderOut(nil)
            stopCapture()
        }
    }

    // MARK: - HUD Scale

    func setHUDScale(
        _ scale: HUDScale
    ) {

        guard scale != hudScale else {
            return
        }

        hudScale =
            scale

        fpsGraphView.applyStyle(scale: scale, background: textBackground)
        batteryIndicator.applyStyle(scale: scale, background: textBackground)
        updateReadingAppearance()

        for label in deviceInfoLabels { label.font = HUDStyle.smallLabelFont(scale: scale) }
        ramSwapTitleLabel?.font = HUDStyle.smallLabelFont(scale: scale)
        ramSwapValueLabel?.font = ramDetailsFont
        ramPressureValueLabel?.font = ramDetailsFont
        for constraint in ramDetailGroupSpacingConstraints.values {
            constraint.constant = 0
        }

        // Update fonts and row constraints.

        for metric in HUDMetric.allCases {
            primaryLabelHeightConstraints[metric]?.constant = HUDStyle.primaryLabelHeight(for: metric, scale: scale)
            ramDetailLabels[metric]?.font = ramDetailsFont
            ramDetailTitleLabels[metric]?.font = HUDStyle.smallLabelFont(scale: scale)

            titleLabels[metric]?
                .font =
                    HUDStyle.titleFont(
                        for: metric,
                        scale: scale
                    )

            valueLabels[metric]?
                .font =
                    HUDStyle.valueFont(
                        for: metric,
                        scale: scale
                    )


            rowHeightConstraints[metric]?
                .constant =
                    metricRowHeight(metric, scale: scale)

            valueSpacingConstraints[metric]?
                .constant =
                    HUDStyle.metricColumnSpacing(
                        scale: scale
                    )

            valueColumnConstraints[metric]?
                .constant =
                    HUDStyle.valueColumnRight(
                        scale: scale
                    )
        }

        // Update stack spacing.

        stackView.spacing =
            HUDStyle.rowSpacing(
                scale: scale
            )

        stackLeadingConstraint?
            .constant =
                HUDStyle.horizontalPadding(scale: scale)

        stackTrailingConstraint?
            .constant =
                -HUDStyle.horizontalPadding(scale: scale)

        stackTopConstraint?
            .constant =
                HUDStyle.verticalPadding(scale: scale)

        updateLayout()
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
        updateCaptureLifecycle()
    }

    private func applyBackgroundAppearance() {
        if hudBackground == .off { stopCapture() }
        backgroundView.isHidden = hudBackground == .off
        switch hudBackground {
        case .light: container.appearance = NSAppearance(named: .aqua)
        case .transparent, .dark, .off, .system: container.appearance = NSAppearance(named: .darkAqua)
        }
        if let customGlass {
            switch hudBackground {
            case .transparent: customGlass.style = .transparent
            case .light: customGlass.style = .light
            case .dark, .off, .system: customGlass.style = .dark
            }
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            switch hudBackground {
            case .light: backgroundView.layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
            case .transparent, .dark, .system: backgroundView.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
            case .off: backgroundView.layer?.borderColor = NSColor.clear.cgColor
            }
            backgroundView.layer?.borderWidth = 0.5
            CATransaction.commit()
        }
        panel.hasShadow = false
        if stackView.superview != nil { attachStackView() }
    }

    var onCaptureStateChange: ((HUDGlassCaptureState) -> Void)?
    var captureState: HUDGlassCaptureState { customGlass?.captureState ?? .off }

    func retryBackground() {
        guard panel.isVisible, hudEnabled, hasVisibleContent, hudBackground != .off else { return }
        customGlass?.retry()
    }

    // MARK: - Captured Glass Lifecycle

    private func setGlassRevealOpacity(_ opacity: Float) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        windowContentView.layer?.opacity = opacity
        CATransaction.commit()
    }

    private func updateGlassRevealReadiness() {
        guard let glass = customGlass else { return }
        glassRevealGate.update(hasFrame: !glass.isShowingFallback,
                               needsAttention: glass.captureState.needsAttention)
    }

    private func updateCaptureLifecycle() {
        if panel.isVisible && hudEnabled && hasVisibleContent && hudBackground != .off {
            customGlass?.start()
        } else {
            stopCapture()
        }
    }

    private func stopCapture() {
        glassRevealGate.finish(cancelled: true)
        captureRefreshTask?.cancel()
        captureRefreshTask = nil
        customGlass?.stop()
    }

    private func scheduleCaptureRefresh() {
        guard customGlass != nil else { return }
        customGlass?.prepareForGeometryChange()
        captureRefreshTask?.cancel()
        captureRefreshTask = Task { [weak self] in
            // Coalesce resize/move notifications; never restart capture for metric values.
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            guard let self, panel.isVisible, hudEnabled,
                  hasVisibleContent, hudBackground != .off else { return }
            windowContentView.layoutSubtreeIfNeeded()
            customGlass?.refreshGeometry()
            captureRefreshTask = nil
        }
    }

    func shutdown() {
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
        panel.orderOut(nil)
        stopCapture()
    }

    // MARK: - Text Appearance

    private func readingFont(for metric: HUDMetric, kind: HUDReadingKind) -> NSFont {
        metric == .fps ? HUDStyle.fpsValueFont(scale: hudScale, highlighted: fpsValueHighlighted)
            : HUDStyle.readingFont(scale: hudScale, highlighted: highlightedReadings[metric, default: []].contains(kind))
    }

    private func readingColor(for metric: HUDMetric, kind: HUDReadingKind) -> NSColor {
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

    private func updateReadingAppearance() {
        let detailValues = Array(ramDetailLabels.values)
            + [ramSwapValueLabel, ramPressureValueLabel].compactMap { $0 }
        for label in detailValues { label.font = ramDetailsFont }
        let detailTitles = Array(ramDetailTitleLabels.values)
            + [ramSwapTitleLabel, ramPressureTitleLabel].compactMap { $0 }
        for label in detailTitles { label.font = HUDStyle.smallLabelFont(scale: hudScale) }

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
        packageTitleLabel?.font = HUDStyle.titleFont(for: .gpuTotal, scale: hudScale)
        packageTitleLabel?.textColor = HUDStyle.primaryTitleColor(for: .gpuTotal, background: textBackground)
        packageValueLabel?.font = HUDStyle.readingFont(scale: hudScale, highlighted: packageOptions.highlighted)
        packageValueLabel?.textColor = HUDStyle.readingColor(background: textBackground)
    }

    private func updateMetricColors() {
        collapsedFPSIndicator.contentTintColor = HUDStyle.titleColor(for: .deviceInfo, background: textBackground)
        fanView.update(sample: fanSample, options: fanOptions, scale: hudScale, background: textBackground)
        defer { updateReadingAppearance(); refreshHorizontalReadings() }
        fpsGraphView.applyStyle(scale: hudScale, background: textBackground)
        batteryIndicator.applyStyle(scale: hudScale, background: textBackground)
        for label in deviceInfoLabels {
            label.textColor = HUDStyle.TextStyle.label.color(background: textBackground)
        }
        ramSwapTitleLabel?.textColor = HUDStyle.TextStyle.label.color(background: textBackground)
        ramPressureTitleLabel?.textColor = HUDStyle.TextStyle.label.color(background: textBackground)
        ramSwapValueLabel?.textColor = HUDStyle.readingColor(background: textBackground)
        ramPressureValueLabel?.textColor = HUDStyle.readingColor(background: textBackground)

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
            let gap = HUDStyle.metricColumnSpacing(scale: hudScale)
            var trailing = readingColumnRight - (valueLabels[metric]?.alignmentRectInsets.right ?? 0)
            if hasUsage { trailing -= usage.intrinsicContentSize.width + gap }
            temperatureTrailingConstraints[metric]?.constant = trailing
            if hasTemperature { trailing -= temperature.intrinsicContentSize.width + gap }
            powerTrailingConstraints[metric]?.constant = trailing
        }

        let cpuPowerRight = powerTrailingConstraints[.cpuTotal]?.constant ?? readingColumnRight
        powerTrailingConstraints[.aneTotal]?.constant = cpuPowerRight
        packageTrailingConstraint?.constant = cpuPowerRight

        batteryIndicator.alignTemperature(trailingInset: batteryTemperatureTrailingInset)
    }

    // Use the same reserved column in both layouts, independent of window width.
    private var batteryTemperatureTrailingInset: CGFloat? {
        guard let reference = [HUDMetric.gpuTotal, .cpuTotal].first(where: {
            enabledMetrics.contains($0) && temperatureMetrics.contains($0) && !hiddenUtilizationMetrics.contains($0)
        }) else { return nil }
        let usage = NSTextField(labelWithString: "100%")
        usage.font = readingFont(for: reference, kind: .totalUse)
        return usage.intrinsicContentSize.width + HUDStyle.metricColumnSpacing(scale: hudScale)
            + (valueLabels[reference]?.alignmentRectInsets.right ?? 0)
    }

    private func refreshHorizontalReadings(forceLayout: Bool = false) {
        guard alignment == .horizontal else { return }
        horizontalView.battery.alignTemperature(trailingInset: batteryTemperatureTrailingInset)
        var sections: [[HUDHorizontalView.Reading]] = []
        for metrics in metricGroups {
            var readings: [HUDHorizontalView.Reading] = []
            for metric in metrics {
                if metric == .fans, enabledMetrics.contains(.fans) {
                    readings.append(contentsOf: horizontalFanReadings())
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
                let resourceGroup = HUDResourceGroup.allCases.first { $0.totalMetric == metric || $0.appMetric == metric }
                func append(_ field: NSTextField?, role: String, reference: String, title: Bool = false) {
                    guard let field, let font = field.font, let color = field.textColor else { return }
                    readings.append(.init(id: "\(metric.rawValue).\(role)", text: field.stringValue,
                        reference: reference, font: font, color: color, help: field.toolTip, startsMetric: title,
                        resourceGroup: resourceGroup, metric: metric,
                        sizingFont: metric == .fps && !title ? HUDStyle.fpsValueFont(scale: hudScale, highlighted: true) : nil))
                }
                append(title, role: "title", reference: metric.hudTitle, title: true)
                if powerMetrics.contains(metric) { append(powerLabels[metric], role: "power", reference: "999.9 W") }
                if temperatureMetrics.contains(metric) { append(temperatureLabels[metric], role: "temperature", reference: "149°C") }
                if metric != .ramTotal && !hiddenUtilizationMetrics.contains(metric) {
                    // App CPU can use multiple cores (>100%). Reserve its hardware
                    // limit so adding a digit cannot resize/restart glass capture.
                    let reference = metric == .fps ? "9999" : metric == .cpu
                        ? "\(ProcessInfo.processInfo.activeProcessorCount * 100)%" : "100%"
                    append(valueLabels[metric], role: "value", reference: reference)
                }
                if showsRAMDetails && (metric == .ram || metric == .ramTotal) {
                    func appendDetail(_ abbreviation: String, value: String, reference: String, help: String) {
                        for (role, text, sizing) in [("title", abbreviation, abbreviation), ("value", value, reference)] {
                            readings.append(.init(id: "\(metric.rawValue).\(abbreviation).\(role)", text: text, reference: sizing,
                                font: role == "value" ? ramDetailsFont : HUDStyle.smallLabelFont(scale: hudScale),
                                color: (role == "value" ? HUDStyle.TextStyle.reading : .label).color(background: textBackground),
                                help: help, startsMetric: false, resourceGroup: .ram, metric: metric,
                                tightLeading: role == "value", leftAligned: true))
                        }
                    }
                    appendDetail("PHY", value: ramDetailLabels[metric]?.stringValue ?? "", reference: "999.99 GB",
                                 help: metric == .ram ? "Physical memory used by the focused app’s tracked process." : "System physical memory used.")
                    if metric == .ramTotal {
                        let pressure = ramPressureValueLabel?.stringValue ?? ""
                        let showsPressureSymbol = pressure == "warning" || pressure == "critical"
                        let swapValue = ramSwapValueLabel?.stringValue ?? ""
                        appendDetail("SWP", value: swapValue, reference: "999.99 GB", help: "System swap used.")
                        // Keep the pressure slot even when normal, so state changes
                        // cannot move RAM usage or resize the screen-capture region.
                        readings.append(.init(id: "ram.pressure", text: "", reference: "",
                            font: ramDetailsFont, color: HUDStyle.titleColor(for: metric, background: textBackground),
                            help: "Memory pressure: \(pressure).", startsMetric: false, resourceGroup: .ram, metric: metric,
                            symbolName: pressure == "critical" ? "exclamationmark.triangle.fill" : "exclamationmark.triangle",
                            symbolVisible: showsPressureSymbol))
                    }
                }
                if metric == .ramTotal && !hiddenUtilizationMetrics.contains(metric) {
                    append(valueLabels[metric], role: "value", reference: "100%")
                }
            }
            if !readings.isEmpty { sections.append(readings) }
        }
        let size = horizontalView.configure(sections: sections, showsBattery: enabledMetrics.contains(.battery),
                                            scale: hudScale, background: textBackground)
        let horizontalPadding = HUDStyle.horizontalPadding(scale: hudScale)
        let verticalPadding = HUDStyle.verticalPadding(scale: hudScale)
        horizontalView.frame = NSRect(x: horizontalPadding, y: verticalPadding, width: size.width, height: size.height)
        let total = pixelAlignedSize(NSSize(width: size.width + 2 * horizontalPadding,
                                            height: size.height + 2 * verticalPadding))
        // Readings usually fit their reserved width. Avoid touching the window or
        // capture geometry on each sample unless the actual size changes.
        if forceLayout || expandedHUDSize != total {
            resizeHUD(width: total.width, height: total.height)
        } else {
            // Sampling must not undo the presentation offset or restart capture.
            applyHUDPresentation()
        }
        horizontalView.alignFPSVertically(heightRounding: total.height - size.height - 2 * verticalPadding)
    }

    private func horizontalFanReadings() -> [HUDHorizontalView.Reading] {
        let font = HUDStyle.readingFont(scale: hudScale, highlighted: false)
        let color = HUDStyle.titleColor(for: .fans, background: textBackground)
        let fans = fanSample.displayReadings(averaged: fanOptions.averages(in: .horizontal))
        guard !fans.isEmpty else {
            let message = fanSample.message ?? "Fan readings unavailable"
            // Reserve the longest status so detection/retry messages cannot
            // resize the HUD and restart its background capture.
            return [.init(id: "fan.status", text: message,
                          reference: "Fan readings unavailable", font: HUDStyle.smallLabelFont(scale: hudScale),
                          color: HUDStyle.TextStyle.label.color(background: textBackground),
                          help: nil, startsMetric: true, metric: .fans)]
        }
        return fans.flatMap { fan -> [HUDHorizontalView.Reading] in
            var values: [HUDHorizontalView.Reading] = [
                .init(id: "fan.\(fan.id).title", text: fan.title, reference: fan.title,
                      font: HUDStyle.titleFont(for: .fans, scale: hudScale),
                      color: color,
                      help: fan.id == "average" ? "Average fan speed" : fan.title,
                      startsMetric: true, metric: .fans, fanMarker: fan.iconMarker)
            ]
            if fanOptions.usage {
                if fanOptions.mode.showsBar {
                    values.append(.init(id: "fan.\(fan.id).bar", text: "", reference: "",
                        font: font, color: color, help: "\(fan.title) speed relative to maximum",
                        startsMetric: false, metric: .fans, barWidth: HUDFanBarView.horizontalSize.width, barFraction: fan.fraction))
                }
                if fanOptions.mode.showsRPM {
                    values.append(.init(id: "fan.\(fan.id).rpm", text: fan.rpmText, reference: "99999 RPM",
                        font: HUDStyle.readingFont(scale: hudScale, highlighted: fanOptions.rpmHighlighted),
                        color: (fanOptions.rpmHighlighted ? HUDStyle.TextStyle.emphasizedReading : .reading).color(background: textBackground),
                        help: nil, startsMetric: false, metric: .fans,
                        sizingFont: HUDStyle.readingFont(scale: hudScale, highlighted: true)))
                }
            }
            return values
        }
    }

    private func metricRowHeight(_ metric: HUDMetric, scale: HUDScale) -> CGFloat {
        if metric == .fans { return fanView.height(scale: scale) }
        if !showsRAMDetails && (metric == .ram || metric == .ramTotal) {
            return HUDStyle.rowHeight(scale: scale)
        }
        return HUDStyle.rowHeight(for: metric, scale: scale)
    }

    private func updateRAMDetailsVisibility() {
        for constraint in ramDetailBottomConstraints.values { constraint.isActive = showsRAMDetails }
        let labels = Array(ramDetailLabels.values) + Array(ramDetailTitleLabels.values)
            + [ramSwapTitleLabel, ramSwapValueLabel, ramPressureTitleLabel, ramPressureValueLabel].compactMap { $0 }
        for label in labels { label.isHidden = !showsRAMDetails }
        for metric in [HUDMetric.ram, .ramTotal] {
            rowHeightConstraints[metric]?.constant = metricRowHeight(metric, scale: hudScale)
        }
    }

    private func updateLayout() {
        // Release the previous width before changing rows/fonts or switching
        // away from a fully collapsed horizontal viewport.
        stackTrailingConstraint?.isActive = false
        customGlass?.hudScale = CGFloat(hudScale.rawValue)
        fpsAnimationTimer?.invalidate()
        fpsAnimationTimer = nil
        // Measure the unchanged expanded stack before applying its presentation crop.
        stackTopConstraint?.constant = HUDStyle.verticalPadding(scale: hudScale)
        for metric in [HUDMetric.fps, .fpsGraph] { metricRows[metric]?.alphaValue = 1 }
        updateReadingAppearance()
        updateRAMDetailsVisibility()
        fanView.update(sample: fanSample, options: fanOptions, scale: hudScale, background: textBackground)
        rowHeightConstraints[.fans]?.constant = fanView.height(scale: hudScale)
        stackView.isHidden = alignment == .horizontal
        horizontalView.isHidden = alignment != .horizontal
        if alignment == .horizontal {
            refreshHorizontalReadings(forceLayout: true)
            return
        }

        packageRow?.isHidden = !showsPackagePower
        packageTitleLabel?.isHidden = !showsPackagePower
        packageValueLabel?.isHidden = !showsPackagePower
        if !showsPackagePower { packageValueLabel?.stringValue = "" }
        let packageHeight = showsPackagePower
            ? (enabledMetrics.isEmpty ? 0 : HUDStyle.rowSpacing(scale: hudScale)) + packageRowHeight : 0
        packageHeightConstraint?.constant = packageRowHeight

        stackLeadingConstraint?.constant = HUDStyle.horizontalPadding(scale: hudScale)
        stackTrailingConstraint?.constant = -HUDStyle.horizontalPadding(scale: hudScale)
        stackTopConstraint?.constant = HUDStyle.verticalPadding(scale: hudScale)
        if let glass = backgroundView as? NSGlassEffectView {
            glass.cornerRadius = 8 * CGFloat(hudScale.rawValue)
            glass.layer?.cornerRadius = glass.cornerRadius
        }

        let dividers = updateDividers()
        let dividerCount = CGFloat(dividers.count)
        // The graph includes its bottom gap so the fade ends close to the divider.
        stackView.setCustomSpacing(0, after: fpsGraphView)
        let graphUsesDividerGap = enabledMetrics.contains(.fpsGraph) && dividerCount > 0

        let visibleCount =
            CGFloat(
                enabledMetrics.count
            )

        let rowHeight = enabledMetrics.reduce(CGFloat.zero) {
            $0 + metricRowHeight($1, scale: hudScale)
        } + packageHeight

        let spacingCount =
            max(
                visibleCount + dividerCount - 1,
                0
            )

        let spacingHeight =
            (spacingCount - (graphUsesDividerGap ? 1 : 0))
            * HUDStyle.rowSpacing(
                scale: hudScale
            )

        let verticalPadding =
            HUDStyle.verticalPadding(scale: hudScale)

        let totalHeight =
            verticalPadding
            + rowHeight
            + dividers.height
            + spacingHeight
            + verticalPadding

        // Keep the compact columns wide enough for the enabled metrics.
        var valueColumnRight =
            HUDStyle.valueColumnRight(scale: hudScale)

        for metric in enabledMetrics {
            guard let titleLabel = titleLabels[metric] else {
                continue
            }

            let sampleValue = NSTextField(
                labelWithString: "100%"
            )
            sampleValue.font = readingFont(for: metric, kind: .totalUse)

            let requiredWidth =
                titleLabel.intrinsicContentSize.width
                + HUDStyle.metricColumnSpacing(scale: hudScale)
                + sampleValue.intrinsicContentSize.width

            valueColumnRight = max(valueColumnRight, requiredWidth)
        }

        if enabledMetrics.contains(.battery) {
            valueColumnRight = max(valueColumnRight, batteryIndicator.minimumRowWidth)
        }

        if enabledMetrics.contains(.deviceInfo) {
            let requiredWidth = deviceInfoLabels.reduce(CGFloat.zero) { $0 + $1.intrinsicContentSize.width }
                + HUDStyle.metricColumnSpacing(scale: hudScale)
            valueColumnRight = max(valueColumnRight, requiredWidth)
        }

        let expandedBaseWidth = HUDStyle.expandedValueColumnRight(valueColumnRight, scale: hudScale)
        for metric in temperatureMetrics.union(powerMetrics).intersection(enabledMetrics) {
            let temperature = NSTextField(labelWithString: "149°C")
            temperature.font = temperatureFont(for: metric)
            let usage = NSTextField(labelWithString: "100%")
            usage.font = readingFont(for: metric, kind: .totalUse)
            let gap = HUDStyle.metricColumnSpacing(scale: hudScale)
            let power = NSTextField(labelWithString: "999.9 W")
            power.font = powerFont(for: metric)
            let titleWidth = max(titleLabels[metric]?.intrinsicContentSize.width ?? 0,
                metric == .cpuTotal && showsPackagePower ? packageTitleLabel?.intrinsicContentSize.width ?? 0 : 0)
            let required = titleWidth
                + (powerMetrics.contains(metric) ? gap + power.intrinsicContentSize.width : 0)
                + (temperatureMetrics.contains(metric) ? gap + temperature.intrinsicContentSize.width : 0)
                + (hiddenUtilizationMetrics.contains(metric) ? 0 : gap + usage.intrinsicContentSize.width)
            valueColumnRight = max(valueColumnRight, required)
        }

        // ANE and Package share CPU's watts column even when their fonts differ.
        // Reserve enough room to the left of that column for their titles/values.
        if enabledMetrics.contains(.aneTotal) && powerMetrics.contains(.aneTotal) || showsPackagePower {
            let gap = HUDStyle.metricColumnSpacing(scale: hudScale)
            func width(_ text: String, _ font: NSFont) -> CGFloat {
                let label = NSTextField(labelWithString: text)
                label.font = font
                return label.intrinsicContentSize.width
            }
            let cpuVisible = enabledMetrics.contains(.cpuTotal)
            let cpuSuffix = cpuVisible
                ? (temperatureMetrics.contains(.cpuTotal) ? gap + width("149°C", temperatureFont(for: .cpuTotal)) : 0)
                    + (hiddenUtilizationMetrics.contains(.cpuTotal) ? 0 : gap + width("100%", readingFont(for: .cpuTotal, kind: .totalUse)))
                : 0
            if enabledMetrics.contains(.aneTotal) && powerMetrics.contains(.aneTotal) {
                valueColumnRight = max(valueColumnRight, (titleLabels[.aneTotal]?.intrinsicContentSize.width ?? 0)
                    + gap + width("999.9 W", powerFont(for: .aneTotal)) + cpuSuffix)
            }
            if showsPackagePower, let font = packageValueLabel?.font {
                valueColumnRight = max(valueColumnRight, (packageTitleLabel?.intrinsicContentSize.width ?? 0)
                    + gap + width("999.9 W", font) + cpuSuffix)
            }
        }

        // Power adds another value column, not another large block of empty space.
        // Retain the normal expanded width, growing only enough to fit the readings.
        if showsPackagePower || !powerMetrics.intersection(enabledMetrics).isEmpty {
            valueColumnRight = max(valueColumnRight, expandedBaseWidth)
        } else {
            valueColumnRight = HUDStyle.expandedValueColumnRight(valueColumnRight, scale: hudScale)
        }

        let fpsOnly = enabledMetrics == [.fps] && !showsPackagePower
        if !fpsOnly {
            // Widen the established label-to-value gap by another 10% (1.188 × 1.10 = 1.3068),
            // keeping spacing within the readings and the outside padding unchanged.
            valueColumnRight = HUDStyle.expandedValueColumnRight(valueColumnRight, scale: hudScale, gapIncrease: 0.3068)
        }
        if fpsOnly {
            valueColumnRight = HUDStyle.compactFPSValueColumnRight(scale: hudScale)
        }

        readingColumnRight = valueColumnRight
        updateReadingPositions()

        for (metric, constraint) in valueColumnConstraints {
            // Match the sample's label frames, accounting for NSTextField alignment insets.
            constraint.constant = valueColumnRight - (valueLabels[metric]?.alignmentRectInsets.right ?? 0)
        }

        let width = max(
            fpsOnly ? 0 : HUDStyle.width(scale: hudScale),
            valueColumnRight + 2 * HUDStyle.horizontalPadding(scale: hudScale)
        )

        resizeHUD(width: width, height: totalHeight)
    }

    private func pixelAlignedSize(_ size: NSSize) -> NSSize {
        let scale = panel.backingScaleFactor
        return NSSize(width: ceil(size.width * scale) / scale, height: ceil(size.height * scale) / scale)
    }

    private func resizeHUD(width proposedWidth: CGFloat, height proposedHeight: CGFloat) {
        resizingHUD = true
        defer { resizingHUD = false }
        // Auto Layout rounds the background to backing pixels. Match that grid
        // so the reserved capture rect cannot drift by a fraction of a point.
        expandedHUDSize = pixelAlignedSize(NSSize(width: proposedWidth, height: proposedHeight))
        let width = expandedHUDSize.width
        let totalHeight = expandedHUDSize.height
        customGlass?.reservedCaptureSize = dynamicFPSActive || autoHidePresentation.enabled ? expandedHUDSize : nil
        let anchor = visibleTopLeft
        let margin = shadowMargin
        panel.setFrame(
            NSRect(x: anchor.x - margin,
                   y: anchor.y - totalHeight - margin,
                   width: width + 2 * margin,
                   height: totalHeight + 2 * margin),
            display: true
        )
        container.frame = NSRect(x: margin, y: margin, width: width, height: totalHeight)
        stackTrailingConstraint?.isActive = alignment == .vertical
        container.layoutSubtreeIfNeeded()

        // The supplied custom view owns its shadow; avoid adding a second one.
        if customGlass == nil {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            container.layer?.shadowColor = NSColor.black.cgColor
            container.layer?.shadowOpacity = hudBackground == .off ? 0 : 0.22
            container.layer?.shadowRadius = 5 * CGFloat(hudScale.rawValue)
            container.layer?.shadowOffset = CGSize(width: 0, height: -2 * CGFloat(hudScale.rawValue))
            container.layer?.shadowPath = hudBackground == .off ? nil : CGPath(
                roundedRect: container.bounds,
                cornerWidth: 8 * CGFloat(hudScale.rawValue),
                cornerHeight: 8 * CGFloat(hudScale.rawValue),
                transform: nil
            )
            CATransaction.commit()
        }
        configureDynamicFPSPresentation()
        scheduleCaptureRefresh()
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
            let expected = NSSize(width: expandedHUDSize.width + 2 * shadowMargin,
                                  height: expandedHUDSize.height + 2 * shadowMargin)
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
        fpsAvailability.advance(to: ProcessInfo.processInfo.systemUptime)
        if dynamicFPSActive && alignment == .horizontal {
            fpsCollapseDistance = max(0, horizontalView.fpsSectionWidth - collapsedFPSHeaderHeight)
        } else if dynamicFPSActive {
            let remaining = enabledMetrics.subtracting([.fps, .fpsGraph])
            if remaining.isEmpty && !showsPackagePower {
                fpsCollapseDistance = max(0, expandedHUDSize.height - collapsedFPSHeaderHeight
                    - 2 * HUDStyle.verticalPadding(scale: hudScale))
            } else {
                // Keep the existing section divider beneath the rolled-up indicator.
                let firstGroup = verticalMetricGroups.indices.dropFirst().first { index in
                    verticalMetricGroups[index].contains { remaining.contains($0) }
                        || (index == 1 && showsPackagePower)
                }
                let divider = firstGroup.flatMap { groupDividers[$0] }
                let firstBody = stackView.arrangedSubviews.first { view in
                    !view.isHidden && view !== metricRows[.fps] && view !== metricRows[.fpsGraph]
                        && !groupDividers.values.contains(where: { $0 === view }) && view !== bottomDivider
                }
                if let first = divider ?? firstBody, let host = stackView.superview {
                    let rect = first.convert(first.bounds, to: host)
                    fpsCollapseDistance = max(0, host.bounds.maxY - rect.maxY - HUDStyle.verticalPadding(scale: hudScale)
                        - collapsedFPSHeaderHeight - HUDStyle.rowSpacing(scale: hudScale))
                }
            }
        }
        fpsProgress = dynamicFPSActive && !fpsAvailability.expanded ? 0 : 1
        applyHUDPresentation()
    }

    private func applyHUDPresentation() {
        let progress = dynamicFPSActive ? fpsProgress : 1
        let scale = panel.backingScaleFactor
        let horizontal = alignment == .horizontal
        let wholeHUD = autoHidePresentation.enabled
        let clipsContent = dynamicFPSActive || wholeHUD
        let reduction = wholeHUD
            ? (horizontal ? expandedHUDSize.width : expandedHUDSize.height) * (1 - autoHidePresentation.progress)
            : fpsCollapseDistance * (1 - progress)
        let height = max(0, (expandedHUDSize.height - (horizontal ? 0 : reduction)) * scale).rounded() / scale
        let width = max(0, (expandedHUDSize.width - (horizontal ? reduction : 0)) * scale).rounded() / scale
        // FPS rolls its rows away; All options keeps the content anchored while
        // the rounded glass edge moves over it, including its rim and shadow.
        let offset = wholeHUD ? 0 : (horizontal ? expandedHUDSize.width - width : expandedHUDSize.height - height)
        let radius = min(customGlass?.glassAppearance.cornerRadius ?? (8 * CGFloat(hudScale.rawValue)), min(width, height) / 2)
        let margin = shadowMargin
        // The top edge, actual window frame, and full capture footprint stay fixed.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = NSRect(x: margin, y: margin + expandedHUDSize.height - height,
                                 width: width, height: height)
        stackTopConstraint?.constant = HUDStyle.verticalPadding(scale: hudScale) - (horizontal ? 0 : offset)
        if horizontal {
            horizontalView.frame.origin.x = HUDStyle.horizontalPadding(scale: hudScale) - offset
            horizontalView.setFPSOpacity(progress)
        }
        backgroundContentView.wantsLayer = true
        for metric in [HUDMetric.fps, .fpsGraph] { metricRows[metric]?.alphaValue = progress }
        // A quiet arrow points toward the space where FPS will return. Cross-fade
        // it near the end of collapse so it does not overlap the regular FPS row.
        collapsedFPSIndicator.image = NSImage(systemSymbolName: horizontal ? "arrow.right" : "arrow.down",
            accessibilityDescription: "FPS enabled; collapsed while waiting for readings")
        collapsedFPSIndicator.isHidden = !dynamicFPSActive || progress >= 0.4
        let headerFade = min(1, max(0, 1 - progress / 0.4))
        collapsedFPSIndicator.alphaValue = headerFade * headerFade * (3 - 2 * headerFade)
        collapsedFPSIndicator.contentTintColor = HUDStyle.titleColor(for: .deviceInfo, background: textBackground)
        let indicatorSize = 12 * CGFloat(hudScale.rawValue)
        collapsedFPSIndicator.frame = NSRect(
            x: horizontal ? HUDStyle.horizontalPadding(scale: hudScale) + (collapsedFPSHeaderHeight - indicatorSize) / 2
                : (width - indicatorSize) / 2,
            y: horizontal ? (height - indicatorSize) / 2
                : height - HUDStyle.verticalPadding(scale: hudScale) - (collapsedFPSHeaderHeight + indicatorSize) / 2,
            width: indicatorSize, height: indicatorSize)
        container.alphaValue = height < 1 || width < 1 ? 0 : 1
        panel.draggableContentRect = clipsContent ? container.frame : nil
        container.layoutSubtreeIfNeeded()
        // Apply after layout so the mask uses this animation frame's bounds.
        HUDCornerShape.applyMask(to: backgroundContentView.layer, radius: clipsContent ? radius : nil)
        HUDCornerShape.applyMask(to: container.layer, radius: hudBackground == .off && clipsContent ? radius : nil)
        customGlass?.updateVisibleSurface()
        CATransaction.commit()
        applyAutoHidePresentation()
    }

    private func animateFPS(to target: CGFloat) {
        if fpsAnimationTimer != nil && fpsAnimationTarget == target { return }
        fpsAnimationTarget = target
        fpsAnimationTimer?.invalidate()
        fpsAnimationTimer = nil
        guard dynamicFPSActive, fpsProgress != target, !glassRevealGate.isWaiting else { return }
        guard hudEnabled, panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
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
        // Do not restart an in-flight expansion for each arriving sample.
        if autoHidePresentation.enabled { animateAutoHide(visible: true) }
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
            if !fpsAvailability.expanded {
                if autoHidePresentation.enabled { animateAutoHide(visible: false) }
                else { animateFPS(to: 0) }
            }
        }
    }

    private var shadowMargin: CGFloat {
        Self.backgroundPreset == .customGlass ? 24 : 16 * CGFloat(hudScale.rawValue)
    }

    private var visibleTopLeft: NSPoint {
        NSPoint(x: panel.frame.minX + container.frame.minX,
                y: panel.frame.minY + container.frame.maxY)
    }

    // MARK: - Screen Position

    func resetPosition() {
        customTopLeft = nil
        HUDPreferences.hudPosition = nil
        restorePosition()
    }

    private func restorePosition() {
        let positioningSize = dynamicFPSActive || autoHidePresentation.enabled ? expandedHUDSize : container.frame.size
        defer { scheduleCaptureRefresh() }
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
                                        y: contentOrigin.y - shadowMargin))
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
            - positioningSize.height
            - inset
            - shadowMargin

        panel.setFrameOrigin(
            NSPoint(
                x: x,
                y: y
            )
        )
    }

    func updateBattery(_ sample: BatterySample?) {
        horizontalView.battery.update(percentage: sample?.percentage, source: sample?.source, temperature: sample?.temperature)
        batteryIndicator.update(percentage: sample?.percentage, source: sample?.source, temperature: sample?.temperature)
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
        defer { refreshHorizontalReadings() }

        if metric == .battery {
            if value.isEmpty { updateBattery(nil) }
            return
        }
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
        refreshHorizontalReadings()
    }

    func updateRAM(_ metric: HUDMetric, usage: RAMUsageSample?) {
        guard metric == .ram || metric == .ramTotal else { return }
        defer { refreshHorizontalReadings() }
        valueLabels[metric]?.stringValue = usage.map { "\(Int($0.percentage.rounded()))%" } ?? ""
        ramDetailLabels[metric]?.stringValue = usage?.gigabytesText ?? ""
        if metric == .ramTotal { ramSwapValueLabel?.stringValue = usage?.swapGigabytesText ?? "" }
    }

    // MARK: - FPS

    func updateFPS(
        _ fps: Double
    ) {

        guard
            fps.isFinite, fps >= 0, fps < Double(Int.max)
        else {

            markFPSUnavailable()

            return
        }

        fpsBecameAvailable()
        updateMetric(
            .fps,
            value:
                String(
                    Int(
                        fps.rounded()
                    )
                )
        )
        if hudEnabled && enabledMetrics.contains(.fpsGraph) {
            fpsGraphView.append(fps)
        }
    }

    func markFPSUnavailable() {
        fpsBecameUnavailable()
        updateMetric(.fps, value: "")
        if hudEnabled && enabledMetrics.contains(.fpsGraph) {
            fpsGraphView.markUnavailable()
        }
    }

    func resetFPS() {
        fpsBecameUnavailable()

        fpsGraphView.reset()

        updateMetric(
            .fps,
            value: ""
        )
    }
}

// The sample uses a quiet 0.5pt line, with 4.5pt of space below it before stack spacing.
@MainActor
private final class HUDSampleDividerView: NSView {
    private let line = NSView()
    private var hudScale: CGFloat = 1
    private var connectsToHistory = false
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        line.wantsLayer = true
        addSubview(line)
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    func applyStyle(scale: HUDScale, background: HUDBackground, connectsToHistory: Bool = false) {
        hudScale = CGFloat(scale.rawValue)
        self.connectsToHistory = connectsToHistory
        line.layer?.backgroundColor = HUDStyle.separatorColor(background: background).cgColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        line.frame = NSRect(x: 0, y: connectsToHistory ? 0 : bounds.height - 5 * hudScale,
                            width: bounds.width, height: 0.5 * hudScale)
    }
}
