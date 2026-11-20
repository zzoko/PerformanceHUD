import AppKit

enum HUDShortcutFeedback {
    case appearance(HUDBackground)
    case loggingStarted
    case loggingStopped
    case loggingRequiresHUD

    var text: String {
        switch self {
        case .appearance(let background): return "Appearance · \(background.menuTitle)"
        case .loggingStarted: return "Logging started"
        case .loggingStopped: return "Logging stopped"
        case .loggingRequiresHUD: return "Enable HUD to start logging"
        }
    }

    var symbol: String {
        switch self {
        case .appearance(.light): return "sun.max"
        case .appearance(.dark): return "moon"
        case .appearance(.system): return "circle.lefthalf.filled"
        case .loggingStarted: return "record.circle"
        case .loggingStopped: return "stop.circle"
        case .loggingRequiresHUD: return "info.circle"
        }
    }
}

/// A transient, click-through confirmation. It never activates the app or
/// changes the HUD's visibility, layout, or monitoring requirements.
@MainActor
final class HUDShortcutFeedbackController {
    private let panel = HUDShortcutFeedbackPanel(contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let background = NativeGlassHUDBackground(frame: .zero)
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var timer: Timer?
    private var shownAt: TimeInterval = 0
    private var initialAlpha: CGFloat = 0
    private var fades = true
    private let duration: TimeInterval = 1.5

    init() {
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.level = .screenSaver // Same fullscreen-capable level as the HUD.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        background.cornerRadius = 14
        panel.contentView = background

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.isSelectable = false
        icon.contentTintColor = .labelColor
        icon.imageScaling = .scaleProportionallyDown
        background.contentView.addSubview(icon)
        background.contentView.addSubview(label)
    }

    func show(_ feedback: HUDShortcutFeedback, on screen: NSScreen? = nil,
              appearance: HUDBackground) {
        guard let screen = screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main else { return }
        timer?.invalidate()
        let isDark = appearance.resolved(isDark: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua) == .dark
        panel.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        background.isDark = isDark
        label.stringValue = feedback.text
        panel.setAccessibilityLabel(feedback.text)
        icon.image = NSImage(systemSymbolName: feedback.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .medium))

        let area = screen.visibleFrame
        let size = NSSize(width: min(max(180, ceil(label.intrinsicContentSize.width) + 64), area.width - 24), height: 44)
        let body = NSRect(x: area.midX - size.width / 2, y: area.maxY - size.height - 28,
                          width: size.width, height: size.height)
        let padding = NativeGlassHUDBackground.shadowPadding
        panel.setFrame(body.insetBy(dx: -padding, dy: -padding), display: false)
        background.layoutSubtreeIfNeeded()
        icon.frame = NSRect(x: 16, y: 14, width: 16, height: 16)
        label.frame = label.frame(forAlignmentRect: NSRect(x: 42, y: (size.height - label.intrinsicContentSize.height) / 2,
            width: size.width - 58, height: label.intrinsicContentSize.height))

        fades = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        initialAlpha = panel.isVisible ? panel.alphaValue : 0
        panel.alphaValue = fades ? initialAlpha : 1
        shownAt = ProcessInfo.processInfo.systemUptime
        panel.orderFrontRegardless()
        let timer = Timer(timeInterval: fades ? 1 / 60 : duration, repeats: fades) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.timer === timer else { return }
                self.advance()
            }
        }
        timer.tolerance = 0.01
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advance() {
        let elapsed = ProcessInfo.processInfo.systemUptime - shownAt
        guard elapsed < duration else { dismiss(); return }
        if fades {
            let fadeIn = min(1, elapsed / 0.12)
            let fadeOut = min(1, (duration - elapsed) / 0.22)
            panel.alphaValue = min(initialAlpha + (1 - initialAlpha) * fadeIn, fadeOut)
        }
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
        panel.alphaValue = 0
    }

    deinit { timer?.invalidate() }
}

@MainActor
private final class HUDShortcutFeedbackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
