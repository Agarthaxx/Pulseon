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

    /// Le retour à l'état d'agent, en attente de la fin de l'animation. Retenu
    /// pour pouvoir l'annuler : une fenêtre rouverte entre-temps doit garder
    /// l'icône du Dock, pas la voir partir une demi-seconde plus tard.
    private var pendingRelease: DispatchWorkItem?

    /// Le délai avant de rendre l'icône du Dock et la barre de menus, une fois
    /// la dernière fenêtre fermée.
    ///
    /// **Mesuré, pas choisi à l'estime.** L'animation de fermeture d'une
    /// fenêtre de 1512 × 949 portant le vrai dashboard dure **83 ms** et rend
    /// six images (filmée à l'écran, `Tools/Preview` cible `Bench`). 250 ms
    /// couvre trois fois la marge sans que l'icône traîne dans le Dock.
    static let closeGrace: TimeInterval = 0.25

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
        becomeRegular()
    }

    /// Recalcule la politique d'activation d'après les fenêtres réellement
    /// présentes.
    private func sync(excluding closing: NSWindow? = nil) {
        if hasCountingWindow(excluding: closing) {
            becomeRegular()
        } else {
            scheduleRelease()
        }
    }

    private func hasCountingWindow(excluding closing: NSWindow?) -> Bool {
        NSApp.windows.contains { window in
            window !== closing && Self.counts(styleMask: window.styleMask, isVisible: window.isVisible)
        }
    }

    /// Devenir une vraie app est immédiat : la fenêtre ne doit jamais
    /// apparaître sans ses menus.
    private func becomeRegular() {
        pendingRelease?.cancel()
        pendingRelease = nil
        apply(.regular)
    }

    /// Redevenir un agent attend la fin de l'animation, et c'est le seul
    /// intérêt de ce délai.
    ///
    /// `setActivationPolicy` ne coûte que ~6 ms de fil principal (mesuré sur
    /// huit fermetures) : ce n'est pas un problème de vitesse. Mais appelée
    /// depuis `willCloseNotification`, elle retire l'icône du Dock et démonte
    /// la barre de menus **pendant que la fenêtre s'efface encore** — deux
    /// disparitions simultanées là où l'œil en attend une seule, puis l'autre.
    /// On laisse donc la fenêtre partir d'abord.
    private func scheduleRelease() {
        pendingRelease?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingRelease = nil
            // Revérifié à l'échéance : une fenêtre a pu rouvrir pendant le
            // délai, et l'annulation ne couvre pas tout (une fenêtre qui
            // s'ouvre sans devenir clé, par exemple).
            guard !self.hasCountingWindow(excluding: nil) else { return }
            self.apply(.accessory)
        }
        pendingRelease = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeGrace, execute: work)
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
