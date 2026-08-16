import AppKit

/// Fait passer Pulseon pour une vraie app **tant qu'une fenêtre est ouverte**,
/// puis le rend à son état d'agent invisible.
///
/// Le problème qu'elle règle a été constaté à l'usage : `LSUIElement` vaut vrai
/// dans l'`Info.plist`, donc l'app n'a ni icône Dock ni **barre de menus**. La
/// fenêtre du dashboard s'ouvrait sans menu « Pulseon », sans menu Fenêtre, donc
/// sans ⌘W, sans ⌘Tab pour la retrouver, et sans plein écran. Une fois passée
/// derrière une autre app, il fallait repasser par la barre de menu pour la
/// revoir.
///
/// L'inverse — retirer `LSUIElement` et devenir une app normale en permanence —
/// coûterait beaucoup plus cher : le réflexe ⌘Q arrêterait la collecte, et une
/// app de mesure qui s'arrête quand on ferme sa fenêtre ne mesure plus rien.
/// C'est la règle fondatrice du projet. D'où la bascule : `.regular` pendant
/// qu'une fenêtre vit, `.accessory` le reste du temps.
@MainActor
public final class DockPresence {
    public static let shared = DockPresence()

    private var observers: [NSObjectProtocol] = []

    private init() {}

    /// Branche l'observation. Appelable plusieurs fois sans dommage.
    public func start() {
        guard observers.isEmpty else { return }

        let center = NotificationCenter.default

        // Une fenêtre qui s'affiche : on devient une vraie app. On écoute
        // `didBecomeKey` et pas seulement l'ouverture explicite, pour couvrir
        // toute fenêtre qu'on n'aurait pas ouverte soi-même.
        observers.append(
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in DockPresence.shared.sync() }
            }
        )

        // Une fenêtre qui se ferme. Elle est **encore** dans `NSApp.windows` et
        // encore visible à cet instant, donc il faut l'exclure explicitement :
        // sans ça on resterait éternellement en `.regular`.
        observers.append(
            center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
                let closing = note.object as? NSWindow
                Task { @MainActor in DockPresence.shared.sync(excluding: closing) }
            }
        )
    }

    /// À appeler juste avant d'ouvrir une fenêtre.
    ///
    /// L'observation suffirait, mais elle arrive après coup : la fenêtre
    /// apparaîtrait un instant sans ses menus. Basculer d'abord évite ce
    /// clignotement.
    public func prepareForWindow() {
        apply(.regular)
    }

    /// Recalcule la politique d'activation d'après les fenêtres réellement
    /// présentes.
    private func sync(excluding closing: NSWindow? = nil) {
        let hasWindow = NSApp.windows.contains { window in
            window !== closing && Self.counts(styleMask: window.styleMask, isVisible: window.isVisible)
        }
        apply(hasWindow ? .regular : .accessory)
    }

    private func apply(_ policy: NSApplication.ActivationPolicy) {
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

    /// Est-ce que cette fenêtre justifie une icône dans le Dock ?
    ///
    /// Fonction pure et exposée pour être testable sans ouvrir de fenêtre, donc
    /// sans session graphique — même raison que le reste de `PulseonMacKit`.
    ///
    /// Le critère est `.titled` : l'élément de barre de menu porte lui aussi une
    /// fenêtre (`NSStatusBarWindow`), et la compter garderait l'icône Dock
    /// allumée en permanence, ce qui reviendrait à supprimer `LSUIElement`.
    /// `nonisolated` parce qu'elle ne touche à rien : sans ça elle héritait de
    /// l'isolation `@MainActor` de la classe, et un test synchrone ne pouvait
    /// pas l'appeler.
    public nonisolated static func counts(styleMask: NSWindow.StyleMask, isVisible: Bool) -> Bool {
        isVisible && styleMask.contains(.titled)
    }
}
