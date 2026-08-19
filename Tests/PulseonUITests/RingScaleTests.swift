import Foundation
import Testing

@testable import PulseonUI

@Suite("La taille d'un rond")
struct RingScaleTests {
    private func diameter(_ value: TimeInterval, of reference: TimeInterval) -> CGFloat {
        RingScale.diameter(for: value, reference: reference, maximum: 100, minimum: 10)
    }

    @Test("la plus grande valeur occupe tout le diamètre")
    func reference() {
        #expect(diameter(3600, of: 3600) == 100)
    }

    @Test("la surface est proportionnelle à la valeur, pas le diamètre")
    func areaIsProportional() {
        // Une valeur quatre fois plus petite occupe un diamètre deux fois plus
        // petit, donc une surface bien quatre fois plus petite. Un diamètre
        // proportionnel aurait donné 25, soit une surface seize fois moindre.
        #expect(diameter(900, of: 3600) == 50)
    }

    @Test("une valeur minuscule reste visible")
    func floor() {
        // 0,01 % du maximum donnerait un point d'un point de large : on
        // sous-représente sa durée plutôt que de nier qu'elle a eu lieu.
        #expect(diameter(1, of: 10_000) == 10)
    }

    @Test("aucun rond ne dépasse le maximum, même hors échelle")
    func ceiling() {
        #expect(diameter(7200, of: 3600) == 100)
    }

    @Test("l'absence de valeur ou de référence rend le plancher, jamais zéro")
    func degenerate() {
        #expect(diameter(0, of: 3600) == 10)
        #expect(diameter(3600, of: 0) == 10)
        #expect(diameter(-60, of: 3600) == 10)
    }
}
