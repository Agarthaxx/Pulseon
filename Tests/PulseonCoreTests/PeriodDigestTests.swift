import Foundation
import Testing

@testable import PulseonCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Paris")!
    return c
}()

private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute))!
}

private let builder = DayDigestBuilder(calendar: cal)

@Test("Une période rend toutes ses journées, y compris les vides")
func emptyDaysAreKept() throws {
    let sessions = [
        ActivitySession(device: .mac, entity: "Xcode", start: date(10, 9), end: date(10, 11)),
        // Rien les 11 et 12.
        ActivitySession(device: .mac, entity: "Safari", start: date(13, 14), end: date(13, 15)),
    ]

    let period = builder.buildPeriod(
        from: date(10, 0), through: date(13, 23), sessions: sessions, samples: [],
        now: date(13, 23))

    #expect(period.days.count == 4, "du 10 au 13 inclus")
    #expect(period.days.map(\.coveredTotal) == [7200, 0, 0, 3600])
    // Deux jours creux au milieu : la période doit pouvoir les montrer.
    #expect(period.daysWithActivity == 2)
}

@Test("Le total couvert d'une période est la somme des journées")
func coveredTotalSumsDays() throws {
    let sessions = [
        ActivitySession(device: .mac, entity: "Xcode", start: date(10, 9), end: date(10, 11)),
        ActivitySession(device: .mac, entity: "Safari", start: date(11, 9), end: date(11, 10)),
    ]

    let period = builder.buildPeriod(
        from: date(10, 0), through: date(11, 23), sessions: sessions, samples: [],
        now: date(11, 23))

    // Deux journées ne se chevauchent jamais : les additionner est licite.
    #expect(period.coveredTotal == 10800)
    #expect(period.summedTotal == 10800)
}

@Test("Une session à cheval sur minuit est comptée dans les deux journées")
func sessionAcrossMidnightCountsInBoth() throws {
    let sessions = [
        ActivitySession(device: .mac, entity: "Xcode", start: date(10, 23), end: date(11, 1))
    ]

    let period = builder.buildPeriod(
        from: date(10, 0), through: date(11, 23), sessions: sessions, samples: [],
        now: date(11, 23))

    // Une heure de chaque côté, pas deux heures d'un seul.
    #expect(period.days.map(\.coveredTotal) == [3600, 3600])
    #expect(period.coveredTotal == 7200)
}

@Test("Les pistes de période cumulent les appareils sans placer d'horaires")
func periodLanesHaveNoBlocks() throws {
    let sessions = [
        ActivitySession(device: .mac, entity: "Xcode", start: date(10, 9), end: date(10, 12)),
        ActivitySession(device: .mac, entity: "Safari", start: date(11, 9), end: date(11, 10)),
        ActivitySession(device: .mac, entity: "Xcode", start: date(11, 14), end: date(11, 15)),
    ]

    let period = builder.buildPeriod(
        from: date(10, 0), through: date(11, 23), sessions: sessions, samples: [],
        now: date(11, 23))

    let mac = try #require(period.lanes.first { $0.device == .mac })
    #expect(mac.total == 18000)
    // Une position dans une journée de 24 h n'a pas de sens sur deux jours.
    #expect(mac.blocks.isEmpty)
    #expect(mac.topEntities.map(\.entity) == ["Xcode", "Safari"])
    #expect(try #require(mac.topEntities.first).total == 4 * 3600)
}

@Test("Une source jamais branchée le reste sur toute la période")
func neverConnectedStaysUnconnected() throws {
    let period = builder.buildPeriod(
        from: date(10, 0), through: date(12, 23),
        sessions: [
            ActivitySession(device: .mac, entity: "Xcode", start: date(10, 9), end: date(10, 10))
        ],
        samples: [], now: date(12, 23))

    #expect(try #require(period.lanes.first { $0.device == .mac }).isConnected)
    #expect(try #require(period.lanes.first { $0.device == .tv }).isConnected == false)
}

@Test("Un jour sans donnée n'efface pas une source branchée les autres jours")
func oneQuietDayDoesNotDisconnect() throws {
    let sessions = [
        ActivitySession(device: .mac, entity: "Xcode", start: date(10, 9), end: date(10, 10)),
        // Rien le 11.
        ActivitySession(device: .mac, entity: "Xcode", start: date(12, 9), end: date(12, 10)),
    ]

    let period = builder.buildPeriod(
        from: date(10, 0), through: date(12, 23), sessions: sessions, samples: [],
        now: date(12, 23))

    #expect(try #require(period.lanes.first { $0.device == .mac }).isConnected)
    // La journée creuse, elle, dit bien qu'elle n'a rien vu.
    #expect(period.days[1].lanes.first { $0.device == .mac }?.isConnected == false)
}

@Test("Une période d'un seul jour vaut la journée seule")
func singleDayPeriodMatchesDayDigest() throws {
    let sessions = [
        ActivitySession(device: .mac, entity: "Xcode", start: date(10, 9), end: date(10, 11))
    ]

    let period = builder.buildPeriod(
        from: date(10, 12), through: date(10, 12), sessions: sessions, samples: [],
        now: date(10, 23))
    let day = builder.build(day: date(10, 12), sessions: sessions, samples: [], now: date(10, 23))

    #expect(period.days.count == 1)
    #expect(period.coveredTotal == day.coveredTotal)
    #expect(period.summedTotal == day.summedTotal)
}

@Test("Les sessions hors période sont ignorées")
func sessionsOutsidePeriodAreIgnored() throws {
    let sessions = [
        ActivitySession(device: .mac, entity: "avant", start: date(5, 9), end: date(5, 10)),
        ActivitySession(device: .mac, entity: "dedans", start: date(10, 9), end: date(10, 10)),
        ActivitySession(device: .mac, entity: "apres", start: date(20, 9), end: date(20, 10)),
    ]

    let period = builder.buildPeriod(
        from: date(10, 0), through: date(11, 23), sessions: sessions, samples: [],
        now: date(25, 23))

    #expect(period.coveredTotal == 3600)
    let mac = try #require(period.lanes.first { $0.device == .mac })
    #expect(mac.topEntities.map(\.entity) == ["dedans"])
}

@Test("Le temps d'un compteur se calcule jour par jour sur la période")
func counterDeltasPerDay() throws {
    let samples = [
        // Référence la veille de la période.
        CounterSample(
            device: .playstation, entity: "Bloodborne", total: 36000, recordedAt: date(9, 22)),
        CounterSample(
            device: .playstation, entity: "Bloodborne", total: 39600, recordedAt: date(10, 21)),
        CounterSample(
            device: .playstation, entity: "Bloodborne", total: 45000, recordedAt: date(11, 21)),
    ]

    let period = builder.buildPeriod(
        from: date(10, 0), through: date(11, 23), sessions: [], samples: samples,
        now: date(11, 23))

    // 1 h le premier jour, 1 h 30 le second.
    #expect(period.days.map(\.summedTotal) == [3600, 5400])
    #expect(period.summedTotal == 9000)
    let ps = try #require(period.lanes.first { $0.device == .playstation })
    #expect(ps.total == 9000)
    #expect(ps.blocks.isEmpty)
}
