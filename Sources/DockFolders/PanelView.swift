import AppKit
import Combine
import SwiftUI

/// Wat het paneel met gebruikersacties doet. Het paneel in de Dock en het voorbeeld in de
/// beheer-app vullen dit elk op hun eigen manier in; nil = actie niet beschikbaar.
struct PanelActions {
    var open: (URL) -> Void = { _ in }
    var edit: () -> Void = {}
    var rename: ((String) -> Void)?
    /// Nieuwe volgorde van de app-paden (alleen bestaande apps).
    var reorder: (([String]) -> Void)?
    var remove: ((String) -> Void)?
}

/// Bladeren via scrollen/vegen: het AppKit-venster ziet de scroll-events, het SwiftUI-paneel
/// houdt de huidige pagina bij.
enum PagingSignal {
    static let name = Notification.Name("DockFoldersPageSwipe")
    static func post(_ direction: Int) {
        NotificationCenter.default.post(name: name, object: nil, userInfo: ["direction": direction])
    }
}

extension IconSize {
    /// Iets groter dan getoond, zodat het icoon bij de hover-vergroting scherp blijft.
    var rasterPoints: CGFloat { (points * 1.1).rounded() }
}

struct LaunchableApp: Identifiable {
    let url: URL
    var id: String { url.path }
    let name: String
    /// Eigen bitmap: SwiftUI kiest anders soms de grijze "heldere" icoonvariant.
    let icon: NSImage
    let running: Bool

    init(url: URL, iconSize: IconSize, running: Bool) {
        self.url = url
        self.name = url.appDisplayName
        self.icon = IconCache.appIcon(url.path, points: iconSize.rasterPoints)
        self.running = running
    }
}

struct FolderPanelView: View {
    let folder: AppFolder
    let actions: PanelActions

    /// Volgorde van de getoonde apps; wordt direct aangepast bij slepen of verwijderen.
    @State private var order: [String]
    @State private var page = 0
    @State private var dropTarget: String?
    /// Eén keer opgebouwd (niet per body-evaluatie; SwiftUI rekent body meerdere keren uit).
    private let appsByPath: [String: LaunchableApp]

    init(folder: AppFolder, actions: PanelActions = PanelActions()) {
        self.folder = folder
        self.actions = actions
        let existing = Self.existingApps(folder)
        let running = Set(NSWorkspace.shared.runningApplications.compactMap {
            $0.bundleURL?.resolvingSymlinksInPath().path
        })
        var byPath: [String: LaunchableApp] = [:]
        for path in existing {
            let url = URL(fileURLWithPath: path)
            byPath[path] = LaunchableApp(url: url, iconSize: folder.grid.iconSize,
                                         running: running.contains(url.resolvingSymlinksInPath().path))
        }
        self.appsByPath = byPath
        _order = State(initialValue: existing)
    }

    private static func existingApps(_ folder: AppFolder) -> [String] {
        folder.apps.filter { FileManager.default.fileExists(atPath: $0) }
    }

    private var grid: GridStyle { folder.grid }
    private var apps: [LaunchableApp] { order.compactMap { appsByPath[$0] } }
    private var columns: Int { grid.columns(for: apps.count) }

