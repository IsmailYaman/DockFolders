import AppKit
import SwiftUI

/// Draait binnen een map-bundle in de Dock. Blijft na de eerste klik actief (net als TinyFolder),
/// zodat volgende klikken het paneel direct openklappen in plaats van een app te starten.
final class LauncherDelegate: NSObject, NSApplicationDelegate {
    let folderID: UUID
    private var panel: FolderPanel?
    private var lastHidden = Date.distantPast

    init(folderID: UUID) {
        self.folderID = folderID
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        prewarmIcons()
        // Bij inloggen start DockFolders ons op de achtergrond, zodat de eerste klik meteen werkt.
        if CommandLine.arguments.contains(FolderBundleBuilder.backgroundArgument) { return }
        // Op dit moment staat de muis nog op het Dock-icoon waarop geklikt is.
        show(at: NSEvent.mouseLocation)
    }

    // Klik op het Dock-icoon terwijl we al draaien: paneel open- of dichtklappen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if panel != nil {
            hide()
        } else if Date().timeIntervalSince(lastHidden) > 0.3 {
            // (Net gesloten doordat de klik op de Dock ons deactiveerde? Dan niet meteen weer openen.)
            show(at: NSEvent.mouseLocation)
        }
        return false
    }

    func applicationDidResignActive(_ notification: Notification) {
        hide(returnFocus: false)
    }

    /// Iconen alvast op de achtergrond klaarzetten, zodat het paneel direct kan openen.
    private func prewarmIcons() {
        guard let folder = FolderStorage.load().first(where: { $0.id == folderID }) else { return }
        IconCache.prewarm(folder.apps, points: LaunchableApp.iconPoints)
    }

    private func show(at anchor: NSPoint) {
        // Elke keer opnieuw inlezen, zodat wijzigingen uit de beheer-app direct zichtbaar zijn.
        guard let folder = FolderStorage.load().first(where: { $0.id == folderID }) else {
            let alert = NSAlert()
            alert.messageText = "This folder no longer exists"
            alert.informativeText = "Open DockFolders to manage your folders."
            NSApp.activate()
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let panel = FolderPanel(folder: folder, anchor: anchor,
                                open: { [weak self] url in self?.launch(url) },
                                edit: { [weak self] in self?.openManager() },
                                close: { [weak self] in self?.hide() })
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.present()
    }

    private func hide(returnFocus: Bool = true) {
        guard let panel else { return }
        self.panel = nil
        lastHidden = Date()
        panel.dismiss { [weak self] in
            panel.orderOut(nil)
            // Focus pas na de animatie teruggeven; NSApp.hide verbergt het paneel anders meteen.
            if returnFocus { NSApp.hide(nil) }
            // Nieuwe apps uit de beheer-app alvast klaarzetten voor de volgende klik.
            self?.prewarmIcons()
        }
    }

    private func launch(_ url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        hide(returnFocus: false)
    }

    private func openManager() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Paths.managerBundleID) {
            launch(url)
        } else {
            hide()
        }
    }
}

final class FolderPanel: NSPanel {
    private let onClose: () -> Void
    /// De afgeronde kaart (achtergrond + inhoud); deze laag wordt geanimeerd.
    private var card: PanelCardView!
    /// Het Dock-icoon, in de coördinaten van het paneel: hier groeit het paneel uit.
    private var growPoint = CGPoint.zero

    init(folder: AppFolder, anchor: NSPoint, open: @escaping (URL) -> Void,
         edit: @escaping () -> Void, close: @escaping () -> Void) {
        self.onClose = close
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        // Geen vensterschaduw: die volgt het rechthoekige venster en geeft een lijn om het glas.
        // Het glas tekent zelf al een rand en schaduw.
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        // NSPanel verbergt zich standaard direct bij wegklikken; wij laten de animatie dat doen.
        hidesOnDeactivate = false

        let hosting = FirstClickHostingView(rootView: FolderPanelView(folder: folder, open: open, edit: edit))
        let size = hosting.fittingSize

        card = PanelCardView(content: hosting, size: size)
        card.apply(folder)

        // Gewone (niet-geflipte) container, zodat de laag van de kaart vrij getransformeerd kan worden.
        // De doorzichtige marge geeft de veeranimatie ruimte, anders wordt de overshoot afgekapt.
        let margin = Self.animationMargin
        let glassFrame = Self.frame(for: size, anchor: anchor)
        let frame = glassFrame.insetBy(dx: -margin, dy: -margin)
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.wantsLayer = true
        card.frame.origin = CGPoint(x: margin, y: margin)
        container.addSubview(card)
        contentView = container

        setFrame(frame, display: true)
        growPoint = CGPoint(x: anchor.x - glassFrame.minX, y: anchor.y - glassFrame.minY)
    }

