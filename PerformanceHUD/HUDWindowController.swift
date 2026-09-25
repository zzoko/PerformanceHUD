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
    private var hudBackground = HUDPreferences.background

    // MARK: - Metric Views

    private var metricRows:
        [HUDMetric: NSView] = [:]

    private var titleLabels:
        [HUDMetric: NSTextField] = [:]

    private var valueLabels:
        [HUDMetric: NSTextField] = [:]

    private let metricGroups: [[HUDMetric]] = [
        [.fps, .fpsGraph],
        [.gpu, .gpuTotal, .cpu, .cpuTotal, .ram, .ramTotal],
        [.battery],
        [.deviceInfo]
    ]


    private var groupDividers: [Int: NSView] = [:]
    private var dividerHeightConstraints: [Int: NSLayoutConstraint] = [:]

    private var bottomDivider: NSView?
    private var bottomDividerHeightConstraint: NSLayoutConstraint?

    private var ramDetailLabels: [HUDMetric: NSTextField] = [:]
    private var ramDetailGroupSpacingConstraints: [HUDMetric: NSLayoutConstraint] = [:]
    private let fpsGraphView = HUDFPSGraphView()
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
    private var packageTitleLabel: NSTextField?
    private var packageValueLabel: NSTextField?
    private var packageTopConstraint: NSLayoutConstraint?
    private var showsPackagePower: Bool {
        [.cpuTotal, .gpuTotal].allSatisfy { powerMetrics.contains($0) && enabledMetrics.contains($0) }
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

        for (index, metrics) in metricGroups.enumerated() {
            if index > 0 {
                let divider = createDivider()
                groupDividers[index] = divider.view
                dividerHeightConstraints[index] = divider.height
            }

            for metric in metrics {
                let row = createRow(for: metric)
                metricRows[metric] = row
                stackView.addArrangedSubview(row)
                if metric == .fpsGraph || metric == .battery {
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

        for (index, metrics) in metricGroups.enumerated() {
            let groupIsVisible = metrics.contains { enabledMetrics.contains($0) }
            let showDivider = groupIsVisible && (lastVisibleGroup != nil || metrics == [.deviceInfo])
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

        let showBottomDivider = hudBackground == .off
            && !enabledMetrics.isEmpty && visibleDividerCount == 0
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
            equalToConstant: HUDStyle.rowHeight(scale: hudScale)
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

            titleLabel.topAnchor.constraint(equalTo: row.topAnchor),

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
            temperature.toolTip = metric == .cpuTotal
                ? "Average of identified CPU temperature sensors, in °C. Sensor coverage varies by model."
                : "Average of available GPU temperature sensors, in °C."
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

            let power = NSTextField(labelWithString: "")
            power.font = powerFont(for: metric)
            power.textColor = HUDStyle.titleColor(for: metric, background: textBackground)
            power.alignment = .right
            power.isHidden = true
            power.translatesAutoresizingMaskIntoConstraints = false
            power.toolTip = "Estimated total \(metric == .cpuTotal ? "CPU" : "GPU") power in watts, averaged over the sampling interval."
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

            if metric == .cpuTotal {
                let title = NSTextField(labelWithString: "Package")
                let value = NSTextField(labelWithString: "")
                value.alignment = .right
                for label in [title, value] {
                    label.font = HUDStyle.ramDetailFont(scale: hudScale)
                    label.textColor = power.textColor
                    label.isHidden = true
                    label.translatesAutoresizingMaskIntoConstraints = false
                    label.toolTip = "Combined CPU, GPU and Neural Engine power estimate in watts. Excludes the display and other whole-Mac components."
                    row.addSubview(label)
                }
                let top = title.topAnchor.constraint(equalTo: titleLabel.bottomAnchor,
                    constant: HUDStyle.rowSpacing(scale: hudScale))
                NSLayoutConstraint.activate([
                    top, title.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                    value.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
                    value.trailingAnchor.constraint(equalTo: power.trailingAnchor),
                    title.trailingAnchor.constraint(lessThanOrEqualTo: value.leadingAnchor,
                        constant: -HUDStyle.metricColumnSpacing(scale: hudScale))
                ])
                packageTitleLabel = title; packageValueLabel = value; packageTopConstraint = top
            }
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
                physicalLabel.toolTip = "Physical RAM in use: app, wired and compressed memory."
                swapTitle.toolTip = "Disk space currently used for swap."
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
                    pressureValue.bottomAnchor.constraint(equalTo: row.bottomAnchor),
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
                detailLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor).isActive = true
            }
        }

        // MARK: Save References

        titleLabels[metric] =
            titleLabel

        valueLabels[metric] =
            valueLabel

        return row
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

    // MARK: - Metric Visibility

    func setResourceOptions(_ options: HUDResourceOptions, for group: HUDResourceGroup) {
        enabledMetrics.remove(group.appMetric)
        enabledMetrics.remove(group.totalMetric)
        enabledMetrics.formUnion(options.visibleMetrics(for: group))
        for metric in [group.appMetric, group.totalMetric] {
            metricRows[metric]?.isHidden = !enabledMetrics.contains(metric)
        }
        if group.supportsTemperature {
            let showPower = options.enabled && options.power
            if showPower { powerMetrics.insert(group.totalMetric) }
            else { powerMetrics.remove(group.totalMetric); powerLabels[group.totalMetric]?.stringValue = "" }
            powerLabels[group.totalMetric]?.isHidden = !showPower
            let showTemperature = options.enabled && options.temperature
            if showTemperature { temperatureMetrics.insert(group.totalMetric) }
            else { temperatureMetrics.remove(group.totalMetric); temperatureLabels[group.totalMetric]?.stringValue = "" }
            temperatureLabels[group.totalMetric]?.isHidden = !showTemperature
            if options.totalUse { hiddenUtilizationMetrics.remove(group.totalMetric) }
            else { hiddenUtilizationMetrics.insert(group.totalMetric) }
            valueLabels[group.totalMetric]?.isHidden = !options.totalUse
            updateTemperatureAppearance()
        }
        updateLayout()
        updateVisibility()
    }

    func updateTemperatures(_ sample: TemperatureSample) {
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
        func text(_ value: Double?) -> String {
            guard let value, value.isFinite, value >= 0 else { return "" }
            return String(format: "%.1f W", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        for (metric, value) in [(HUDMetric.cpuTotal, sample.cpu), (.gpuTotal, sample.gpu)] {
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
            !enabledMetrics.isEmpty {

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
        updateTemperatureAppearance()

        for label in deviceInfoLabels { label.font = HUDStyle.ramDetailFont(scale: scale) }
        ramSwapTitleLabel?.font = HUDStyle.ramDetailFont(scale: scale)
        ramSwapValueLabel?.font = HUDStyle.ramDetailFont(scale: scale)
        ramPressureTitleLabel?.font = HUDStyle.ramDetailFont(scale: scale)
        ramPressureValueLabel?.font = HUDStyle.ramDetailFont(scale: scale)
        for constraint in ramDetailGroupSpacingConstraints.values {
            constraint.constant = HUDStyle.rowSpacing(scale: scale)
        }

        // Update fonts and row constraints.

        for metric in HUDMetric.allCases {
            primaryLabelHeightConstraints[metric]?.constant = HUDStyle.rowHeight(scale: scale)
            ramDetailLabels[metric]?.font = HUDStyle.ramDetailFont(scale: scale)
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
                    HUDStyle.rowHeight(
                        for: metric, scale: scale
                    )

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
        hudBackground = background
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
        case .transparent, .dark, .off: container.appearance = NSAppearance(named: .darkAqua)
        }
        if let customGlass {
            switch hudBackground {
            case .transparent: customGlass.style = .transparent
            case .light: customGlass.style = .light
            case .dark, .off: customGlass.style = .dark
            }
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            switch hudBackground {
            case .light: backgroundView.layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
            case .transparent, .dark: backgroundView.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
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
        guard panel.isVisible, hudEnabled, !enabledMetrics.isEmpty, hudBackground != .off else { return }
        customGlass?.retry()
    }

    // MARK: - Captured Glass Lifecycle

    private func updateCaptureLifecycle() {
        if panel.isVisible && hudEnabled && !enabledMetrics.isEmpty && hudBackground != .off {
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
                  !enabledMetrics.isEmpty, hudBackground != .off else { return }
            windowContentView.layoutSubtreeIfNeeded()
            customGlass?.refreshGeometry()
            captureRefreshTask = nil
        }
    }

    func shutdown() {
        fpsGraphView.reset()
        panel.stopModifierTracking()
        stopCapture()
        panel.orderOut(nil)
    }

    // MARK: - Text Appearance

    private func temperatureFont(for metric: HUDMetric) -> NSFont {
        hiddenUtilizationMetrics.contains(metric)
            ? HUDStyle.valueFont(for: metric, scale: hudScale)
            : HUDStyle.ramDetailFont(scale: hudScale)
    }

    private func powerIsPrimary(for metric: HUDMetric) -> Bool {
        hiddenUtilizationMetrics.contains(metric) && !temperatureMetrics.contains(metric)
    }

    private func powerFont(for metric: HUDMetric) -> NSFont {
        powerIsPrimary(for: metric)
            ? HUDStyle.valueFont(for: metric, scale: hudScale)
            : HUDStyle.ramDetailFont(scale: hudScale)
    }

    private func updateTemperatureAppearance() {
        for (metric, label) in temperatureLabels {
            label.font = temperatureFont(for: metric)
            label.textColor = hiddenUtilizationMetrics.contains(metric)
                ? HUDStyle.valueColor(background: textBackground)
                : HUDStyle.titleColor(for: metric, background: textBackground)
        }
        for (metric, label) in powerLabels {
            label.font = powerFont(for: metric)
            label.textColor = powerIsPrimary(for: metric)
                ? HUDStyle.valueColor(background: textBackground)
                : HUDStyle.titleColor(for: metric, background: textBackground)
        }
        packageTitleLabel?.font = HUDStyle.ramDetailFont(scale: hudScale)
        packageTitleLabel?.textColor = HUDStyle.titleColor(for: .cpuTotal, background: textBackground)
        packageValueLabel?.font = powerFont(for: .cpuTotal)
        packageValueLabel?.textColor = powerIsPrimary(for: .cpuTotal)
            ? HUDStyle.valueColor(background: textBackground)
            : HUDStyle.titleColor(for: .cpuTotal, background: textBackground)
    }

    private func updateMetricColors() {
        fpsGraphView.applyStyle(scale: hudScale, background: textBackground)
        batteryIndicator.applyStyle(scale: hudScale, background: textBackground)
        updateTemperatureAppearance()
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

            // Keep values neutral and readable on the selected background.
            valueLabels[metric]?
                .textColor =
                    HUDStyle.valueColor(background: textBackground)
        }
    }

    // MARK: - Layout

    private func updateReadingPositions() {
        guard readingColumnRight > 0 else { return }
        let metrics: [HUDMetric] = [.gpuTotal, .cpuTotal]
        for metric in metrics {
            let hasTemperature = temperatureMetrics.contains(metric)
            let hasUsage = !hiddenUtilizationMetrics.contains(metric)
            // Keep a compact, stable cluster anchored at the right edge.
            // Reference widths prevent changing readings from shifting columns.
            let temperature = NSTextField(labelWithString: "149°C")
            temperature.font = temperatureFont(for: metric)
            let usage = NSTextField(labelWithString: "100%")
            usage.font = HUDStyle.valueFont(for: metric, scale: hudScale)
            let gap = HUDStyle.metricColumnSpacing(scale: hudScale)
            var trailing = readingColumnRight - (valueLabels[metric]?.alignmentRectInsets.right ?? 0)
            if hasUsage { trailing -= usage.intrinsicContentSize.width + gap }
            temperatureTrailingConstraints[metric]?.constant = trailing
            if hasTemperature { trailing -= temperature.intrinsicContentSize.width + gap }
            powerTrailingConstraints[metric]?.constant = trailing
        }

        // Follow a visible secondary temperature column; keep the battery's
        // primary temperature right-aligned when its Energy option is disabled.
        let reference = metrics.first {
            enabledMetrics.contains($0) && temperatureMetrics.contains($0) && !hiddenUtilizationMetrics.contains($0)
        }
        batteryIndicator.alignTemperature(trailingInset: reference.flatMap { metric in
            temperatureTrailingConstraints[metric].map { readingColumnRight - $0.constant }
        })
    }

    private func updateLayout() {

        packageTitleLabel?.isHidden = !showsPackagePower
        packageValueLabel?.isHidden = !showsPackagePower
        if !showsPackagePower { packageValueLabel?.stringValue = "" }
        let packageHeight = showsPackagePower
            ? HUDStyle.rowSpacing(scale: hudScale) + HUDStyle.ramDetailHeight(scale: hudScale) : 0
        rowHeightConstraints[.cpuTotal]?.constant = HUDStyle.rowHeight(scale: hudScale) + packageHeight
        packageTopConstraint?.constant = HUDStyle.rowSpacing(scale: hudScale)

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
            $0 + HUDStyle.rowHeight(for: $1, scale: hudScale)
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
            sampleValue.font = HUDStyle.valueFont(for: metric, scale: hudScale)

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
            usage.font = HUDStyle.valueFont(for: metric, scale: hudScale)
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

        // Power adds another value column, not another large block of empty space.
        // Retain the normal expanded width, growing only enough to fit the readings.
        if !powerMetrics.intersection(enabledMetrics).isEmpty {
            valueColumnRight = max(valueColumnRight, expandedBaseWidth)
        } else {
            valueColumnRight = HUDStyle.expandedValueColumnRight(valueColumnRight, scale: hudScale)
        }

        let fpsOnly = enabledMetrics == [.fps]
        if !fpsOnly {
            // Reduce the previously expanded gap by 10% (1.20 × 0.90 = 1.08), leaving the compact
            // spacing within the readings and the outside padding unchanged.
            valueColumnRight = HUDStyle.expandedValueColumnRight(valueColumnRight, scale: hudScale, gapIncrease: 0.08)
        }
        if fpsOnly, let title = titleLabels[.fps] {
            // Halve the usual gap using a stable two-digit reference, so changing
            // FPS readings never cause the window to resize.
            let reference = NSTextField(labelWithString: "60")
            reference.font = HUDStyle.valueFont(for: .fps, scale: hudScale)
            let textWidth = title.intrinsicContentSize.width + reference.intrinsicContentSize.width
            let gap = max(HUDStyle.metricColumnSpacing(scale: hudScale), (valueColumnRight - textWidth) / 2)
            valueColumnRight = textWidth + gap
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
                HUDPositioning.distanceSquared(from: customTopLeft, to: left.visibleFrame)
                    < HUDPositioning.distanceSquared(from: customTopLeft, to: right.visibleFrame)
            }!
            let contentOrigin = HUDPositioning.origin(
                for: customTopLeft,
                size: container.frame.size,
                in: screen.visibleFrame
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
        batteryIndicator.update(percentage: sample?.percentage, source: sample?.source, temperature: sample?.temperature)
    }

    func setBatteryOptions(_ options: HUDBatteryOptions) {
        batteryIndicator.setOptions(options)
        setMetricEnabled(.battery, enabled: options.enabled)
    }

    // MARK: - Generic Metric Updating

    func updateMetric(
        _ metric: HUDMetric,
        value: String
    ) {

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
    }

    func updateRAM(_ metric: HUDMetric, usage: RAMUsageSample?) {
        guard metric == .ram || metric == .ramTotal else { return }
        updateMetric(metric, value: usage.map { "\(Int($0.percentage.rounded()))%" } ?? "")
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
