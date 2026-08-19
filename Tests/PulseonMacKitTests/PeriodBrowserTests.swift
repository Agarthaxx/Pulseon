import Foundation
import PulseonCore
import PulseonUI
import SwiftData
import Testing

@testable import PulseonMacKit

/// Voir `TestBase` dans CounterStoreTests : le conteneur doit rester vivant
/// aussi longtemps que le contexte, sinon le processus de test meurt sur un
/// signal sans message d'erreur.
@MainActor
private final class WeekBase {
    let container: ModelContainer
    let store: SessionStore

    init() throws {
        container = try ModelContainer(
            for: StoredSession.self, StoredCounterSample.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = SessionStore(context: container.mainContext)
    }

    /// Ajoute une session un jour donné de la semaine affichée.
    ///
    /// - Parameter dayOffset: 0 pour le premier jour de la semaine (ici lundi).
    func add(_ name: String, dayOffset: Int, fromHour: Int, toHour: Int) throws {
        let day = try #require(
            paris.date(byAdding: .day, value: dayOffset, to: weekStart)
        )
        // Par le calendrier et non par un multiple de 3 600, pour la même
        // raison que le code de production : un jour de changement d'heure ne
        // se découpe pas à la calculette.
        let start = try #require(paris.date(byAdding: .hour, value: fromHour, to: day))
        let end = try #require(paris.date(byAdding: .hour, value: toHour, to: day))
        container.mainContext.insert(
            StoredSession(device: .mac, entity: name, start: start, end: end)
        )
    }
}

/// Un **mercredi** à 15 h, en heure fixe : aucun test ne doit dépendre de
/// l'heure qu'il est réellement.
private let now = Date(timeIntervalSince1970: 1_770_213_600)

/// Le premier jour de la semaine est fixé au lundi, et pas laissé au réglage
/// par défaut : `Calendar(identifier: .gregorian)` commence ses semaines le
/// dimanche tant qu'aucune locale ne le corrige, ce qui décalerait chaque
/// index de journée de ces tests sans rien dire.
private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    calendar.firstWeekday = 2
    return calendar
}()

/// Le lundi 2 février 2026 à minuit, début de la semaine contenant `now`.
private let weekStart = paris.dateInterval(of: .weekOfYear, for: now)!.start

/// Mercredi est le troisième jour de cette semaine, donc l'index 2.
private let todayOffset = 2

@MainActor
private func browser(_ base: WeekBase) -> PeriodBrowser {
    PeriodBrowser(store: base.store, calendar: paris, clock: { now })
}

@MainActor
private func loaded(_ browser: PeriodBrowser) throws -> PeriodPresentation {
    guard case .loaded(let period) = browser.load else {
        Issue.record("la semaine n'a pas pu être lue")
        throw CancellationError()
    }
    return period
}

@Suite("La semaine affichée")
@MainActor
struct PeriodBrowserTests {
    @Test("porte ses sept journées, y compris les vides")
    func sevenDays() throws {
        let base = try WeekBase()
        try base.add("Xcode", dayOffset: 0, fromHour: 10, toHour: 12)

        let period = try loaded(browser(base))

        #expect(period.days.count == 7)
        #expect(period.days.first?.start == weekStart)
        // Le mardi n'a rien : il doit rester dans la liste, pas disparaître
        // entre le lundi et le mercredi.
        #expect(period.days[1].total == 0)
    }

    @Test("commence le lundi de la semaine en cours")
    func startsOnMonday() throws {
        let base = try WeekBase()
        let browser = browser(base)

        #expect(browser.weekStart == weekStart)
        #expect(paris.component(.weekday, from: browser.weekStart) == 2)
    }

    @Test("distingue aujourd'hui, le passé et ce qui n'a pas eu lieu")
    func threeStates() throws {
        let base = try WeekBase()
        let period = try loaded(browser(base))

        #expect(period.days[todayOffset].isToday)
        #expect(!period.days[todayOffset].isFuture)
        // Lundi et mardi ont eu lieu.
        #expect(!period.days[0].isFuture)
        // Jeudi à dimanche n'existent pas encore : ni un zéro, ni un trou de
        // mesure.
        #expect(period.days[todayOffset + 1].isFuture)
        #expect(period.days[6].isFuture)
    }

    @Test("additionne les journées de la semaine")
    func total() throws {
        let base = try WeekBase()
        try base.add("Xcode", dayOffset: 0, fromHour: 10, toHour: 12)
        try base.add("Ghostty", dayOffset: todayOffset, fromHour: 9, toHour: 14)

        let period = try loaded(browser(base))

        #expect(period.digest.coveredTotal == 7 * 3600)
    }

    @Test("exclut de la moyenne la journée en cours et les journées non mesurées")
    func average() throws {
        let base = try WeekBase()
        // Lundi : deux heures, journée terminée et mesurée.
        try base.add("Xcode", dayOffset: 0, fromHour: 10, toHour: 12)
        // Mardi : rien du tout, donc « collecteur éteint », pas « zéro ».
        // Mercredi (aujourd'hui) : cinq heures, mais la journée n'est pas finie.
        try base.add("Ghostty", dayOffset: todayOffset, fromHour: 9, toHour: 14)

        let period = try loaded(browser(base))
        let average = try #require(period.dailyAverage)

        #expect(period.averagedDays.count == 1)
        #expect(average == 2 * 3600)
    }

    @Test("ne prétend pas à une moyenne quand rien n'est mesuré et terminé")
    func noAverage() throws {
        let base = try WeekBase()
        // Seule la journée en cours porte quelque chose : il n'y a rien à
        // moyenner, et zéro serait une affirmation fausse.
        try base.add("Xcode", dayOffset: todayOffset, fromHour: 9, toHour: 14)

        let period = try loaded(browser(base))

        #expect(period.dailyAverage == nil)
        #expect(period.averagedDays.isEmpty)
    }

    @Test("ne navigue pas dans le futur")
    func noFutureWeek() throws {
        let base = try WeekBase()
        let browser = browser(base)

        #expect(!browser.canGoForward)
        browser.goToNextWeek()
        #expect(browser.weekStart == weekStart)
    }

    @Test("recule d'une semaine entière, et sait revenir")
    func navigation() throws {
        let base = try WeekBase()
        let browser = browser(base)

        browser.goToPreviousWeek()
        let previous = try #require(
            paris.date(byAdding: .weekOfYear, value: -1, to: weekStart)
        )
        #expect(browser.weekStart == previous)
        #expect(browser.canGoForward)

        // Une semaine passée est entièrement jouée : plus rien n'y est « en
        // cours », donc plus rien n'en est exclu.
        let period = try loaded(browser)
        #expect(!period.isCurrent)
        #expect(period.days.allSatisfy { !$0.isFuture })

        browser.goToCurrentWeek()
        #expect(browser.weekStart == weekStart)
    }

    @Test("une semaine sans la moindre mesure se dit vide, pas à zéro")
    func emptyWeek() throws {
        let base = try WeekBase()
        let period = try loaded(browser(base))

        #expect(period.isEmpty)
        #expect(period.days.allSatisfy { !$0.isMeasured })
        #expect(period.dailyAverage == nil)
    }
}
