import AppKit
import SwiftUI

/// De afgeronde "kaart" van het mappaneel: een achtergrond (Liquid Glass of effen kleur) met de
/// inhoud erbovenop. Het glas ligt in een eigen laag, zodat doorzichtigheid de iconen niet raakt.
/// Gebruikt door het echte paneel én het live voorbeeld in de beheer-app.
final class PanelCardView: NSView {
    static let cornerRadius: CGFloat = 34

    private let glass = NSGlassEffectView()
    private let solid = NSView()
    let content: NSView

    init(content: NSView, size: NSSize) {
        self.content = content
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true

        glass.cornerRadius = Self.cornerRadius
        solid.wantsLayer = true
        solid.layer?.cornerRadius = Self.cornerRadius
        solid.layer?.cornerCurve = .continuous
        solid.layer?.masksToBounds = true

        for view in [glass, solid, content] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func apply(_ folder: AppFolder) {
        let style = folder.panel
        glass.isHidden = !style.glass
        solid.isHidden = style.glass

        if style.glass {
            glass.style = style.background == .clear ? .clear : .regular
            glass.tintColor = style.glassTint(tint: folder.tint)
            glass.alphaValue = 1 - style.transparency * 0.85
        } else {
            // Via effectiveAppearance, zodat systeemkleuren (licht/donker) goed worden opgelost.
            effectiveAppearance.performAsCurrentDrawingAppearance {
                solid.layer?.backgroundColor = style.solidColor(tint: folder.tint).cgColor
            }
        }

        switch style.appearance(tint: folder.tint) {
        case .dark: appearance = NSAppearance(named: .darkAqua)
        case .light: appearance = NSAppearance(named: .aqua)
        case .system: appearance = nil
        }
    }
}

/// Live voorbeeld van het paneel voor in de beheer-app.
struct PanelPreview: NSViewRepresentable {
    let folder: AppFolder

    func makeNSView(context: Context) -> PanelCardView {
        let hosting = NSHostingView(rootView: FolderPanelView(folder: folder, open: { _ in }, edit: {}))
        let card = PanelCardView(content: hosting, size: hosting.fittingSize)
        card.apply(folder)
        context.coordinator.shown = folder
        return card
    }

    final class Coordinator {
        var shown: AppFolder?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateNSView(_ card: PanelCardView, context: Context) {
        // Inhoud en grootte alleen opnieuw bij andere naam/apps; bij schuiven verandert alleen de stijl.
        let previous = context.coordinator.shown
        if previous?.name != folder.name || previous?.apps != folder.apps,
           let hosting = card.content as? NSHostingView<FolderPanelView> {
            hosting.rootView = FolderPanelView(folder: folder, open: { _ in }, edit: {})
            card.setFrameSize(hosting.fittingSize)
        }
        context.coordinator.shown = folder
        card.apply(folder)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PanelCardView, context: Context) -> CGSize? {
        nsView.frame.size
    }
}
