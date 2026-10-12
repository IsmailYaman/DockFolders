import AppKit
import Combine

@MainActor
final class FolderStore: ObservableObject {
    @Published private(set) var folders: [AppFolder]
    /// Wordt verhoogd na elke rebuild, zodat views (Dock-status, icoon) verversen.
    @Published private(set) var revision = 0

    private var pendingBuilds: [UUID: DispatchWorkItem] = [:]

    init() {
        folders = FolderStorage.load()
        // Altijd bijwerken bij starten, zodat bundles de nieuwste binary bevatten.
        for folder in folders {
            FolderBundleBuilder.terminateRunning(id: folder.id)
            if let url = try? FolderBundleBuilder.build(folder), DockManager.contains(url) {
                FolderBundleBuilder.launchInBackground(url)
            }
        }
        LoginItem.configure()
    }

    func folder(_ id: UUID) -> AppFolder? { folders.first { $0.id == id } }

    @discardableResult
    func addFolder() -> UUID {
        var name = "Nieuwe map"
        var n = 2
        while folders.contains(where: { $0.name == name }) {
            name = "Nieuwe map \(n)"
            n += 1
        }
        let folder = AppFolder(name: name, tint: FolderTint.allCases[folders.count % FolderTint.allCases.count])
        folders.append(folder)
        persist()
        rebuild(folder.id, delay: 0)
        return folder.id
    }

    func delete(_ id: UUID) {
        pendingBuilds[id]?.cancel()
        folders.removeAll { $0.id == id }
        persist()
        FolderBundleBuilder.remove(id: id)
        revision += 1
    }

    func update(_ id: UUID, _ change: (inout AppFolder) -> Void) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        var copy = folders[i]
        change(&copy)
        guard copy != folders[i] else { return }
        folders[i] = copy
        persist()
        rebuild(id)
    }

    func addApps(_ urls: [URL], to id: UUID) {
        let paths = urls.filter { $0.pathExtension == "app" }.map { $0.resolvingSymlinksInPath().path }
        update(id) { folder in
            for p in paths where !folder.apps.contains(p) { folder.apps.append(p) }
        }
    }

    // MARK: Dock

    func isInDock(_ id: UUID) -> Bool {
        guard let url = FolderBundleBuilder.bundleURL(for: id) else { return false }
        return DockManager.contains(url)
    }

    func addToDock(_ id: UUID) {
        guard let folder = folder(id), let url = try? FolderBundleBuilder.build(folder) else { return }
        DockManager.add(url)
        FolderBundleBuilder.launchInBackground(url)
        revision += 1
    }

    func removeFromDock(_ id: UUID) {
        guard let url = FolderBundleBuilder.bundleURL(for: id) else { return }
        DockManager.remove(url)
        // Een draaiende map-app buiten de Dock zou als los icoon blijven staan.
        FolderBundleBuilder.terminateRunning(id: id)
        revision += 1
    }

    func revealInFinder(_ id: UUID) {
        guard let url = FolderBundleBuilder.bundleURL(for: id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Private

    private func persist() {
        FolderStorage.save(folders)
    }

    private func rebuild(_ id: UUID, delay: TimeInterval = 0.3) {
        pendingBuilds[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let folder = self.folder(id) else { return }
            do {
                let url = try FolderBundleBuilder.build(folder)
                if DockManager.contains(url) { DockManager.restart(after: 0.8) }
            } catch {
                NSLog("DockFolders: bouwen mislukt: \(error)")
            }
            self.revision += 1
        }
        pendingBuilds[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
