import Foundation
import PulseonCore
import Testing

@testable import PulseonUI

/// Ce que l'en-tête écrit au-dessus d'un écran.
///
/// **Né d'un défaut d'affichage, pas d'un calcul faux** : le titre portait un
/// mot générique (« Journée », « Semaine ») et le retour à aujourd'hui
/// s'écrivait en or à droite, sans cadre. Une journée passée montrait donc
/// « Aujourd'hui » plus visiblement que sa propre date. Arthur, le 2026-08-25 :
/// « c'est marqué aujourd'hui partout ».
///
/// Aucun test ne pouvait le voir — c'est de la composition — mais ce qui le
/// remplace, lui, se teste : une date porte sa capitale, et une journée sait à
/// quelle distance d'aujourd'hui elle se trouve.
@Suite("Ce que l'en-tête annonce") struct HeaderDatesTests {
    /// Fixe, pour que « Hier » ne dépende pas de l'heure qu'il est chez celui
    /// qui lance les tests.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        // Explicite : un `Calendar(identifier:)` nu commence sa semaine le
        // dimanche, et le premier jour de la semaine décide de quelle semaine
        // contient quelle date.
        calendar.firstWeekday = 2
        return calendar
    }

    private func day(_ components: DateComponents) -> Date {
        calendar.date(from: components)!
    }

    private func presentation(dayStart: Date, now: Date? = nil, today: Date? = nil)
        -> DayPresentation
    {
        DayPresentation(
            digest: DayDigestBuilder(calendar: calendar).build(
                day: dayStart, sessions: [], samples: [], now: now ?? dayStart
            ),
            dayStart: dayStart,
            dayLength: 24 * 3600,
            now: now,
            today: today
        )
    }

    @Test("Le titre est la date, et elle commence par une capitale")
    func headlineCarriesTheDate() {
        let start = day(DateComponents(year: 2026, month: 8, day: 24))
        let headline = presentation(dayStart: start).headline

        #expect(headline == presentation(dayStart: start).title.prefix(1).uppercased()
            + presentation(dayStart: start).title.dropFirst())
        #expect(headline.first?.isUppercase == true)
        // La date elle-même, et pas un mot à sa place.
        #expect(headline.contains("24"))
    }

    @Test("La journée en cours se reconnaît à sa tête de lecture, sans repère")
    func todayNeedsNoReference() {
        let start = day(DateComponents(year: 2026, month: 8, day: 25))
        let now = start.addingTimeInterval(11 * 3600)

        #expect(presentation(dayStart: start, now: now).situation(calendar: calendar)
            == "Aujourd'hui")
    }

    @Test("La veille se dit « Hier »")
    func yesterdayIsNamed() {
        let yesterday = day(DateComponents(year: 2026, month: 8, day: 24))
        let today = day(DateComponents(year: 2026, month: 8, day: 25))

        #expect(presentation(dayStart: yesterday, today: today).situation(calendar: calendar)
            == "Hier")
    }

    @Test("Au-delà, on compte les jours")
    func olderDaysAreCounted() {
        let old = day(DateComponents(year: 2026, month: 8, day: 21))
        let today = day(DateComponents(year: 2026, month: 8, day: 25))

        #expect(presentation(dayStart: old, today: today).situation(calendar: calendar)
            == "il y a 4 jours")
    }

    /// **Le calendrier, jamais une division par 86 400.** La nuit du 25 au
    /// 26 octobre 2026 fait 25 heures : « hier » n'y est pas « il y a
    /// 86 400 secondes », et un compte en secondes rendrait « il y a 1 jour »
    /// une fois sur deux selon l'heure.
    @Test("Un changement d'heure ne décale pas « Hier »")
    func daylightSavingKeepsYesterday() {
        let yesterday = day(DateComponents(year: 2026, month: 10, day: 25))
        let today = day(DateComponents(year: 2026, month: 10, day: 26))

        #expect(presentation(dayStart: yesterday, today: today).situation(calendar: calendar)
            == "Hier")
    }

    @Test("Sans repère, on ne situe rien plutôt que d'inventer")
    func noReferenceSaysNothing() {
        let start = day(DateComponents(year: 2026, month: 8, day: 24))
        let presented = presentation(dayStart: start)

        #expect(presented.situation(calendar: calendar) == nil)
        // La date, elle, reste vraie et reste affichée.
        #expect(presented.headline.contains("24"))
    }

    // MARK: La semaine

    private func week(containing date: Date, today: Date?, includesToday: Bool)
        -> PeriodPresentation
    {
        // La semaine est celle du calendrier, jamais « les sept derniers
        // jours » : c'est ce que fait `PeriodBrowser`, et le test doit
        // découper comme lui.
        let start = calendar.dateInterval(of: .weekOfYear, for: date)!.start
        let days = (0..<7).compactMap { offset -> PeriodPresentation.Day? in
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: start)
            else { return nil }
            return PeriodPresentation.Day(
                start: dayStart,
                digest: DayDigestBuilder(calendar: calendar).build(
                    day: dayStart, sessions: [], samples: [], now: dayStart
                ),
                isToday: includesToday
                    && today.map { calendar.isDate(dayStart, inSameDayAs: $0) } == true,
                isFuture: false
            )
        }
        return PeriodPresentation(
            digest: PeriodDigest(
                days: days.map(\.digest), lanes: [], summedTotal: 0, coveredTotal: 0,
                daysWithActivity: 0
            ),
            days: days,
            today: today
        )
    }

    @Test("La semaine en cours se dit « Cette semaine »")
    func currentWeek() {
        let today = day(DateComponents(year: 2026, month: 8, day: 25))

        #expect(
            week(containing: today, today: today, includesToday: true)
                .situation(calendar: calendar) == "Cette semaine")
    }

    @Test("La précédente porte son nom, les plus anciennes se comptent")
    func pastWeeks() {
        let today = day(DateComponents(year: 2026, month: 8, day: 25))
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: today)!
        let older = calendar.date(byAdding: .day, value: -21, to: today)!

        #expect(
            week(containing: lastWeek, today: today, includesToday: false)
                .situation(calendar: calendar) == "La semaine dernière")
        #expect(
            week(containing: older, today: today, includesToday: false)
                .situation(calendar: calendar) == "il y a 3 semaines")
    }
}
