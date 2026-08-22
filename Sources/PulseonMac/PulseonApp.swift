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
            // Icône *et* texte : le total du jour est visible en permanence,
            // sans avoir à ouvrir le menu. Il avance d'une minute par minute
            // tant qu'on est devant l'écran — et s'arrête quand on ne l'est
            // plus, ce qui n'est pas une panne mais le comportement voulu.
            //
            // `Label(_:systemImage:)` ne convient pas ici, et ça a été vu à
            // l'exécution : le libellé d'un `MenuBarExtra` est traité comme une
            // icône de barre de menu, donc le texte est silencieusement jeté et
            // le total n'apparaissait qu'en ouvrant le menu. Un `Text` qui
            // *interpole* l'image garde les deux, parce que tout est alors un
            // seul texte aux yeux du système.
            Text("\(Image(systemName: engine.menuBarSymbol)) \(engine.menuBarTitle)")
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

    @Environment(\.colorScheme) private var scheme

    /// La journée en cours grandit pendant qu'on la regarde. Une minute suffit
    /// — un bloc d'une minute fait moins d'un point de large sur 24 h, donc
    /// rafraîchir plus vite ne changerait rien à ce qu'on voit. Ici, à la
    /// différence de la barre de menu, ce sont de vraies lectures de base.
    private let refresh = Timer.publish(every: 60, tolerance: 15, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        let palette = PulseonTheme.palette(for: scheme)

        VStack(spacing: 0) {
            ScreenPicker(selection: $screen, palette: palette)
                .padding(.top, 12)

            switch screen {
            case .day:
                DayDashboard(
                    load: browser.load,
                    canGoForward: browser.canGoForward,
                    onPrevious: browser.goToPreviousDay,
                    onNext: browser.goToNextDay,
                    onToday: browser.goToToday
                )
            case .week:
                WeekDashboard(
                    load: periods.load,
                    canGoForward: periods.canGoForward,
                    onPrevious: periods.goToPreviousWeek,
                    onNext: periods.goToNextWeek,
                    onCurrent: periods.goToCurrentWeek
                )
            case .timeline:
                // La chronologie regarde **la même journée** que l'écran du
                // jour, et partage donc son `DayBrowser` : deux navigations
                // séparées feraient dériver les deux écrans l'un de l'autre,
                // et basculer d'onglet changerait la date sans le dire.
                DayTimeline(
                    load: browser.load,
                    canGoForward: browser.canGoForward,
                    onPrevious: browser.goToPreviousDay,
                    onNext: browser.goToNextDay,
                    onToday: browser.goToToday
                )
            }
        }
        .background(palette.ground)
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
    }

    private func reloadVisible() {
        switch screen {
        case .day, .timeline: browser.reload()
        case .week: periods.reload()
        }
    }
}

/// Détient le conteneur SwiftData et le moniteur, et les garde en vie tant
/// que l'app tourne.
@MainActor
@Observable
final class CollectionEngine {
    let container: ModelContainer
    private(set) var isCollecting = false
    /// Non-nil quand la persistance a échoué : la collecte tourne en mémoire
    /// et sera perdue. Le menu doit le dire — un agent qui ne dit rien laisse
    /// croire qu'il enregistre.
    private(set) var failure: String?
    private(set) var launchAtLogin: LaunchAtLogin.State = LaunchAtLogin.state
    /// Non-nil quand la *lecture* a échoué — distinct de `failure`, qui parle
    /// de l'écriture. Les deux méritent d'être dits séparément.
    private(set) var readFailure: String?

    /// La journée en cours, recalculée chaque seconde. C'est elle qui fait
    /// défiler le temps en haut de l'écran.
    private(set) var today: DayDigest?

    /// Ce que la barre de menu affiche à côté de l'icône, tenu à jour par le
    /// tick. Propriété *stockée* et non calculée : elle n'est réassignée que
    /// quand le texte change réellement, ce qui évite de redessiner la barre
    /// une fois par seconde quand le compteur est gelé.
    private(set) var menuBarTitle = "—"

    /// Ce qui alimente la fenêtre du dashboard. Détenu par le moteur pour que
    /// la journée affichée survive à la fermeture de la fenêtre.
    let browser: DayBrowser

    /// Ce qui alimente l'écran de la semaine, détenu pour la même raison.
    let periods: PeriodBrowser

    private let monitor: ActivityMonitor
    private let store: SessionStore
    private var reloadTimer: Timer?
    private var tickTimer: Timer?

    /// Le collecteur TV, s'il est configuré. Non-nil seulement quand un nom
    /// d'hôte a été déposé (voir `TVSettings`) : sans télé à interroger, un
    /// collecteur ne ferait qu'échouer toutes les trente secondes.
    private var tv: TVMonitor?

    /// Ce que la télé a répondu au dernier relevé, pour que le menu puisse dire
    /// qu'elle est injoignable — ce qui n'est pas la même chose qu'éteinte.
    var tvIsUnreachable: Bool { tv?.lastReading == .unknown }

    /// Les sessions et relevés de la journée, gardés en mémoire entre deux
    /// relectures. C'est ce qui rend le défilement gratuit : `build` borne les
    /// sessions ouvertes sur l'horizon qu'on lui passe, donc avancer d'une
    /// seconde ne demande qu'une addition — pas une requête.
    private var cachedSessions: [ActivitySession] = []
    private var cachedSamples: [CounterSample] = []
    private var cachedDayStart: Date?

    /// Relecture du disque. Une minute suffit : entre deux, seule la session
    /// déjà ouverte progresse, et le cache sait la faire progresser seul.
    private let reloadInterval: TimeInterval = 60

