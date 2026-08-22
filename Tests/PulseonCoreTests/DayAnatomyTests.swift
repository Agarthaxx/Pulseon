import Foundation
import Testing

@testable import PulseonCore

/// La forme d'une journée : quand elle commence, quand elle s'arrête, si elle
/// tient d'une traite ou en confettis.
@Suite("L'anatomie de la journée")
struct DayAnatomyTests {
    private let hour: TimeInterval = 3600

    /// Un bloc, en heures décimales depuis minuit.
    private func block(_ start: Double, _ duration: Double, _ entity: String? = "Xcode")
        -> TraceBlock
    {
        TraceBlock(entity: entity, startOffset: start * 3600, duration: duration * 3600)
    }

    private func digest(mac: [TraceBlock] = [], tv: [TraceBlock] = [], playstation: Double = 0)
        -> DayDigest
    {
        var lanes: [Lane] = [
            Lane(
                device: .mac, total: mac.reduce(0) { $0 + $1.duration }, blocks: mac,
                topEntities: [], isConnected: !mac.isEmpty
            ),
            Lane(
                device: .tv, total: tv.reduce(0) { $0 + $1.duration }, blocks: tv,
                topEntities: [], isConnected: !tv.isEmpty
            ),
        ]
        if playstation > 0 {
            lanes.append(
                Lane(
                    device: .playstation, total: playstation * 3600, blocks: [],
                    topEntities: [EntityTotal(entity: "Elden Ring", total: playstation * 3600)],
                    isConnected: true
                )
            )
        }
        return DayDigest(
            date: DateComponents(year: 2026, month: 8, day: 22), lanes: lanes,
            summedTotal: 0, coveredTotal: 0
        )
    }

    private func build(_ digest: DayDigest, minimumBreak: TimeInterval = 5 * 60) -> DayAnatomy? {
        DayAnatomyBuilder(minimumBreak: minimumBreak).build(from: digest)
    }

    // MARK: Les bornes

