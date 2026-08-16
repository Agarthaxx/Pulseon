import Foundation
import Testing

@testable import PulseonCore

/// La règle de comparaison entre journées.
///
/// Elle décide surtout **quand se taire**, ce qui est le point délicat : une
/// moyenne annoncée sur trop peu de journées, ou calculée sur des journées où le
/// collecteur était éteint, serait un chiffre faux présenté comme un fait.
@Suite struct DayComparisonTests {
    /// Une journée dont on ne fixe que le total et le fait qu'une source ait
    /// écrit — c'est tout ce que la comparaison regarde.
    private func day(covered: TimeInterval, measured: Bool = true) -> DayDigest {
        DayDigest(
            date: DateComponents(year: 2026, month: 8, day: 16),
            lanes: [
                Lane(
                    device: .mac, total: covered, blocks: [], topEntities: [],
                    isConnected: measured
                )
            ],
            summedTotal: covered,
            coveredTotal: covered
        )
    }

    private func hours(_ value: Double) -> TimeInterval { value * 3600 }

    @Test("La moyenne se calcule sur les journées mesurées")
    func averagesMeasuredDays() throws {
        let comparison = try #require(
            DayComparisonBuilder.compare(
                subject: day(covered: hours(9)),
                against: [day(covered: hours(6)), day(covered: hours(8)), day(covered: hours(10))],
                isPartial: false
            )
        )

        #expect(comparison.average == hours(8))
        #expect(comparison.delta == hours(1))
        #expect(comparison.referenceDays == 3)
        #expect(comparison.isPartial == false)
    }

    /// Le point le plus important : une journée où **aucune source n'a écrit**
    /// veut dire « le collecteur était éteint », pas « zéro minute d'écran ». La
    /// compter tirerait la moyenne vers le bas pour une raison qui n'a aucun
    /// rapport avec l'usage.
    @Test("Une journée sans aucune source mesurée est écartée de la moyenne")
    func unmeasuredDaysAreExcluded() throws {
        let comparison = try #require(
            DayComparisonBuilder.compare(
                subject: day(covered: hours(9)),
                against: [
                    day(covered: hours(6)),
                    day(covered: hours(8)),
                    day(covered: hours(10)),
                    day(covered: 0, measured: false),
                    day(covered: 0, measured: false),
                ],
                isPartial: false
            )
        )

        #expect(comparison.average == hours(8))
        #expect(comparison.referenceDays == 3)
    }

    /// L'inverse, qui est tout aussi important : une journée où une source était
    /// branchée et n'a rien enregistré est un **vrai zéro**, et elle compte.
    @Test("Une journée mesurée à zéro compte dans la moyenne")
    func measuredZeroCounts() throws {
        let comparison = try #require(
            DayComparisonBuilder.compare(
                subject: day(covered: hours(9)),
                against: [day(covered: hours(6)), day(covered: hours(6)), day(covered: 0)],
                isPartial: false
            )
        )

        #expect(comparison.average == hours(4))
        #expect(comparison.referenceDays == 3)
    }

    /// Une « moyenne » sur deux journées n'est pas une moyenne. Se taire est plus
    /// honnête que d'annoncer une tendance qui n'existe pas.
    @Test("En dessous de trois journées mesurées, on ne dit rien")
    func tooFewDaysSaysNothing() {
        #expect(
            DayComparisonBuilder.compare(
                subject: day(covered: hours(9)),
                against: [day(covered: hours(6)), day(covered: hours(8))],
                isPartial: false
            ) == nil
        )
        #expect(
            DayComparisonBuilder.compare(
                subject: day(covered: hours(9)), against: [], isPartial: false
            ) == nil
        )
    }

    @Test("Cinq minutes d'écart ne sont pas un écart")
    func smallDeltasAreTypical() throws {
        let comparison = try #require(
            DayComparisonBuilder.compare(
                subject: day(covered: hours(8) + 120),
                against: [day(covered: hours(8)), day(covered: hours(8)), day(covered: hours(8))],
                isPartial: false
            )
        )

        #expect(comparison.isTypical)
        #expect(comparison.delta == 120)
    }

    @Test("Un écart franc n'est pas dans la moyenne")
    func largeDeltasAreNotTypical() throws {
        let comparison = try #require(
            DayComparisonBuilder.compare(
                subject: day(covered: hours(3)),
                against: [day(covered: hours(8)), day(covered: hours(8)), day(covered: hours(8))],
                isPartial: false
            )
        )

        #expect(!comparison.isTypical)
        #expect(comparison.delta == -hours(5))
    }

    @Test("Le caractère partiel de la comparaison est transmis tel quel")
    func partialFlagIsCarried() throws {
        let comparison = try #require(
            DayComparisonBuilder.compare(
                subject: day(covered: hours(4)),
                against: [day(covered: hours(3)), day(covered: hours(3)), day(covered: hours(3))],
                isPartial: true
            )
        )

        #expect(comparison.isPartial)
    }

    @Test("Une journée sans source mesurée se distingue d'une journée à zéro")
    func measuredSourceIsWhatCounts() {
        #expect(day(covered: 0).hasMeasuredSource)
        #expect(!day(covered: 0, measured: false).hasMeasuredSource)
    }
}
