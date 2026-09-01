import PulseonCore
import PulseonMacKit
import PulseonUI
import SwiftData
import SwiftUI

/// Le verrou de collecte, tenu tant que le processus vit. Global et non local,
/// pour qu'il ne soit jamais libéré avant la fin — un `flock` relâché rouvrirait
/// la porte à un second collecteur.
@MainActor private let collectionLock = InstanceLock()

/// Agent en barre de menu. Il n'a pas de fenêtre principale : la collecte
/// doit tourner en continu, indépendamment de toute fenêtre ouverte, et
/// c'est ce qui remplace le trio script + venv + launchd de la v1.
@main
struct PulseonApp: App {
    // Déclaré sans valeur initiale, et c'est volontaire : l'expression par
    // défaut d'un `@State` est évaluée **avant** le corps d'`init`, donc un
    // `= CollectionEngine()` ici ouvrirait la base et lancerait la collecte
    // avant même le contrôle d'instance unique juste en dessous.
    @State private var engine: CollectionEngine

    init() {
        // Un seul Pulseon écrit dans la base. Deux se sont partagé la même le
        // 2026-08-18 — le `LaunchAgent` et un élément d'ouverture ajouté à la
        // main — et la journée affichait 51 h au lieu de 2 h. Voir
        // `InstanceLock` pour le détail du dégât.
        //
        // Le second part sans rien dire : c'est un agent, il n'a pas de fenêtre
        // où s'expliquer, et celui qui tient déjà le verrou mesure très bien.
        // `exit` et pas `NSApp.terminate` — AppKit n'a pas fini de démarrer.
        guard collectionLock.acquire() else {
            FileHandle.standardError.write(
                Data("Pulseon tourne déjà : cette instance s'arrête.\n".utf8)
            )
            exit(0)
        }

        // L'agent devient une vraie app tant qu'une fenêtre est ouverte : icône
        // Dock, menus, ⌘W, ⌘Tab, plein écran. Puis il redevient invisible, pour
        // que ⌘Q ne soit jamais à portée de main — la collecte ne doit pas
        // pouvoir s'arrêter en fermant une fenêtre.
        DockPresence.shared.start()

        _engine = State(wrappedValue: CollectionEngine())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(engine: engine)
        } label: {
            MenuBarLabel(engine: engine)
        }
        .menuBarExtraStyle(.menu)
        .modelContainer(engine.container)

        // La fenêtre du dashboard. Elle n'existe que si on l'ouvre : l'app
        // reste un agent, et la collecte n'a jamais dépendu d'une fenêtre.
        Window("Pulseon", id: DashboardWindow.id) {
            DashboardWindow(browser: engine.browser, periods: engine.periods)
        }
        .defaultSize(width: 860, height: 560)
        .modelContainer(engine.container)
    }
}

/// Le libellé de la barre de menu : l'icône et le total du jour.
///
/// **Une vue à part, et c'est une correction de performance mesurée.** Le
/// libellé était écrit directement dans le corps de `PulseonApp`, qui lisait
/// donc `engine.menuBarTitle` — une valeur qui change **chaque seconde**. À
/// chaque changement, SwiftUI réévaluait tout le corps de l'app :
/// `MenuBarExtra`, mais aussi la scène `Window` du dashboard et ses deux
/// `.modelContainer`, alors même qu'aucune fenêtre n'est ouverte.
///
/// Coût relevé sur l'app installée, agent seul, aucune fenêtre : **6,4 % d'un
/// cœur en continu**, contre 0,38 % le titre gelé — et 1,4 % pour ce même geste
/// dans une sonde minimale. On payait donc quatre fois le prix du compteur.
///
/// Ici, seule cette vue-ci dépend du titre : le graphe de scènes n'est plus
/// reconstruit. **Même leçon que le halo du fond : isoler ce qui change.**
///
/// `Label(_:systemImage:)` ne convient pas, et ça a été vu à l'exécution : le
/// libellé d'un `MenuBarExtra` est traité comme une icône de barre de menu,
/// donc le texte est silencieusement jeté et le total n'apparaît qu'en ouvrant
/// le menu. Un `Text` qui *interpole* l'image garde les deux, parce que tout
/// est alors un seul texte aux yeux du système.
private struct MenuBarLabel: View {
    let engine: CollectionEngine

    var body: some View {
        Text("\(Image(systemName: engine.menuBarSymbol)) \(engine.menuBarTitle)")
    }
}

/// La fenêtre du dashboard, et rien d'autre : elle relit la journée à
/// l'ouverture et chaque minute, puis laisse `DayDashboard` dessiner.
private struct DashboardWindow: View {
    static let id = "dashboard"

    let browser: DayBrowser
    let periods: PeriodBrowser

    /// L'écran affiché. Un `@State` et non un réglage persistant : rouvrir
    /// Pulseon doit montrer la journée, qui est la question à laquelle l'app
    /// répond en premier.
    @State private var screen: PulseonScreen = .day

