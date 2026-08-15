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

    /// Totaux cumulés par entité, tels que la source les rend, en secondes.
    ///
    /// Rendre un dictionnaire vide est une réponse valide : « la source
    /// répond, elle n'a rien à déclarer ». C'est différent d'une erreur, qui
    /// signifie qu'on ne sait pas.
    func readTotals() async throws -> [String: TimeInterval]
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
                let totals = try await self.source.readTotals()
                let now = Date()
                var written = 0
                for (entity, total) in totals {
                    let isNew = self.store.record(
                        device: self.source.device, entity: entity, total: total, at: now
                    )
                    if isNew { written += 1 }
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
