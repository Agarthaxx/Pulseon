import Foundation

/// Où commence et où finit chaque arc de l'anneau, en fractions de tour.
///
/// Séparé des vues pour être testable sans simulateur — même raison que
/// `TimelineGeometry`.
///
/// **L'anneau dit une composition, jamais une progression.** Il fait toujours
/// le tour complet : ses arcs sont les parts de la journée, pas l'avancement
/// vers un objectif. C'est ce qui le rend compatible avec la règle « aucune
/// comparaison ne juge » — un anneau qui se remplit vers une cible annoncerait
/// une réussite ou un échec, et Pulseon mesure sans dire si c'est bien.
public enum RingLayout {
    public struct Arc: Equatable, Sendable {
        /// Fractions de tour, dans `0...1`, à faire tourner de -90° à l'écran
        /// pour que le premier arc parte du haut.
        public let start: Double
        public let end: Double

        public var sweep: Double { end - start }
    }

    /// La part minimale qu'un arc occupe, même s'il ne la mérite pas.
    ///
    /// Une minute sur une journée de huit heures fait 0,2 % de tour, soit un
    /// arc invisible : l'afficher à sa taille exacte reviendrait à dire qu'elle
    /// n'a pas eu lieu. Même raisonnement que le plancher de 2 points de
    /// `TimelineGeometry`. Le prix est assumé et borné : les proportions sont
    /// légèrement faussées en faveur des petites parts, et les chiffres à côté
    /// de l'anneau, eux, restent exacts.
    public static let minimumSweep = 0.012

    /// - Parameter values: les durées, dans l'ordre d'affichage. Les valeurs
    ///   nulles ou négatives ne prennent aucun arc — une source à zéro n'occupe
    ///   pas l'anneau.
    public static func arcs(for values: [TimeInterval]) -> [Arc?] {
        let positives = values.map { max(0, $0) }
        let total = positives.reduce(0, +)
        guard total > 0 else { return values.map { _ in nil } }

        let shown = positives.filter { $0 > 0 }.count
        // Trop de parts minuscules pour que le plancher tienne dans un tour :
        // on partage alors le tour à parts égales plutôt que de déborder.
        let floor = Double(shown) * minimumSweep > 1 ? 1 / Double(shown) : minimumSweep

        // Les arcs sous le plancher le prennent ; les autres se partagent ce
        // qu'il reste, au prorata — sinon la somme dépasserait le tour.
        let raw = positives.map { $0 / total }
        let boosted = raw.filter { $0 > 0 && $0 < floor }
        let borrowed = boosted.reduce(0) { $0 + (floor - $1) }
        let generous = raw.filter { $0 >= floor }.reduce(0, +)
        let shrink = generous > 0 ? max(0, generous - borrowed) / generous : 1

        var cursor = 0.0
        return raw.map { fraction in
            guard fraction > 0 else { return nil }
            let sweep = fraction < floor ? floor : fraction * shrink
            let arc = Arc(start: cursor, end: min(1, cursor + sweep))
            cursor = arc.end
            return arc
        }
    }
}
