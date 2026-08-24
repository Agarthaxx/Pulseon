import Foundation
import PulseonCore
import SwiftData
import Testing

@testable import PulseonMacKit

/// Le moteur de collecte, enfin testable.
///
/// **Il a vécu 250 lignes durant dans la cible exécutable**, donc hors de
/// portée : le `@main` d'un exécutable démarre SwiftUI dans le processus de
/// test. Ce qu'il porte — le cache de la journée, le total affiché, la
/// distinction entre « rien mesuré » et « lecture impossible » — est pourtant
/// exactement ce qui mérite d'être vérifié.
///
/// Tous ces tests passent par `collecting: false` : un moteur qui **lit sans
/// mesurer**. Sans ça, chacun ouvrirait la vraie base d'Arthur et planterait
/// des moniteurs système dans le runloop de la suite.
@Suite("Le moteur de collecte")
struct CollectionEngineTests {
    /// Le conteneur doit rester vivant aussi longtemps que le moteur : un
    /// `ModelContext` ne retient pas son `ModelContainer`, et tout accès
    /// ultérieur tue le processus de test sur un signal.
    @MainActor
    private final class Base {
        let container: ModelContainer
        let store: SessionStore

        init() throws {
            container = try ModelContainer(
                for: StoredSession.self, StoredCounterSample.self, StoredApp.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            store = SessionStore(context: container.mainContext)
        }

        func engine() -> CollectionEngine {
            CollectionEngine(container: container, collecting: false)
        }

        /// Une fenêtre **déjà écoulée** dans la journée en cours.
        ///
        /// Une session placée à une heure fixe (« 20 h ») serait verte le soir
        /// et rouge le matin : le moteur ne compte que jusqu'à l'instant
        /// présent, donc du temps posé dans le futur vaut zéro. La fenêtre part
        /// de minuit et s'arrête à la moitié de ce qui s'est écoulé.
        func elapsed(upTo wanted: TimeInterval) -> (start: Date, duration: TimeInterval) {
            let dayStart = Calendar.current.startOfDay(for: Date())
            let sinceMidnight = Date().timeIntervalSince(dayStart)
            return (dayStart, min(wanted, sinceMidnight / 2))
        }
    }

    @Test("Une journée sans la moindre session vaut zéro, pas un tiret")
    @MainActor
    func emptyDayIsZeroNotUnknown() throws {
        let base = try Base()
        let engine = base.engine()

        // La distinction que tout le projet tient : « la base répond et il n'y
        // a rien » n'est pas « on n'a pas pu lire ». Le tiret est réservé au
        // second, et l'afficher ici ferait passer une journée mesurée à zéro
        // pour une panne.
        #expect(engine.today?.coveredTotal == 0)
        #expect(engine.menuBarTitle != "—")
    }

    @Test("Le total affiché est celui des sessions du jour")
    @MainActor
    func totalReflectsTheDay() throws {
        let base = try Base()
        let (start, duration) = base.elapsed(upTo: 1800)

        base.store.openSession(device: .mac, entity: "Xcode", at: start)
        base.store.closeOpenSession(device: .mac, at: start.addingTimeInterval(duration))

        let engine = base.engine()
        let digest = try #require(engine.today)
        #expect(digest.coveredTotal == duration)
        #expect(engine.menuBarTitle == DurationFormat.live(duration))
    }

    @Test("Deux écrans en même temps ne comptent qu'une fois dans la barre")
    @MainActor
    func simultaneousScreensAreMergedInTheMenuBar() throws {
        let base = try Base()
        let (start, duration) = base.elapsed(upTo: 3600)

        // Du Mac et de la télé, exactement sur la même tranche.
        base.store.openSession(device: .mac, entity: "IINA", at: start)
        base.store.closeOpenSession(device: .mac, at: start.addingTimeInterval(duration))
        base.store.openSession(device: .tv, entity: "YouTube", at: start)
        base.store.closeOpenSession(device: .tv, at: start.addingTimeInterval(duration))

        let engine = base.engine()
        let digest = try #require(engine.today)
        // La barre de menu porte le `coveredTotal` : on n'a pas passé deux
        // heures devant un écran, on en a passé une devant deux écrans.
        #expect(digest.coveredTotal == duration)
        #expect(digest.summedTotal == duration * 2)
        #expect(engine.menuBarTitle == DurationFormat.live(duration))
    }

    @Test("Une relecture ne réécrit le titre que s'il change")
    @MainActor
    func refreshKeepsTheTitleStable() throws {
        let base = try Base()
        let (start, duration) = base.elapsed(upTo: 600)
        base.store.openSession(device: .mac, entity: "Ghostty", at: start)
        base.store.closeOpenSession(device: .mac, at: start.addingTimeInterval(duration))

        let engine = base.engine()
        let before = engine.menuBarTitle
        engine.refresh()

        // Le tick tourne une fois par seconde pour toujours : réassigner un
        // titre identique réveillerait les vues pour rien. C'est la même
        // discipline que `noteApp`, qui n'écrit pas quand rien n'a changé.
        #expect(engine.menuBarTitle == before)
    }

    @Test("La journée d'hier n'entre pas dans le total du jour")
    @MainActor
    func yesterdayIsNotCounted() throws {
        let base = try Base()
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = today.addingTimeInterval(-6 * 3600)

        base.store.openSession(device: .mac, entity: "Xcode", at: yesterday)
        base.store.closeOpenSession(device: .mac, at: yesterday.addingTimeInterval(3600))

        let engine = base.engine()
        #expect(engine.today?.coveredTotal == 0)
    }
}
