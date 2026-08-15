import PulseonCore
import PulseonMacKit
import SwiftData
import SwiftUI

/// Agent en barre de menu. Il n'a pas de fenêtre principale : la collecte
/// doit tourner en continu, indépendamment de toute fenêtre ouverte, et
/// c'est ce qui remplace le trio script + venv + launchd de la v1.
@main
struct PulseonApp: App {
    @State private var engine = CollectionEngine()

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

    private let monitor: ActivityMonitor
    private let store: SessionStore
    private var reloadTimer: Timer?
    private var tickTimer: Timer?

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
        isCollecting = true
        refresh()
    }

    func stop() {
        guard isCollecting else { return }
        monitor.stop()
        isCollecting = false
        refresh()
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
