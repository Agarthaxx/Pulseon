import Foundation
import Testing

@testable import PulseonCore

/// Le temps passé sur plusieurs écrans à la fois.
///
/// Né d'une question d'Arthur devant l'app le 2026-08-22 : « le rond indique
/// 1h29 mais j'ai 1h29 de télé et de pc ? donc ça devrait me montrer le double
/// non ? ». Le rond avait raison ; c'est l'écran qui ne disait pas pourquoi.
@Suite("Les écrans simultanés")
struct SimultaneityTests {
    private let hour: TimeInterval = 3600

    private func block(_ start: Double, _ duration: Double) -> TraceBlock {
        TraceBlock(entity: nil, startOffset: start * 3600, duration: duration * 3600)
    }

    private func digest(
        mac: [TraceBlock] = [], tv: [TraceBlock] = []
    ) -> DayDigest {
        let lanes = [
            Lane(
                device: .mac, total: 0, blocks: mac, topEntities: [], isConnected: !mac.isEmpty
            ),
            Lane(
                device: .tv, total: 0, blocks: tv, topEntities: [], isConnected: !tv.isEmpty
            ),
        ]
        return DayDigest(
            date: DateComponents(year: 2026, month: 8, day: 22), lanes: lanes,
            summedTotal: 0, coveredTotal: 0
        )
    }

    // MARK: Le cas d'Arthur

    /// La soirée du 2026-08-22, aux chiffres près : la télé allumée de 22h20 à
    /// 23h50, le Mac de 22h20 à 23h36. Le rond disait 1h30 et la légende
    /// « Mac 1h16 · TV 1h29 ».
    @Test("Regarder la télé en étant sur le Mac se dit, et se chiffre")
    func arthursEvening() {
        let simultaneity = digest(
            mac: [block(22 + 20.0 / 60, 1 + 16.0 / 60)],
            tv: [block(22 + 20.0 / 60, 1 + 29.0 / 60)]
        ).simultaneity
        // Les deux ont démarré ensemble, donc la simultanéité vaut le plus court.
        #expect(abs(simultaneity.duration - (1 + 16.0 / 60) * hour) < 1)
        #expect(simultaneity.peak == 2)
    }

    @Test("Sans chevauchement, il n'y a rien à dire")
    func noOverlapMeansNothing() {
        let simultaneity = digest(mac: [block(9, 2)], tv: [block(20, 2)]).simultaneity
        #expect(simultaneity.duration == 0)
        #expect(simultaneity.peak == 1)
    }

    @Test("Un seul appareil n'est jamais simultané avec lui-même")
    func oneDeviceIsNeverSimultaneous() {
        let simultaneity = digest(mac: [block(9, 2), block(14, 2)]).simultaneity
        #expect(simultaneity.duration == 0)
        #expect(simultaneity.peak == 1)
    }

    /// **La leçon de la journée de 51 heures, appliquée ici.** Deux sessions du
    /// même appareil qui se chevauchent viennent d'un défaut d'écriture, pas
    /// d'une simultanéité : un Mac ne peut pas être allumé deux fois à la fois.
    @Test("Deux sessions du même appareil qui se chevauchent ne sont pas une simultanéité")
    func overlappingSessionsOfOneDeviceAreNotSimultaneity() {
        let simultaneity = digest(mac: [block(9, 2), block(10, 2)]).simultaneity
        #expect(simultaneity.duration == 0)
        #expect(simultaneity.peak == 1)
    }

    // MARK: Ce qu'une soustraction dirait de faux

    /// **La raison pour laquelle ce n'est pas `summedTotal - coveredTotal`.**
    ///
    /// À trois écrans allumés une heure ensemble, la soustraction rend deux
    /// heures alors qu'on n'a vécu qu'une heure de simultanéité. Le balayage,
    /// lui, compte l'instant une seule fois et retient le pic à part.
    ///
    /// Testé sur `IntervalMath` directement et non sur un `DayDigest` : le
    /// projet ne mesure que deux appareils, mais l'algorithme doit tenir le
    /// troisième le jour où il arrive — c'est justement ce que la soustraction
    /// ne saurait pas faire.
    @Test("Trois écrans une heure ensemble font une heure, pas deux")
    func threeScreensForAnHourIsOneHour() {
        let together = [block(20, 1)]
        let (duration, peak) = IntervalMath.simultaneity(of: [together, together, together])

        #expect(duration == hour)
        #expect(peak == 3)
        // Ce que la soustraction aurait dit : 3 h additionnées − 1 h couverte.
        #expect(duration != 2 * hour)
    }

    // MARK: Les bords

    /// Deux sessions bout à bout se suivent, elles ne se chevauchent pas. Sans
    /// tri des fermetures avant les ouvertures, l'instant de contact compterait.
    @Test("Deux sessions qui se touchent ne se chevauchent pas")
    func touchingSessionsDoNotOverlap() {
        let simultaneity = digest(mac: [block(9, 1)], tv: [block(10, 1)]).simultaneity
        #expect(simultaneity.duration == 0)
    }

    @Test("Une journée sans le moindre bloc ne dit rien")
    func emptyDaySaysNothing() {
        let simultaneity = digest().simultaneity
        #expect(simultaneity.duration == 0)
        #expect(simultaneity.peak == 0)
    }

    /// Le chevauchement est borné par la plus courte des deux présences : il ne
    /// peut pas dépasser le temps de l'appareil le moins allumé.
    @Test("Le chevauchement ne dépasse jamais la plus courte des présences")
    func overlapNeverExceedsTheShortest() {
        let simultaneity = digest(
            mac: [block(8, 8)], tv: [block(20, 0.5)]
        ).simultaneity
        #expect(simultaneity.duration == 0)

        let nested = digest(mac: [block(8, 8)], tv: [block(10, 0.5)]).simultaneity
        #expect(nested.duration == 0.5 * hour)
    }
}
