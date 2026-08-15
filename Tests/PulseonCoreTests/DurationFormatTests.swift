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

@Test("La forme vivante montre les secondes, avec son unité")
func liveForm() {
    #expect(DurationFormat.live(0) == "0s")
    #expect(DurationFormat.live(42) == "42s")
    #expect(DurationFormat.live(59) == "59s")
    // Le palier change dès la première minute : pas de « 0m59 ».
    #expect(DurationFormat.live(60) == "1m00")
    #expect(DurationFormat.live(7 * 60 + 12) == "7m12")
    #expect(DurationFormat.live(3599) == "59m59")
    // Et dès la première heure : pas de « 60m00 ».
    #expect(DurationFormat.live(3600) == "1h00:00")
    #expect(DurationFormat.live(3 * 3600 + 7 * 60 + 12) == "3h07:12")
    #expect(DurationFormat.live(12 * 3600 + 34 * 60 + 56) == "12h34:56")
}

@Test("La forme vivante tronque aussi, et encaisse l'absurde")
func liveFormStaysHonest() {
    // 3h07:59,9 n'est pas encore 3h08 : arrondir annoncerait une seconde qui
    // n'a pas eu lieu.
    #expect(DurationFormat.live(3 * 3600 + 7 * 60 + 59.9) == "3h07:59")
    #expect(DurationFormat.live(-1) == "0s")
    #expect(DurationFormat.live(.infinity) == "0s")
    #expect(DurationFormat.live(.nan) == "0s")
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
