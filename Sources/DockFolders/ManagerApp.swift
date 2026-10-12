import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class ManagerAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Debug: DOCKFOLDERS_SNAPSHOT=<pad.png> legt het eigen venster vast (geen schermopname-rechten nodig).
        if let path = ProcessInfo.processInfo.environment["DOCKFOLDERS_SNAPSHOT"] {
            // DOCKFOLDERS_SNAPSHOT_MIN=1: eerst naar de kleinst toegestane vensterbreedte.
            if ProcessInfo.processInfo.environment["DOCKFOLDERS_SNAPSHOT_MIN"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    guard let window = NSApp.windows.first(where: \.isVisible) else { return }
                    var frame = window.frame
                    frame.size.width = window.minSize.width
                    window.setFrame(frame, display: true)
                }
            }
            // DOCKFOLDERS_CLICK="x,y" (punten vanaf linksboven): klik via window.sendEvent, net als een echte muisklik.
            if let click = ProcessInfo.processInfo.environment["DOCKFOLDERS_CLICK"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    guard let window = NSApp.windows.first(where: \.isVisible) else { return }
                    // Zoals bij een echte klik: de app is dan actief.
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                    let xy = click.split(separator: ",").compactMap { Double($0) }
                    let point = NSPoint(x: xy[0], y: window.frame.height - xy[1])
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                                          windowNumber: window.windowNumber, context: nil,
                                                          eventNumber: 0, clickCount: 1, pressure: 1) {
                            window.sendEvent(event)
                        }
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                // Via de CALayer-boom: cacheDisplay slaat laag-inhoud (verlopen, glas) over.
                // Het kader rond de inhoud, zodat ook de vensterknoppen erop staan.
                guard let content = NSApp.windows.first(where: \.isVisible)?.contentView,
                      let view = content.superview ?? Optional(content),
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

enum Layout {
    /// Eén maat voor de rand van het venster én de ruimte tussen de kolommen.
    static let gap: CGFloat = 8
    static let sidebarWidth: CGFloat = 270
    static let inspectorWidth: CGFloat = 340
    static let paneRadius: CGFloat = 18
    /// Binnenmarge van het voorbeeld rond het paneel.
    static let stageInset: CGFloat = 32
}

struct ContentView: View {
    @EnvironmentObject private var store: FolderStore
    @Binding var selection: UUID?

    /// Het midden moet minstens het paneel kunnen tonen (het Dock-icoon kan erboven); de
    /// minimale vensterbreedte volgt daaruit, zodat de kolommen nooit buiten het venster vallen.
    private var minWidth: CGFloat {
        let panel = selection.flatMap(store.folder).map { PanelPreview.size(for: $0).width } ?? 0
        // Begrensd: een groter paneel wordt in het voorbeeld verkleind.
        let stage = max(420, min(panel + 2 * Layout.stageInset, 640))
        return Layout.sidebarWidth + stage + Layout.inspectorWidth + 4 * Layout.gap
    }

