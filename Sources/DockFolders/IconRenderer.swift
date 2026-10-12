import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Tekent een map-icoon: afgeronde tegel in de gekozen kleur met een 3x3 raster van app-iconen.
enum IconRenderer {
    static func image(for folder: AppFolder, size: CGFloat = 1024) -> NSImage {
        // Uit de cache, op ongeveer het formaat van een rastervak: veel sneller dan steeds de
        // 1024px-versie van elk app-icoon verkleinen.
        let cell = max(16, (size * 0.8 / 3).rounded(.up))
        let icons = folder.apps.prefix(9).map { IconCache.appIcon($0, points: cell) }
        let (top, bottom) = folder.tint.colors

        return NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let s = rect.width
            // macOS-icoonraster: de tegel is ~824/1024 van het canvas.
            let body = rect.insetBy(dx: s * 0.1, dy: s * 0.1)
            let radius = body.width * 0.225
            let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowBlurRadius = s * 0.025
            shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
            shadow.set()
            NSGradient(starting: top, ending: bottom)?.draw(in: path, angle: 90)
            NSGraphicsContext.restoreGraphicsState()

            // Subtiele glans bovenaan en een lichte rand.
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])?
                .draw(in: NSRect(x: body.minX, y: body.minY, width: body.width, height: body.height * 0.5), angle: 90)
            NSGraphicsContext.restoreGraphicsState()

            let rim = NSBezierPath(roundedRect: body.insetBy(dx: s * 0.003, dy: s * 0.003),
                                   xRadius: radius, yRadius: radius)
            rim.lineWidth = s * 0.006
            NSColor.white.withAlphaComponent(0.35).setStroke()
            rim.stroke()

            if icons.isEmpty {
                let config = NSImage.SymbolConfiguration(pointSize: s * 0.3, weight: .semibold)
                if let symbol = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(config) {
                    let tinted = NSImage(size: symbol.size, flipped: false) { r in
                        symbol.draw(in: r)
                        NSColor.white.withAlphaComponent(0.85).set()
                        r.fill(using: .sourceAtop)
                        return true
                    }
                    let sz = tinted.size
                    tinted.draw(in: NSRect(x: body.midX - sz.width / 2, y: body.midY - sz.height / 2,
                                           width: sz.width, height: sz.height),
                                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
                return true
            }

            let pad = body.width * 0.07
            let gap = body.width * 0.01
            let cell = (body.width - 2 * pad - 2 * gap) / 3
            for (i, icon) in icons.enumerated() {
                let row = CGFloat(i / 3), col = CGFloat(i % 3)
                let frame = NSRect(x: body.minX + pad + col * (cell + gap),
                                   y: body.minY + pad + row * (cell + gap),
                                   width: cell, height: cell)
                icon.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1,
                          respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
            }
            return true
        }
    }

    static func writeICNS(for folder: AppFolder, to url: URL) throws {
        let image = image(for: folder)
        // (punten, schaal): elke maat in 1x en 2x, zoals een iconset.
        let variants = [16, 32, 128, 256, 512].flatMap { [($0, 1), ($0, 2)] }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.icns.identifier as CFString,
                                                         variants.count, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for (points, scale) in variants {
            guard let cg = cgImage(image, pixels: points * scale) else { continue }
            let dpi = 72 * scale
            let props = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
            CGImageDestinationAddImage(dest, cg, props)
        }
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func cgImage(_ image: NSImage, pixels px: Int) -> CGImage? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: px, height: px)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
}

extension NSImage {
    /// Kopie als vaste bitmap (2x), getekend zoals de Dock/Finder het icoon tonen.
    func rasterized(points: CGFloat, scale: CGFloat = 2) -> NSImage {
        let px = Int(points * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return self }
        rep.size = NSSize(width: points, height: points)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(x: 0, y: 0, width: points, height: points))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
