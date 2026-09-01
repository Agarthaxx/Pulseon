import Foundation
import Testing

@testable import PulseonCore

@Suite("Le battement de la journée")
struct DayPulseTests {
    private let hour: TimeInterval = 3600
    private let day: TimeInterval = 86_400

    private func lane(
        _ device: Device, _ blocks: [TraceBlock], connected: Bool = true
    ) -> Lane {
        Lane(
            device: device,
            total: blocks.reduce(0) { $0 + $1.duration },
            blocks: blocks,
            topEntities: [],
            isConnected: connected
        )
    }

    private func block(_ startHour: Double, _ hours: Double) -> TraceBlock {
        TraceBlock(entity: nil, startOffset: startHour * hour, duration: hours * hour)
    }

    @Test("une heure pleine remplit ses quatre quarts d'heure")
    func fullHour() throws {
        let pulse = DayPulseBuilder.build(
            lanes: [lane(.mac, [block(9, 1)])], dayLength: day)

        // 09:00 → 10:00, soit les tranches 36 à 39.
        for index in 36..<40 {
            #expect(pulse.intensities[index] == 1)
        }
        #expect(pulse.intensities[35] == 0)
        #expect(pulse.intensities[40] == 0)
    }

    @Test("une demi-tranche donne une demi-intensité")
    func partialBucket() throws {
        // 09:00 → 09:07:30, soit la moitié du premier quart d'heure.
        let pulse = DayPulseBuilder.build(
            lanes: [lane(.mac, [TraceBlock(entity: nil, startOffset: 9 * hour, duration: 450)])],
            dayLength: day
        )
        #expect(pulse.intensities[36] == 0.5)
    }

    @Test("deux écrans en même temps ne dépassent jamais 100 %")
    func simultaneousScreensDoNotStack() throws {
        // C'est la leçon de la journée de 51 heures, appliquée au battement :
        // deux mesures d'un même instant restent un seul instant.
        let pulse = DayPulseBuilder.build(
            lanes: [lane(.mac, [block(21, 1)]), lane(.tv, [block(21, 1)])],
            dayLength: day
        )
        #expect(pulse.intensities[84] == 1)
        #expect(pulse.intensities.allSatisfy { $0 <= 1 })
    }

    @Test("une journée sans mesure se tait, au lieu de dessiner un plat")
    func silentDay() throws {
        let pulse = DayPulseBuilder.build(lanes: [], dayLength: day)
        #expect(pulse.isSilent)
        #expect(pulse.peakIndex == nil)
    }

    @Test("le pic désigne la tranche la plus chargée")
    func peak() throws {
        let pulse = DayPulseBuilder.build(
            lanes: [
                lane(
                    .mac,
                    [
                        TraceBlock(entity: nil, startOffset: 9 * hour, duration: 300),
                        block(14, 1),
                    ])
            ],
            dayLength: day
        )
        let peak = try #require(pulse.peakIndex)
        #expect(peak == 56)  // 14:00
        #expect(pulse.offset(ofBucket: peak) == 14 * hour + 450)
    }

    @Test("une journée de 23 heures n'a pas 96 tranches")
    func shortDay() throws {
        // Le passage à l'heure d'été. Caler la courbe sur 24 h décalerait
        // toutes les tranches ce jour-là.
        let pulse = DayPulseBuilder.build(lanes: [], dayLength: 23 * hour)
        #expect(pulse.intensities.count == 92)
    }

    @Test("un bloc qui déborde de la journée est borné")
    func clampedToDay() throws {
        let pulse = DayPulseBuilder.build(
            lanes: [lane(.mac, [block(23, 3)])], dayLength: day)
        #expect(pulse.intensities.count == 96)
        #expect(pulse.intensities[95] == 1)
        #expect(pulse.intensities.allSatisfy { $0 <= 1 })
    }
}

@Suite("La fenêtre la plus dense")
struct DensestWindowTests {
    private let hour: TimeInterval = 3600
    private let day: TimeInterval = 86_400

    private func lane(_ blocks: [TraceBlock]) -> Lane {
        Lane(
            device: .mac, total: blocks.reduce(0) { $0 + $1.duration },
            blocks: blocks, topEntities: [], isConnected: true
        )
    }

    private func block(_ startHour: Double, _ hours: Double) -> TraceBlock {
        TraceBlock(entity: nil, startOffset: startHour * hour, duration: hours * hour)
    }

    @Test("désigne la vraie zone dense, pas le premier maximum venu")
    func picksTheWindowNotThePeak() throws {
        // Une matinée hachée et un après-midi plein. `peakIndex` renvoie la
        // première tranche à 100 %, qui est le matin — c'est le bug trouvé en
        // PNG le 2026-08-24.
        let pulse = DayPulseBuilder.build(
            lanes: [lane([block(8, 0.25), block(14, 3)])], dayLength: day)

        let window = try #require(pulse.densestWindow(spanning: 2 * hour))
        #expect(window.start == 14 * hour)
        #expect(window.end == 16 * hour)
    }

    @Test("se tait quand rien n'est mesuré")
    func silent() throws {
        let pulse = DayPulseBuilder.build(lanes: [], dayLength: day)
        #expect(pulse.densestWindow(spanning: 2 * hour) == nil)
    }

    @Test("à égalité, garde la fenêtre la plus précoce")
    func stableOnTies() throws {
        // Deux traites identiques : le résultat ne doit pas dépendre de
        // l'ordre de parcours, sinon deux ouvertures de la même journée
        // afficheraient deux heures différentes.
        let pulse = DayPulseBuilder.build(
            lanes: [lane([block(9, 2), block(15, 2)])], dayLength: day)
        let window = try #require(pulse.densestWindow(spanning: 2 * hour))
        #expect(window.start == 9 * hour)
    }
}
