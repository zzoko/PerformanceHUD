// Appended to the glass source by the runner to exercise the private surface.
@main struct GlassTransitionTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        func heldLayer(_ surface: HUDGlassSurfaceView) -> CALayer {
            Mirror(reflecting: surface).children.first { $0.label == "heldFrameLayer" }!.value as! CALayer
        }
        func frame(scale: Int) -> CGImage {
            let context = CGContext(data: nil, width: 320 * scale, height: 500 * scale,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            // CGImage pixel rows start at the top. Model a collapsed capture:
            // the top 150 points are visible and the reserved bottom is transparent.
            context.setFillColor(CGColor(red: 0.3, green: 0.4, blue: 0.5, alpha: 1))
            context.fill(CGRect(x: 0, y: 350 * scale, width: 320 * scale, height: 150 * scale))
            return context.makeImage()!
        }
        let surface = HUDGlassSurfaceView(frame: NSRect(x: 0, y: 0, width: 320, height: 500))
        surface.setVisibleSize(NSSize(width: 320, height: 150), radius: 10)
        surface.holdLastFrame()
        precondition(surface.isShowingFallback, "No previous frame must use the checkerboard")
        var changes = 0
        surface.onFallbackChange = { changes += 1 }
        for scale in [1, 2] {
            surface.frame.size = NSSize(width: 320, height: 500)
            surface.setVisibleSize(NSSize(width: 320, height: 150), radius: 10)
            surface.show(image: frame(scale: scale), scale: CGFloat(scale))
            let count = changes
            surface.holdLastFrame()
            let held = heldLayer(surface)
            let image = held.contents as! CGImage
            precondition(image.width == 320 * scale && image.height == 150 * scale,
                         "Snapshot must exclude transparent reserved space")
            let data = image.dataProvider!.data! as Data
            precondition(data[image.bytesPerRow * (image.height - 1) + image.width * 2 + 3] == 255,
                         "Crop includes the opaque visible area, not the hidden bottom")
            for size in [NSSize(width: 640, height: 900), NSSize(width: 960, height: 40), NSSize(width: 160, height: 75)] {
                surface.frame.size = size
                surface.setVisibleSize(size, radius: 10)
                surface.holdLastFrame()
                precondition(held.frame == surface.bounds && !held.isHidden && held.masksToBounds,
                             "Held image follows vertical/horizontal bounds and rounded clipping")
                precondition((held.contents as! CGImage) === image, "Repeated resizing reuses one snapshot")
                precondition(!surface.isShowingFallback && changes == count, "No placeholder or foreground flicker")
            }
            surface.showFallback()
            precondition(held.contents == nil && held.isHidden && surface.isShowingFallback,
                         "Stop/failure clears the old image immediately")
            surface.holdLastFrame()
            precondition(surface.isShowingFallback, "A failed image cannot be revived")
        }
        surface.frame.size = NSSize(width: 320, height: 500)
        surface.setVisibleSize(NSSize(width: 320, height: 150), radius: 10)
        surface.show(image: frame(scale: 1), scale: 1)
        surface.holdLastFrame()
        try await Task.sleep(for: .milliseconds(2200))
        precondition(surface.isShowingFallback, "No new capture eventually returns to checkerboard")
        surface.show(image: frame(scale: 1), scale: 1)
        surface.holdLastFrame()
        surface.show(image: frame(scale: 1), scale: 1)
        try await Task.sleep(for: .milliseconds(2200))
        precondition(!surface.isShowingFallback && heldLayer(surface).contents == nil,
                     "Fresh capture cancels the hold timeout and replaces the snapshot")
        print("PASS: no-frame fallback, Retina/non-Retina crop, both layout shapes, repeated resizing, stable foreground, failure clearing, hold timeout, fresh-frame recovery")
    }
}
