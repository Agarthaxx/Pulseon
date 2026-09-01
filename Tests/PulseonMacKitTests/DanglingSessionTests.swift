import Foundation
import PulseonCore
import SwiftData
import Testing

@testable import PulseonMacKit

/// Voir `TestBase` dans CounterStoreTests : le conteneur doit rester vivant
/// aussi longtemps que le contexte.
@MainActor
private final class RepairBase {
    let container: ModelContainer
    let store: SessionStore

    init() throws {
        container = try ModelContainer(
            for: StoredSession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = SessionStore(context: container.mainContext)
    }

    /// Écrit une session ouverte directement, sans passer par `openSession` —
    /// qui refuserait justement d'en laisser deux. C'est ce que produisaient
    /// deux collecteurs sur la même base, et ce qu'on doit savoir réparer.
    func addOpen(_ name: String, at start: Date) {
        container.mainContext.insert(
            StoredSession(device: .mac, entity: name, start: start, end: nil)
        )
    }
}

private let t0 = Date(timeIntervalSince1970: 1_770_000_000)
private func at(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

@Test("Toutes les épaves sont fermées, pas seulement la dernière")
@MainActor
func everyDanglingSessionIsRepaired() throws {
    let base = try RepairBase()

    base.addOpen("Xcode", at: at(0))
    base.addOpen("Firefox", at: at(600))
    base.addOpen("Excel", at: at(1200))

    #expect(base.store.closeDanglingSessions(at: at(1800)) == 3)

    let sessions = try base.store.sessions(from: at(-3600), to: at(7200))
    #expect(sessions.allSatisfy { $0.end != nil })
    #expect(base.store.hasOpenSession(for: .mac) == false)
}

@Test("Une épave ne peut plus être prise pour la session en cours")
@MainActor
func staleSessionIsNotMistakenForTheCurrentOne() throws {
    let base = try RepairBase()

    // L'épave du matin, et la session réellement en cours.
    base.addOpen("Excel", at: at(0))
    base.addOpen("Firefox", at: at(3600))

    // Ce que fait un retour d'inactivité : fermer la session en cours.
    base.store.closeOpenSession(device: .mac, at: at(3900))

    let sessions = try base.store.sessions(from: at(-3600), to: at(7200))
    let excel = try #require(sessions.first { $0.entity == "Excel" })
    let firefox = try #require(sessions.first { $0.entity == "Firefox" })

    // C'est bien la récente qui a été fermée. Fermer l'épave lui aurait
    // attribué 65 minutes qui n'ont pas eu lieu — c'est exactement comme ça
    // qu'une journée de 2 h en a affiché 51.
    #expect(firefox.end == at(3900))
    #expect(excel.end == nil)
}

@Test("Sans trace de vie, l'épave est fermée sur son propre début")
@MainActor
func withoutHeartbeatSessionsCloseOnTheirStart() throws {
    let base = try RepairBase()

    base.addOpen("Xcode", at: at(0))
    base.addOpen("Firefox", at: at(600))

    #expect(base.store.closeDanglingSessions(at: nil) == 2)

    let sessions = try base.store.sessions(from: at(-3600), to: at(7200))
    // Durée nulle plutôt qu'une fin inventée, chacune sur son propre début.
    #expect(sessions.allSatisfy { $0.end == $0.start })
}
