import CoreGraphics
import Foundation

/// Quelle taille donner à un rond pour qu'il dise une quantité.
///
/// Du calcul pur, séparé des vues pour être testable sans simulateur — même
/// raison que `TimelineGeometry` et `RingLayout`.
///
/// **Pourquoi la taille, et pas le remplissage.** Un anneau qui ne fait pas le
/// tour se lit « objectif atteint à 66 % », et l'objectif quotidien a été retiré
/// de la maquette : la règle « aucune comparaison ne juge » l'interdit. Les arcs
/// font donc toujours le tour, à toutes les échelles, et c'est le diamètre qui
/// porte la quantité.
///
/// **Pourquoi la racine carrée.** L'œil compare des *surfaces*, pas des
/// diamètres. À diamètre proportionnel, une valeur deux fois plus grande occupe
/// quatre fois plus de place et paraît quatre fois plus grande : c'est le défaut
/// classique des graphiques à bulles, et il exagère toujours dans le même sens.
/// La surface est donc proportionnelle à la valeur, donc le diamètre suit sa
/// racine carrée.
public enum RingScale {
    /// - Parameters:
    ///   - value: la durée à représenter.
    ///   - reference: la plus grande durée de l'ensemble, qui occupe `maximum`.
    ///   - maximum: le diamètre de la plus grande.
    ///   - minimum: le diamètre en dessous duquel un rond cesse d'être lisible.
    ///     Une valeur minuscule le prend : on sous-représente sa quantité plutôt
    ///     que de nier qu'elle a eu lieu — même arbitrage que le plancher d'arc
    ///     de `RingLayout` et que celui de `TimelineGeometry`.
    public static func diameter(
        for value: TimeInterval,
        reference: TimeInterval,
        maximum: CGFloat,
        minimum: CGFloat
    ) -> CGFloat {
        guard value > 0, reference > 0, maximum > 0 else { return minimum }
        let share = min(1, value / reference)
        return max(minimum, min(maximum, maximum * sqrt(share)))
    }
}
