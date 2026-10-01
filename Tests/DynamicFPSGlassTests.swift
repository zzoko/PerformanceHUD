// The runner appends this to the glass source in a temporary file so the test
// can exercise its private Metal renderer without exposing test hooks in the app.
@main struct DynamicFPSGlassTests {
    static func main() throws {
        let geometry = HUDGlassCaptureGeometry(square: CGRect(x: 100, y: 100, width: 320, height: 500),
            screen: CGRect(x: 0, y: 0, width: 1000, height: 1000), scale: 1)
        var pixelBuffer: CVPixelBuffer?
        let w = Int(geometry.source.width), h = Int(geometry.source.height)
        precondition(CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferMetalCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &pixelBuffer) == kCVReturnSuccess)
        let buffer = pixelBuffer!
        CVPixelBufferLockBaseAddress(buffer, [])
        let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * rowBytes + x * 4
                bytes[i] = UInt8(30 + y * 180 / h)
                bytes[i + 1] = UInt8(30 + x * 140 / w)
                bytes[i + 2] = 80
                bytes[i + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for style in [PerformanceHUDGlassStyle.dark, .light, .transparent] {
            let viewport = HUDGlassViewport()
            let renderer = try HUDGlassRenderer(geometry: geometry, glass: true,
                appearance: PerformanceHUDGlassAppearance(theme: style), viewport: viewport)
            var referencePixel: [UInt8]?
            for height: CGFloat in [500, 300, 120, 0, 500] {
                _ = viewport.setSize(CGSize(width: 320, height: height))
                let image = try renderer.render(buffer: buffer)!
                precondition(image.width == 320 && image.height == 500, "Output texture stays the expanded size")
                let data = image.dataProvider!.data! as Data
                if height == 0 {
                    precondition(stride(from: 3, to: data.count, by: 4).allSatisfy { data[$0] == 0 }, "Fully collapsed glass must be transparent")
                } else {
                    precondition(data[50 * image.bytesPerRow + 160 * 4 + 3] == 255, "Visible glass remains opaque")
                    let pixel = Array(data[(50 * image.bytesPerRow + 160 * 4)..<(50 * image.bytesPerRow + 160 * 4 + 3)])
                    if let referencePixel {
                        precondition(zip(pixel, referencePixel).allSatisfy { abs(Int($0) - Int($1)) <= 3 }, "The backdrop is cropped, not stretched")
                    } else { referencePixel = pixel }
                    if height < 500 {
                        let firstHiddenRow = Int(height)
                        precondition(stride(from: firstHiddenRow * image.bytesPerRow + 3, to: data.count, by: 4).allSatisfy { data[$0] == 0 }, "No old expanded glass remains below the visible edge")
                    }
                    if CommandLine.arguments.contains("--preview") {
                        let bitmap = NSBitmapImageRep(cgImage: image)
                        try bitmap.representation(using: .png, properties: [:])!.write(to:
                            URL(fileURLWithPath: "/tmp/phud-dynamic-glass-\(style)-\(Int(height)).png"))
                    }
                }
            }
        }
        // Width-only transitions use the same full capture texture.
        for style in [PerformanceHUDGlassStyle.dark, .light, .transparent] {
            let viewport = HUDGlassViewport()
            let renderer = try HUDGlassRenderer(geometry: geometry, glass: true,
                appearance: PerformanceHUDGlassAppearance(theme: style), viewport: viewport)
            var referencePixel: [UInt8]?
            for width: CGFloat in [320, 240, 100, 320] {
                _ = viewport.setSize(CGSize(width: width, height: 500))
                let image = try renderer.render(buffer: buffer)!
                precondition(image.width == 320 && image.height == 500, "Horizontal output texture stays fixed")
                let data = image.dataProvider!.data! as Data
                let offset = 250 * image.bytesPerRow + 40 * 4
                precondition(data[offset + 3] == 255, "Visible horizontal glass remains opaque")
                let pixel = Array(data[offset..<(offset + 3)])
                if let referencePixel {
                    precondition(zip(pixel, referencePixel).allSatisfy { abs(Int($0) - Int($1)) <= 3 }, "Horizontal backdrop is cropped, not stretched")
                } else { referencePixel = pixel }
                for y in 0..<image.height {
                    for x in Int(width)..<image.width {
                        precondition(data[y * image.bytesPerRow + x * 4 + 3] == 0, "No expanded glass remains to the right")
                    }
                }
            }
        }
        print("PASS: real Metal glass rendering at full/partial/zero height and partial width, fixed textures, cropped backdrop, transparent hidden area, all three appearances")
    }
}
