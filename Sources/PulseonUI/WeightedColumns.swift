import SwiftUI

/// Des colonnes de largeurs pondérées, côte à côte.
///
/// SwiftUI sait faire deux colonnes égales — `frame(maxWidth: .infinity)` sur
/// chacune — mais pas deux colonnes dans un rapport donné. Or c'est exactement
/// ce que demande une grille de tableau de bord : **toutes les cases ne pèsent
/// pas le même poids.** L'anneau porte le total de la journée et sa composition,
/// la carte des appareils porte trois lignes ; leur donner la même largeur
/// dirait qu'elles se valent.
///
/// Le calcul est séparé du dessin, comme `RingLayout` et `TimelineGeometry` : ce
/// qui se teste sans simulateur doit se tester sans simulateur.
struct WeightedColumns: Layout {
    /// Les poids, dans l'ordre des colonnes. Leur échelle n'a pas
    /// d'importance — seul leur rapport compte.
    let weights: [CGFloat]
    let spacing: CGFloat

    /// Comment se partagent `total` points entre les colonnes.
    ///
    /// Fonction pure et statique, pour être vérifiable sans vue.
    ///
    /// **Les poids nuls ou négatifs sont ramenés à un partage égal** plutôt que
    /// de produire une division par zéro ou une largeur négative : une grille
    /// mal pondérée doit rester lisible, pas disparaître.
    static func widths(
        of total: CGFloat, weights: [CGFloat], spacing: CGFloat
    ) -> [CGFloat] {
        guard !weights.isEmpty else { return [] }
        let gaps = spacing * CGFloat(weights.count - 1)
        let usable = max(0, total - gaps)

        let clean = weights.map { $0 > 0 ? $0 : 0 }
        let sum = clean.reduce(0, +)
        guard sum > 0 else {
            return Array(repeating: usable / CGFloat(weights.count), count: weights.count)
        }
        return clean.map { usable * $0 / sum }
    }

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        // Sans largeur proposée — c'est le cas quand `ViewThatFits` demande la
        // taille idéale —, on répond la somme des idéaux. C'est ce qui permet à
        // l'appelant de décider que la grille ne tient pas et de replier sur une
        // colonne unique.
        let width = proposal.width ?? idealWidth(of: subviews)
        let columns = Self.widths(of: width, weights: normalized(subviews.count), spacing: spacing)

        let height = zip(subviews, columns).reduce(CGFloat.zero) { tallest, pair in
            max(tallest, pair.0.sizeThatFits(.init(width: pair.1, height: proposal.height)).height)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let columns = Self.widths(
            of: bounds.width, weights: normalized(subviews.count), spacing: spacing
        )
        var x = bounds.minX
        for (subview, width) in zip(subviews, columns) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }

    /// Les poids ramenés au nombre réel de colonnes : une case qui disparaît
    /// (pas d'anatomie, pas de répartition) ne doit pas laisser un trou.
    private func normalized(_ count: Int) -> [CGFloat] {
        if weights.count == count { return weights }
        if weights.count > count { return Array(weights.prefix(count)) }
        return weights + Array(repeating: 1, count: count - weights.count)
    }

    private func idealWidth(of subviews: Subviews) -> CGFloat {
        let content = subviews.reduce(CGFloat.zero) {
            $0 + $1.sizeThatFits(.unspecified).width
        }
        return content + spacing * CGFloat(max(0, subviews.count - 1))
    }
}
