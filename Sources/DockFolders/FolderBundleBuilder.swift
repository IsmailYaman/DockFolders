import AppKit

/// Maakt per map een mini-.app in ~/Applications/DockFolders. Die bundle bevat een kopie van
/// deze binary; bij starten ziet hij DockFolderID in zijn Info.plist en toont hij het mappaneel.
enum FolderBundleBuilder {
    static let executableName = "DockFolders"

    /// Alle bestaande map-bundles, per map-id.
    static func existingBundles() -> [UUID: URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: Paths.bundles, includingPropertiesForKeys: nil) else {
            return [:]
        }
        var result: [UUID: URL] = [:]
        for url in items where url.pathExtension == "app" {
            if let id = folderID(of: url) { result[id] = url }
        }
        return result
    }

    static func folderID(of bundle: URL) -> UUID? {
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plist),
              let string = dict[Paths.folderIDKey] as? String else { return nil }
        return UUID(uuidString: string)
    }

    static func bundleURL(for id: UUID) -> URL? { existingBundles()[id] }

    private static func fileName(for folder: AppFolder, avoiding taken: Set<String>) -> String {
        var base = folder.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty || base.hasPrefix(".") { base = "Folder" }
        var candidate = base
        var n = 2
        while taken.contains(candidate.lowercased()) {
            candidate = "\(base) \(n)"
            n += 1
        }
        return candidate
    }

    /// Bouwt (of werkt bij) de bundle. Geeft de URL terug en of het pad veranderd is.
    @discardableResult
    static func build(_ folder: AppFolder) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: Paths.bundles, withIntermediateDirectories: true)

        let existing = existingBundles()
        let taken = Set(existing.filter { $0.key != folder.id }
            .map { $0.value.deletingPathExtension().lastPathComponent.lowercased() })
        let dest = Paths.bundles.appendingPathComponent(fileName(for: folder, avoiding: taken) + ".app")

        // Vóór een eventuele verplaatsing vastleggen: hernoemt een map-app zichzelf, dan staat zijn
        // eigen binary na de verplaatsing op een nieuwe plek.
        guard var source = Bundle.main.executableURL?.standardizedFileURL else { throw CocoaError(.fileNoSuchFile) }

        // Hernoemd? Verplaats de bestaande bundle en werk de Dock bij.
        if let old = existing[folder.id], old.standardizedFileURL != dest.standardizedFileURL {
            let oldPath = old.standardizedFileURL.path + "/"
            if source.path.hasPrefix(oldPath) {
                source = URL(fileURLWithPath: dest.standardizedFileURL.path + "/" + source.path.dropFirst(oldPath.count))
            }
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: old, to: dest)
            DockManager.replace(old, with: dest)
        }

        let contents = dest.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        let resources = contents.appendingPathComponent("Resources")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        // Binary: eerst kopiëren naar een tijdelijk bestand en dat op de plek zetten. Zo krijgt de
        // bundle een nieuw bestand, en blijft een draaiend proces (ook een map-app die zichzelf
        // bijwerkt) zijn oude bestand houden; codesign past alleen het nieuwe aan.
        let exe = macOS.appendingPathComponent(executableName)
        let temp = macOS.appendingPathComponent(".\(executableName).\(UUID().uuidString)")
        try fm.copyItem(at: source, to: temp)
        if fm.fileExists(atPath: exe.path) { try fm.removeItem(at: exe) }
        try fm.moveItem(at: temp, to: exe)

        // Info.plist
        let info: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": executableName,
            "CFBundleIdentifier": bundleID(for: folder.id),
            "CFBundleName": folder.name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "CFBundleIconFile": "FolderIcon",
            "LSMinimumSystemVersion": "26.0",
            "NSHighResolutionCapable": true,
            // Apps op het map-icoon in de Dock slepen voegt ze toe aan de map.
            "CFBundleDocumentTypes": [[
                "CFBundleTypeName": "Application",
                "CFBundleTypeRole": "Viewer",
                "LSHandlerRank": "None",
                "LSItemContentTypes": ["com.apple.application-bundle"],
            ]],
            Paths.folderIDKey: folder.id.uuidString,
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plistData.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)

        // Icoon
        try IconRenderer.writeICNS(for: folder, to: resources.appendingPathComponent("FolderIcon.icns"))

        codesign(dest)
        // LaunchServices cachet de Info.plist; forceer dat hij de nieuwe versie leest.
        run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            ["-f", dest.path])
        // Mod-datum aanraken zodat LaunchServices/Finder het nieuwe icoon oppikken.
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: dest.path)
        NSWorkspace.shared.noteFileSystemChanged(dest.path)
        return dest
    }

    static let backgroundArgument = "--background"

    /// Start een map-app zonder paneel en zonder focus te pakken. Doet niets als hij al draait
    /// (anders krijgt hij een "reopen" en klapt het paneel open).
    static func launchInBackground(_ url: URL, completion: (() -> Void)? = nil) {
        guard let id = folderID(of: url),
              NSRunningApplication.runningApplications(withBundleIdentifier: bundleID(for: id)).isEmpty else {
            completion?()
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        config.arguments = [backgroundArgument]
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error { NSLog("DockFolders: starten mislukt: \(error)") }
            completion?()
        }
    }

    static func bundleID(for id: UUID) -> String {
        "\(Paths.managerBundleID).folder.\(id.uuidString.lowercased())"
    }

    /// Map-apps blijven draaien na de eerste klik; sluit ze af zodat ze de nieuwe binary laden.
    static func terminateRunning(id: UUID) {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID(for: id)) {
            app.terminate()
        }
    }

    static func remove(id: UUID) {
        terminateRunning(id: id)
        guard let url = bundleURL(for: id) else { return }
        DockManager.remove(url)
        try? FileManager.default.removeItem(at: url)
    }

    private static func codesign(_ url: URL) {
        run("/usr/bin/codesign", ["--force", "--sign", "-", url.path])
    }

    private static func run(_ tool: String, _ arguments: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = arguments
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            NSLog("DockFolders: \(tool) mislukt: \(error)")
        }
    }
}
