import AppKit

/// Cache voor app- en map-iconen als kant-en-klare bitmaps. Een icoon omzetten kost ~10-20 ms;
/// zonder cache gebeurde dat bij elke SwiftUI-update opnieuw, voor elke app.
/// Thread-safe, zodat de map-app de cache bij het opstarten op de achtergrond kan vullen.
enum IconCache {
    private static var cache: [String: NSImage] = [:]
    private static let lock = NSLock()

    /// Icoon van een app, getekend op `points` (2x). De sleutel bevat de wijzigingsdatum,
    /// zodat een bijgewerkte app vanzelf een nieuw icoon krijgt.
    static func appIcon(_ path: String, points: CGFloat) -> NSImage {
        let modified = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        let key = "app|\(points)|\(modified)|\(path)"
        return cached(key) {
            NSWorkspace.shared.icon(forFile: path).rasterized(points: points)
        }
    }

    /// Map-icoon (raster van app-iconen in de mapkleur).
    static func folderIcon(_ folder: AppFolder, points: CGFloat) -> NSImage {
        let key = "folder|\(points)|\(folder.tint.rawValue)|\(folder.apps.prefix(9).joined(separator: ":"))"
        return cached(key) {
            IconRenderer.image(for: folder, size: points).rasterized(points: points)
        }
    }

    /// Vul de cache vooraf op de achtergrond, zodat de eerste klik meteen snel is.
    static func prewarm(_ paths: [String], points: CGFloat) {
        DispatchQueue.global(qos: .userInitiated).async {
            for path in paths { _ = appIcon(path, points: points) }
        }
    }

    private static func cached(_ key: String, make: () -> NSImage) -> NSImage {
        lock.lock()
        if let image = cache[key] {
            lock.unlock()
            return image
        }
        lock.unlock()
        let image = make()
        lock.lock()
        cache[key] = image
        lock.unlock()
        return image
    }
}
