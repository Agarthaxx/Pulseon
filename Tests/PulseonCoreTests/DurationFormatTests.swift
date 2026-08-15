import Foundation
import Testing

@testable import PulseonCore

@Test("La forme resserrée tient dans la barre de menu")
func compactForm() {
    #expect(DurationFormat.compact(0) == "0 min")
    #expect(DurationFormat.compact(59) == "0 min")
    #expect(DurationFormat.compact(60) == "1 min")
    #expect(DurationFormat.compact(3599) == "59 min")
    #expect(DurationFormat.compact(3600) == "1h00")
    #expect(DurationFormat.compact(3660) == "1h01")
    #expect(DurationFormat.compact(12 * 3600 + 34 * 60) == "12h34")
}

@Test("La forme longue s'affiche dans le menu")
func longForm() {
    #expect(DurationFormat.long(0) == "0 min")
    #expect(DurationFormat.long(60) == "1 min")
    #expect(DurationFormat.long(3600) == "1 h 00")
    #expect(DurationFormat.long(3660) == "1 h 01")
    #expect(DurationFormat.long(12 * 3600 + 34 * 60) == "12 h 34")
}

@Test("Les minutes sont tronquées, jamais arrondies")
func minutesAreTruncated() {
    // 59 min 40 s ne doit pas s'afficher « 1 h » : ce serait annoncer du temps
    // qui n'a pas eu lieu.
    #expect(DurationFormat.compact(59 * 60 + 40) == "59 min")
    #expect(DurationFormat.compact(3600 + 59 * 60 + 59) == "1h59")
}

@Test("Une durée aberrante ne produit pas d'affichage aberrant")
func absurdInputsStayReadable() {
    #expect(DurationFormat.compact(-1) == "0 min")
    #expect(DurationFormat.compact(-7200) == "0 min")
    #expect(DurationFormat.compact(.infinity) == "0 min")
    #expect(DurationFormat.compact(.nan) == "0 min")
    // Une journée entière devant l'écran reste lisible.
    #expect(DurationFormat.compact(24 * 3600) == "24h00")
}
