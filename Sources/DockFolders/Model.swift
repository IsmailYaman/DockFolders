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
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .orange: "Orange"
        case .green: "Green"
        case .graphite: "Graphite"
        case .frost: "Light"
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
    var panel = PanelStyle()
    var grid = GridStyle()
    var icon = CustomIcon()

    init(id: UUID = UUID(), name: String, apps: [String] = [], tint: FolderTint = .blue,
         panel: PanelStyle = PanelStyle(), grid: GridStyle = GridStyle(), icon: CustomIcon = CustomIcon()) {
        self.id = id
        self.name = name
        self.apps = apps
        self.tint = tint
        self.panel = panel
        self.grid = grid
        self.icon = icon
    }

    // Ontbrekende velden (oudere folders.json) krijgen hun standaardwaarde.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        apps = try c.decodeIfPresent([String].self, forKey: .apps) ?? []
        tint = try c.decodeIfPresent(FolderTint.self, forKey: .tint) ?? .blue
        panel = try c.decodeIfPresent(PanelStyle.self, forKey: .panel) ?? PanelStyle()
        grid = try c.decodeIfPresent(GridStyle.self, forKey: .grid) ?? GridStyle()
        icon = try c.decodeIfPresent(CustomIcon.self, forKey: .icon) ?? CustomIcon()
    }

    /// Velden die het Dock-icoon of de bundle bepalen; alleen dan hoeft de bundle opnieuw gebouwd.
    func affectsBundle(comparedTo other: AppFolder) -> Bool {
        name != other.name || tint != other.tint || icon != other.icon
            || (!icon.enabled && apps.prefix(9) != other.apps.prefix(9))
    }
}

// MARK: - Raster en pagina's

enum IconSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var label: String { switch self { case .small: "S"; case .medium: "M"; case .large: "L" } }
    var points: CGFloat { switch self { case .small: 64; case .medium: 88; case .large: 112 } }
    var labelSize: CGFloat { switch self { case .small: 12; case .medium: 14; case .large: 15 } }
}

enum GridDensity: String, Codable, CaseIterable, Identifiable {
    case tight, normal, airy
    var id: String { rawValue }
    var label: String { switch self { case .tight: "Tight"; case .normal: "Normal"; case .airy: "Airy" } }
    var spacing: (horizontal: CGFloat, vertical: CGFloat) {
        switch self {
        case .tight: (2, 4)
        case .normal: (8, 10)
        case .airy: (18, 20)
        }
    }
}

struct GridStyle: Codable, Hashable {
    /// Automatisch aantal kolommen op basis van het aantal apps.
    var autoLayout = true
    /// Vast aantal kolommen als autoLayout uit staat.
    var columns = 4
    var iconSize = IconSize.medium
    var density = GridDensity.normal
    /// Maximaal aantal rijen per pagina; meer apps gaan naar een volgende pagina.
    var rowsPerPage = 4
    var hidePagination = false
    /// Puntje onder apps die draaien.
    var showRunning = true

    static let columnRange = 2...7
    static let rowRange = 1...6

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GridStyle()
        autoLayout = try c.decodeIfPresent(Bool.self, forKey: .autoLayout) ?? d.autoLayout
        columns = try c.decodeIfPresent(Int.self, forKey: .columns) ?? d.columns
        iconSize = try c.decodeIfPresent(IconSize.self, forKey: .iconSize) ?? d.iconSize
        density = try c.decodeIfPresent(GridDensity.self, forKey: .density) ?? d.density
        rowsPerPage = try c.decodeIfPresent(Int.self, forKey: .rowsPerPage) ?? d.rowsPerPage
        hidePagination = try c.decodeIfPresent(Bool.self, forKey: .hidePagination) ?? d.hidePagination
        showRunning = try c.decodeIfPresent(Bool.self, forKey: .showRunning) ?? d.showRunning
    }

    func columns(for count: Int) -> Int {
        guard autoLayout else { return columns }
        switch count {
        case 0...3: return max(count, 1)
        case 4: return 4
        case 5...9: return 3
        case 10...16: return 4
        default: return 5
        }
    }
}

// MARK: - Eigen map-icoon

