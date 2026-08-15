import Foundation
import PulseonCore
import SwiftData
import Testing

@testable import PulseonMacKit

/// Voir `TestBase` dans CounterStoreTests : le conteneur doit rester vivant
/// aussi longtemps que le contexte.
@MainActor
private final class QueryBase {
    let container: ModelContainer
    let store: SessionStore

    init() throws {
        container = try ModelContainer(
            for: StoredSession.self, StoredCounterSample.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = SessionStore(context: container.mainContext)
    }

    /// Écrit une session close directement, sans passer par la machine à états
    /// d'`openSession` — on teste la lecture, pas l'écriture.
    func add(_ name: String, from: Date, to: Date?) {
        container.mainContext.insert(
            StoredSession(device: .mac, entity: name, start: from, end: to)
        )
    }
}

private let noon = Date(timeIntervalSince1970: 1_770_000_000)
private let windowStart = noon
private let windowEnd = noon.addingTimeInterval(3600)

private func at(_ offset: TimeInterval) -> Date { noon.addingTimeInterval(offset) }

@Test("La fenêtre retient ce qui la chevauche, et rien d'autre")
@MainActor
func windowKeepsOverlapsOnly() throws {
    let base = try QueryBase()

    base.add("avant", from: at(-7200), to: at(-3600))
    base.add("finit pile au debut", from: at(-3600), to: at(0))
    base.add("chevauche le debut", from: at(-1800), to: at(600))
    base.add("dedans", from: at(600), to: at(1200))
    base.add("chevauche la fin", from: at(3000), to: at(5400))
    base.add("commence pile a la fin", from: at(3600), to: at(7200))
    base.add("apres", from: at(7200), to: at(9000))
    base.add("englobe toute la fenetre", from: at(-9000), to: at(9000))

    let found = try base.store.sessions(from: windowStart, to: windowEnd)
        .map(\.entity).compactMap { $0 }

    #expect(
        Set(found) == [
            "chevauche le debut", "dedans", "chevauche la fin", "englobe toute la fenetre",
        ])
}

@Test("Une session encore ouverte compte si elle a commencé avant la fin")
@MainActor
func openSessionsAreIncluded() throws {
    let base = try QueryBase()

    base.add("ouverte, commencee avant", from: at(-1800), to: nil)
    base.add("ouverte, commencee dedans", from: at(600), to: nil)
    base.add("ouverte, commencee apres", from: at(7200), to: nil)

    let found = try base.store.sessions(from: windowStart, to: windowEnd)
        .map(\.entity).compactMap { $0 }

    #expect(Set(found) == ["ouverte, commencee avant", "ouverte, commencee dedans"])
}

@Test("Le tri rend les sessions dans l'ordre chronologique")
@MainActor
func resultsAreSorted() throws {
    let base = try QueryBase()

    base.add("troisieme", from: at(2400), to: at(3000))
    base.add("premier", from: at(60), to: at(600))
    base.add("deuxieme", from: at(1200), to: at(1800))

    let found = try base.store.sessions(from: windowStart, to: windowEnd)
        .map(\.entity).compactMap { $0 }

    #expect(found == ["premier", "deuxieme", "troisieme"])
}

@Test("Une fenêtre vide ne rend rien")
@MainActor
func emptyWindowIsEmpty() throws {
    let base = try QueryBase()
    base.add("hier", from: at(-90000), to: at(-86400))

    #expect(try base.store.sessions(from: windowStart, to: windowEnd).isEmpty)
}
