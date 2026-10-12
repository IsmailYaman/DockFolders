import AppKit
import SwiftUI

// Eén binary, meerdere modi:
//  1. Gekopieerd in een map-bundle (Info.plist bevat DockFolderID) → toon het mappaneel.
//  2. `--login` → bij inloggen alle map-apps in de Dock op de achtergrond starten.
//  3. `--render-panel <pad>` → debug: paneel van de eerste map naar PNG.
//  4. `--export-icon <pad>` → schrijf het app-icoon (gebruikt door build.sh).
//  5. Anders → de beheer-app.

let args = CommandLine.arguments

if let idString = Bundle.main.object(forInfoDictionaryKey: Paths.folderIDKey) as? String,
   let folderID = UUID(uuidString: idString) {
    let app = NSApplication.shared
    let delegate = LauncherDelegate(folderID: folderID)
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
} else if args.contains(LoginItem.argument) {
    LoginItem.launchFoldersInDock()
} else if let i = args.firstIndex(of: "--render-panel"), i + 1 < args.count {
    // Debug: render het paneel van de eerste map naar een PNG en print de berekende grootte.
    MainActor.assumeIsolated {
        guard let folder = FolderStorage.load().first else { exit(1) }
        let view = FolderPanelView(folder: folder, open: { _ in }, edit: {})
        let hosting = NSHostingView(rootView: view)
        print("fittingSize:", hosting.fittingSize)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let cg = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
            print("rendered:", cg.width / 2, "x", cg.height / 2)
        }
    }
} else if let i = args.firstIndex(of: "--export-icon"), i + 1 < args.count {
    let sample = AppFolder(
        name: "DockFolders",
        apps: ["/System/Applications/Notes.app", "/System/Applications/Calendar.app",
               "/System/Applications/Music.app", "/System/Applications/Maps.app",
               "/System/Applications/Photos.app", "/System/Applications/Reminders.app",
               "/System/Applications/Messages.app", "/System/Applications/Podcasts.app",
               "/System/Applications/Mail.app"],
        tint: .blue
    )
    do {
        try IconRenderer.writeICNS(for: sample, to: URL(fileURLWithPath: args[i + 1]))
    } catch {
        FileHandle.standardError.write("Icon export failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
} else {
    ManagerApp.main()
}