    var body: some View {
        HStack(spacing: Layout.gap) {
            FoldersSidebar(selection: $selection)
                .frame(width: Layout.sidebarWidth)
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
            .clipShape(RoundedRectangle(cornerRadius: Layout.paneRadius, style: .continuous))

            Group {
                if let id = selection, store.folder(id) != nil {
                    InspectorView(folderID: id, onDelete: { selection = store.folders.first?.id })
                        .id(id)
                } else {
                    Color.clear
                }
            }
            .frame(width: Layout.inspectorWidth)
            .paneBackground()
        }
        .padding(Layout.gap)
        .frame(minWidth: minWidth, minHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowConfigurator())
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
            RoundedRectangle(cornerRadius: Layout.paneRadius, style: .continuous)
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
        // Boven minder ruimte: de rij met het tandwiel valt zo gelijk met de vensterknoppen.
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .padding(.top, WindowConfigurator.buttonRowTop)
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
    @EnvironmentObject var store: FolderStore
    let folderID: UUID
    @State private var inDock = false
    @State private var dropTargeted = false

    var body: some View {
        if let folder = store.folder(folderID) {
            ZStack {
                let size = PanelPreview.size(for: folder)
                GeometryReader { geo in
                    // Ruimte binnen de marges, minus de In Dock-schakelaar boven en de knop onder.
                    let room = CGSize(width: geo.size.width - 2 * Layout.stageInset,
                                      height: geo.size.height - 2 * Layout.stageInset - 120)
                    // Naast elkaar als het past, anders het Dock-icoon boven het paneel.
                    let beside = size.width + 150 <= room.width
                    let panelRoom = beside ? CGSize(width: room.width - 150, height: room.height)
                                           : CGSize(width: room.width, height: room.height - 112)
                    // Groot raster? Dan het voorbeeld verkleinen in plaats van het venster op te rekken.
                    let scale = max(0.3, min(1, panelRoom.width / size.width, panelRoom.height / size.height))
                    let panel = PanelPreview(folder: folder, actions: previewActions)
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(scale)
                        .frame(width: size.width * scale, height: size.height * scale)

                    Group {
                        if beside {
                            HStack(spacing: 30) {
                                dockIcon(folder, size: 120)
                                panel
                            }
                        } else {
                            VStack(spacing: 24) {
                                dockIcon(folder, size: 88)
                                panel
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }

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

extension PreviewStage {
    /// In het voorbeeld werken slepen en verwijderen ook; openen en hernoemen niet.
    var previewActions: PanelActions {
        var actions = PanelActions()
        actions.reorder = { order in
            store.update(folderID) { $0.apps = order + $0.apps.filter { !order.contains($0) } }
        }
        actions.remove = { path in
            store.update(folderID) { $0.apps.removeAll { $0 == path } }
        }
        return actions
    }
}

/// Zo ziet de map eruit in je Dock.
private func dockIcon(_ folder: AppFolder, size: CGFloat) -> some View {
    Image(nsImage: IconCache.folderIcon(folder, points: size))
        .resizable()
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
}

/// Zet de vensterknoppen netjes binnen de zijbalk, op dezelfde hoogte als het tandwiel en de
/// tabbladen. Geen NSToolbar daarvoor gebruiken: die vangt alle klikken in de bovenste strook af
/// (tabbladen, tandwiel, In Dock-schakelaar werkten dan niet).
struct WindowConfigurator: NSViewRepresentable {
    /// Hoogte van de titelbalkstrook; de knoppen staan verticaal in het midden (26 pt).
    static let titlebarHeight: CGFloat = 52
    /// Bovenmarge binnen een kolom waarbij een rij van 28 pt gelijk valt met de vensterknoppen.
    static let buttonRowTop: CGFloat = titlebarHeight / 2 - Layout.gap - 14
    /// Afstand van de sluitknop tot de linkerrand van het venster (binnen de zijbalk).
    static let buttonLeading: CGFloat = Layout.gap + 14

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.configure(view.window, coordinator: context.coordinator) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var observers: [NSObjectProtocol] = []
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }

    private static func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window, coordinator.observers.isEmpty else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        layoutButtons(in: window)
        // AppKit zet de knoppen terug bij o.a. vergroten en volledig scherm.
        let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                                          NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification,
                                          NSWindow.didResignKeyNotification]
        coordinator.observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak window] _ in
                if let window { layoutButtons(in: window) }
            }
        }
    }

    static func layoutButtons(in window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let titlebar = close.superview, let container = titlebar.superview else { return }
        let height = titlebarHeight
        container.frame = NSRect(x: 0, y: window.frame.height - height, width: window.frame.width, height: height)
        titlebar.frame = container.bounds
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (index, type) in buttons.enumerated() {
            guard let button = window.standardWindowButton(type) else { continue }
            button.setFrameOrigin(NSPoint(x: buttonLeading + CGFloat(index) * 20,
                                          y: (height - button.frame.height) / 2))
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
        case grid = "Grid"
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
            // Tabtitels op dezelfde hoogte als de vensterknoppen.
            .padding(.top, WindowConfigurator.buttonRowTop + 4)
            Divider()

            switch tab {
            case .icon: IconSettings(folderID: folderID, onDelete: onDelete)
            case .popup: PopupSettings(folderID: folderID)
            case .grid: GridSettings(folderID: folderID)
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
                            ForEach(FolderTint.presets) { tint in
                                Button {
                                    store.update(folderID) { $0.tint = tint }
                                } label: {
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
                                }
                                .buttonStyle(.plain)
                                .help(tint.name)
                            }
                            CustomTintSwatch(folder: folder)
                        }
                        .padding(4)
                    }
                    .card()

                    CustomIconCard(folderID: folderID)

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
            .onDisappear { ColorPanelBridge.shared.detach() }
            // Hernoemd vanuit het paneel in de Dock: naamveld bijwerken (tenzij je er net in typt).
            .onChange(of: folder.name) { _, newName in
                if !nameFocused { name = newName }
            }
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

/// Laatste blokje bij de kleuren: kiest een eigen kleur via het kleurenpaneel van macOS.
private struct CustomTintSwatch: View {
    @EnvironmentObject private var store: FolderStore
    let folder: AppFolder

    private var selected: Bool { folder.tint == .custom }

    var body: some View {
        Button(action: pick) { swatch }
            .buttonStyle(.plain)
            .help("Custom color")
    }

    private func pick() {
        let id = folder.id
        store.update(id) { $0.tint = .custom }
        ColorPanelBridge.shared.open(color: folder.customTint.nsColor) { color in
            store.update(id) { $0.tint = .custom; $0.customTint = RGBAColor(color) }
        }
    }

    private var swatch: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(selected ? AnyShapeStyle(folder.tintSwatch)
                           : AnyShapeStyle(AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan,
                                                                    .blue, .purple, .pink, .red],
                                                           center: .center)))
            .frame(height: 44)
            .overlay {
                Image(systemName: selected ? "eyedropper" : "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 2)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
                    .padding(-4)
                    .opacity(selected ? 1 : 0)
            )
            .contentShape(Rectangle())
    }
}

/// Koppelt het gedeelde kleurenpaneel van macOS aan één callback (de map die je nu bewerkt).
final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()
    private var onChange: ((NSColor) -> Void)?

    func open(color: NSColor, onChange: @escaping (NSColor) -> Void) {
        self.onChange = nil
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = color
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        self.onChange = onChange
        panel.orderFront(nil)
    }

    /// Andere map gekozen: het paneel mag de vorige map niet meer aanpassen.
    func detach() { onChange = nil }

    @objc private func changed(_ sender: NSColorPanel) {
        onChange?(sender.color)
    }
}

/// Optioneel eigen map-icoon (standaard uit): emoji, SF Symbol of afbeelding.
private struct CustomIconCard: View {
    @EnvironmentObject private var store: FolderStore
    let folderID: UUID
    @FocusState private var emojiFocused: Bool

