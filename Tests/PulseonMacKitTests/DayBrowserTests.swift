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
            for: StoredSession.self,
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

/// Un mercredi à 15 h (heure de Paris), en heure fixe : aucun test ne doit dépendre de l'heure
/// qu'il est réellement.
private let now = Date(timeIntervalSince1970: 1_770_213_600)

private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

@MainActor
private func browser(_ base: BrowserBase) -> DayBrowser {
    DayBrowser(store: base.store, calendar: paris, clock: { now })
}

extension BrowserBase {
    /// Ajoute une session sur une journée passée, à une heure donnée.
    ///
    /// - Parameters:
    ///   - daysAgo: 1 pour hier. Passe par le calendrier et non par un multiple
    ///     de 86 400, pour la même raison que le code de production.
    @MainActor
    func add(_ name: String, daysAgo: Int, fromHour: Int, toHour: Int) throws {
        let day = try #require(
            paris.date(byAdding: .day, value: -daysAgo, to: paris.startOfDay(for: now))
        )
        add(
            name,
            from: try #require(paris.date(byAdding: .hour, value: fromHour, to: day)),
            to: try #require(paris.date(byAdding: .hour, value: toHour, to: day))
        )
    }
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

// MARK: - La comparaison

@Test("Une journée se compare aux précédentes")
@MainActor
func comparesAgainstPreviousDays() throws {
    let base = try BrowserBase()
    base.add("Ghostty", from: now.addingTimeInterval(-2 * 3600), to: now)
    for daysAgo in 1...4 {
        try base.add("Xcode", daysAgo: daysAgo, fromHour: 9, toHour: 13)
    }

    let comparison = try #require(browser(base).comparison)

    #expect(comparison.referenceDays == 4)
    #expect(comparison.average == 4 * 3600)
    #expect(comparison.subject == 2 * 3600)
    #expect(comparison.delta == -2 * 3600)
}

/// **Le test qui justifie tout le mécanisme.** Comparer une matinée à des
/// journées entières donnerait « toujours en dessous de ta moyenne » à 11 h du
/// matin, ce qui ne dit rien. Les journées de référence sont donc coupées à la
/// même heure du jour.
@Test("Une journée en cours se compare à la même heure des journées passées")
@MainActor
func partialComparisonStopsAtTheSameHour() throws {
    let base = try BrowserBase()
    // Aujourd'hui, il est 14 h et deux heures ont été mesurées.
    base.add("Ghostty", from: now.addingTimeInterval(-2 * 3600), to: now)
    for daysAgo in 1...3 {
        // Trois heures avant 14 h, et trois heures après : seules les premières
        // doivent compter.
        try base.add("Xcode", daysAgo: daysAgo, fromHour: 9, toHour: 12)
        try base.add("IINA", daysAgo: daysAgo, fromHour: 20, toHour: 23)
    }

    let comparison = try #require(browser(base).comparison)

    #expect(comparison.isPartial)
    #expect(comparison.average == 3 * 3600)
    #expect(comparison.referenceDays == 3)
}

@Test("Une journée passée se compare sur des journées entières")
@MainActor
func pastDayComparesWholeDays() throws {
    let base = try BrowserBase()
    for daysAgo in 1...5 {
        try base.add("Xcode", daysAgo: daysAgo, fromHour: 9, toHour: 12)
        try base.add("IINA", daysAgo: daysAgo, fromHour: 20, toHour: 23)
    }

    let browser = browser(base)
    // On regarde hier : les journées de référence sont entières, donc six heures.
    browser.goToPreviousDay()
    let comparison = try #require(browser.comparison)

    #expect(!comparison.isPartial)
    #expect(comparison.average == 6 * 3600)
    #expect(comparison.subject == 6 * 3600)
    #expect(comparison.isTypical)
}

@Test("Sans historique suffisant, aucune comparaison n'est annoncée")
@MainActor
func noComparisonWithoutHistory() throws {
    let base = try BrowserBase()
    base.add("Ghostty", from: now.addingTimeInterval(-3600), to: now)
    try base.add("Xcode", daysAgo: 1, fromHour: 9, toHour: 12)

    // Une seule journée de référence mesurée : se taire est la bonne réponse.
    #expect(browser(base).comparison == nil)
}

/// Remonter avant le début de l'historique ne doit pas inventer une moyenne :
/// les journées de référence n'ont aucune source mesurée, donc il n'y a rien à
/// dire. C'est le même chemin que le premier jour d'utilisation de l'app.
@Test("Avant le début de l'historique, aucune comparaison")
@MainActor
func noComparisonBeforeHistoryBegins() throws {
    let base = try BrowserBase()
    for daysAgo in 1...4 {
        try base.add("Xcode", daysAgo: daysAgo, fromHour: 9, toHour: 13)
    }

    let browser = browser(base)
    #expect(browser.comparison != nil)

    // Une semaine plus tôt : plus rien devant, donc plus de moyenne possible.
    for _ in 1...12 { browser.goToPreviousDay() }

    #expect(browser.comparison == nil)
    #expect(try loaded(browser).isEmpty)
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
