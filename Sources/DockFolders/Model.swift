import AppKit
import SwiftUI

enum Paths {
    static let folderIDKey = "DockFolderID"
    static let managerBundleID = "com.ismail.dockfolders"

    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DockFolders", isDirectory: true)
    }

    static var config: URL { support.appendingPathComponent("folders.json") }

    /// Hier komen de kleine .app-bundles die in de Dock staan.
    static var bundles: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/DockFolders", isDirectory: true)
    }
}

enum FolderTint: Int, CaseIterable, Codable, Identifiable {
    case blue, purple, pink, orange, green, graphite, frost

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .blue: "Blauw"
        case .purple: "Paars"
        case .pink: "Roze"
        case .orange: "Oranje"
        case .green: "Groen"
        case .graphite: "Grafiet"
        case .frost: "Licht"
        }
    }

    /// (boven, onder)
    var colors: (NSColor, NSColor) {
        func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
            NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
        }
        switch self {
        case .blue: return (c(94, 170, 255), c(28, 104, 230))
        case .purple: return (c(186, 128, 255), c(112, 60, 220))
        case .pink: return (c(255, 128, 170), c(222, 52, 112))
        case .orange: return (c(255, 190, 90), c(240, 120, 30))
        case .green: return (c(110, 220, 140), c(36, 160, 80))
        case .graphite: return (c(120, 124, 132), c(52, 54, 60))
        case .frost: return (c(250, 250, 252), c(214, 218, 226))
        }
    }

    var swatch: LinearGradient {
        LinearGradient(colors: [Color(nsColor: colors.0), Color(nsColor: colors.1)],
                       startPoint: .top, endPoint: .bottom)
    }
}

struct AppFolder: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    /// Absolute paden naar .app-bundles.
    var apps: [String] = []
    var tint: FolderTint = .blue
}

enum FolderStorage {
    static func load() -> [AppFolder] {
        guard let data = try? Data(contentsOf: Paths.config) else { return [] }
        return (try? JSONDecoder().decode([AppFolder].self, from: data)) ?? []
    }

    static func save(_ folders: [AppFolder]) {
        do {
            try FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(folders).write(to: Paths.config, options: .atomic)
        } catch {
            NSLog("DockFolders: opslaan mislukt: \(error)")
        }
    }
}

extension URL {
    var appDisplayName: String {
        FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
    }
}
