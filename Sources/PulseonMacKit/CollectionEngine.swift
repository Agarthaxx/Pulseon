import AppKit
import PulseonCore
import PulseonUI
import SwiftData
import SwiftUI

/// Détient le conteneur SwiftData et le moniteur, et les garde en vie tant
/// que l'app tourne.
///
/// **Il vit dans `PulseonMacKit` et non dans la cible exécutable**, pour la
/// raison qui vaut pour tout le code macOS de ce projet : le `@main` d'une
/// cible exécutable démarre SwiftUI **dans le processus de test**, donc rien
/// de ce qu'elle contient n'est testable. Le moteur y est resté jusqu'au
/// 2026-08-24 — 250 lignes qui portent le cache de la journée, le tick
/// d'affichage et le passage de minuit, c'est-à-dire précisément ce qui
/// mérite des tests.
@MainActor
@Observable
public final class CollectionEngine {
    public let container: ModelContainer
    public private(set) var isCollecting = false
    /// Non-nil quand la persistance a échoué : la collecte tourne en mémoire
    /// et sera perdue. Le menu doit le dire — un agent qui ne dit rien laisse
    /// croire qu'il enregistre.
    public private(set) var failure: String?
    /// Ce que le dernier export a produit, affiché dans le menu. Un export
    /// silencieux ne distingue pas « tout est là » de « le fichier est vide ».
    public private(set) var lastExport: String?
    public private(set) var launchAtLogin: LaunchAtLogin.State = LaunchAtLogin.state
    /// Non-nil quand la *lecture* a échoué — distinct de `failure`, qui parle
    /// de l'écriture. Les deux méritent d'être dits séparément.
    public private(set) var readFailure: String?

    /// La journée en cours, recalculée chaque seconde. C'est elle qui fait
    /// défiler le temps en haut de l'écran.
    public private(set) var today: DayDigest?

    /// Ce que la barre de menu affiche à côté de l'icône, tenu à jour par le
    /// tick. Propriété *stockée* et non calculée : elle n'est réassignée que
    /// quand le texte change réellement, ce qui évite de redessiner la barre
    /// une fois par seconde quand le compteur est gelé.
    public private(set) var menuBarTitle = "—"

    /// Ce qui alimente la fenêtre du dashboard. Détenu par le moteur pour que
    /// la journée affichée survive à la fermeture de la fenêtre.
    public let browser: DayBrowser

    /// Ce qui alimente l'écran de la semaine, détenu pour la même raison.
    public let periods: PeriodBrowser

    /// Vrai quand le moteur **lit sans mesurer**.
    ///
    /// Il change une chose et une seule : l'horizon d'affichage. Un moteur qui
    /// collecte le prend au moniteur, qui seul se souvient du dernier instant
    /// d'activité *observée* — c'est ce qui empêche le compteur de reculer.
    /// Un moteur silencieux n'a pas de moniteur qui tourne : lui demander cet
    /// horizon rendrait « il y a vingt minutes » un jour et « maintenant » un
    /// autre, selon que quelqu'un a touché le clavier. Sa journée s'arrête donc
    /// à l'instant présent, ce qui est à la fois vrai et reproductible.
    private let silent: Bool

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
    public var tvIsUnreachable: Bool { tv?.lastReading == .unknown }

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

    /// - Parameters:
    ///   - container: la base à lire et écrire. `nil` ouvre celle de l'app,
    ///     dans `~/Library/Application Support/Pulseon`.
    ///   - collecting: faux pour un moteur qui **lit sans mesurer**. C'est ce
    ///     qui rend cette classe testable : un test ne doit ni ouvrir la vraie
    ///     base, ni démarrer les moniteurs système, ni planter des timers dans
    ///     le runloop qui l'exécute.
    public init(container injected: ModelContainer? = nil, collecting: Bool = true) {
        self.silent = !collecting
        let (container, failure): (ModelContainer, String?) =
            if let injected { (injected, nil) } else { StoreLocation.makeContainer() }
        self.container = container
        self.failure = failure
        let store = SessionStore(context: container.mainContext)
        self.store = store
        self.monitor = ActivityMonitor(store: store)
        let registry = AppRegistry(context: container.mainContext)
        self.browser = DayBrowser(store: store, registry: registry)
        self.periods = PeriodBrowser(store: store, registry: registry)
        if collecting {
            start()
            startRefreshing()
        } else {
            // Le moteur silencieux lit quand même une fois : sans ça, un test
            // n'observerait que l'état initial et ne verrait jamais ce que la
            // base contient.
            refresh()
        }
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
    public func refresh() {
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

    public var menuBarSymbol: String {
        if failure != nil || readFailure != nil { return "exclamationmark.triangle" }
        return isCollecting ? "waveform" : "waveform.slash"
    }

    public func start() {
        guard !isCollecting else { return }
        monitor.start()
        startTV()
        isCollecting = true
        refresh()
    }

    public func stop() {
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

    /// Écrit tout l'historique dans un fichier choisi par l'utilisateur.
    ///
    /// **L'envers de « rien ne sort de ta machine »** : rien n'en sort tout
    /// seul, et tout doit pouvoir en sortir sur demande. Une app de mesure qui
    /// garde ses mesures prisonnières demande de lui faire confiance sans
    /// contrepartie.
    public func export(_ format: DataExport.Format) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Exporter.suggestedName(for: format, on: Date())
        panel.canCreateDirectories = true
        panel.title = "Exporter les données de Pulseon"

        // Une app en barre de menu n'est pas active au moment du clic : sans
        // ça, le panneau s'ouvrirait derrière la fenêtre du dessus.
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let written = try Exporter.write(format, from: store, to: url)
            failure = nil
            lastExport = "\(written.sessions) sessions exportées"
            // La confirmation standard de macOS, et la seule qui prouve
            // vraiment quelque chose : le fichier est là, on le voit.
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            // Un export raté doit se dire. Un fichier absent après un clic
            // ressemble à un export réussi qu'on n'a pas su retrouver.
            failure = "Export impossible — \(error.localizedDescription)"
        }
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
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

    /// Jusqu'où la journée est comptée. Voir `silent`.
    private func horizon(_ now: Date) -> Date {
        silent ? now : monitor.observedActivityEnd(now: now)
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
            now: horizon(now)
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