    private var pages: [[LaunchableApp]] {
        let perPage = max(1, columns * grid.rowsPerPage)
        return stride(from: 0, to: apps.count, by: perPage).map {
            Array(apps[$0..<min($0 + perPage, apps.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            EditableTitle(name: folder.name, onRename: actions.rename)

            if apps.isEmpty {
                VStack(spacing: 10) {
                    Text("No apps in this folder yet")
                        .foregroundStyle(.secondary)
                    Button("Add Apps…", action: actions.edit)
                }
                .frame(width: 280, height: 110)
            } else {
                let pages = pages
                let current = min(page, pages.count - 1)
                // Alle pagina's gestapeld: het paneel krijgt de maat van de grootste en springt niet.
                ZStack(alignment: .topLeading) {
                    ForEach(pages.indices, id: \.self) { index in
                        pageGrid(pages[index])
                            .opacity(index == current ? 1 : 0)
                            .allowsHitTesting(index == current)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: current)

                if pages.count > 1 && !grid.hidePagination {
                    PageDots(count: pages.count, current: current) { page = $0 }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit Folder…", action: actions.edit)
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { turn(-1); return .handled }
        .onKeyPress(.rightArrow) { turn(1); return .handled }
        .onReceive(NotificationCenter.default.publisher(for: PagingSignal.name)) { note in
            turn(note.userInfo?["direction"] as? Int ?? 0)
        }
        // Apps van buitenaf gewijzigd (bv. in de beheer-app): volgorde opnieuw overnemen.
        .onChange(of: folder.apps) { _, _ in order = Self.existingApps(folder) }
    }

    private func turn(_ direction: Int) {
        let count = pages.count
        guard count > 1 else { return }
        page = min(max(0, min(page, count - 1) + direction), count - 1)
    }

    private func pageGrid(_ apps: [LaunchableApp]) -> some View {
        let spacing = grid.density.spacing
        return Grid(alignment: .top, horizontalSpacing: spacing.horizontal, verticalSpacing: spacing.vertical) {
            ForEach(Array(stride(from: 0, to: apps.count, by: columns)), id: \.self) { start in
                GridRow {
                    ForEach(apps[start..<min(start + columns, apps.count)]) { app in
                        tile(app)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tile(_ app: LaunchableApp) -> some View {
        let tile = AppTile(app: app, size: grid.iconSize, showRunning: grid.showRunning,
                           dropTargeted: dropTarget == app.id) { actions.open(app.url) }
            .contextMenu { appMenu(app) }

        if actions.reorder != nil {
            tile
                .draggable(app.id) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: grid.iconSize.points, height: grid.iconSize.points)
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let moved = items.first else { return false }
                    move(moved, before: app.id)
                    return true
                } isTargeted: { targeted in
                    if targeted { dropTarget = app.id } else if dropTarget == app.id { dropTarget = nil }
                }
        } else {
            tile
        }
    }

    @ViewBuilder
    private func appMenu(_ app: LaunchableApp) -> some View {
        Button("Open") { actions.open(app.url) }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
        if app.running {
            Button("Quit") {
                let path = app.url.resolvingSymlinksInPath().path
                NSWorkspace.shared.runningApplications
                    .filter { $0.bundleURL?.resolvingSymlinksInPath().path == path }
                    .forEach { $0.terminate() }
            }
        }
        if let remove = actions.remove {
            Divider()
            Button("Remove from Folder") {
                withAnimation(.easeOut(duration: 0.15)) { order.removeAll { $0 == app.id } }
                remove(app.id)
            }
        }
    }

    private func move(_ path: String, before target: String) {
        guard let newOrder = Self.reordered(order, moving: path, onto: target) else { return }
        withAnimation(.easeOut(duration: 0.18)) { order = newOrder }
        actions.reorder?(newOrder)
    }

    /// Nieuwe volgorde als `path` op `target` wordt gesleept, of nil als er niets verandert.
    /// Naar achteren slepen plaatst ná het doel, naar voren ervóór: het voelt alsof je erop "landt".
    static func reordered(_ order: [String], moving path: String, onto target: String) -> [String]? {
        guard path != target, let from = order.firstIndex(of: path), order.contains(target) else { return nil }
        var newOrder = order
        newOrder.remove(at: from)
        let to = newOrder.firstIndex(of: target)!
        newOrder.insert(path, at: from <= to ? to + 1 : to)
        return newOrder
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(Color.primary.opacity(index == current ? 0.75 : 0.25))
                    .frame(width: 7, height: 7)
                    .padding(3)
                    .contentShape(Circle())
                    .onTapGesture { select(index) }
            }
        }
    }
}

/// Titel van het paneel; dubbelklik om te hernoemen. Enter of wegklikken bewaart, Esc annuleert.
private struct EditableTitle: View {
    let name: String
    let onRename: ((String) -> Void)?

    @State private var editing = false
    @State private var draft = ""
    /// Direct de nieuwe naam tonen, ook al wordt de bundle nog op de achtergrond bijgewerkt.
    @State private var renamed: String?
    @FocusState private var focused: Bool

    private var current: String { renamed ?? name }

    var body: some View {
        Group {
            if editing {
                TextField("Folder name", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused && editing { commit() }
                    }
                    .onAppear { focused = true }
            } else {
                Text(current)
                    .onTapGesture(count: 2) {
                        guard onRename != nil else { return }
                        draft = current
                        editing = true
                    }
                    .help(onRename != nil ? "Double-click to rename" : "")
            }
        }
        .font(.system(size: 26, weight: .regular))
        .padding(.horizontal, 6)
    }

    private func commit() {
        editing = false
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != current else { return }
        renamed = trimmed
        onRename?(trimmed)
    }
}

struct AppTile: View {
    let app: LaunchableApp
    let size: IconSize
    let showRunning: Bool
    let dropTargeted: Bool
    let action: () -> Void
    @State private var hovering = false

    private var width: CGFloat { size.points + 24 }

    var body: some View {
        // Geen Button: macOS dimt knopinhoud in een venster dat nog niet actief is.
        VStack(spacing: 6) {
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size.points, height: size.points)
                .scaleEffect(hovering ? 1.06 : 1)
            Text(app.name)
                .font(.system(size: size.labelSize, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: width)
            if showRunning {
                Circle()
                    .fill(Color.primary.opacity(0.7))
                    .frame(width: 4, height: 4)
                    .opacity(app.running ? 1 : 0)
            }
        }
        .frame(width: width)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(dropTargeted ? 0.12 : 0))
        )
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .onTapGesture(perform: action)
        .help(app.name)
    }
}