    /// Dans quel sens la dernière navigation est allée, pour que la journée
    /// glisse **dans le sens du geste**. Sans ça, reculer et avancer produisent
    /// la même transition et l'animation ne dit plus rien.
    @State private var direction: SlideDirection = .forward

    @Environment(\.colorScheme) private var scheme

    /// Vrai tant que l'écran de lancement couvre la fenêtre.
    ///
    /// Il se rejoue à **chaque ouverture de fenêtre**, et non une fois par
    /// démarrage du processus : Pulseon est un agent qui vit des jours sans
    /// fenêtre, donc « une fois par lancement » voudrait dire « presque
    /// jamais ». Le lancement, pour qui s'en sert, c'est l'ouverture de la
    /// fenêtre — et c'est aussi le moment où la journée se lit sur le disque,
    /// donc le seul où il y a quelque chose à couvrir.
    @State private var launching = true

    /// La journée en cours grandit pendant qu'on la regarde. Une minute suffit
    /// — un bloc d'une minute fait moins d'un point de large sur 24 h, donc
    /// rafraîchir plus vite ne changerait rien à ce qu'on voit. Ici, à la
    /// différence de la barre de menu, ce sont de vraies lectures de base.
    private let refresh = Timer.publish(every: 60, tolerance: 15, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        let palette = PulseonTheme.palette(for: scheme)

        ZStack {
            VStack(spacing: 0) {
                ScreenPicker(selection: $screen, palette: palette)
                    .padding(.top, 12)

                switch screen {
                case .day:
                    DayDashboard(
                        load: browser.load,
                        canGoForward: browser.canGoForward,
                        onPrevious: { navigate(.backward, browser.goToPreviousDay) },
                        onNext: { navigate(.forward, browser.goToNextDay) },
                        onToday: { navigate(.forward, browser.goToToday) }
                    )
                    // L'identité change avec la journée : c'est ce qui fait que
                    // SwiftUI remplace la vue au lieu de la mettre à jour, donc ce
                    // qui rend une transition possible.
                    .id(browser.dayStart)
                    .transition(direction.transition)
                case .week:
                    WeekDashboard(
                        load: periods.load,
                        canGoForward: periods.canGoForward,
                        onPrevious: { navigate(.backward, periods.goToPreviousWeek) },
                        onNext: { navigate(.forward, periods.goToNextWeek) },
                        onCurrent: { navigate(.forward, periods.goToCurrentWeek) }
                    )
                    .id(periods.weekStart)
                    .transition(direction.transition)
                case .timeline:
                    // La chronologie regarde **la même journée** que l'écran du
                    // jour, et partage donc son `DayBrowser` : deux navigations
                    // séparées feraient dériver les deux écrans l'un de l'autre,
                    // et basculer d'onglet changerait la date sans le dire.
                    DayTimeline(
                        load: browser.load,
                        canGoForward: browser.canGoForward,
                        onPrevious: { navigate(.backward, browser.goToPreviousDay) },
                        onNext: { navigate(.forward, browser.goToNextDay) },
                        onToday: { navigate(.forward, browser.goToToday) }
                    )
                    .id(browser.dayStart)
                    .transition(direction.transition)
                }
            }
            // Le même ton que le haut du dégradé des écrans : cette bande porte le
            // sélecteur, au-dessus de leur fond, et un aplat plus clair ou plus
            // sombre y ferait une couture nette en travers de la fenêtre.
            .background(palette.groundTop)
            .background(keyboard)
            // Les icônes descendent par l'environnement : les lignes qui les
            // affichent sont imbriquées loin sous le dashboard, et les traverser
            // toutes avec un argument de plus rendrait chaque vue intermédiaire
            // dépendante d'une chose qu'elle n'utilise pas.
            .environment(\.appIcons, browser.appIcons)
            .onAppear { reloadVisible() }
            // **Seul l'écran visible est relu.** Relire les deux chaque minute
            // doublerait les requêtes pour une vue que personne ne regarde ; celle
            // qu'on découvre est rafraîchie au moment où on l'affiche.
            .onChange(of: screen) { reloadVisible() }
            .onReceive(refresh) { _ in reloadVisible() }
            .onKeyPress(.leftArrow) { goBack(); return .handled }
            .onKeyPress(.rightArrow) { goForward(); return .handled }

            if launching {
                // Au-dessus de tout, opaque : il couvre la lecture du disque,
                // donc l'instant où le dashboard n'a encore rien à montrer.
                LaunchSplash(palette: palette, scheme: scheme)
                    .transition(.opacity)
            }
        }
        // **Le mouvement n'est allumé qu'ici.** Partout ailleurs — previews,
        // rendus hors écran — les vues se dessinent complètes. Voir
        // `PulseonMotion`.
        .environment(\.pulseonMotion, true)
        .task {
            try? await Task.sleep(
                nanoseconds: UInt64(PulseonMotion.launchHold * 1_000_000_000))
            withAnimation(PulseonMotion.launchFade) { launching = false }
        }
    }