    /// Cadence d'affichage. Ce sont des additions en mémoire, jamais des
    /// lectures de base — aucun rapport avec les 450 Mo/jour d'hier.
    private let tickInterval: TimeInterval = 1

    init() {
        let (container, failure) = StoreLocation.makeContainer()
        self.container = container
        self.failure = failure
        let store = SessionStore(context: container.mainContext)
        self.store = store
        self.monitor = ActivityMonitor(store: store)
        let registry = AppRegistry(context: container.mainContext)
        self.browser = DayBrowser(store: store, registry: registry)
        self.periods = PeriodBrowser(store: store, registry: registry)
        start()
        startRefreshing()
    }

    /// Le rafraîchissement vit indépendamment de la collecte : suspendre la
    /// collecte ne doit pas figer l'affichage de ce qui a déjà été enregistré.
    private func startRefreshing() {
        refresh()

        let reload = Timer.scheduledTimer(withTimeInterval: reloadInterval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        reload.tolerance = reloadInterval / 4
        reloadTimer = reload
        RunLoop.main.add(reload, forMode: .common)

        // Pas de tolérance ici, contrairement à partout ailleurs : une seconde
        // qui glisse d'une demi-seconde se voit à l'œil nu. Le tick ne réveille
        // rien de coûteux — deux appels système et une addition.
        let tick = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tickTimer = tick
        RunLoop.main.add(tick, forMode: .common)
    }

    /// Relit le disque, puis recalcule.
    func refresh() {
        reloadFromStore()
        recompute()
    }

    /// Fait avancer l'affichage sans toucher au disque.
    private func tick() {
        // Minuit : le cache porte la journée d'hier, plus rien ne la fera
        // bouger. On relit plutôt que d'afficher une journée périmée.
        if cachedDayStart != Calendar.current.startOfDay(for: Date()) {
            reloadFromStore()
        }
        recompute()
    }

    var menuBarSymbol: String {
        if failure != nil || readFailure != nil { return "exclamationmark.triangle" }
        return isCollecting ? "waveform" : "waveform.slash"
    }

    func start() {
        guard !isCollecting else { return }
        monitor.start()
        startTV()
        isCollecting = true
        refresh()
    }

    func stop() {
        guard isCollecting else { return }
        monitor.stop()
        tv?.stop()
        tv = nil
        isCollecting = false
        refresh()
    }

    /// Branche le collecteur TV si une télé est configurée.
    ///
    /// La télé est une source à **intervalles**, comme le Mac : elle sait dire
    /// *quand* son écran était allumé, donc elle ouvre et ferme de vraies
    /// sessions. Rien à voir avec une source à compteur.
    private func startTV() {
        guard tv == nil, let host = TVSettings.host else { return }

        let witness = NetworkWitness()
        let monitor = TVMonitor(
            probe: SamsungTVProbe(host: host, hasNetwork: { witness.hasNetwork }),
            // La même télé, interrogée sur une autre question : « quelle app est
            // à l'écran ? ». Tout reste sur le réseau local — rien ne sort de la
            // machine, contrairement à ce qu'exigerait un service de favicons.
            appProbe: SamsungTVAppProbe(host: host),
            store: store
        )
        tv = monitor
        monitor.start()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if let error = LaunchAtLogin.setEnabled(enabled) {
            failure = error
        }
        // Le système fait foi : après un enregistrement il peut exiger une
        // approbation, ce qui n'est ni « activé » ni « désactivé ».
        launchAtLogin = LaunchAtLogin.state
    }

    /// Recharge en mémoire les sessions et relevés de la journée en cours.
    ///
    /// Une lecture qui échoue est signalée, pas maquillée : rendre une journée
    /// vide ferait croire à zéro minute d'écran alors qu'on ne sait tout
    /// simplement pas.
    private func reloadFromStore() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        do {
            cachedSessions = try store.sessions(from: start, to: end)
            cachedSamples = try store.samples(before: end)
            cachedDayStart = start
            readFailure = nil
        } catch {
            cachedSessions = []
            cachedSamples = []
            // Le cache n'est marqué sur aucune journée : le prochain tick
            // retentera la lecture au lieu de se croire à jour.
            cachedDayStart = nil
            readFailure = error.localizedDescription
        }
    }

    /// Recalcule la journée à partir du cache, sans aucune I/O.
    ///
    /// L'horizon vient du moniteur et pas de `Date()` : on ne compte que de
    /// l'activité constatée. Voir `ActivityMonitor.observedActivityEnd`.
    private func recompute() {
        guard let dayStart = cachedDayStart else {
            today = nil
            // Un tiret quand on ne sait pas, plutôt qu'un zéro qui mentirait.
            menuBarTitle = "—"
            return
        }

        let now = Date()
        let digest = DayDigestBuilder(calendar: Calendar.current).build(
            day: dayStart,
            sessions: cachedSessions,
            samples: cachedSamples,
            now: monitor.observedActivityEnd(now: now)
        )

        // Réassigner à l'identique réveillerait les vues pour rien : quand le
        // compteur est gelé, ce tick ne doit rien coûter à l'écran.
        if today?.coveredTotal != digest.coveredTotal { today = digest }

        // Format vivant (`3h07:12`) : la barre de menu est un espace partagé,
        // mais l'unité `h`/`m`/`s` est ce qui empêche de lire le total comme
        // l'heure qu'il est, juste à côté.
        let title = DurationFormat.live(digest.coveredTotal)
        if menuBarTitle != title { menuBarTitle = title }
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
