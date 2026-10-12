import Foundation

/// Start DockFolders bij inloggen via een LaunchAgent. Die draait `DockFolders --login`, wat alle
/// map-apps in de Dock op de achtergrond opstart, zodat een klik ze direct openklapt.
enum LoginItem {
    static let label = "\(Paths.managerBundleID).login"
    static let argument = "--login"
    private static let setupKey = "loginItemConfigured"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(true, forKey: setupKey)
        guard enabled else {
            try? FileManager.default.removeItem(at: plistURL)
            return
        }
        guard let exe = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exe, argument],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } catch {
            NSLog("DockFolders: login-item schrijven mislukt: \(error)")
        }
    }

    /// Standaard aan bij de eerste start; daarna het pad bijwerken (de app kan verplaatst zijn).
    static func configure() {
        if !UserDefaults.standard.bool(forKey: setupKey) || isEnabled {
            setEnabled(true)
        }
    }

    /// Uitgevoerd door de LaunchAgent bij inloggen.
    /// Via `open`: vanuit dit proces zonder vensters geeft NSWorkspace de argumenten niet door.
    static func launchFoldersInDock() {
        for url in FolderBundleBuilder.existingBundles().values where DockManager.contains(url) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-g", url.path, "--args", FolderBundleBuilder.backgroundArgument]
            try? p.run()
            p.waitUntilExit()
        }
    }
}
