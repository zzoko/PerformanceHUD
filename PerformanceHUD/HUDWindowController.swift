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
    private var fanSample = FanSample.checking
    private var alignment = HUDPreferences.alignment
    private var ramDetailTitleLabels: [HUDMetric: NSTextField] = [:]
    private var ramSwapTitleLabel: NSTextField?
    private var ramSwapValueLabel: NSTextField?
    private var ramPressureTitleLabel: NSTextField?
    private var ramPressureValueLabel: NSTextField?
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

    private var customGlass: PerformanceHUDGlassBackground? {
        backgroundView as? PerformanceHUDGlassBackground
    }

    private var textBackground: HUDBackground {
        // Light-mode text needs a temporary light foreground over the dark placeholder.
        hudBackground == .light && customGlass?.isShowingFallback == true ? .dark : hudBackground
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        for observer in geometryObservers { NotificationCenter.default.removeObserver(observer) }
        captureRefreshTask?.cancel()
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

        container =
            NSView(
                frame: .zero
            )

        stackView =
            NSStackView()

        configureWindow()
        configureContainer()
        configureStackView()
        createMetricRows()

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
                MainActor.assumeIsolated { self?.scheduleCaptureRefresh() }
            })
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restorePosition() }
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

        NSLayoutConstraint.activate([
            leading,
            trailing,
            top
        ])
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

            // Match the horizontal FPS baseline without changing the row's height.
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
            temperature.textColor = HUDStyle.titleColor(for: metric, background: textBackground)
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
            power.textColor = HUDStyle.titleColor(for: metric, background: textBackground)
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
            detailLabel.textColor = HUDStyle.titleColor(for: metric, background: textBackground)
            detailLabel.alignment = .right
            detailLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(detailLabel)
            let detailTop = detailLabel.topAnchor.constraint(
                equalTo: valueLabel.bottomAnchor,
                constant: HUDStyle.rowSpacing(scale: hudScale))
            ramDetailGroupSpacingConstraints[metric] = detailTop
            NSLayoutConstraint.activate([
                detailTop,
                detailLabel.trailingAnchor.constraint(equalTo: valueLabel.trailingAnchor),
                detailLabel.leadingAnchor.constraint(greaterThanOrEqualTo: row.leadingAnchor)
            ])
            ramDetailLabels[metric] = detailLabel

            if metric == .ramTotal {
                let physicalLabel = NSTextField(labelWithString: "Physical")
                let swapTitle = NSTextField(labelWithString: "Swap")
                let swapValue = NSTextField(labelWithString: "")
                let pressureTitle = NSTextField(labelWithString: "Pressure")
                let pressureValue = NSTextField(labelWithString: "")
                swapValue.alignment = .right
                pressureValue.alignment = .right
                for label in [physicalLabel, swapTitle, swapValue, pressureTitle, pressureValue] {
                    label.font = detailLabel.font
                    label.textColor = detailLabel.textColor
                    label.translatesAutoresizingMaskIntoConstraints = false
                    row.addSubview(label)
                }
                let bottom = pressureValue.bottomAnchor.constraint(equalTo: row.bottomAnchor)
                ramDetailBottomConstraints[metric] = bottom
                NSLayoutConstraint.activate([
                    physicalLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                    physicalLabel.topAnchor.constraint(equalTo: detailLabel.topAnchor),
                    physicalLabel.bottomAnchor.constraint(equalTo: detailLabel.bottomAnchor),
                    physicalLabel.trailingAnchor.constraint(lessThanOrEqualTo: detailLabel.leadingAnchor),
                    swapValue.topAnchor.constraint(equalTo: detailLabel.bottomAnchor),
                    swapValue.heightAnchor.constraint(equalTo: detailLabel.heightAnchor),
                    swapValue.trailingAnchor.constraint(equalTo: valueLabel.trailingAnchor),
                    swapTitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                    swapTitle.topAnchor.constraint(equalTo: swapValue.topAnchor),
                    swapTitle.bottomAnchor.constraint(equalTo: swapValue.bottomAnchor),
                    swapTitle.trailingAnchor.constraint(lessThanOrEqualTo: swapValue.leadingAnchor),
                    pressureValue.topAnchor.constraint(equalTo: swapValue.bottomAnchor),
                    pressureValue.heightAnchor.constraint(equalTo: detailLabel.heightAnchor),
                    bottom,
                    pressureValue.trailingAnchor.constraint(equalTo: valueLabel.trailingAnchor),
                    pressureTitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                    pressureTitle.topAnchor.constraint(equalTo: pressureValue.topAnchor),
                    pressureTitle.bottomAnchor.constraint(equalTo: pressureValue.bottomAnchor),
                    pressureTitle.trailingAnchor.constraint(lessThanOrEqualTo: pressureValue.leadingAnchor)
                ])
                ramDetailTitleLabels[metric] = physicalLabel
                ramSwapTitleLabel = swapTitle
                ramSwapValueLabel = swapValue
                ramPressureTitleLabel = pressureTitle
                ramPressureValueLabel = pressureValue
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
            label.textColor = HUDStyle.titleColor(for: .cpuTotal, background: textBackground)
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
            label.font = HUDStyle.ramDetailFont(scale: hudScale)
            label.textColor = HUDStyle.titleColor(for: .deviceInfo, background: textBackground)
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

        updateVisibility()
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

        if hudEnabled &&
            hasVisibleContent {

            restorePosition()

            panel.orderFrontRegardless()
            panel.startModifierTracking()
            updateCaptureLifecycle()

        } else {

            stopCapture()
            panel.stopModifierTracking()
            panel.orderOut(
                nil
            )
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

        for label in deviceInfoLabels { label.font = HUDStyle.ramDetailFont(scale: scale) }
        ramSwapTitleLabel?.font = HUDStyle.ramDetailFont(scale: scale)
        ramSwapValueLabel?.font = ramDetailsFont
        ramPressureTitleLabel?.font = HUDStyle.ramDetailFont(scale: scale)
        ramPressureValueLabel?.font = ramDetailsFont
        for constraint in ramDetailGroupSpacingConstraints.values {
            constraint.constant = HUDStyle.rowSpacing(scale: scale)
        }

        // Update fonts and row constraints.

        for metric in HUDMetric.allCases {
            primaryLabelHeightConstraints[metric]?.constant = HUDStyle.primaryLabelHeight(for: metric, scale: scale)
            ramDetailLabels[metric]?.font = ramDetailsFont
            ramDetailTitleLabels[metric]?.font = HUDStyle.ramDetailFont(scale: scale)

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

    var onCaptureStateChange: ((HUDGlassCaptureState) -> Void)? {
        didSet { customGlass?.onCaptureStateChange = onCaptureStateChange }
    }
    var captureState: HUDGlassCaptureState { customGlass?.captureState ?? .off }

    func retryBackground() {
        guard panel.isVisible, hudEnabled, hasVisibleContent, hudBackground != .off else { return }
        customGlass?.retry()
    }

    // MARK: - Captured Glass Lifecycle

    private func updateCaptureLifecycle() {
        if panel.isVisible && hudEnabled && hasVisibleContent && hudBackground != .off {
            customGlass?.start()
        } else {
            stopCapture()
        }
    }

    private func stopCapture() {
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
        appearanceObservation?.invalidate()
        appearanceObservation = nil
        fpsGraphView.reset()
        panel.stopModifierTracking()
        stopCapture()
        panel.orderOut(nil)
    }

    // MARK: - Text Appearance

    private func readingFont(for metric: HUDMetric, kind: HUDReadingKind) -> NSFont {
        metric == .fps ? HUDStyle.valueFont(for: metric, scale: hudScale)
            : HUDStyle.readingFont(scale: hudScale, highlighted: highlightedReadings[metric, default: []].contains(kind))
    }

    private func readingColor(for metric: HUDMetric, kind: HUDReadingKind) -> NSColor {
        metric == .fps
            ? HUDStyle.valueColor(background: textBackground)
            : HUDStyle.titleColor(for: metric, background: textBackground)
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
        for label in detailTitles { label.font = HUDStyle.ramDetailFont(scale: hudScale) }

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
        packageValueLabel?.textColor = HUDStyle.titleColor(for: .cpuTotal, background: textBackground)
    }

    private func updateMetricColors() {
        fanView.update(sample: fanSample, options: fanOptions, scale: hudScale, background: textBackground)
        defer { updateReadingAppearance(); refreshHorizontalReadings() }
        fpsGraphView.applyStyle(scale: hudScale, background: textBackground)
        batteryIndicator.applyStyle(scale: hudScale, background: textBackground)
        for label in deviceInfoLabels {
            label.textColor = HUDStyle.titleColor(for: .deviceInfo, background: textBackground)
        }
        ramSwapTitleLabel?.textColor = HUDStyle.titleColor(for: .ramTotal, background: textBackground)
        ramSwapValueLabel?.textColor = HUDStyle.titleColor(for: .ramTotal, background: textBackground)
        ramPressureTitleLabel?.textColor = HUDStyle.titleColor(for: .ramTotal, background: textBackground)
        ramPressureValueLabel?.textColor = HUDStyle.titleColor(for: .ramTotal, background: textBackground)

        for metric in HUDMetric.allCases {

            ramDetailLabels[metric]?.textColor = HUDStyle.titleColor(for: metric, background: textBackground)
            ramDetailTitleLabels[metric]?.textColor = HUDStyle.titleColor(for: metric, background: textBackground)

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

    private func refreshHorizontalReadings() {
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
                        resourceGroup: resourceGroup, metric: metric))
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
                                font: role == "value" ? ramDetailsFont : HUDStyle.ramDetailFont(scale: hudScale),
                                color: HUDStyle.titleColor(for: metric, background: textBackground),
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
        let total = NSSize(width: size.width + 2 * horizontalPadding, height: size.height + 2 * verticalPadding)
        // Readings usually fit their reserved width. Avoid touching the window or
        // capture geometry on each sample unless the actual size changes.
        if container.frame.size != total { resizeHUD(width: total.width, height: total.height) }
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
                          reference: "Fan readings unavailable", font: font, color: color,
                          help: nil, startsMetric: true, metric: .fans)]
        }
        return fans.flatMap { fan -> [HUDHorizontalView.Reading] in
            var values: [HUDHorizontalView.Reading] = [
                .init(id: "fan.\(fan.id).title", text: fan.title, reference: fan.title,
                      font: HUDStyle.titleFont(for: .fans, scale: hudScale),
                      color: HUDStyle.primaryTitleColor(for: .fans, background: textBackground),
                      help: nil, startsMetric: true, metric: .fans)
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
                        color: color, help: nil, startsMetric: false, metric: .fans,
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
        updateReadingAppearance()
        updateRAMDetailsVisibility()
        fanView.update(sample: fanSample, options: fanOptions, scale: hudScale, background: textBackground)
        rowHeightConstraints[.fans]?.constant = fanView.height(scale: hudScale)
        stackView.isHidden = alignment == .horizontal
        horizontalView.isHidden = alignment != .horizontal
        if alignment == .horizontal {
            refreshHorizontalReadings()
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

    private func resizeHUD(width: CGFloat, height totalHeight: CGFloat) {
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
        scheduleCaptureRefresh()
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
        defer { scheduleCaptureRefresh() }
        if let customTopLeft, !NSScreen.screens.isEmpty {
            // Choose the nearest remaining display if the saved display was disconnected.
            let screen = NSScreen.screens.min { left, right in
                HUDPositioning.distanceSquared(from: customTopLeft, to: left.frame)
                    < HUDPositioning.distanceSquared(from: customTopLeft, to: right.frame)
            }!
            let contentOrigin = HUDPositioning.origin(
                for: customTopLeft,
                size: container.frame.size,
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
            - container.frame.height
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
            fps.isFinite
        else {

            markFPSUnavailable()

            return
        }

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
        updateMetric(.fps, value: "")
        if hudEnabled && enabledMetrics.contains(.fpsGraph) {
            fpsGraphView.markUnavailable()
        }
    }

    func resetFPS() {

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
