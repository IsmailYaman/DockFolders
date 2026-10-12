import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class ManagerAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Debug: DOCKFOLDERS_SNAPSHOT=<pad.png> legt het eigen venster vast (geen schermopname-rechten nodig).
        if let path = ProcessInfo.processInfo.environment["DOCKFOLDERS_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                // Via de CALayer-boom: cacheDisplay slaat laag-inhoud (verlopen, glas) over.
                guard let view = NSApp.windows.first(where: \.isVisible)?.contentView,
                      let layer = view.layer,
                      let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2),
                                                 pixelsHigh: Int(view.bounds.height * 2), bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                      let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { return }
                ctx.scaleBy(x: 2, y: 2)
                if view.layer?.isGeometryFlipped == true || view.isFlipped {
                    ctx.translateBy(x: 0, y: view.bounds.height)
                    ctx.scaleBy(x: 1, y: -1)
                }
                layer.render(in: ctx)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}

struct ManagerApp: App {
    @NSApplicationDelegateAdaptor(ManagerAppDelegate.self) private var delegate
    @StateObject private var store = FolderStore()
    @State private var selection: UUID?

    var body: some Scene {
        Window("DockFolders", id: "main") {
            ContentView(selection: $selection)
                .environmentObject(store)
                .frame(minWidth: 1240, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Folder") { selection = store.addFolder() }
                    .keyboardShortcut("n")
            }
        }
    }
}

// MARK: - Layout: mappen | voorbeeld | instellingen

struct ContentView: View {
    @EnvironmentObject private var store: FolderStore
    @Binding var selection: UUID?

    var body: some View {
        HStack(spacing: 12) {
            FoldersSidebar(selection: $selection)
                .frame(width: 270)
                .paneBackground()

            Group {
                if let id = selection, store.folder(id) != nil {
                    PreviewStage(folderID: id)
                } else {
                    emptyStage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { Wallpaper() }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Group {
                if let id = selection, store.folder(id) != nil {
                    InspectorView(folderID: id, onDelete: { selection = store.folders.first?.id })
                        .id(id)
                } else {
                    Color.clear
                }
            }
            .frame(width: 340)
            .paneBackground()
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .onAppear {
            if selection == nil { selection = store.folders.first?.id }
        }
    }

    private var emptyStage: some View {
        VStack(spacing: 14) {
            Text("Create your first folder")
                .font(.system(size: 22, weight: .semibold))
            Button {
                selection = store.addFolder()
            } label: {
                Label("New Folder", systemImage: "plus")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glass)
        }
    }
}

private extension View {
    func paneBackground() -> some View {
        background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    func card() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Links: mappen

struct FoldersSidebar: View {
    @EnvironmentObject private var store: FolderStore
    @Binding var selection: UUID?
    @State private var showSettings = false
    @State private var startAtLogin = LoginItem.isEnabled

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Ruimte voor de vensterknoppen, met instellingen rechts.
            HStack {
                Spacer()
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Launch at login", isOn: $startAtLogin)
                            .toggleStyle(.switch)
                            .onChange(of: startAtLogin) { _, on in LoginItem.setEnabled(on) }
                        Text("Gets your Dock folders ready at login,\nso they open instantly.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                }
            }
            .frame(height: 28)
            .padding(.top, 10)

            if let id = selection, let folder = store.folder(id) {
                SelectedFolderHeader(folder: folder)
            }

            Text("My Folders")
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 4)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(store.folders) { folder in
                        FolderTile(folder: folder, selected: folder.id == selection)
                            .onTapGesture { selection = folder.id }
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    store.delete(folder.id)
                                    if selection == folder.id { selection = store.folders.first?.id }
                                }
                            }
                    }
                }
            }
            .scrollIndicators(.never)

            Button {
                selection = store.addFolder()
            } label: {
                Label("New Folder", systemImage: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
    }
}

private struct SelectedFolderHeader: View {
    @EnvironmentObject private var store: FolderStore
    let folder: AppFolder

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: IconCache.folderIcon(folder, points: 44))
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(store.isInDock(folder.id) ? "In your Dock" : "Not in your Dock")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.14))
        )
    }
}

