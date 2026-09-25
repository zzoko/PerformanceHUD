import AppKit

@MainActor
final class HUDSizeMenuView: NSView {
    var onScaleSelected: ((HUDScale) -> Void)?
    private var selectedScale: HUDScale
    private let slider = HUDFillSlider()
    private let valueLabel = NSTextField(labelWithString: "")

    init(selectedScale: HUDScale) {
        self.selectedScale = selectedScale
        let width = HUDMenuLayout.labelLeading + HUDMenuLayout.labelWidth + HUDMenuLayout.spacing
            + HUDMenuLayout.backgroundOptionsWidth + 12 + 44 + 12
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 28))

        let label = NSTextField(labelWithString: "Size")
        label.font = .menuFont(ofSize: 0)
        label.textColor = .labelColor
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        slider.minValue = HUDScale.minimum
        slider.maxValue = HUDScale.maximum
        slider.numberOfTickMarks = HUDScale.allCases.count
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(scaleChanged(_:))
        slider.toolTip = "Adjust HUD size from 0.75× to 1.25× in 0.05× steps. Default: 1×."
        slider.setAccessibilityLabel("HUD size")

        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right

        let stack = NSStackView(views: [label, slider, valueLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = HUDMenuLayout.spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 30),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.widthAnchor.constraint(equalToConstant: HUDMenuLayout.labelWidth),
            slider.widthAnchor.constraint(equalToConstant: HUDMenuLayout.backgroundOptionsWidth),
            slider.heightAnchor.constraint(equalToConstant: 24),
            valueLabel.widthAnchor.constraint(equalToConstant: 44)
        ])
        updateSelection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func scaleChanged(_ sender: NSSlider) {
        let scale = HUDScale(rawValue: sender.doubleValue)
        guard scale != selectedScale else { return }
        selectedScale = scale
        updateSelection()
        onScaleSelected?(scale)
    }

    private func updateSelection() {
        slider.doubleValue = selectedScale.rawValue
        valueLabel.stringValue = selectedScale.menuTitle
        slider.setAccessibilityValueDescription(selectedScale.menuTitle)
        slider.needsDisplay = true
    }
}

/// A stepped native slider with a filled track instead of a separate knob.
@MainActor
final class HUDFillSlider: NSSlider {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: bounds.minX, y: bounds.midY - 6, width: bounds.width, height: 12)
        let path = NSBezierPath(roundedRect: track, xRadius: 6, yRadius: 6)
        NSColor.labelColor.withAlphaComponent(0.16).setFill()
        path.fill()
        let fraction = max(0, min(1, (doubleValue - minValue) / (maxValue - minValue)))
        guard fraction > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let fill = NSRect(x: track.minX, y: track.minY, width: track.width * fraction, height: track.height)
        NSColor.labelColor.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: fill, xRadius: 6, yRadius: 6).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func updateValue(at event: NSEvent) {
        guard bounds.width > 0 else { return }
        let location = convert(event.locationInWindow, from: nil)
        let fraction = max(0, min(1, (location.x - bounds.minX) / bounds.width))
        doubleValue = HUDScale(rawValue: minValue + fraction * (maxValue - minValue)).rawValue
        needsDisplay = true
        sendAction(action, to: target)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        updateValue(at: event)
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            updateValue(at: next)
            if next.type == .leftMouseUp { break }
        }
    }
}
