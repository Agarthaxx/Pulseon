import Foundation
import Testing

@testable import PulseonCore

@Test("Les formes que l'API PlayStation produit réellement")
func readsRealPSNDurations() throws {
    #expect(PlayDuration.seconds(from: "PT1H") == 3600)
    #expect(PlayDuration.seconds(from: "PT30M") == 1800)
    #expect(PlayDuration.seconds(from: "PT45S") == 45)
    #expect(PlayDuration.seconds(from: "PT12H34M56S") == 45296)
    #expect(PlayDuration.seconds(from: "PT0S") == 0)
    // Des centaines d'heures sur un jeu au long cours : rien ne déborde.
    #expect(PlayDuration.seconds(from: "PT999H") == 3_596_400)
    #expect(PlayDuration.seconds(from: "P2DT3H") == 183_600)
}

@Test("Une durée illisible est refusée, jamais devinée")
func refusesRatherThanGuesses() throws {
    // Mois et années n'ont pas de durée fixe : les convertir serait inventer.
    #expect(PlayDuration.seconds(from: "P1M") == nil)
    #expect(PlayDuration.seconds(from: "P1Y") == nil)

    #expect(PlayDuration.seconds(from: "") == nil)
    #expect(PlayDuration.seconds(from: "P") == nil)
    #expect(PlayDuration.seconds(from: "PT") == nil)
    #expect(PlayDuration.seconds(from: "12H") == nil, "sans le P initial")
    #expect(PlayDuration.seconds(from: "PT1X") == nil, "unité inconnue")
    #expect(PlayDuration.seconds(from: "PTH") == nil, "unité sans nombre")
    #expect(PlayDuration.seconds(from: "PT1H2") == nil, "nombre sans unité")
    #expect(PlayDuration.seconds(from: "PT1D") == nil, "jours après le T")
    #expect(PlayDuration.seconds(from: "PT1HT2M") == nil, "deux sections T")
}

@Test("Le M change de sens de part et d'autre du T")
func minutesAreNotMonths() throws {
    // Le seul vrai piège du format : même lettre, deux sens.
    #expect(PlayDuration.seconds(from: "PT1M") == 60)
    #expect(PlayDuration.seconds(from: "P1M") == nil)
}
