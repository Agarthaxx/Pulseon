import Foundation
import PulseonCore
import Testing

@testable import PulseonUI

private let day: TimeInterval = 86_400
private let geometry = TimelineGeometry(width: 1000, dayLength: day)

@Test("Une heure de la journée tombe à sa place sur la piste")
func offsetsMapToPositions() {
    #expect(geometry.x(atOffset: 0) == 0)
    #expect(geometry.x(atOffset: day / 2) == 500)
    #expect(geometry.x(atOffset: day) == 1000)
    #expect(geometry.x(atOffset: 6 * 3600) == 250)
}

@Test("Rien ne déborde du cadre")
func positionsStayInside() {
    // Une session qui a commencé hier, ou un instant au-delà de minuit : la
    // timeline les range aux bornes plutôt que de dessiner hors du panneau.
    #expect(geometry.x(atOffset: -3600) == 0)
    #expect(geometry.x(atOffset: 2 * day) == 1000)

    let late = geometry.rect(offset: day - 1, duration: 1)
    #expect(late.x + late.width <= 1000)
}

@Test("Une minute d'activité reste visible")
func shortBlocksStayVisible() {
    // 60 s sur 24 h font 0,7 point : sans plancher, la minute disparaîtrait,
    // ce qui reviendrait à dire qu'elle n'a pas eu lieu.
    let minute = geometry.rect(offset: 3600, duration: 60)
    #expect(minute.width >= 2)

    let hour = geometry.rect(offset: 0, duration: 3600)
    #expect(abs(hour.width - 1000 / 24) < 0.001)
}

@Test("Les journées de changement d'heure ne font pas 24 h")
func daylightSavingDaysAreNot24Hours() {
    // 23 h en octobre : minuit suivant doit rester le bord droit du panneau,
    // sinon toute la soirée de ce jour-là est décalée.
    let shortDay = TimelineGeometry(width: 1000, dayLength: 23 * 3600)
    #expect(shortDay.x(atOffset: 23 * 3600) == 1000)
    #expect(abs(shortDay.x(atOffset: 3600 * 11.5) - 500) < 0.001)

    let longDay = TimelineGeometry(width: 1000, dayLength: 25 * 3600)
    #expect(longDay.x(atOffset: 24 * 3600) < 1000)
}

@Test("Une largeur absurde ne fait pas dérailler le tracé")
func absurdGeometryStaysSafe() {
    let zero = TimelineGeometry(width: 0, dayLength: day)
    #expect(zero.x(atOffset: 3600) == 0)

    // Une longueur de jour nulle retomberait sur une division par zéro : on
    // revient à 24 h plutôt que de produire des NaN plein l'écran.
    let broken = TimelineGeometry(width: 1000, dayLength: 0)
    #expect(broken.x(atOffset: day / 2) == 500)
}

@Test("La règle s'allège quand la fenêtre rétrécit")
func rulerThinsOutOnNarrowWindows() {
    let wide = TimelineGeometry(width: 900, dayLength: day).hourTicks()
    let narrow = TimelineGeometry(width: 320, dayLength: day).hourTicks()
    #expect(narrow.count < wide.count)
    // Les deux bornes de la journée restent graduées dans tous les cas.
    #expect(wide.first == 0 && wide.last == 24)
    #expect(narrow.first == 0 && narrow.last == 24)
}

@Test("La tête de lecture n'existe que sur une journée en cours")
func playheadOnlyOnToday() {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let digest = DayDigest(date: DateComponents(), lanes: [], summedTotal: 0, coveredTotal: 0)

    let past = DayPresentation(digest: digest, dayStart: start, dayLength: day, now: nil)
    #expect(past.nowOffset == nil)

    let today = DayPresentation(
        digest: digest, dayStart: start, dayLength: day,
        now: start.addingTimeInterval(3600)
    )
    #expect(today.nowOffset == 3600)

    // Un « maintenant » hors de la journée affichée ne plante pas de tête de
    // lecture au bord : il n'y en a simplement pas.
    let mismatched = DayPresentation(
        digest: digest, dayStart: start, dayLength: day,
        now: start.addingTimeInterval(3 * day)
    )
    #expect(mismatched.nowOffset == nil)
}