    @Test("Le premier et le dernier écran sont ceux qu'on a observés")
    func firstAndLastScreen() throws {
        let anatomy = try #require(
            build(digest(mac: [block(9, 1), block(14, 2), block(21, 0.5)]))
        )
        #expect(anatomy.firstScreen == 9 * hour)
        #expect(anatomy.lastScreen == 21.5 * hour)
    }

    /// L'amplitude n'est pas du temps d'écran, et c'est tout l'intérêt de la
    /// distinguer : ici 3 h 30 devant l'écran, étalées sur 12 h 30.
    @Test("L'amplitude n'est pas le temps d'écran")
    func spanIsNotScreenTime() throws {
        let anatomy = try #require(
            build(digest(mac: [block(9, 1), block(14, 2), block(21, 0.5)]))
        )
        #expect(anatomy.span == 12.5 * hour)
    }

    // MARK: Les traites et les coupures

    @Test("La plus longue traite est la plus longue suite sans coupure")
    func longestStretch() throws {
        let anatomy = try #require(
            build(digest(mac: [block(9, 1), block(14, 2.5), block(21, 0.5)]))
        )
        #expect(anatomy.longestStretch.start == 14 * hour)
        #expect(anatomy.longestStretch.duration == 2.5 * hour)
    }

    /// **Le seuil, sans lequel le chiffre ne dirait rien de la journée.** Le
    /// collecteur tolère déjà deux minutes d'inactivité avant de fragmenter une
    /// session ; annoncer une coupure pour chaque respiration décrirait le pas
    /// d'échantillonnage, pas la matinée.
    @Test("Un trou plus court que le seuil n'est pas une coupure")
    func shortGapIsNotABreak() throws {
        // Deux minutes entre les deux blocs.
        let anatomy = try #require(
            build(digest(mac: [block(9, 1), block(10 + 2.0 / 60, 1)]))
        )
        #expect(anatomy.breaks.isEmpty)
        // Et les deux blocs ne font qu'une seule traite : compter deux traites
        // contredirait le « zéro coupure » affiché juste à côté.
        #expect(anatomy.longestStretch.duration == (2 + 2.0 / 60) * hour)
    }

    @Test("Une vraie coupure est retenue, avec son heure et sa durée")
    func realBreakIsKept() throws {
        let anatomy = try #require(build(digest(mac: [block(9, 1), block(11, 1)])))
        #expect(anatomy.breaks.count == 1)
        let pause = try #require(anatomy.breaks.first)
        #expect(pause.start == 10 * hour)
        #expect(pause.duration == 1 * hour)
        #expect(anatomy.longestBreak == pause)
    }

    /// Une nuit de sommeil n'est pas une pause dans la journée : il n'y a de
    /// coupure qu'**entre** deux traites.
    @Test("Ni le début ni la fin de journée ne comptent comme des coupures")
    func nightIsNotABreak() throws {
        let anatomy = try #require(build(digest(mac: [block(9, 1)])))
        #expect(anatomy.breaks.isEmpty)
        #expect(anatomy.firstScreen == 9 * hour)
    }

    // MARK: Ce qui traverse les appareils

    /// **Passer du Mac à la télé n'est pas une coupure** : l'écran n'a pas
    /// cessé, seul l'écran a changé. Même raison qui fait exister
    /// `coveredTotal` à côté de `summedTotal`.
    @Test("Changer d'appareil ne coupe pas la traite")
    func switchingDeviceIsNotABreak() throws {
        let anatomy = try #require(
            build(digest(mac: [block(19, 2)], tv: [block(20.5, 2)]))
        )
        #expect(anatomy.breaks.isEmpty)
        #expect(anatomy.longestStretch.start == 19 * hour)
        #expect(anatomy.longestStretch.duration == 3.5 * hour)
        #expect(anatomy.lastScreen == 22.5 * hour)
    }

    // MARK: Ce dont on ne sait rien

    /// **La règle 1 du projet.** La PlayStation ne donne qu'un total cumulé :
    /// la faire entrer ici lui inventerait une heure de début.
    @Test("Une source à compteur n'entre pas dans l'anatomie")
    func counterSourceIsExcluded() throws {
        let anatomy = try #require(
            build(digest(mac: [block(9, 1)], playstation: 3))
        )
        #expect(anatomy.firstScreen == 9 * hour)
        #expect(anatomy.lastScreen == 10 * hour)
        #expect(anatomy.longestStretch.duration == 1 * hour)
    }

    /// Une journée dont on ne connaît aucun horaire n'a pas commencé à minuit :
    /// elle n'a pas d'anatomie du tout. Zéro serait une affirmation fausse.
    @Test("Sans horaire connu, il n'y a pas d'anatomie — et surtout pas des zéros")
    func noScheduleMeansNoAnatomy() {
        #expect(build(digest(playstation: 3)) == nil)
        #expect(build(digest()) == nil)
    }

    /// Une session réparée après un double collecteur vaut zéro seconde. La
    /// compter avancerait le premier écran de la journée sur du vide.
    @Test("Un bloc de durée nulle n'est pas un instant d'écran")
    func zeroLengthBlockIsIgnored() throws {
        let anatomy = try #require(
            build(digest(mac: [block(3, 0), block(9, 1)]))
        )
        #expect(anatomy.firstScreen == 9 * hour)
    }

    // MARK: La fusion elle-même

    @Test("Des blocs qui se chevauchent ne font qu'une traite")
    func overlappingBlocksMergeIntoOne() throws {
        let anatomy = try #require(
            build(digest(mac: [block(9, 2), block(10, 2), block(10.5, 0.5)]))
        )
        #expect(anatomy.breaks.isEmpty)
        #expect(anatomy.longestStretch.duration == 3 * hour)
    }

    /// La somme des durées fusionnées doit rester celle qu'`IntervalMath`
    /// annonçait déjà : les traites et le total lisent les mêmes données.
    @Test("Les traites et le total couvert disent la même chose")
    func runsAgreeWithMergedDuration() {
        let blocks = [block(9, 2), block(10, 2), block(14, 1)]
        let runs = IntervalMath.mergedRuns(of: blocks)
        #expect(runs.reduce(0) { $0 + $1.duration } == IntervalMath.mergedDuration(of: blocks))
    }
}
