// Appended to the glass source to verify the real Metal output and private
// fallback/held-frame layers without starting screen capture.
@main struct CornerRadiusTests {
    @MainActor static func member<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }
    @MainActor static func main() throws {
        _ = NSApplication.shared
        UserDefaults.standard.setVolatileDomain(["hud.enabled": false, "hud.autoHide.mode": "fps",
            "hud.background": "dark"], forName: UserDefaults.argumentDomain)
        let hud = HUDWindowController()
        defer { hud.shutdown() }
        let glass: PerformanceHUDGlassBackground = member(hud, "backgroundView")
        let content: NSView = member(hud, "backgroundContentView")
        let surface: HUDGlassSurfaceView = member(glass, "surface")
        let checker: HUDCaptureCheckerboardView = member(surface, "checkerboard")
        let held: CALayer = member(surface, "heldFrameLayer")
        for alignment in [HUDAlignment.vertical, .horizontal] {
            hud.setAlignment(alignment)
            hud.updateFPS(60)
            for scale in [HUDScale.small, .normal, .large] {
                hud.setHUDScale(scale)
                let expected = 14 * CGFloat(scale.rawValue)
                precondition(glass.glassAppearance.cornerRadius == expected)
                precondition(checker.cornerRadius == expected)
                for layer in [content.layer!, held] {
                    precondition(layer.cornerRadius == 0 && layer.masksToBounds)
                    precondition((layer.mask as? CAShapeLayer)?.path == HUDCornerShape.path(in: layer.bounds, radius: expected),
                                 "Content and held glass must use the same continuous outline")
                }
                let expectedShadow = HUDCornerShape.path(in: glass.bounds, radius: expected)
                precondition(glass.layer?.shadowPath == expectedShadow, "The shadow must follow the glass radius")
            }
        }
        for style in [PerformanceHUDGlassStyle.dark, .light, .transparent] {
            for scale: CGFloat in [0.5, 1, 2] {
                for backing: CGFloat in [1, 2] {
                    let appearance = PerformanceHUDGlassAppearance(theme: style, hudScale: scale)
                    let geometry = HUDGlassCaptureGeometry(square: CGRect(x: 100, y: 100, width: 160 * scale, height: 100 * scale),
                        screen: CGRect(x: 0, y: 0, width: 1200, height: 1200), scale: backing)
                    var optional: CVPixelBuffer?
                    let w = Int((geometry.source.width * backing).rounded())
                    let h = Int((geometry.source.height * backing).rounded())
                    precondition(CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                        [kCVPixelBufferMetalCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
                        &optional) == kCVReturnSuccess)
                    let buffer = optional!
                    CVPixelBufferLockBaseAddress(buffer, [])
                    memset(CVPixelBufferGetBaseAddress(buffer)!, 180, CVPixelBufferGetBytesPerRow(buffer) * h)
                    CVPixelBufferUnlockBaseAddress(buffer, [])
                    let renderer = try HUDGlassRenderer(geometry: geometry, glass: true, appearance: appearance)
                    let image = try renderer.render(buffer: buffer)!
                    let data = image.dataProvider!.data! as Data
                    // Compare native masks against actual shader coverage around
                    // all four corners. Ignore the subpixel antialiasing fringe.
                    let outline = HUDCornerShape.path(in: CGRect(origin: .zero, size: geometry.size).insetBy(dx: 0.5, dy: 0.5),
                                                     radius: appearance.cornerRadius)
                    let reach = Int(ceil((appearance.cornerRadius * HUDCornerShape.reach + 1) * backing))
                    let epsilon = 0.75 / backing
                    for y in 0..<reach {
                        for x in 0..<reach {
                            for px in [x, image.width - x - 1] {
                                for py in [y, image.height - y - 1] {
                                    let point = CGPoint(x: (CGFloat(px) + 0.5) / backing, y: (CGFloat(py) + 0.5) / backing)
                                    let neighbors = [-epsilon, epsilon].flatMap { dx in
                                        [-epsilon, epsilon].map { dy in outline.contains(CGPoint(x: point.x + dx, y: point.y + dy)) }
                                    }
                                    let alpha = data[py * image.bytesPerRow + px * 4 + 3]
                                    if neighbors.allSatisfy({ $0 }) { precondition(alpha > 230, "Native mask must not extend beyond the glass") }
                                    if neighbors.allSatisfy({ !$0 }) { precondition(alpha < 25, "Glass must not extend beyond the native mask") }
                                }
                            }
                        }
                    }
                    // These normalized points straddle the arc at every size, staying
                    // clear of the antialiasing fringe even at 0.5× on a 1× display.
                    // An unscaled radius fails this at both 0.5× and 2×.
                    for (fraction, inside): (CGFloat, Bool) in [(0.18, false), (0.55, true)] {
                        let inset = Int((appearance.cornerRadius * fraction * backing).rounded(.down))
                        for x in [inset, image.width - 1 - inset] {
                            for y in [inset, image.height - 1 - inset] {
                                let alpha = data[y * image.bytesPerRow + x * 4 + 3]
                                precondition(inside ? alpha > 240 : alpha < 15,
                                             "Corner proportion mismatch at scale=\(scale) backing=\(backing) style=\(style) alpha=\(alpha)")
                            }
                        }
                    }
                }
            }
        }
        // Very thin animation frames must stay finite, fully clipped and
        // symmetric while retaining the full-sized backing texture.
        let geometry = HUDGlassCaptureGeometry(square: CGRect(x: 100, y: 100, width: 160, height: 100),
            screen: CGRect(x: 0, y: 0, width: 1000, height: 1000), scale: 2)
        var optional: CVPixelBuffer?
        precondition(CVPixelBufferCreate(kCFAllocatorDefault, Int(geometry.source.width * 2), Int(geometry.source.height * 2),
            kCVPixelFormatType_32BGRA, [kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &optional) == kCVReturnSuccess)
        let buffer = optional!
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer)!, 180, CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for scale: CGFloat in [0.5, 1, 2] {
            let viewport = HUDGlassViewport()
            let renderer = try HUDGlassRenderer(geometry: geometry, glass: true,
                appearance: PerformanceHUDGlassAppearance(theme: .dark, hudScale: scale), viewport: viewport)
            for extent: CGFloat in [0, 0.5, 1, 3, 10, 30] {
                for size in [CGSize(width: 160, height: extent), CGSize(width: extent, height: 100)] {
                    _ = viewport.setSize(size)
                    let image = try renderer.render(buffer: buffer)!
                    let data = image.dataProvider!.data! as Data
                    let width = Int(size.width * 2), height = Int(size.height * 2)
                    for y in 0..<image.height {
                        for x in 0..<image.width {
                            let alpha = data[y * image.bytesPerRow + x * 4 + 3]
                            if x >= width || y >= height {
                                precondition(alpha == 0, "Collapsed region must remain fully transparent")
                            } else {
                                precondition(alpha == data[y * image.bytesPerRow + (width - x - 1) * 4 + 3])
                                precondition(alpha == data[(height - y - 1) * image.bytesPerRow + x * 4 + 3])
                            }
                        }
                    }
                }
            }
        }
        print("PASS: continuous CPU/Metal corner agreement, thin collapse frames, proportional corners at 0.5×/1×/2×, both layouts, all appearances, 1×/2× Retina backing, real Metal pixels, shadow, held glass, checkerboard, and content masks")
    }
}
