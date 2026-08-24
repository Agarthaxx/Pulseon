import Foundation
import PulseonCore
import SwiftData
import Testing

@testable import PulseonMacKit

/// Le collecteur TV, sans télé et sans réseau : la sonde est simulée.
///
/// Les faits qu'elle simule, eux, ont été mesurés sur la vraie télé (voir
/// `SamsungTVProbe`) : le ping répond même éteinte, et seul le port 8001 dit la
/// vérité.
@Suite struct TVMonitorTests {
    private let now = Date(timeIntervalSince1970: 1_770_213_600)

    // MARK: La lecture de la réponse

    @Test("Un écran allumé est reconnu")
    func powerStateOnIsRead() {
        let body = Data(#"{"device":{"PowerState":"on","modelName":"TQ55S90CATXXC"}}"#.utf8)
        #expect(SamsungTVProbe.reading(from: body) == .on)
    }

    @Test("La veille est reconnue comme éteinte")
    func standbyIsOff() {
        #expect(SamsungTVProbe.reading(from: Data(#"{"device":{"PowerState":"standby"}}"#.utf8)) == .off)
    }

    @Test("La casse de la réponse n'a pas d'importance")
    func caseDoesNotMatter() {
        #expect(SamsungTVProbe.reading(from: Data(#"{"device":{"PowerState":"ON"}}"#.utf8)) == .on)
    }

    /// Une réponse qu'on ne comprend pas n'est pas une télé éteinte. Conclure
    /// « éteinte » effacerait une soirée de film sur un changement de firmware.
    @Test("Une réponse incompréhensible ne vaut pas éteinte")
    func malformedIsUnknown() {
        #expect(SamsungTVProbe.reading(from: Data("pas du json".utf8)) == .unknown)
        #expect(SamsungTVProbe.reading(from: Data(#"{"device":{}}"#.utf8)) == .unknown)
        #expect(SamsungTVProbe.reading(from: Data()) == .unknown)
    }

    // MARK: La décision

    @Test("Un écran allumé ouvre une session, puis n'en ouvre plus")
    func onOpensOnce() {
        #expect(
            TVDecision.next(reading: .on, isOpen: false, now: now, lastSeenOn: nil) == .open
        )
        #expect(
            TVDecision.next(reading: .on, isOpen: true, now: now, lastSeenOn: now) == .nothing
        )
    }

    /// **Le test central de l'honnêteté du comptage.** Entre deux relevés on ignore
    /// à quelle seconde l'écran s'est éteint : fermer à `now` compterait jusqu'à
    /// trente secondes de télé qui n'ont peut-être pas eu lieu.
    @Test("Une extinction ferme la session au dernier instant observé, pas à maintenant")
    func offClosesAtLastObservedInstant() {
        let seen = now.addingTimeInterval(-30)

        #expect(
            TVDecision.next(reading: .off, isOpen: true, now: now, lastSeenOn: seen)
                == .close(at: seen)
        )
    }

    @Test("Une extinction sans session ouverte ne fait rien")
    func offWithoutSessionDoesNothing() {
        #expect(
            TVDecision.next(reading: .off, isOpen: false, now: now, lastSeenOn: nil) == .nothing
        )
    }

    /// Sans instant observé — cas théorique, la session ayant forcément été
    /// ouverte sur une observation — on se rabat sur `now` plutôt que d'inventer.
    @Test("Sans instant observé, l'extinction se rabat sur maintenant")
    func offWithoutObservationFallsBackToNow() {
        #expect(
            TVDecision.next(reading: .off, isOpen: true, now: now, lastSeenOn: nil)
                == .close(at: now)
        )
    }

    /// Une micro-coupure Wi-Fi ne doit pas découper une soirée de film en
    /// confettis : on tolère de ne rien savoir pendant un moment.
    @Test("Ne rien savoir brièvement ne ferme pas la session")
    func shortUnknownIsTolerated() {
        #expect(
            TVDecision.next(
                reading: .unknown, isOpen: true, now: now,
                lastSeenOn: now.addingTimeInterval(-30)
            ) == .nothing
        )
    }

    /// Mais une panne réseau d'une nuit ne doit pas compter huit heures de télé.
    @Test("Ne rien savoir longtemps ferme la session au dernier instant observé")
    func longUnknownClosesAtLastObservedInstant() {
        let seen = now.addingTimeInterval(-10 * 60)

        #expect(
            TVDecision.next(reading: .unknown, isOpen: true, now: now, lastSeenOn: seen)
                == .close(at: seen)
        )
    }

    @Test("Ne rien savoir sans session ouverte ne fait rien")
    func unknownWithoutSessionDoesNothing() {
        #expect(
            TVDecision.next(reading: .unknown, isOpen: false, now: now, lastSeenOn: nil)
                == .nothing
        )
    }

    // MARK: Ce qui finit vraiment en base

    /// Voir `TestBase` ailleurs : le conteneur doit rester vivant aussi longtemps
    /// que le contexte, sinon le processus de test meurt sur un signal.
    @MainActor
    private final class TVBase {
        let container: ModelContainer
        let store: SessionStore
        let monitor: TVMonitor

        init() throws {
            container = try ModelContainer(
                for: StoredSession.self, StoredCounterSample.self, StoredApp.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            store = SessionStore(context: container.mainContext)
            monitor = TVMonitor(probe: SilentProbe(), store: store)
        }

        func sessions(_ device: Device, around date: Date) throws -> [ActivitySession] {
            try store.sessions(
                from: date.addingTimeInterval(-86_400), to: date.addingTimeInterval(86_400)
            )
            .filter { $0.device == device }
        }
    }

    /// La sonde n'est jamais appelée dans ces tests : on pousse les lectures à la
    /// main pour maîtriser l'horloge.
    private struct SilentProbe: TVProbe {
        func read() async -> TVReading { .unknown }
    }

    @Test("Arrêter le collecteur ferme la session de la télé, au dernier instant vu")
    @MainActor
    func stoppingClosesTheTVSession() throws {
        let base = try TVBase()
        let start = now
        let lastSeen = now.addingTimeInterval(120)

        base.monitor.apply(.on, at: start)
        base.monitor.apply(.on, at: lastSeen)

        // Quitter Pulseon la télé allumée. Sans fermeture ici, la session
        // restait ouverte jusqu'au démarrage suivant, où elle était refermée à
        // la date du battement de cœur — celui du *Mac*, donc juste par
        // accident. Le Mac fermait bien la sienne : l'asymétrie ne se voyait
        // que sur une soirée de télé.
        base.monitor.stop()

        let sessions = try base.sessions(.tv, around: start)
        let session = try #require(sessions.first)
        // Au dernier instant **observé** allumé, jamais à l'heure courante.
        #expect(session.end == lastSeen)
    }

    @Test("Redémarrer le collecteur ne coupe pas la soirée en cours")
    @MainActor
    func restartingDoesNotCloseTheSession() throws {
        let base = try TVBase()
        base.monitor.apply(.on, at: now)

        // `start()` remet son timer en place et **ne doit pas** passer par
        // `stop()`, qui ferme désormais la session : sinon chaque redémarrage
        // du collecteur couperait la soirée en deux.
        base.monitor.start()
        base.monitor.stop()

        let sessions = try base.sessions(.tv, around: now)
        #expect(sessions.count == 1)
    }

    @Test("Une télé allumée puis éteinte laisse une session bornée")
    @MainActor
    func onThenOffWritesABoundedSession() throws {
        let base = try TVBase()
        let start = now
        let lastSeen = now.addingTimeInterval(60)

        base.monitor.apply(.on, at: start)
        base.monitor.apply(.on, at: lastSeen)
        // Trente secondes plus tard, la télé est éteinte : la session doit se
        // fermer sur `lastSeen`, pas sur cet instant.
        base.monitor.apply(.off, at: lastSeen.addingTimeInterval(30))

        let sessions = try base.sessions(.tv, around: now)
        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.start == start)
        #expect(session.end == lastSeen)
        // La télé ne dit pas ce qu'elle diffuse, et le supposer serait une
        // invention.
        #expect(session.entity == nil)
    }

    /// **Le bug que ce collecteur aurait révélé.** `closeOpenSession(at:)` fermait
    /// les sessions de *tous* les appareils : la mise en veille du Mac aurait clos
    /// la session d'une télé restée allumée, et rien ne l'aurait signalé.
    @Test("Fermer la session de la télé ne touche pas celle du Mac")
    @MainActor
    func closingTVLeavesTheMacAlone() throws {
        let base = try TVBase()
        base.store.openSession(device: .mac, entity: "Xcode", at: now)
        base.monitor.apply(.on, at: now)
        base.monitor.apply(.off, at: now.addingTimeInterval(60))

        #expect(base.store.hasOpenSession(for: .mac))
        #expect(!base.store.hasOpenSession(for: .tv))
    }

    @Test("Une télé éteinte depuis le début n'écrit rien")
    @MainActor
    func neverOnWritesNothing() throws {
        let base = try TVBase()
        base.monitor.apply(.off, at: now)
        base.monitor.apply(.unknown, at: now.addingTimeInterval(30))

        #expect(try base.sessions(.tv, around: now).isEmpty)
        // Rien écrit : la piste doit donc rester « pas encore branchée », pas
        // « journée à zéro ».
        #expect(!base.store.hasOpenSession(for: .tv))
    }
}
