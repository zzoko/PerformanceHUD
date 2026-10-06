import AppKit
import QuartzCore

/// Apple's regular Liquid Glass with a soft exterior shadow.
/// The frame INCLUDES 24pt transparent padding on every side. Add HUD text to
/// contentView (body-local coordinates); don't add the padding a second time.
/// This view draws visuals only. NativeGlassSession owns the refresh listener.
@available(macOS 26.0, *)
@MainActor
final class NativeGlassHUDBackground: NSView {
    static let shadowPadding: CGFloat = 24

    // Transparent sibling above the glass: existing labels/graphs stay independent.
    let contentView = NSView(frame: .zero)
    private let glass = NSGlassEffectView()
    private let outsideShadow = CALayer()
    private let shadowCutout = CAShapeLayer()

    var isDark = true {
        didSet { if isDark != oldValue { updateAppearance() } }
    }
    var clipsContent = false { didSet { needsLayout = true } }
    var cornerRadius: CGFloat = 16 {
        didSet { needsLayout = true }
    }

    /// Body rectangle in this padded view's coordinates; excludes shadow padding.
    var bodyFrame: NSRect {
        let inset = Self.shadowPadding
        return NSRect(x: bounds.minX + inset, y: bounds.minY + inset,
                      width: max(0, bounds.width - 2 * inset),
                      height: max(0, bounds.height - 2 * inset))
    }

    static func sizeIncludingShadow(bodySize: NSSize) -> NSSize {
        NSSize(width: bodySize.width + 2 * shadowPadding,
               height: bodySize.height + 2 * shadowPadding)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        outsideShadow.shadowColor = NSColor.black.cgColor
        outsideShadow.shadowRadius = 6
        outsideShadow.shadowOffset = CGSize(width: 0, height: -2)
        shadowCutout.fillRule = .evenOdd
        shadowCutout.fillColor = NSColor.black.cgColor
        outsideShadow.mask = shadowCutout
        layer?.addSublayer(outsideShadow)

        // No tint, custom opacity, gradient, refraction shader, or background capture.
        glass.style = .regular
        glass.tintColor = nil
        if #available(macOS 27.0, *) { glass.effectIsInteractive = false }
        addSubview(glass)
        addSubview(contentView, positioned: .above, relativeTo: glass)
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let body = bodyFrame
        glass.frame = body
        contentView.frame = body
        contentView.wantsLayer = true
        contentView.layer?.masksToBounds = clipsContent
        contentView.layer?.cornerCurve = .continuous
        let radius = max(0, min(cornerRadius, min(body.width, body.height) / 2))
        glass.cornerRadius = radius
        contentView.layer?.cornerRadius = clipsContent ? radius : 0
        outsideShadow.frame = bounds
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        outsideShadow.contentsScale = scale
        shadowCutout.contentsScale = scale

        // Paths are in the shadow layer's local coordinates, even for nonzero bounds.
        let localBody = body.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        let shape = CGPath(roundedRect: localBody, cornerWidth: radius,
                           cornerHeight: radius, transform: nil)
        outsideShadow.shadowPath = shape
        let cutout = CGMutablePath()
        cutout.addRect(outsideShadow.bounds)
        cutout.addPath(shape)
        shadowCutout.frame = outsideShadow.bounds
        shadowCutout.path = cutout
        // Only the shadow is masked. No shadow fill darkens the translucent interior;
        // Apple's glass and its own edge treatment remain completely untouched.
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    private func updateAppearance() {
        appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Keep the exterior shadow softer in light appearance.
        outsideShadow.shadowOpacity = isDark ? 0.32 : 0.17
        CATransaction.commit()
        needsLayout = true
    }
}