private struct FolderTile: View {
    let folder: AppFolder
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: IconCache.folderIcon(folder, points: 64))
                .resizable()
                .frame(width: 64, height: 64)
            Text(folder.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(hovering || selected ? 0.07 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(selected ? 1 : 0)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering = $0 }
    }
}

// MARK: - Midden: voorbeeld

struct PreviewStage: View {
    @EnvironmentObject private var store: FolderStore
    let folderID: UUID
    @State private var inDock = false
    @State private var dropTargeted = false

    var body: some View {
        if let folder = store.folder(folderID) {
            ZStack {
                HStack(spacing: 30) {
                    // Zo ziet de map eruit in je Dock.
                    Image(nsImage: IconCache.folderIcon(folder, points: 120))
                        .resizable()
                        .frame(width: 120, height: 120)
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                    let size = PanelPreview.size(for: folder)
                    PanelPreview(folder: folder)
                        .frame(width: size.width, height: size.height)
                }
                .padding(40)

                VStack {
                    HStack {
                        Spacer()
                        Toggle(isOn: Binding(
                            get: { inDock },
                            set: { on in
                                inDock = on
                                on ? store.addToDock(folderID) : store.removeFromDock(folderID)
                            }
                        )) {
                            Text("In Dock")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .toggleStyle(.switch)
                        .padding(.leading, 14)
                        .padding(.trailing, 10)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                    }
                    Spacer()
                    Button {
                        AppPicker.pick { store.addApps($0, to: folderID) }
                    } label: {
                        Label("App Picker", systemImage: "plus.app")
                            .font(.system(size: 15, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                }
                .padding(18)

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 4)
                    .opacity(dropTargeted ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .dropDestination(for: URL.self) { urls, _ in
                let apps = urls.filter { $0.pathExtension == "app" }
                store.addApps(apps, to: folderID)
                return !apps.isEmpty
            } isTargeted: { dropTargeted = $0 }
            .onAppear { inDock = store.isInDock(folderID) }
            .onChange(of: folderID) { inDock = store.isInDock(folderID) }
            .onChange(of: store.revision) { inDock = store.isInDock(folderID) }
        }
    }
}

enum AppPicker {
    static func pick(_ completion: ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Choose Apps"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        completion(panel.urls)
    }
}

// MARK: - Rechts: instellingen

struct InspectorView: View {
    @EnvironmentObject private var store: FolderStore
    let folderID: UUID
    let onDelete: () -> Void
    @State private var tab = Tab.icon

    enum Tab: String, CaseIterable {
        case icon = "Icon"
        case popup = "Popup"
        case apps = "Apps"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Button {
                        tab = t
                    } label: {
                        VStack(spacing: 8) {
                            Text(t.rawValue)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(tab == t ? Color.primary : Color.secondary)
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(height: 3)
                                .opacity(tab == t ? 1 : 0)
                        }
                        .fixedSize()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            Divider()

            switch tab {
            case .icon: IconSettings(folderID: folderID, onDelete: onDelete)
            case .popup: PopupSettings(folderID: folderID)
            case .apps: AppsSettings(folderID: folderID)
            }
        }
    }
}

private struct IconSettings: View {
    @EnvironmentObject private var store: FolderStore
    let folderID: UUID
    let onDelete: () -> Void
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private let swatchColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        if let folder = store.folder(folderID) {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Name")
                        TextField("Name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                            .focused($nameFocused)
                            .onSubmit(commitName)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Color")
                        LazyVGrid(columns: swatchColumns, spacing: 10) {
                            ForEach(FolderTint.allCases) { tint in
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(tint.swatch)
                                    .frame(height: 44)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Color.accentColor, lineWidth: 2.5)
                                            .padding(-4)
                                            .opacity(folder.tint == tint ? 1 : 0)
                                    )
                                    .help(tint.name)
                                    .onTapGesture { store.update(folderID) { $0.tint = tint } }
                            }
                        }
                        .padding(4)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Folder")
                        Button {
                            store.revealInFinder(folderID)
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        Button(role: .destructive) {
                            store.delete(folderID)
                            onDelete()
                        } label: {
                            Label("Delete Folder", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                    }
                    .card()
                }
                .padding(16)
            }
            .onAppear { name = folder.name }
            .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
            .onDisappear { commitName() }
        }
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            name = store.folder(folderID)?.name ?? ""
            return
        }
        store.update(folderID) { $0.name = trimmed }
    }
}

private struct PopupSettings: View {
    @EnvironmentObject private var store: FolderStore
    let folderID: UUID

    private var folder: AppFolder? { store.folder(folderID) }
    private var style: PanelStyle { folder?.panel ?? PanelStyle() }

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

    private let choiceColumns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("Background")
                    LazyVGrid(columns: choiceColumns, spacing: 8) {
                        ForEach(PanelBackground.allCases) { bg in
                            BackgroundChoice(background: bg, folder: folder, selected: style.background == bg)
                                .onTapGesture { store.update(folderID) { $0.panel.background = bg } }
                        }
                    }
                    if style.background == .custom {
                        ColorPicker("Color", selection: customColor, supportsOpacity: false)
                            .padding(.top, 4)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Glass")
                                .font(.system(size: 15, weight: .semibold))
                            Text(style.glass ? "Liquid Glass behind your apps" : "Solid background")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: binding(\.glass))
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    if style.glass {
                        Divider()
                        SliderRow(title: "Strength", value: binding(\.strength))
                        SliderRow(title: "Transparency", value: binding(\.transparency))
                    }
                }
                .card()

                Button("Reset to Default") {
                    store.update(folderID) { $0.panel = PanelStyle() }
                }
                .disabled(style == PanelStyle())
                .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
    }
}