    private static let animationMargin: CGFloat = 16

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) { onClose() }

    func present() {
        guard let layer = card.layer else {
            makeKeyAndOrderFront(nil)
            return
        }
        alphaValue = 1
        layer.opacity = 0
        layer.transform = transform(scale: 0.35)
        makeKeyAndOrderFront(nil)

        CATransaction.begin()
        // Verende groei vanuit het Dock-icoon.
        let grow = CASpringAnimation(keyPath: "transform")
        grow.fromValue = transform(scale: 0.35)
        grow.toValue = CATransform3DIdentity
        grow.mass = 1
        // ~100 ms, bijna kritisch gedempt (ζ ≈ 0,83): een heel kleine bounce.
        grow.stiffness = 2300
        grow.damping = 80
        grow.duration = 0.1
        layer.transform = CATransform3DIdentity
        layer.add(grow, forKey: "grow")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.07
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.opacity = 1
        layer.add(fade, forKey: "fade")
        CATransaction.commit()
    }

    func dismiss(completion: @escaping () -> Void) {
        guard let layer = card.layer else {
            completion()
            return
        }
        let target = transform(scale: 0.4)

        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        let shrink = CABasicAnimation(keyPath: "transform")
        shrink.fromValue = layer.presentation()?.transform ?? CATransform3DIdentity
        shrink.toValue = target
        shrink.duration = 0.1
        shrink.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.9, 0.6)
        layer.transform = target
        layer.add(shrink, forKey: "grow")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? 1
        fade.toValue = 0
        fade.duration = 0.09
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.opacity = 0
        layer.add(fade, forKey: "fade")
        CATransaction.commit()
    }

    /// Schaal rond het Dock-icoon (in plaats van rond het ankerpunt van de laag).
    private func transform(scale: CGFloat) -> CATransform3D {
        guard let layer = card.layer else { return CATransform3DIdentity }
        let pivot = CGPoint(x: growPoint.x - layer.anchorPoint.x * layer.bounds.width,
                            y: growPoint.y - layer.anchorPoint.y * layer.bounds.height)
        var t = CATransform3DMakeTranslation(pivot.x, pivot.y, 0)
        t = CATransform3DScale(t, scale, scale, 1)
        return CATransform3DTranslate(t, -pivot.x, -pivot.y, 0)
    }

    /// Plaats het paneel naast de Dock, aan de kant waar de Dock staat.
    private static func frame(for size: NSSize, anchor: NSPoint) -> NSRect {
        let screen = NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) } ?? NSScreen.main!
        let full = screen.frame
        let visible = screen.visibleFrame
        let margin: CGFloat = 10

        enum Edge { case bottom, left, right }
        let edge: Edge
        if visible.minY > full.minY + 1 { edge = .bottom }
        else if visible.minX > full.minX + 1 { edge = .left }
        else if visible.maxX < full.maxX - 1 { edge = .right }
        else {
            // Dock automatisch verbergen: kies de rand die het dichtst bij de muis is.
            let d = [(Edge.bottom, anchor.y - full.minY), (.left, anchor.x - full.minX), (.right, full.maxX - anchor.x)]
            edge = d.min { $0.1 < $1.1 }!.0
        }
        // Bij een verborgen Dock: ruimte laten voor de Dock die nu zichtbaar is.
        let dockGap: CGFloat = visible == full || (edge == .bottom && visible.minY <= full.minY + 1) ? 80 : 0

        var origin: NSPoint
        switch edge {
        case .bottom:
            origin = NSPoint(x: anchor.x - size.width / 2, y: visible.minY + margin + dockGap)
        case .left:
            origin = NSPoint(x: visible.minX + margin + dockGap, y: anchor.y - size.height / 2)
        case .right:
            origin = NSPoint(x: visible.maxX - margin - dockGap - size.width, y: anchor.y - size.height / 2)
        }
        origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - size.width - margin)
        origin.y = min(max(origin.y, visible.minY + margin), visible.maxY - size.height - margin)
        return NSRect(origin: origin, size: size)
    }
}

/// Laat de eerste klik direct naar de knop gaan, ook als de app nog niet actief was.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct LaunchableApp: Identifiable {
    let url: URL
    var id: String { url.path }
    let name: String
    /// Eigen bitmap: SwiftUI kiest anders soms de grijze "heldere" icoonvariant. Iets groter dan
    /// de 88 pt waarop hij getoond wordt, zodat hij bij de hover-vergroting scherp blijft.
    let icon: NSImage

    static let iconPoints: CGFloat = 96

    init(url: URL) {
        self.url = url
        self.name = url.appDisplayName
        self.icon = IconCache.appIcon(url.path, points: Self.iconPoints)
    }
}

struct FolderPanelView: View {
    let folder: AppFolder
    let open: (URL) -> Void
    let edit: () -> Void
    /// Eén keer opgebouwd (niet per body-evaluatie; SwiftUI rekent body meerdere keren uit).
    private let apps: [LaunchableApp]

    init(folder: AppFolder, open: @escaping (URL) -> Void, edit: @escaping () -> Void) {
        self.folder = folder
        self.open = open
        self.edit = edit
        self.apps = folder.apps
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { LaunchableApp(url: URL(fileURLWithPath: $0)) }
    }

    private var columns: Int {
        switch apps.count {
        case 0...3: max(apps.count, 1)
        case 4: 4
        case 5...9: 3
        case 10...16: 4
        default: 5
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(folder.name)
                .font(.system(size: 26, weight: .regular))
                .padding(.horizontal, 6)

            if apps.isEmpty {
                VStack(spacing: 10) {
                    Text("No apps in this folder yet")
                        .foregroundStyle(.secondary)
                    Button("Add Apps…", action: edit)
                }
                .frame(width: 280, height: 110)
            } else {
                Grid(horizontalSpacing: 8, verticalSpacing: 10) {
                    ForEach(Array(stride(from: 0, to: apps.count, by: columns)), id: \.self) { start in
                        GridRow {
                            ForEach(apps[start..<min(start + columns, apps.count)]) { app in
                                AppTile(app: app) { open(app.url) }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit Folder…", action: edit)
        }
    }
}

struct AppTile: View {
    static let width: CGFloat = 112

    let app: LaunchableApp
    let action: () -> Void
    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        // Geen Button: macOS dimt knopinhoud in een venster dat nog niet actief is.
        VStack(spacing: 8) {
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 88, height: 88)
                .scaleEffect(hovering ? 1.06 : 1)
                .brightness(pressed ? -0.15 : 0)
            Text(app.name)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: Self.width)
        }
        .frame(width: Self.width)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .onTapGesture(perform: action)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .help(app.name)
    }
}
