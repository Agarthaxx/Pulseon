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
            Label(engine.menuBarTitle, systemImage: engine.menuBarSymbol)
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

    /// La journée en cours, relue périodiquement. C'est elle qui fait défiler
    /// le temps en haut de l'écran.
    private(set) var today: DayDigest?

    private let monitor: ActivityMonitor
    private let store: SessionStore
    private var refreshTimer: Timer?

    /// Une minute : c'est la plus petite unité qu'on affiche, donc rafraîchir
    /// plus vite ne changerait rien à l'écran. Ce sont des *lectures*, jamais
    /// des écritures — aucun rapport avec les 450 Mo/jour d'hier.
    private let refreshInterval: TimeInterval = 60

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
        let timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = refreshInterval / 4
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func refresh() {
        today = todayDigest()
    }

    /// Ce que la barre de menu affiche à côté de l'icône.
    ///
    /// Format resserré (`3h07`) et pas celui du menu (`3 h 07`) : la barre de
    /// menu est un espace partagé avec toutes les autres apps, et chaque
    /// caractère y coûte.
    var menuBarTitle: String {
        // Un tiret quand on ne sait pas, plutôt qu'un zéro qui mentirait.
        guard let today else { return "—" }
        return DurationFormat.compact(today.coveredTotal)
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

    /// Relit la journée en cours.
    ///
    /// Une lecture qui échoue est signalée, pas maquillée : rendre une journée
    /// vide ferait croire à zéro minute d'écran alors qu'on ne sait tout
    /// simplement pas.
    private func todayDigest() -> DayDigest? {
        let calendar = Calendar.current
        let day = Date()
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        do {
            let digest = DayDigestBuilder(calendar: calendar).build(
                day: day,
                sessions: try store.sessions(from: start, to: end),
                samples: try store.samples(before: end)
            )
            readFailure = nil
            return digest
        } catch {
            readFailure = error.localizedDescription
            return nil
        }
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
