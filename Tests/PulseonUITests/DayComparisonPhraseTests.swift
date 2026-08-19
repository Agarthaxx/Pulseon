import Foundation
import PulseonCore
import Testing

@testable import PulseonUI

/// Les phrases de la comparaison. Elles décrivent un écart, elles ne le
/// qualifient jamais — c'est la règle qui empêche Pulseon de devenir un juge.
@Suite struct DayComparisonPhraseTests {
    private func comparison(
        subject: TimeInterval,
        average: TimeInterval,
        days: Int = 7,
        isPartial: Bool = false
    ) -> DayComparison {
        DayComparison(
            subject: subject, average: average, referenceDays: days, isPartial: isPartial
        )
    }

    @Test("Au-dessus de la moyenne, l'écart se dit sans le qualifier")
    func aboveAverage() {
        let phrase = DayComparisonPhrase.headline(
            comparison(subject: 9 * 3600, average: 7 * 3600 + 40 * 60)
        )
        #expect(phrase == "1h20 de plus que d'habitude")
    }

    @Test("En dessous de la moyenne, la phrase change de sens et pas de ton")
    func belowAverage() {
        let phrase = DayComparisonPhrase.headline(
            comparison(subject: 2 * 3600, average: 2 * 3600 + 45 * 60)
        )
        #expect(phrase == "45 min de moins que d'habitude")
    }

    /// Cinq minutes d'écart sur une journée ne distinguent rien : les annoncer
    /// serait du bruit présenté comme une information.
    @Test("Un écart négligeable ne s'annonce pas comme un écart")
    func tinyGapIsTypical() {
        let phrase = DayComparisonPhrase.headline(
            comparison(subject: 5 * 3600 + 3 * 60, average: 5 * 3600)
        )
        #expect(phrase == "comme d'habitude")
    }

    /// Sans cette mention, une journée en cours confrontée à des journées
    /// entières se lirait « en dessous de la normale » à 11 h du matin — un
    /// constat mécanique, qui n'apprend rien.
    @Test("Une journée en cours dit à quelle heure elle est comparée")
    func partialSaysSo() {
        let above = DayComparisonPhrase.headline(
            comparison(subject: 4 * 3600, average: 3 * 3600, isPartial: true)
        )
        let typical = DayComparisonPhrase.headline(
            comparison(subject: 3 * 3600, average: 3 * 3600, isPartial: true)
        )
        #expect(above == "1h00 de plus que d'habitude à cette heure-ci")
        #expect(typical == "comme d'habitude à cette heure-ci")
    }

    /// Une moyenne sur trois journées et une moyenne sur trente ne se valent
    /// pas : celui qui lit doit pouvoir en juger lui-même.
    @Test("Le détail dit sur combien de journées la moyenne repose")
    func detailCarriesTheReferenceCount() {
        #expect(
            DayComparisonPhrase.detail(comparison(subject: 0, average: 4 * 3600 + 30 * 60))
                == "moyenne de 4h30 sur 7 jours mesurés"
        )
        // Le builder n'en rend jamais moins de trois, mais le type, lui,
        // l'accepte : un accord faux se remarquerait le jour où ce seuil
        // bougerait.
        #expect(
            DayComparisonPhrase.detail(comparison(subject: 0, average: 3600, days: 1))
                == "moyenne de 1h00 sur 1 jour mesuré"
        )
    }
}
