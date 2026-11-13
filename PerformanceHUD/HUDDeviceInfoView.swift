import AppKit

@MainActor
final class HUDDeviceInfoView: NSView {
    private let chipLabel: NSTextField
    private let versionLabel: NSTextField
    private let cpuLabel: NSTextField
    private let gpuLabel: NSTextField
    private var lineHeights: [NSLayoutConstraint] = []
    private var options = HUDDeviceInfoOptions()

    init(info: HUDDeviceInfo = .current) {
        chipLabel = NSTextField(labelWithString: info.chipName)
        versionLabel = NSTextField(labelWithString: info.macOSVersion)
        cpuLabel = NSTextField(labelWithString: info.cpuConfiguration)
        gpuLabel = NSTextField(labelWithString: info.gpuConfiguration)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        for label in [chipLabel, versionLabel, cpuLabel, gpuLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.alignment = label === versionLabel ? .right : .left
            addSubview(label)
            let height = label.heightAnchor.constraint(equalToConstant: 18)
            lineHeights.append(height)
            height.isActive = true
        }
        chipLabel.setAccessibilityLabel("Chip")
        versionLabel.setAccessibilityLabel("macOS version")
        cpuLabel.setAccessibilityLabel("CPU core configuration")
        gpuLabel.setAccessibilityLabel("GPU core configuration")
        NSLayoutConstraint.activate([
            chipLabel.topAnchor.constraint(equalTo: topAnchor),
            versionLabel.topAnchor.constraint(equalTo: topAnchor),
            chipLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: chipLabel.alignmentRectInsets.left),
            versionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -versionLabel.alignmentRectInsets.right),
            cpuLabel.topAnchor.constraint(equalTo: chipLabel.bottomAnchor),
            gpuLabel.topAnchor.constraint(equalTo: cpuLabel.bottomAnchor),
            cpuLabel.leadingAnchor.constraint(equalTo: chipLabel.leadingAnchor),
            gpuLabel.leadingAnchor.constraint(equalTo: chipLabel.leadingAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(info:)") }

    func configure(options: HUDDeviceInfoOptions, scale: HUDScale, background: HUDBackground) {
        self.options = options
        chipLabel.isHidden = !options.showsChip
        versionLabel.isHidden = !options.showsOS
        cpuLabel.isHidden = !options.showsChip || options.chipMode != .full
        gpuLabel.isHidden = cpuLabel.isHidden
        for label in [chipLabel, versionLabel, cpuLabel, gpuLabel] {
            label.font = HUDStyle.smallLabelFont(scale: scale)
            label.textColor = HUDStyle.TextStyle.label.color(background: background)
        }
        for constraint in lineHeights { constraint.constant = HUDStyle.ramDetailHeight(scale: scale) }
    }

    func height(scale: HUDScale) -> CGFloat {
        guard options.isVisible else { return 0 }
        return HUDStyle.ramDetailHeight(scale: scale) * (options.chipMode == .full ? 3 : 1)
    }
}
