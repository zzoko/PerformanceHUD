import AppKit
import CoreText

/// A soft rounded-square fan badge, drawn as vectors at every HUD size.
@MainActor
enum HUDFanIcon {
    static let side: CGFloat = 21
    private static var images: [String: NSImage] = [:]

    static func image(marker: String) -> NSImage {
        if let image = images[marker] { return image }
        let image = NSImage(size: NSSize(width: 100, height: 100), flipped: false) { rect in
            draw(in: rect, marker: marker, color: .black)
            return true
        }
        image.isTemplate = true
        images[marker] = image
        return image
    }

    static func draw(in rect: NSRect, marker: String, color: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        let placement = NSAffineTransform()
        placement.translateX(by: rect.minX, yBy: rect.minY)
        placement.scaleX(by: rect.width / 100, yBy: rect.height / 100)
        placement.concat()
        color.setFill()
        color.setStroke()
        let badge = NSBezierPath(roundedRect: NSRect(x: 6, y: 6, width: 88, height: 88),
                                 xRadius: 20, yRadius: 20)
        badge.lineWidth = 6
        badge.stroke()
        let font = NSFont.systemFont(ofSize: marker.count > 1 ? 44 : 58, weight: .semibold)
        // Centre the visible glyph outlines, not the font's line box (which
        // includes unequal ascender/descender padding, especially noticeable on A).
        let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        let characters = Array(marker.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(ctFont, characters, &glyphs, characters.count)
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(ctFont, .horizontal, glyphs, &advances, glyphs.count)
        let outlines = CGMutablePath()
        var x: CGFloat = 0
        for (index, glyph) in glyphs.enumerated() {
            if let path = CTFontCreatePathForGlyph(ctFont, glyph, nil) {
                outlines.addPath(path, transform: CGAffineTransform(translationX: x, y: 0))
            }
            x += advances[index].width
        }
        let ink = outlines.boundingBoxOfPath
        if !ink.isNull, let context = NSGraphicsContext.current?.cgContext {
            let flipped = NSGraphicsContext.current?.isFlipped == true
            var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: flipped ? -1 : 1,
                tx: 50 - ink.midX, ty: 50 + (flipped ? ink.midY : -ink.midY))
            if let centered = outlines.copy(using: &transform) {
                context.setFillColor(color.cgColor)
                context.addPath(centered)
                context.fillPath()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
