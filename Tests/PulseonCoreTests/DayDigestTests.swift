import Foundation
import Testing

@testable import PulseonCore

/// Calendrier et horaires figés : sans ça les tests dépendraient du fuseau de
/// la machine et de l'heure à laquelle on les lance.
private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Paris")!
    return c
}()

private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(
        from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute)
    )!
}

private let builder = DayDigestBuilder(calendar: calendar)

@Test("Une session est tronquée aux bornes du jour affiché")
func sessionCrossingMidnightIsClamped() {
    // 22h00 la veille → 01h00 le jour affiché : seule 1h appartient au jour.
    let session = ActivitySession(
        device: .mac, entity: "Xcode", start: date(13, 22), end: date(14, 1)
    )
    let digest = builder.build(
        day: date(14, 12), sessions: [session], samples: [], now: date(14, 23)
    )
    let mac = digest.lanes.first { $0.device == .mac }!

    #expect(mac.total == 3600)
    #expect(mac.blocks.first?.startOffset == 0)
}

@Test("Une session encore ouverte est bornée à maintenant, pas à minuit")
func openSessionIsBoundedToNow() {
    let session = ActivitySession(
        device: .mac, entity: "Safari", start: date(14, 9), end: nil
    )
    let digest = builder.build(
        day: date(14, 12), sessions: [session], samples: [], now: date(14, 11)
    )

    // 9h → 11h = 2h. Compter jusqu'à minuit afficherait du temps pas écoulé.
    #expect(digest.lanes.first { $0.device == .mac }!.total == 7200)
}

@Test("Le temps d'un compteur exige un relevé antérieur au jour")
func counterWithoutBaselineCountsNothing() {
    // Un seul relevé dans la journée : impossible de savoir ce qui a été joué
    // aujourd'hui plutôt qu'avant. On ne compte rien.
    let sample = CounterSample(
        device: .playstation, entity: "Elden Ring",
        total: 150_000, recordedAt: date(14, 20)
    )
    let digest = builder.build(
        day: date(14, 12), sessions: [], samples: [sample], now: date(14, 23)
    )

    #expect(digest.lanes.first { $0.device == .playstation }!.total == 0)
}

@Test("Le temps d'un compteur est la progression depuis le dernier relevé de la veille")
func counterUsesDeltaFromBaseline() {
    let samples = [
        CounterSample(
            device: .playstation, entity: "Elden Ring",
            total: 148_000, recordedAt: date(13, 23)
        ),
        CounterSample(
            device: .playstation, entity: "Elden Ring",
            total: 155_200, recordedAt: date(14, 22)
        ),
    ]
    let digest = builder.build(
        day: date(14, 12), sessions: [], samples: samples, now: date(14, 23)
    )
    let ps = digest.lanes.first { $0.device == .playstation }!

    #expect(ps.total == 7200)
    // Sans horaires, la piste ne place aucun bloc sur la timeline.
    #expect(ps.blocks.isEmpty)
}

@Test("Le total couvert ne compte pas deux fois les écrans simultanés")
func coveredTotalMergesOverlap() {
    // Mac 20h→22h et TV 21h→23h : 4h cumulées, mais 3h devant un écran.
    let sessions = [
        ActivitySession(device: .mac, entity: "Safari", start: date(14, 20), end: date(14, 22)),
        ActivitySession(device: .tv, entity: nil, start: date(14, 21), end: date(14, 23)),
    ]
    let digest = builder.build(
        day: date(14, 12), sessions: sessions, samples: [], now: date(15, 0)
    )

    #expect(digest.summedTotal == 4 * 3600)
    #expect(digest.coveredTotal == 3 * 3600)
}

@Test("Un appareil ne peut pas être allumé deux fois en même temps")
func laneTotalMergesItsOwnOverlaps() throws {
    // Ce que deux collecteurs sur la même base ont vraiment écrit : la même
    // heure enregistrée deux fois sur le Mac, plus une session restée ouverte
    // qui recouvre les autres. Additionner ces blocs donnait « Mac : 51 h » sur
    // une journée de 2 h. Le chevauchement compte entre appareils, jamais à
    // l'intérieur d'un seul.
    let sessions = [
        ActivitySession(device: .mac, entity: "Excel", start: date(14, 9), end: date(14, 10)),
        ActivitySession(device: .mac, entity: "Excel", start: date(14, 9), end: date(14, 10)),
        ActivitySession(device: .mac, entity: "Windows App", start: date(14, 9), end: nil),
    ]
    let digest = builder.build(
        day: date(14, 12), sessions: sessions, samples: [], now: date(14, 10)
    )
    let mac = try #require(digest.lanes.first { $0.device == .mac })

    #expect(mac.total == 3600)
    #expect(digest.summedTotal == 3600)
    #expect(digest.coveredTotal == 3600)
    // Les blocs, eux, restent tels quels : c'est la timeline qui les dessine,
    // et elle doit pouvoir montrer ce qui a été enregistré.
    #expect(mac.blocks.count == 3)
}

@Test("Une source sans donnée se distingue d'une journée à zéro")
func missingCollectorIsNotAQuietDay() {
    let session = ActivitySession(
        device: .mac, entity: "Safari", start: date(14, 9), end: date(14, 10)
    )
    let digest = builder.build(
        day: date(14, 12), sessions: [session], samples: [], now: date(14, 23)
    )

    #expect(digest.lanes.first { $0.device == .mac }!.isConnected)
    // La TV n'a jamais rien écrit : l'UI doit pouvoir dire "pas branchée".
    #expect(digest.lanes.first { $0.device == .tv }!.isConnected == false)
}

@Test("Les apps sont classées par temps décroissant")
func entitiesAreRankedByTime() throws {
    let sessions = [
        ActivitySession(device: .mac, entity: "Safari", start: date(14, 9), end: date(14, 10)),
        ActivitySession(device: .mac, entity: "Xcode", start: date(14, 10), end: date(14, 13)),
        ActivitySession(device: .mac, entity: "Safari", start: date(14, 14), end: date(14, 15)),
    ]
    let digest = builder.build(
        day: date(14, 12), sessions: sessions, samples: [], now: date(14, 23)
    )
    let top = digest.lanes.first { $0.device == .mac }!.topEntities

    #expect(top.map(\.entity) == ["Xcode", "Safari"])
    // On déballe avec #require au lieu de comparer `top.first?.total` : à
    // l'intérieur de #expect, comparer un optionnel à une expression de
    // littéraux entiers (`3 * 3600`) fait échouer la comparaison alors que les
    // valeurs sont égales — la macro type l'opérande droit isolément, il tombe
    // en Int, et la comparaison se fait entre deux types différents.
    #expect(try #require(top.first).total == 3 * 3600)
    #expect(try #require(top.last).total == 2 * 3600)
}
