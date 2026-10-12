import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class ManagerAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ManagerApp: App {
    @NSApplicationDelegateAdaptor(ManagerAppDelegate.self) private var delegate
    @StateObject private var store = FolderStore()
    @State private var selection: UUID?

    var body: some Scene {
        Window("DockFolders", id: "main") {
            ContentView(selection: $selection)
                .environmentObject(store)
                .frame(minWidth: 760, minHeight: 480)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nieuwe map") { selection = store.addFolder() }
                    .keyboardShortcut("n")
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: FolderStore
    @Binding var selection: UUID?
    @State private var startAtLogin = LoginItem.isEnabled

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(store.folders) { folder in
                    Label {
                        Text(folder.name)
                    } icon: {
                        Image(nsImage: IconCache.folderIcon(folder, points: 22))
                            .resizable()
                            .frame(width: 22, height: 22)
                    }
                    .tag(folder.id)
                    .contextMenu {
                        Button("Verwijderen", role: .destructive) { store.delete(folder.id) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        selection = store.addFolder()
                    } label: {
                        Label("Nieuwe map", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    Toggle("Start bij inloggen", isOn: $startAtLogin)
                        .toggleStyle(.checkbox)
                        .onChange(of: startAtLogin) { _, on in LoginItem.setEnabled(on) }
                        .help("Zet je mappen in de Dock bij het inloggen klaar, zodat ze meteen openklappen")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
        } detail: {
            if let id = selection, store.folder(id) != nil {
                FolderDetailView(folderID: id, onDelete: { selection = nil })
                    .id(id)
            } else {
                ContentUnavailableView {
                    Label("Geen map gekozen", systemImage: "square.grid.3x3")
                } description: {
                    Text("Maak een map, voeg apps toe en zet hem in je Dock.")
                } actions: {
                    Button("Nieuwe map") { selection = store.addFolder() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear {
            if selection == nil { selection = store.folders.first?.id }
        }
    }
}

struct FolderDetailView: View {
    @EnvironmentObject private var store: FolderStore
    let folderID: UUID
    let onDelete: () -> Void

    @State private var name = ""
    @State private var inDock = false
    @State private var dropTargeted = false
    @State private var tab = DetailTab.apps
    @FocusState private var nameFocused: Bool

    enum DetailTab: String, CaseIterable {
        case apps = "Apps"
        case appearance = "Uiterlijk"
    }

    var body: some View {
        if let folder = store.folder(folderID) {
            VStack(spacing: 0) {
                header(folder)
                Picker("", selection: $tab) {
                    ForEach(DetailTab.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.bottom, 12)
                Divider()
                switch tab {
                case .apps: appList(folder)
                case .appearance: AppearanceView(folderID: folderID)
                }
            }
            .toolbar {
                ToolbarItem {
                    Button("Apps toevoegen", systemImage: "plus.app") { pickApps() }
                }
                ToolbarItem {
                    Button("Verwijder map", systemImage: "trash") {
                        store.delete(folderID)
                        onDelete()
                    }
                }
            }
            .onAppear {
                name = folder.name
                inDock = store.isInDock(folderID)
            }
            .onChange(of: store.revision) { inDock = store.isInDock(folderID) }
            .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
            .onDisappear { commitName() }
        }
    }

    private func header(_ folder: AppFolder) -> some View {
        HStack(alignment: .center, spacing: 20) {
            Image(nsImage: IconCache.folderIcon(folder, points: 112))
                .resizable()
                .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 12) {
                TextField("Naam", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .semibold))
                    .focused($nameFocused)
                    .onSubmit(commitName)

                HStack(spacing: 8) {
                    ForEach(FolderTint.allCases) { tint in
                        Circle()
                            .fill(tint.swatch)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(.black.opacity(0.12)))
                            .padding(3)
                            .overlay(
                                Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                                    .opacity(folder.tint == tint ? 1 : 0)
                            )
                            .help(tint.name)
                            .onTapGesture { store.update(folderID) { $0.tint = tint } }
                    }
                }

                HStack(spacing: 8) {
                    if inDock {
                        Button("Uit Dock halen", systemImage: "minus.circle") {
                            store.removeFromDock(folderID)
                        }
                    } else {
                        Button("Zet in Dock", systemImage: "dock.rectangle") {
                            commitName()
                            store.addToDock(folderID)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("Toon in Finder", systemImage: "folder") { store.revealInFinder(folderID) }
                }
                .controlSize(.regular)
            }
            Spacer()
        }
        .padding(20)
    }

    private func appList(_ folder: AppFolder) -> some View {
        List {
            ForEach(folder.apps, id: \.self) { path in
                AppRow(path: path) {
                    store.update(folderID) { $0.apps.removeAll { $0 == path } }
                }
            }
            .onMove { from, to in
                store.update(folderID) { $0.apps.move(fromOffsets: from, toOffset: to) }
            }
        }
        .overlay {
            if folder.apps.isEmpty {
                ContentUnavailableView {
                    Label("Sleep apps hierheen", systemImage: "arrow.down.app")
                } description: {
                    Text("Of klik op ‘Apps toevoegen…’. De eerste negen apps vormen het icoon.")
                } actions: {
                    Button("Apps toevoegen…") { pickApps() }
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, lineWidth: 3)
                .padding(6)
                .opacity(dropTargeted ? 1 : 0)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let apps = urls.filter { $0.pathExtension == "app" }
            store.addApps(apps, to: folderID)
            return !apps.isEmpty
        } isTargeted: { dropTargeted = $0 }
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            name = store.folder(folderID)?.name ?? ""
            return
        }
        store.update(folderID) { $0.name = trimmed }
    }

    private func pickApps() {
        let panel = NSOpenPanel()
        panel.title = "Kies apps"
        panel.prompt = "Toevoegen"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        store.addApps(panel.urls, to: folderID)
    }
}

struct AppRow: View {
    let path: String
    let remove: () -> Void
    @State private var hovering = false

    private var url: URL { URL(fileURLWithPath: path) }
    private var exists: Bool { FileManager.default.fileExists(atPath: path) }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: IconCache.appIcon(path, points: 32))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.appDisplayName)
                Text(exists ? url.deletingLastPathComponent().path : "Niet gevonden")
                    .font(.caption)
                    .foregroundStyle(exists ? Color.secondary : Color.red)
            }
            Spacer()
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Uit map verwijderen")
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Uit map verwijderen", action: remove)
            Button("Toon in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
}

/// Instellingen voor de achtergrond van het paneel, met live voorbeeld.
struct AppearanceView: View {
    @EnvironmentObject private var store: FolderStore
    let folderID: UUID

    private var style: PanelStyle { store.folder(folderID)?.panel ?? PanelStyle() }

    private func binding<T>(_ keyPath: WritableKeyPath<PanelStyle, T>) -> Binding<T> {
        Binding(
            get: { style[keyPath: keyPath] },
            set: { value in store.update(folderID) { $0.panel[keyPath: keyPath] = value } }
        )
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: style.customColor.nsColor) },
            set: { store.update(folderID) { [c = RGBAColor(NSColor($0))] f in f.panel.customColor = c } }
        )
    }

    var body: some View {
        if let folder = store.folder(folderID) {
            ScrollView {
                VStack(spacing: 0) {
                    preview(folder)
                    Form {
                        Section("Achtergrond") {
                            Picker("Stijl", selection: binding(\.background)) {
                                ForEach(PanelBackground.allCases) { Text($0.name).tag($0) }
                            }
                            if style.background == .custom {
                                ColorPicker("Kleur", selection: customColor, supportsOpacity: false)
                            }
                        }
                        Section {
                            Toggle("Glas", isOn: binding(\.glass))
                            if style.glass {
                                LabeledContent("Sterkte") {
                                    Slider(value: binding(\.strength), in: 0...1)
                                }
                                LabeledContent("Doorzichtigheid") {
                                    Slider(value: binding(\.transparency), in: 0...1)
                                }
                            }
                        } footer: {
                            Text(style.glass
                                 ? "Sterkte bepaalt hoeveel kleur er in het glas zit, doorzichtigheid hoeveel je erdoorheen ziet."
                                 : "Zonder glas krijgt het paneel een effen achtergrond.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Section {
                            Button("Standaard herstellen") {
                                store.update(folderID) { $0.panel = PanelStyle() }
                            }
                            .disabled(style == PanelStyle())
                        }
                    }
                    .formStyle(.grouped)
                    .scrollDisabled(true)
                    .frame(maxWidth: 520)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Het echte paneel op je bureaubladachtergrond, zodat je het glas goed ziet.
    private func preview(_ folder: AppFolder) -> some View {
        PanelPreview(folder: folder)
            .padding(28)
            .frame(maxWidth: .infinity)
            .background {
                Wallpaper()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding([.horizontal, .top], 20)
    }
}

/// De huidige bureaubladachtergrond (of een kleurverloop als die niet te lezen is).
struct Wallpaper: View {
    private static let image: NSImage? = {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        if let image = Self.image {
            // Via overlay: de afbeelding vult het vlak maar bepaalt de grootte niet.
            Color.clear.overlay {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipped()
        } else {
            LinearGradient(colors: [.indigo, .purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
