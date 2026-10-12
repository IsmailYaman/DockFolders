import Foundation

/// Leest en schrijft de vaste apps in de Dock (com.apple.dock → persistent-apps).
enum DockManager {
    private static let domain = "com.apple.dock" as CFString
    private static let key = "persistent-apps" as CFString

    private static func tiles() -> [[String: Any]] {
        CFPreferencesAppSynchronize(domain)
        return (CFPreferencesCopyAppValue(key, domain) as? [[String: Any]]) ?? []
    }

    private static func setTiles(_ tiles: [[String: Any]]) {
        CFPreferencesSetAppValue(key, tiles as NSArray, domain)
        CFPreferencesAppSynchronize(domain)
    }

    private static func path(of tile: [String: Any]) -> String? {
        guard let data = tile["tile-data"] as? [String: Any],
              let file = data["file-data"] as? [String: Any],
              let string = file["_CFURLString"] as? String,
              let url = URL(string: string) else { return nil }
        return url.standardizedFileURL.path
    }

    private static func tile(for url: URL) -> [String: Any] {
        [
            "tile-type": "file-tile",
            "tile-data": [
                "file-label": url.deletingPathExtension().lastPathComponent,
                "file-data": [
                    "_CFURLString": url.absoluteString,
                    "_CFURLStringType": 15,
                ],
            ] as [String: Any],
        ]
    }

    static func contains(_ url: URL) -> Bool {
        let target = url.standardizedFileURL.path
        return tiles().contains { path(of: $0) == target }
    }

    static func add(_ url: URL) {
        guard !contains(url) else { return }
        setTiles(tiles() + [tile(for: url)])
        restart()
    }

    static func remove(_ url: URL) {
        let target = url.standardizedFileURL.path
        let current = tiles()
        let filtered = current.filter { path(of: $0) != target }
        guard filtered.count != current.count else { return }
        setTiles(filtered)
        restart()
    }

    /// Na hernoemen van een map: zelfde plek in de Dock, nieuw pad.
    static func replace(_ old: URL, with new: URL) {
        let target = old.standardizedFileURL.path
        var changed = false
        let updated = tiles().map { t -> [String: Any] in
            guard path(of: t) == target else { return t }
            changed = true
            return tile(for: new)
        }
        guard changed else { return }
        setTiles(updated)
        restart()
    }

    private static var pendingRestart: DispatchWorkItem?

    /// De Dock cachet iconen; herstarten is de enige betrouwbare manier om een nieuw icoon te tonen.
    static func restart(after delay: TimeInterval = 0.4) {
        pendingRestart?.cancel()
        let work = DispatchWorkItem {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            p.arguments = ["Dock"]
            try? p.run()
        }
        pendingRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
