import Foundation
import PulseonCore

/// Une source qui ne sait dire qu'un total cumulé, jamais un horaire.
///
/// La PlayStation en est l'exemple : son API rend un `playDuration` par jeu,
/// mis à jour avec du retard, sans indiquer quand on a joué. Toute source
/// future du même genre implémente ce protocole et n'a rien d'autre à savoir
/// du reste du système.
public protocol CounterSource: Sendable {
    var device: Device { get }

    /// Ce que la source dit d'elle-même, en un seul appel.
    ///
    /// Rendre un relevé vide est une réponse valide : « la source répond, elle
    /// n'a rien à déclarer ». C'est différent d'une erreur, qui signifie qu'on
    /// ne sait pas.
    func read() async throws -> CounterReading
}

/// Ce qu'une source à compteur rapporte d'un passage.
///
/// Les totaux et les identités arrivent ensemble parce qu'ils viennent de la
/// **même** réponse : les séparer en deux méthodes ferait deux appels réseau
/// pour un seul relevé, et surtout ouvrirait la porte à un total sans son
/// identité, donc à un jeu bien compté et mal classé.
public struct CounterReading: Sendable, Equatable {
    /// Totaux cumulés par entité, tels que la source les rend, en secondes.
    public let totals: [String: TimeInterval]

    /// Ce que la source **déclare** de chaque entité, brut.
    ///
    /// Jamais notre interprétation : même règle que la catégorie déclarée par
    /// macOS, stockée telle quelle pour que tout l'historique se reclasse le
    /// jour où la table de correspondance change d'avis.
    public let declaredCategories: [String: String]

    /// L'identifiant de l'entité, quand il est **sans ambiguïté**.
    ///
    /// Absent dès que deux titres partagent un nom : ils sont additionnés sous
    /// ce nom, donc aucun des deux identifiants ne le désigne. En choisir un
    /// serait inventer une identité.
    public let identifiers: [String: String]

    public init(
        totals: [String: TimeInterval],
        declaredCategories: [String: String] = [:],
        identifiers: [String: String] = [:]
    ) {
        self.totals = totals
        self.declaredCategories = declaredCategories
        self.identifiers = identifiers
    }
}

/// Interroge une source à compteur à intervalle régulier et range ce qu'elle
/// dit.
///
/// Ne calcule aucun temps de jeu : il enregistre des relevés bruts. La
/// conversion en durée du jour se fait à la lecture, par différence entre deux
/// relevés (`DayDigestBuilder`). C'est ce qui permet de ne jamais inventer
/// d'horaire pour ces sources.
@MainActor
public final class CounterPoller {
    /// Un quart d'heure. Inutile d'aller plus vite : l'API PlayStation ne
    /// rafraîchit ses totaux qu'avec du retard, et un relevé plus fréquent
    /// n'apporterait qu'un doublon de plus à ignorer.
    public var interval: TimeInterval = 15 * 60

    /// Dernière erreur rencontrée, pour que le menu puisse dire que la source
    /// est muette au lieu de laisser croire qu'elle est à zéro.
    public private(set) var lastFailure: String?
    public private(set) var lastSuccess: Date?

    private let source: CounterSource
    private let store: SessionStore
    private var timer: Timer?
    private var inFlight = false

    public init(source: CounterSource, store: SessionStore) {
        self.source = source
        self.store = store
    }

    public func start() {
        stop()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { _ = self?.pollNow() }
        }
        timer.tolerance = interval / 4
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        pollNow()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// - Returns: le nombre de relevés réellement écrits — les totaux
    ///   inchangés ne comptent pas.
    @discardableResult
    public func pollNow() -> Task<Int, Never> {
        Task { [weak self] in
            guard let self, !self.inFlight else { return 0 }
            self.inFlight = true
            defer { self.inFlight = false }

            do {
                let reading = try await self.source.read()
                let now = Date()
                var written = 0
                for (entity, total) in reading.totals {
                    let isNew = self.store.record(
                        device: self.source.device, entity: entity, total: total, at: now
                    )
                    if isNew { written += 1 }

                    // L'identité ne se réécrit que quand elle change —
                    // `noteApp` s'en charge. Sans ça on referait l'erreur du
                    // `lastSeen` en base : soixante-dix titres réécrits tous
                    // les quarts d'heure pour une information qui ne bouge
                    // jamais.
                    self.store.noteApp(
                        name: entity,
                        device: self.source.device,
                        bundleID: reading.identifiers[entity],
                        declaredCategory: reading.declaredCategories[entity],
                        at: now
                    )
                }
                self.lastSuccess = now
                self.lastFailure = nil
                return written
            } catch {
                // Une source injoignable ne doit ni faire tomber l'agent, ni
                // se confondre avec « rien joué ». On le note, on réessaiera
                // au prochain tour.
                self.lastFailure = error.localizedDescription
                return 0
            }
        }
    }
}
