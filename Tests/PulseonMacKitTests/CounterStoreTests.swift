import Foundation
import PulseonCore
import SwiftData
import Testing

@testable import PulseonMacKit

/// Une base neuve en mémoire par test : rien ne touche le disque, rien ne
/// fuite d'un test à l'autre.
///
/// Détient le conteneur **et** le store, et ce n'est pas de la décoration :
/// `ModelContext` ne retient pas son `ModelContainer`. Rendre le seul store
/// laisserait le conteneur se faire libérer à la sortie de la fonction, et le
/// contexte survivant plante le processus de test sur un signal, sans le
/// moindre message d'erreur.
@MainActor
private final class TestBase {
    let container: ModelContainer
    let store: SessionStore

    init() throws {
        container = try ModelContainer(
            for: StoredSession.self, StoredCounterSample.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = SessionStore(context: container.mainContext)
    }
}

private let t0 = Date(timeIntervalSince1970: 1_770_000_000)

@Test("Un relevé qui n'apprend rien n'est pas écrit")
@MainActor
func identicalTotalsAreSkipped() throws {
    let base = try TestBase()

    #expect(base.store.record(device: .playstation, entity: "Bloodborne", total: 3600, at: t0))
    // Même total un quart d'heure plus tard : on n'a pas joué.
    #expect(
        base.store.record(
            device: .playstation, entity: "Bloodborne", total: 3600,
            at: t0.addingTimeInterval(900)) == false)
    #expect(
        base.store.record(
            device: .playstation, entity: "Bloodborne", total: 3600,
            at: t0.addingTimeInterval(1800)) == false)

    #expect(try base.store.samples(before: t0.addingTimeInterval(9999)).count == 1)
}

@Test("Un total qui bouge est écrit")
@MainActor
func changedTotalsAreRecorded() throws {
    let base = try TestBase()

    #expect(base.store.record(device: .playstation, entity: "Bloodborne", total: 3600, at: t0))
    #expect(
        base.store.record(
            device: .playstation, entity: "Bloodborne", total: 5400,
            at: t0.addingTimeInterval(900)))

    let samples = try base.store.samples(before: t0.addingTimeInterval(9999))
    #expect(samples.count == 2)
    #expect(samples.map(\.total) == [3600, 5400])
}

@Test("Chaque jeu a son propre compteur")
@MainActor
func entitiesAreIndependent() throws {
    let base = try TestBase()

    #expect(base.store.record(device: .playstation, entity: "Bloodborne", total: 3600, at: t0))
    // Même total, autre jeu : ce n'est pas un doublon.
    #expect(base.store.record(device: .playstation, entity: "Returnal", total: 3600, at: t0))

    let samples = try base.store.samples(before: t0.addingTimeInterval(9999))
    #expect(Set(samples.map(\.entity)) == ["Bloodborne", "Returnal"])
}

@Test("Un total qui baisse est enregistré tel quel, pas corrigé")
@MainActor
func decreasingTotalsAreStoredAsIs() throws {
    let base = try TestBase()

    #expect(base.store.record(device: .playstation, entity: "Bloodborne", total: 7200, at: t0))
    // Aberrant pour un compteur cumulatif, mais c'est ce que la source a dit.
    // On n'invente pas à sa place : c'est à l'agrégation de refuser le delta.
    #expect(
        base.store.record(
            device: .playstation, entity: "Bloodborne", total: 3600,
            at: t0.addingTimeInterval(900)))

    #expect(try base.store.samples(before: t0.addingTimeInterval(9999)).map(\.total) == [7200, 3600])
}

@Test("Le dédoublonnage ne casse pas le calcul du temps du jour")
@MainActor
func dedupPreservesDailyMath() throws {
    let base = try TestBase()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!

    let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 12))!
    let dayStart = calendar.startOfDay(for: day)

    // Avant-hier : 10 h au compteur. Hier : rien joué, donc aucun relevé écrit
    // — c'est précisément le cas que le dédoublonnage crée.
    base.store.record(
        device: .playstation, entity: "Bloodborne", total: 36000,
        at: dayStart.addingTimeInterval(-2 * 86400))
    // Aujourd'hui : deux heures de plus.
    base.store.record(
        device: .playstation, entity: "Bloodborne", total: 43200,
        at: dayStart.addingTimeInterval(3600))

    let end = calendar.date(byAdding: .day, value: 1, to: dayStart)!
    let digest = DayDigestBuilder(calendar: calendar).build(
        day: day,
        sessions: [],
        samples: try base.store.samples(before: end),
        now: dayStart.addingTimeInterval(7200)
    )

    let lane = try #require(digest.lanes.first { $0.device == .playstation })
    // Le relevé de référence date d'avant-hier : il fait tout aussi bien
    // l'affaire, puisque le total n'avait pas bougé entre-temps.
    #expect(lane.total == 7200)
    #expect(lane.isConnected)
    // Une source à compteur ne place rien sur la timeline.
    #expect(lane.blocks.isEmpty)
}
