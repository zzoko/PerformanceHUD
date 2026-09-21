import AppKit

@MainActor
final class HUDPanel: NSPanel {
    var onDragFinished: (() -> Void)?
    private var modifierTimer: Timer?
    private var dragging = false

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static func dragModifiersHeld(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection([.control, .option, .command, .shift]) == [.control, .option, .command]
    }

    func startModifierTracking() {
        guard modifierTimer == nil else { return }
        // Query only modifier state; no keyboard interception or Accessibility permission.
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouseAccess() }
        }
        modifierTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        updateMouseAccess()
    }

    func stopModifierTracking() {
        modifierTimer?.invalidate()
        modifierTimer = nil
        dragging = false
        ignoresMouseEvents = true
    }

    private func updateMouseAccess() {
        if dragging && NSEvent.pressedMouseButtons & 1 == 0 {
            dragging = false
            onDragFinished?()
        }
        ignoresMouseEvents = !isVisible || (!dragging && !Self.dragModifiersHeld(NSEvent.modifierFlags))
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown && Self.dragModifiersHeld(event.modifierFlags) {
            dragging = true
            performDrag(with: event)
            return
        }
        super.sendEvent(event)
    }

    deinit {
        modifierTimer?.invalidate()
    }
}

// Store the top-left point so scale and metric changes do not move the HUD's anchor.
enum HUDPositioning {
    static func distanceSquared(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    static func origin(for topLeft: NSPoint, size: NSSize, in frame: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(topLeft.x, frame.minX), max(frame.minX, frame.maxX - size.width)),
            y: min(max(topLeft.y - size.height, frame.minY), max(frame.minY, frame.maxY - size.height))
        )
    }
}