enum CustomIconKind: String, Codable, CaseIterable, Identifiable {
    case emoji, symbol, image
    var id: String { rawValue }
    var label: String { switch self { case .emoji: "Emoji"; case .symbol: "Symbol"; case .image: "Image" } }
}

/// Optioneel eigen icoon in plaats van het raster met app-iconen. Standaard uit.
struct CustomIcon: Codable, Hashable {
    var enabled = false
    var kind = CustomIconKind.emoji
    var emoji = "📁"
    var symbol = "star.fill"
    /// Kopie van de gekozen afbeelding in Application Support.
    var imagePath: String?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CustomIcon()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        kind = try c.decodeIfPresent(CustomIconKind.self, forKey: .kind) ?? d.kind
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? d.emoji
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? d.symbol
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
    }
}

// MARK: - Uiterlijk van het paneel

enum PanelBackground: String, Codable, CaseIterable, Identifiable {
    case folderColor, clear, smoked, custom

    var id: String { rawValue }

    var name: String {
        switch self {
        case .folderColor: "Folder Color"
        case .clear: "Clear Glass"
        case .smoked: "Smoked Glass"
        case .custom: "Custom Color"
        }
    }
}

struct RGBAColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .systemBlue
        self.init(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
    }

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    static let defaultCustom = RGBAColor(red: 0.35, green: 0.30, blue: 0.85)
}

enum PanelAppearance { case light, dark, system }

struct PanelStyle: Codable, Hashable {
    var background: PanelBackground = .folderColor
    var customColor: RGBAColor = .defaultCustom
    var glass = true
    /// Hoe sterk de kleur in het glas doorkomt (0...1).
    var strength = 0.35
    /// Hoe doorzichtig het glas is (0 = normaal, 1 = bijna weg).
    var transparency = 0.0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PanelStyle()
        background = try c.decodeIfPresent(PanelBackground.self, forKey: .background) ?? d.background
        customColor = try c.decodeIfPresent(RGBAColor.self, forKey: .customColor) ?? d.customColor
        glass = try c.decodeIfPresent(Bool.self, forKey: .glass) ?? d.glass
        strength = try c.decodeIfPresent(Double.self, forKey: .strength) ?? d.strength
        transparency = try c.decodeIfPresent(Double.self, forKey: .transparency) ?? d.transparency
    }

    /// De kleur waar deze stijl op gebaseerd is.
    func baseColor(tint: FolderTint) -> NSColor {
        switch background {
        case .folderColor: tint.colors.0
        case .clear: .white
        case .smoked: .black
        case .custom: customColor.nsColor
        }
    }

    /// Tint over het glas, of nil voor puur glas.
    func glassTint(tint: FolderTint) -> NSColor? {
        switch background {
        case .folderColor:
            tint == .frost ? NSColor.white.withAlphaComponent(strength * 0.6)
                           : tint.colors.0.withAlphaComponent(strength)
        case .clear:
            strength > 0.01 ? NSColor.white.withAlphaComponent(strength * 0.5) : nil
        case .smoked:
            NSColor.black.withAlphaComponent(0.2 + strength * 0.6)
        case .custom:
            customColor.nsColor.withAlphaComponent(strength)
        }
    }

    /// Effen achtergrond als glas uit staat.
    func solidColor(tint: FolderTint) -> NSColor {
        switch background {
        case .folderColor: tint.colors.0
        case .clear: .windowBackgroundColor
        case .smoked: NSColor(white: 0.12, alpha: 1)
        case .custom: customColor.nsColor
        }
    }

    /// Lichte of donkere tekst, afhankelijk van hoe donker de achtergrond wordt.
    func appearance(tint: FolderTint) -> PanelAppearance {
        switch background {
        case .smoked: return .dark
        case .clear: return .system
        case .folderColor, .custom:
            let lum = baseColor(tint: tint).luminance
            if glass {
                return strength >= 0.45 && lum < 0.55 ? .dark : .system
            }
            return lum < 0.6 ? .dark : .light
        }
    }
}

extension NSColor {
    var luminance: Double {
        guard let c = usingColorSpace(.sRGB) else { return 0.5 }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }
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