    /// Navigue, en retenant le sens pour la transition.
    private func navigate(_ way: SlideDirection, _ move: () -> Void) {
        direction = way
        withAnimation(PulseonMotion.slide) { move() }
    }

    /// Les raccourcis clavier.
    ///
    /// Des boutons cachés plutôt qu'un `.commands` : la fenêtre appartient à un
    /// agent en barre de menu, dont la barre de menus n'existe que le temps
    /// d'une fenêtre ouverte (voir `DockPresence`). Un raccourci porté par la
    /// vue vit exactement aussi longtemps que la fenêtre qu'il pilote.
    ///
    /// **Les flèches ne sont pas des `keyboardShortcut`** : une flèche seule
    /// n'est pas un raccourci de menu, et l'affecter à un bouton invisible la
    /// volerait à tout champ de saisie. `onKeyPress` la rend au premier
    /// répondant qui en veut.
    @ViewBuilder
    private var keyboard: some View {
        ZStack {
            Button("") { screen = .day }.keyboardShortcut("1", modifiers: .command)
            Button("") { screen = .week }.keyboardShortcut("2", modifiers: .command)
            Button("") { screen = .timeline }.keyboardShortcut("3", modifiers: .command)
            Button("") { goToStart() }.keyboardShortcut("t", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// Ramène à aujourd'hui — ou à la semaine en cours, selon l'écran regardé.
    private func goToStart() {
        switch screen {
        case .day, .timeline: navigate(.forward, browser.goToToday)
        case .week: navigate(.forward, periods.goToCurrentWeek)
        }
    }

    private func goBack() {
        switch screen {
        case .day, .timeline: navigate(.backward, browser.goToPreviousDay)
        case .week: navigate(.backward, periods.goToPreviousWeek)
        }
    }

    private func goForward() {
        switch screen {
        case .day, .timeline:
            guard browser.canGoForward else { return }
            navigate(.forward, browser.goToNextDay)
        case .week:
            guard periods.canGoForward else { return }
            navigate(.forward, periods.goToNextWeek)
        }
    }

    private func reloadVisible() {
        switch screen {
        case .day, .timeline: browser.reload()
        case .week: periods.reload()
        }
    }
}

private struct MenuContent: View {
    let engine: CollectionEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // On lit la journée déjà relue par le moteur, sans relancer de requête
        // à chaque ouverture du menu : elle date d'une minute au plus.
        let digest = engine.today

        if let failure = engine.failure {
            Text("⚠︎ Rien n'est enregistré — \(failure)")
        }

        if let digest {
            Text("Aujourd'hui — \(format(digest.coveredTotal)) devant un écran")

            ForEach(digest.lanes.filter(\.isConnected), id: \.device) { lane in
                Text("\(lane.device.label) · \(format(lane.total))")
            }
        } else {
            // Pas « 0 min » : on ne sait pas, et le dire est plus honnête.
            Text("⚠︎ Lecture impossible — \(engine.readFailure ?? "raison inconnue")")
        }

        // Injoignable n'est pas éteinte : le dire évite de croire à une soirée
        // sans télé alors qu'on n'en sait rien.
        if engine.tvIsUnreachable {
            Text("⚠︎ TV injoignable — état inconnu")
        }

        Divider()

        Button("Ouvrir la journée") {
            engine.browser.goToToday()
            // Devenir une vraie app *avant* d'ouvrir, sinon la fenêtre apparaît
            // un instant sans sa barre de menus. Voir `DockPresence`.
            DockPresence.shared.prepareForWindow()
            openWindow(id: DashboardWindow.id)
            // Sans ça la fenêtre s'ouvre derrière : une app en barre de menu
            // n'est pas active au moment du clic.
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("j")

        Divider()

        Button("Exporter en CSV…") { engine.export(.csv) }
        Button("Exporter en JSON…") { engine.export(.json) }
        if let lastExport = engine.lastExport {
            Text(lastExport)
        }

        Divider()

        Button(engine.isCollecting ? "Suspendre la collecte" : "Reprendre la collecte") {
            engine.isCollecting ? engine.stop() : engine.start()
        }

        launchAtLoginItem

        Button("Quitter Pulseon") {
            engine.stop()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// Le menu dit toujours la vérité sur l'état réel du système : si l'app
    /// tourne hors bundle, on l'annonce au lieu d'afficher une case à cocher
    /// qui ne cocherait rien.
    @ViewBuilder
    private var launchAtLoginItem: some View {
        switch engine.launchAtLogin {
        case .unavailable:
            Text("Démarrage auto — installe Pulseon dans Applications")
        case .enabled:
            Button("✓ Lancer au démarrage") { engine.setLaunchAtLogin(false) }
        case .disabled:
            Button("Lancer au démarrage") { engine.setLaunchAtLogin(true) }
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        DurationFormat.long(seconds)
    }
}
