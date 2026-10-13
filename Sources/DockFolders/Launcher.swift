import AppKit
import SwiftUI

/// Draait binnen een map-bundle in de Dock. Blijft na de eerste klik actief (net als TinyFolder),
/// zodat volgende klikken het paneel direct openklappen in plaats van een app te starten.
final class LauncherDelegate: NSObject, NSApplicationDelegate {
    let folderID: UUID
    private var panel: FolderPanel?
    private var lastHidden = Date.distantPast
    /// Apps of volgorde gewijzigd vanuit het paneel: na sluiten de bundle (Dock-icoon) bijwerken.
    private var needsRebuild = false

    init(folderID: UUID) {
        self.folderID = folderID
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        prewarmIcons()
        updateDockIcon()
        watchConfig()
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

    /// Apps op het map-icoon in de Dock gesleept: toevoegen en het paneel tonen.
    /// (Wordt bij een koude start vóór applicationDidFinishLaunching aangeroepen.)
    func application(_ application: NSApplication, open urls: [URL]) {
        let paths = urls.filter { $0.pathExtension == "app" }.map { $0.resolvingSymlinksInPath().path }
        guard !paths.isEmpty else { return }
        updateFolder { folder in
            for path in paths where !folder.apps.contains(path) { folder.apps.append(path) }
        }
        rebuildBundle()
        if panel != nil {
            panel?.orderOut(nil)
            panel = nil
        }
        if NSApp.isRunning { show(at: NSEvent.mouseLocation) }
    }

    func applicationDidResignActive(_ notification: Notification) {
        hide(returnFocus: false)
    }

    /// Iconen alvast op de achtergrond klaarzetten, zodat het paneel direct kan openen.
    private func prewarmIcons() {
        guard let folder = FolderStorage.load().first(where: { $0.id == folderID }) else { return }
        IconCache.prewarm(folder.apps, points: folder.grid.iconRasterPoints)
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

        let actions = makeActions()
        let panel = FolderPanel(folder: folder, anchor: anchor, actions: actions,
                                close: { [weak self] in self?.hide() })
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.present()
    }

    /// Wat het paneel in de Dock doet bij openen, hernoemen, slepen en verwijderen.
    func makeActions() -> PanelActions {
        var actions = PanelActions()
        actions.open = { [weak self] url in self?.launch(url) }
        actions.edit = { [weak self] in self?.openManager() }
        actions.rename = { [weak self] name in self?.rename(to: name) }
        actions.reorder = { [weak self] order in
            self?.updateFolder { folder in
                // Apps die (tijdelijk) niet gevonden worden niet kwijtraken: achteraan houden.
                folder.apps = order + folder.apps.filter { !order.contains($0) }
            }
            self?.needsRebuild = true
        }
        actions.remove = { [weak self] path in
            self?.updateFolder { $0.apps.removeAll { $0 == path } }
            self?.needsRebuild = true
        }
        return actions
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
            // Pas nu het Dock-icoon bijwerken: dat herstart de Dock, wat niet moet gebeuren
            // terwijl je nog in het paneel aan het slepen bent.
            if self?.needsRebuild == true {
                self?.needsRebuild = false
                self?.rebuildBundle()
            }
        }
    }

    /// Lees-wijzig-schrijf op folders.json voor deze map. De beheer-app leest de wijziging vanzelf in.
    private func updateFolder(_ change: (inout AppFolder) -> Void) {
        var folders = FolderStorage.load()
        guard let i = folders.firstIndex(where: { $0.id == folderID }) else { return }
        change(&folders[i])
        FolderStorage.save(folders)
    }

    /// Bundle opnieuw bouwen (icoon, naam) en de Dock herstarten als het icoon erin staat.
    /// Verplaatsen, signeren en herstarten duurt even: niet op de main thread.
    private func rebuildBundle() {
        guard let folder = FolderStorage.load().first(where: { $0.id == folderID }) else { return }
        updateDockIcon()
        // De bundle (icoon voor als we niet draaien, naam) op de achtergrond bijwerken. Geen
        // Dock-herstart nodig: het Dock-icoon zetten we hierboven zelf. (Bij hernoemen herstart
        // build() de Dock wel, want het label komt van de bestandsnaam.)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FolderBundleBuilder.build(folder)
            } catch {
                NSLog("DockFolders: bijwerken mislukt: \(error)")
            }
        }
    }

    // MARK: Live Dock-icoon

    private var configWatcher: DispatchSourceFileSystemObject?
    private var shownIconSignature: String?

    /// Een draaiende app kan zijn Dock-icoon direct vervangen. Zo is een wijziging (apps, kleur,
    /// eigen icoon) meteen zichtbaar, zonder de Dock te herstarten of op zijn icooncache te wachten.
    private func updateDockIcon() {
        guard let folder = FolderStorage.load().first(where: { $0.id == folderID }) else { return }
        let signature = IconCache.signature(of: folder)
        guard signature != shownIconSignature else { return }
        shownIconSignature = signature
        // Renderen kost even (negen app-iconen): op de achtergrond, daarna op de main thread zetten.
        DispatchQueue.global(qos: .userInitiated).async {
            let image = IconCache.folderIcon(folder, points: 512)
            DispatchQueue.main.async {
                // Intussen alweer gewijzigd? Dan is er een nieuwere render onderweg.
                guard self.shownIconSignature == signature else { return }
                NSApp.applicationIconImage = image
            }
        }
    }

    /// De beheer-app (of een ander proces) past folders.json aan: Dock-icoon direct bijwerken.
    /// (De map in de gaten houden, niet het bestand: opslaan is atomisch en vervangt het bestand.)
    private func watchConfig() {
        let fd = open(Paths.support.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in self?.updateDockIcon() }
        source.setCancelHandler { close(fd) }
        source.resume()
        configWatcher = source
    }

    /// Nieuwe naam opslaan en de bundle (en daarmee de naam in de Dock) bijwerken.
    private func rename(to name: String) {
        updateFolder { $0.name = name }
        rebuildBundle()
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

    init(folder: AppFolder, anchor: NSPoint, actions: PanelActions, close: @escaping () -> Void) {
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

        let hosting = FirstClickHostingView(rootView: FolderPanelView(folder: folder, actions: actions))
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

/// Laat de eerste klik direct naar de knop gaan, ook als de app nog niet actief was, en vertaalt
/// scrollen/vegen naar bladeren tussen pagina's.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    private var scrollAccumulator: CGFloat = 0
    private var swipedThisGesture = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func scrollWheel(with event: NSEvent) {
        // Trackpad: één bladzijde per veeggebaar. Muiswiel: één bladzijde per tik.
        if event.phase == .began || event.phase == [] && event.momentumPhase == [] {
            if event.phase == .began {
                scrollAccumulator = 0
                swipedThisGesture = false
            }
        }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? -event.scrollingDeltaX : -event.scrollingDeltaY
        if event.phase == [] && event.momentumPhase == [] {
            if delta != 0 { PagingSignal.post(delta > 0 ? 1 : -1) }
            return
        }
        guard !swipedThisGesture, event.momentumPhase == [] else { return }
        scrollAccumulator += delta
        if abs(scrollAccumulator) > 30 {
            swipedThisGesture = true
            PagingSignal.post(scrollAccumulator > 0 ? 1 : -1)
        }
    }
}
