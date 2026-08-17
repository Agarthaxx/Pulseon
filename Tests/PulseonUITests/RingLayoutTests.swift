import Foundation
import Testing

@testable import PulseonUI

@Suite("L'anneau de composition")
struct RingLayoutTests {
    @Test("Deux parts égales font chacune un demi-tour")
    func halves() {
        let arcs = RingLayout.arcs(for: [3600, 3600]).compactMap { $0 }
        #expect(arcs.count == 2)
        #expect(abs(arcs[0].sweep - 0.5) < 0.001)
        #expect(abs(arcs[1].sweep - 0.5) < 0.001)
    }

    @Test("Les arcs s'enchaînent sans trou et bouclent le tour")
    func contiguous() {
        let arcs = RingLayout.arcs(for: [7200, 3600, 1800]).compactMap { $0 }
        #expect(arcs[0].start == 0)
        for (previous, next) in zip(arcs, arcs.dropFirst()) {
            #expect(abs(previous.end - next.start) < 0.0001)
        }
        #expect(abs((arcs.last?.end ?? 0) - 1) < 0.001)
    }

    @Test("Une part nulle ne prend aucun arc")
    func zeroTakesNothing() {
        let arcs = RingLayout.arcs(for: [3600, 0, 3600])
        #expect(arcs[1] == nil)
        #expect(arcs[0] != nil)
        #expect(arcs[2] != nil)
    }

    @Test("Une journée entièrement vide ne dessine rien")
    func emptyDay() {
        #expect(RingLayout.arcs(for: [0, 0]).allSatisfy { $0 == nil })
        #expect(RingLayout.arcs(for: []).isEmpty)
    }

    /// Une minute sur huit heures fait 0,2 % de tour : à sa taille exacte, l'arc
    /// serait invisible, ce qui reviendrait à dire qu'elle n'a pas eu lieu.
    @Test("Une part minuscule reste visible")
    func tinyStaysVisible() {
        let arcs = RingLayout.arcs(for: [8 * 3600, 60]).compactMap { $0 }
        // À l'epsilon près : le cumul des bornes se fait en flottant, donc le
        // plancher se retrouve à 0,0119999… plutôt qu'à 0,012 pile.
        #expect(arcs[1].sweep >= RingLayout.minimumSweep - 0.0001)
        // Et il est bien monté à sa valeur plancher, pas resté à sa part exacte
        // (60 s sur 8 h font 0,2 % de tour).
        #expect(arcs[1].sweep > 0.01)
    }

    /// Le plancher est pris sur les grandes parts, jamais ajouté au tour : sans
    /// ça la somme dépasserait 1 et le dernier arc repasserait sur le premier.
    @Test("Le plancher ne fait pas déborder le tour")
    func floorDoesNotOverflow() {
        let arcs = RingLayout.arcs(for: [10 * 3600, 30, 30, 30]).compactMap { $0 }
        #expect((arcs.last?.end ?? 0) <= 1.0001)
    }

    /// Cas dégénéré : tant de parts minuscules que le plancher ne tient pas dans
    /// un tour. Mieux vaut un partage égal qu'un anneau qui déborde.
    @Test("Trop de parts minuscules se partagent le tour à égalité")
    func tooManyTinyParts() {
        let values = Array(repeating: 1.0, count: 200)
        let arcs = RingLayout.arcs(for: values).compactMap { $0 }
        #expect(arcs.count == 200)
        #expect((arcs.last?.end ?? 0) <= 1.0001)
    }

    @Test("Une seule part fait le tour complet")
    func single() {
        let arcs = RingLayout.arcs(for: [1234]).compactMap { $0 }
        #expect(arcs.count == 1)
        #expect(abs(arcs[0].sweep - 1) < 0.001)
    }

    @Test("Une durée négative est traitée comme une absence")
    func negative() {
        let arcs = RingLayout.arcs(for: [-500, 3600])
        #expect(arcs[0] == nil)
        #expect(arcs[1] != nil)
    }
}