    private var icon: CustomIcon { store.folder(folderID)?.icon ?? CustomIcon() }

    private func binding<T>(_ keyPath: WritableKeyPath<CustomIcon, T>) -> Binding<T> {
        Binding(
            get: { icon[keyPath: keyPath] },
            set: { value in store.update(folderID) { $0.icon[keyPath: keyPath] = value } }
        )
    }

    private static let symbols = [
        "star.fill", "heart.fill", "bolt.fill", "flame.fill", "leaf.fill", "moon.fill",
        "briefcase.fill", "hammer.fill", "paintbrush.fill", "camera.fill", "music.note", "gamecontroller.fill",
        "terminal.fill", "globe", "book.fill", "cart.fill", "message.fill", "folder.fill",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom icon")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Use an emoji, symbol or image instead of the app grid.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: binding(\.enabled))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if icon.enabled {
                Picker("", selection: binding(\.kind)) {
                    ForEach(CustomIconKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch icon.kind {
                case .emoji:
                    HStack {
                        TextField("Emoji", text: Binding(
                            get: { icon.emoji },
                            // Eén teken (een emoji kan uit meerdere scalars bestaan).
                            set: { value in store.update(folderID) { $0.icon.emoji = String(value.suffix(1)) } }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 20))
                        .frame(width: 60)
                        .focused($emojiFocused)
                        Button("Emoji Picker…") {
                            emojiFocused = true
                            DispatchQueue.main.async { NSApp.orderFrontCharacterPalette(nil) }
                        }
                    }

                case .symbol:
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                        ForEach(Self.symbols, id: \.self) { name in
                            Image(systemName: name)
                                .font(.system(size: 16))
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(icon.symbol == name ? Color.accentColor.opacity(0.25)
                                                                  : Color.primary.opacity(0.05))
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { store.update(folderID) { $0.icon.symbol = name } }
                                .help(name)
                        }
                    }
                    TextField("SF Symbol name", text: binding(\.symbol))
                        .textFieldStyle(.roundedBorder)

                case .image:
                    HStack {
                        Button("Choose Image…", action: chooseImage)
                        if let path = icon.imagePath {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
        .card()
    }

    /// Kopie in Application Support, zodat het icoon blijft werken als het origineel verdwijnt.
    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let dir = Paths.support.appendingPathComponent("Icons", isDirectory: true)
        let dest = dir.appendingPathComponent("\(folderID.uuidString)-\(UUID().uuidString).\(source.pathExtension)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: dest)
            let old = icon.imagePath
            store.update(folderID) { $0.icon.imagePath = dest.path }
            if let old { try? FileManager.default.removeItem(atPath: old) }
        } catch {
            NSLog("DockFolders: afbeelding kopiëren mislukt: \(error)")
        }
    }
}

/// Raster, pagina's en draaiende apps.
private struct GridSettings: View {
    @EnvironmentObject private var store: FolderStore
    let folderID: UUID

    private var grid: GridStyle { store.folder(folderID)?.grid ?? GridStyle() }

    private func binding<T>(_ keyPath: WritableKeyPath<GridStyle, T>) -> Binding<T> {
        Binding(
            get: { grid[keyPath: keyPath] },
            set: { value in store.update(folderID) { $0.grid[keyPath: keyPath] = value } }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    ToggleRow(title: "Auto layout",
                              detail: grid.autoLayout ? "Columns adapt to the number of apps."
                                                      : "Pick the column count below — rows flow as needed.",
                              isOn: binding(\.autoLayout))
                    if !grid.autoLayout {
                        Picker("", selection: binding(\.columns)) {
                            ForEach(Array(GridStyle.columnRange), id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel("Apps grid")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icon size").font(.system(size: 13))
                        Picker("", selection: binding(\.iconSize)) {
                            ForEach(IconSize.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Density").font(.system(size: 13))
                        Picker("", selection: binding(\.density)) {
                            ForEach(GridDensity.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    Divider()
                    ToggleRow(title: "Show running apps",
                              detail: "A dot under apps that are open.",
                              isOn: binding(\.showRunning))
                }
                .card()

                VStack(alignment: .leading, spacing: 14) {
                    ToggleRow(title: "Magnification",
                              detail: "Icons grow as the pointer moves over them, like the Dock.",
                              isOn: binding(\.magnification))
                    if grid.magnification {
                        VStack(spacing: 4) {
                            Slider(value: binding(\.magnificationAmount), in: 0...1)
                                .controlSize(.small)
                            HStack {
                                Text("Small")
                                Spacer()
                                Text("Large")
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel("Pages")
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Rows per page").font(.system(size: 13))
                            Text("More apps continue on the next page.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Stepper("\(grid.rowsPerPage)", value: binding(\.rowsPerPage), in: GridStyle.rowRange)
                            .monospacedDigit()
                    }
                    Divider()
                    ToggleRow(title: "Hide pagination",
                              detail: "Swipe, scroll or use the arrow keys to change pages.",
                              isOn: binding(\.hidePagination))
                }
                .card()

                Button("Reset to Default") {
                    store.update(folderID) { $0.grid = GridStyle() }
                }
                .disabled(grid == GridStyle())
                .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
    }
}

private struct ToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
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
        case .folderColor: AnyShapeStyle(folder?.tintSwatch ?? FolderTint.blue.swatch)
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
