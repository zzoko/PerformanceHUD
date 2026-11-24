// Writes static/media/social-preview.jpg (1200 x 630), the link-preview image (og:image) and GitHub social
// preview: the silver MacBook from the homepage with the light HUD render's first frame on its screen.
// Run from site/:  swift tools/make_social_image.swift
import AppKit

let media = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "static/media")
let size = CGSize(width: 1200, height: 630)
let background = NSColor(srgbRed: 0xf5 / 255, green: 0xf5 / 255, blue: 0xf7 / 255, alpha: 1)

// The full MacBook frame (viewBox -4 100 1608 996) and its screen opening, as in style.css (.device-screen).
let deviceAspect = 1608.0 / 996.0
let screenBox = (left: 0.08893, top: 0.032129, width: 0.821517, height: 0.871034)

guard let poster = NSImage(contentsOf: media.appendingPathComponent("hero-screen-poster.jpg")),
      let frame = NSImage(contentsOf: media.appendingPathComponent("macbook-pro-14-silver.svg")) else {
    fatalError("Missing the poster or the frame in \(media.path)")
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

background.setFill()
NSRect(origin: .zero, size: size).fill()

// The MacBook, centred, 560 px tall (AppKit's origin is bottom-left).
let deviceHeight = 560.0, deviceWidth = deviceHeight * deviceAspect
let device = NSRect(x: (size.width - deviceWidth) / 2, y: (size.height - deviceHeight) / 2 - 4,
                    width: deviceWidth, height: deviceHeight)
let screen = NSRect(x: device.minX + device.width * screenBox.left,
                    y: device.maxY - device.height * (screenBox.top + screenBox.height),
                    width: device.width * screenBox.width, height: device.height * screenBox.height)

// Poster fills the screen (object-fit: cover), black around it like .device-screen.
NSColor.black.setFill()
screen.insetBy(dx: -2, dy: -2).fill()
let scale = max(screen.width / poster.size.width, screen.height / poster.size.height)
let drawn = NSSize(width: poster.size.width * scale, height: poster.size.height * scale)
NSGraphicsContext.saveGraphicsState()
NSBezierPath(rect: screen).addClip()
poster.draw(in: NSRect(x: screen.midX - drawn.width / 2, y: screen.midY - drawn.height / 2,
                       width: drawn.width, height: drawn.height))
NSGraphicsContext.restoreGraphicsState()
frame.draw(in: device)

NSGraphicsContext.restoreGraphicsState()
let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88])!
try! jpeg.write(to: media.appendingPathComponent("social-preview.jpg"))
print("wrote social-preview.jpg (\(jpeg.count / 1024) KB)")