private struct BackgroundChoice: View {
    let background: PanelBackground
    let folder: AppFolder?
    let selected: Bool

    private var swatch: AnyShapeStyle {
        switch background {
        case .folderColor: AnyShapeStyle(folder?.tint.swatch ?? FolderTint.blue.swatch)
        case .clear: AnyShapeStyle(Color.white.opacity(0.35))
        case .smoked: AnyShapeStyle(Color.black.opacity(0.75))
        case .custom: AnyShapeStyle(Color(nsColor: folder?.panel.customColor.nsColor ?? .systemPurple))
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(swatch)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                .frame(width: 18, height: 18)
            Text(background.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                .opacity(selected ? 1 : 0)
        )
        .contentShape(Rectangle())
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: 0...1)
                .controlSize(.small)
        }
    }
}

private struct AppsSettings: View {
    @EnvironmentObject private var store: FolderStore
    let folderID: UUID

    var body: some View {
        if let folder = store.folder(folderID) {
            VStack(spacing: 0) {
                HStack {
                    SectionLabel("\(folder.apps.count) apps")
                    Spacer()
                    Button {
                        AppPicker.pick { store.addApps($0, to: folderID) }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                if folder.apps.isEmpty {
                    ContentUnavailableView {
                        Label("No apps yet", systemImage: "square.grid.3x3")
                    } description: {
                        Text("Drop apps on the preview or click ‘Add’. The first nine make up the icon.")
                    }
                } else {
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
                    .scrollContentBackground(.hidden)
                    Text("Drag to reorder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 12)
                }
            }
        }
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
                if !exists {
                    Text("Not found")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Remove from folder")
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Remove from Folder", action: remove)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
}

/// De huidige bureaubladachtergrond (of een kleurverloop als die niet te lezen is).
struct Wallpaper: View {
    private static let image: NSImage? = {
        // Staat de achtergrond in een afgeschermde map (bv. Downloads), dan krijgen we een leeg
        // plaatje terug; controleer daarom of er echt pixels zijn.
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let image = NSImage(contentsOf: url),
              image.isValid, image.size.width > 0 else { return nil }
        return image
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
            // Lijkt op de standaard macOS-achtergrond, zodat het glas iets heeft om te tonen.
            ZStack {
                LinearGradient(colors: [Color(red: 0.55, green: 0.75, blue: 0.95),
                                        Color(red: 0.93, green: 0.90, blue: 0.86),
                                        Color(red: 0.20, green: 0.45, blue: 0.90),
                                        Color(red: 0.05, green: 0.20, blue: 0.65)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color.white.opacity(0.35), .clear],
                               center: .init(x: 0.3, y: 0.55), startRadius: 0, endRadius: 420)
            }
        }
    }
}
