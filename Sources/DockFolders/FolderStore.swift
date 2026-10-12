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
        watchConfig()
        // Uitgestelde opslag niet kwijtraken bij afsluiten.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    func folder(_ id: UUID) -> AppFolder? { folders.first { $0.id == id } }

    @discardableResult
    func addFolder() -> UUID {
        var name = "New Folder"
        var n = 2
        while folders.contains(where: { $0.name == name }) {
            name = "New Folder \(n)"
            n += 1
        }
        let folder = AppFolder(name: name, tint: FolderTint.presets[folders.count % FolderTint.presets.count])
        folders.append(folder)
        persist()
        rebuild(folder.id, delay: 0)
        return folder.id
    }

    func delete(_ id: UUID) {
        pendingBuilds[id]?.cancel()
        if let image = folder(id)?.icon.imagePath { try? FileManager.default.removeItem(atPath: image) }
        folders.removeAll { $0.id == id }
        persist()
        FolderBundleBuilder.remove(id: id)
        revision += 1
    }

    func update(_ id: UUID, _ change: (inout AppFolder) -> Void) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        var copy = folders[i]
        change(&copy)
        let old = folders[i]
        guard copy != old else { return }
        folders[i] = copy
        persist()
        // Uiterlijk van het paneel leest de map-app zelf bij elke klik; geen rebuild of Dock-herstart nodig.
        if copy.affectsBundle(comparedTo: old) { rebuild(id) }
    }

    func addApps(_ urls: [URL], to id: UUID) {
        let paths = urls.filter { $0.pathExtension == "app" }.map { $0.resolvingSymlinksInPath().path }
        update(id) { folder in
            for p in paths where !folder.apps.contains(p) { folder.apps.append(p) }
        }
    }

    // MARK: Dock

    private var dockCache: (revision: Int, ids: [UUID: Bool]) = (-1, [:])

    /// Gecachet per revisie: dit leest de Dock-voorkeuren en een map op schijf, en views vragen
    /// het bij elke update op (bv. tijdens het slepen van een schuifje).
    func isInDock(_ id: UUID) -> Bool {
        if dockCache.revision != revision { dockCache = (revision, [:]) }
        if let cached = dockCache.ids[id] { return cached }
        let inDock = FolderBundleBuilder.bundleURL(for: id).map(DockManager.contains) ?? false
        dockCache.ids[id] = inDock
        return inDock
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

    private var pendingSave: DispatchWorkItem?
    private var configWatcher: DispatchSourceFileSystemObject?

    /// Map-apps kunnen folders.json zelf aanpassen (bv. hernoemen vanuit het paneel). Houd de map
    /// in de gaten en lees wijzigingen van buitenaf in, anders overschrijft de volgende opslag ze.
    /// (De map, niet het bestand: opslaan is atomisch en vervangt het bestand.)
    private func watchConfig() {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        let fd = open(Paths.support.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reloadFromDisk() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        configWatcher = source
    }

    private func reloadFromDisk() {
        // Eigen wijziging onderweg? Die is nieuwer en wordt zo opgeslagen.
        guard pendingSave == nil else { return }
        let disk = FolderStorage.load()
        guard !disk.isEmpty, disk != folders else { return }
        folders = disk
        revision += 1
    }

    private func flush() {
        guard let pending = pendingSave else { return }
        pending.cancel()
        pendingSave = nil
        FolderStorage.save(folders)
    }

    /// Kort uitgesteld: een schuifje slepen geeft tientallen wijzigingen per seconde.
    private func persist() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSave = nil
            FolderStorage.save(self.folders)
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
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
