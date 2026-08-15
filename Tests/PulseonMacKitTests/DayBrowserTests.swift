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
private final class BrowserBase {
    let container: ModelContainer
    let store: SessionStore

    init() throws {
        container = try ModelContainer(
            for: StoredSession.self, StoredCounterSample.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = SessionStore(context: container.mainContext)
    }

    func add(_ name: String, from: Date, to: Date) {
        container.mainContext.insert(
            StoredSession(device: .mac, entity: name, start: from, end: to)
        )
    }
}

/// Un mardi à 14 h, en heure fixe : aucun test ne doit dépendre de l'heure
/// qu'il est réellement.
private let now = Date(timeIntervalSince1970: 1_770_213_600)

@MainActor
private func browser(_ base: BrowserBase) -> DayBrowser {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return DayBrowser(store: base.store, calendar: calendar, clock: { now })
}

@MainActor
private func loaded(_ browser: DayBrowser) throws -> DayPresentation {
    guard case .loaded(let day) = browser.load else {
        Issue.record("la journée n'a pas pu être lue")
        throw CancellationError()
    }
    return day
}

@Test("La journée du jour s'ouvre sur aujourd'hui")
@MainActor
func opensOnToday() throws {
    let base = try BrowserBase()
    base.add("Ghostty", from: now.addingTimeInterval(-3600), to: now)
    let day = try loaded(browser(base))

    #expect(day.digest.coveredTotal == 3600)
    // La journée est en cours, donc la tête de lecture existe.
    #expect(day.nowOffset != nil)
    #expect(day.dayLength == 86_400)
}

@Test("On ne navigue pas dans le futur")
@MainActor
func neverGoesForwardPastToday() throws {
    let base = try BrowserBase()
    let browser = browser(base)

    // Depuis aujourd'hui, il n'y a rien après : demain n'a pas eu lieu.
    #expect(browser.canGoForward == false)
    let today = browser.dayStart
    browser.goToNextDay()
    #expect(browser.dayStart == today)

    browser.goToPreviousDay()
    #expect(browser.canGoForward)
    #expect(browser.dayStart < today)
}

@Test("Une journée passée n'a pas de tête de lecture")
@MainActor
func pastDaysHaveNoPlayhead() throws {
    let base = try BrowserBase()
    let browser = browser(base)
    browser.goToPreviousDay()

    let day = try loaded(browser)
    #expect(day.nowOffset == nil)
    // Rien enregistré ce jour-là, et aucune source branchée : l'écran doit
    // pouvoir le dire au lieu d'afficher un zéro.
    #expect(day.isEmpty)
}

@Test("Revenir à aujourd'hui remet la journée en cours")
@MainActor
func todayIsAlwaysOneClickAway() throws {
    let base = try BrowserBase()
    let browser = browser(base)
    browser.goToPreviousDay()
    browser.goToPreviousDay()
    browser.goToToday()

    #expect(browser.canGoForward == false)
    #expect(try loaded(browser).nowOffset != nil)
}

@Test("Chaque journée ne montre que ce qui lui appartient")
@MainActor
func daysDoNotBleedIntoEachOther() throws {
    let base = try BrowserBase()
    // Deux heures hier, une heure aujourd'hui.
    base.add("Xcode", from: now.addingTimeInterval(-26 * 3600), to: now.addingTimeInterval(-24 * 3600))
    base.add("Ghostty", from: now.addingTimeInterval(-3600), to: now)

    let browser = browser(base)
    #expect(try loaded(browser).digest.coveredTotal == 3600)

    browser.goToPreviousDay()
    #expect(try loaded(browser).digest.coveredTotal == 2 * 3600)
}
