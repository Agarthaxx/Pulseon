import Foundation
import Testing

@testable import PulseonUI

/// Le partage en colonnes pondérées de la grille du tableau de bord.
///
/// Testable sans vue parce que le calcul est séparé du dessin — même raison que
/// `RingLayout` et `TimelineGeometry`.
@Suite("Les colonnes pondérées")
struct WeightedColumnsTests {
    private func widths(_ total: CGFloat, _ weights: [CGFloat], spacing: CGFloat = 14)
        -> [CGFloat]
    {
        WeightedColumns.widths(of: total, weights: weights, spacing: spacing)
    }

    @Test("Les colonnes se partagent la place selon leurs poids")
    func splitFollowsWeights() throws {
        let columns = widths(1014, [57, 43])
        // 1014 moins un écart de 14 : 1000 à partager.
        #expect(columns.count == 2)
        #expect(abs(try #require(columns.first) - 570) < 0.001)
        #expect(abs(try #require(columns.last) - 430) < 0.001)
    }

    /// L'écart entre les colonnes est pris sur la largeur, jamais ajouté :
    /// sinon la grille dépasserait la fenêtre d'exactement un écart, ce qui est
    /// le genre de débordement qui rogne toute la colonne du dessous.
    @Test("Les écarts sont pris sur la largeur, pas ajoutés")
    func spacingIsTakenFromTheWidth() {
        let columns = widths(1000, [1, 1], spacing: 20)
        #expect(columns.reduce(0, +) + 20 == 1000)
    }

    @Test("Des poids égaux donnent des colonnes égales")
    func equalWeightsGiveEqualColumns() {
        let columns = widths(1014, [1, 1])
        #expect(columns[0] == columns[1])
    }

    /// L'échelle des poids ne compte pas, seul leur rapport.
    @Test("Doubler tous les poids ne change rien")
    func scaleDoesNotMatter() {
        #expect(widths(1014, [57, 43]) == widths(1014, [114, 86]))
    }

    /// Une grille mal pondérée doit rester lisible, pas disparaître : un poids
    /// nul produirait une division par zéro ou une colonne de largeur nulle.
    @Test("Des poids nuls retombent sur un partage égal")
    func zeroWeightsFallBackToAnEqualSplit() {
        let columns = widths(1014, [0, 0])
        #expect(columns[0] == columns[1])
        #expect(columns[0] > 0)
    }

    @Test("Un poids négatif ne produit pas de colonne négative")
    func negativeWeightIsNotNegativeWidth() {
        let columns = widths(1014, [-5, 10])
        #expect(columns.allSatisfy { $0 >= 0 })
    }

    /// Une fenêtre plus étroite que les écarts ne doit pas produire de largeurs
    /// négatives — c'est le genre de valeur qui fait planter un dessin.
    @Test("Une largeur trop petite pour les écarts ne devient pas négative")
    func tinyWidthStaysPositive() {
        let columns = widths(10, [1, 1], spacing: 40)
        #expect(columns.allSatisfy { $0 >= 0 })
    }

    @Test("Sans colonne, il n'y a rien à partager")
    func noColumnsNoWidths() {
        #expect(widths(1000, []).isEmpty)
    }

    /// La grille du jour : la case de l'anneau doit rester la plus large, à
    /// toutes les tailles de fenêtre où la grille est retenue.
    @Test("La case de l'anneau reste la plus large")
    func ringCellStaysWidest() {
        for window in [DayDashboardContent.gridMinimumWidth, 1200, 1512, 2560] as [CGFloat] {
            let columns = widths(
                window,
                [DayDashboardContent.leadingWeight, DayDashboardContent.trailingWeight]
            )
            #expect(columns[0] > columns[1], "à \(window) points")
        }
    }
}
