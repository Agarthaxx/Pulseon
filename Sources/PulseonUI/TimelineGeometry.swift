import CoreGraphics
import Foundation

/// Convertit des secondes depuis minuit en position sur une piste.
///
/// Du calcul pur, séparé des vues pour être testable sans simulateur — même
/// raison que `PulseonCore` : ce qui mérite d'être vérifié ne doit pas exiger
/// qu'on lance une app pour le voir.
///
/// La longueur du jour est **fournie**, jamais supposée égale à 86 400 : les
/// journées de changement d'heure font 23 ou 25 heures, et une timeline qui
/// l'ignore décale toute la soirée de ces jours-là.
public struct TimelineGeometry: Equatable, Sendable {
    public let width: CGFloat
    public let dayLength: TimeInterval

    /// Un bloc plus fin que ça ne se verrait pas. Une minute de Mac sur une
    /// journée entière fait 0,7 point de large : la rendre invisible reviendrait
    /// à dire qu'elle n'a pas eu lieu.
    public let minimumBlockWidth: CGFloat

    public init(width: CGFloat, dayLength: TimeInterval, minimumBlockWidth: CGFloat = 2) {
        self.width = max(0, width)
        self.dayLength = dayLength > 0 ? dayLength : 86_400
        self.minimumBlockWidth = minimumBlockWidth
    }

    /// Position horizontale d'un instant de la journée, bornée aux deux bouts.
    public func x(atOffset offset: TimeInterval) -> CGFloat {
        let ratio = min(max(offset / dayLength, 0), 1)
        return width * ratio
    }

    /// Largeur d'un bloc, jamais nulle et jamais débordante.
    ///
    /// L'élargissement d'un bloc minuscule le pousserait hors du cadre s'il
    /// tombe en fin de journée : on le recale plutôt que de le laisser dépasser.
    public func rect(offset: TimeInterval, duration: TimeInterval) -> (x: CGFloat, width: CGFloat) {
        let start = x(atOffset: offset)
        let end = x(atOffset: offset + max(duration, 0))
        let drawn = max(end - start, minimumBlockWidth)
        return (min(start, max(0, width - drawn)), min(drawn, width))
    }

    /// Les heures à graduer. On en montre moins quand la fenêtre est étroite :
    /// une règle illisible n'aide personne à situer sa journée.
    public func hourTicks() -> [Int] {
        let step: Int
        switch width {
        case ..<360: step = 6
        case ..<680: step = 3
        default: step = 2
        }
        return stride(from: 0, through: 24, by: step).map { $0 }
    }

    /// Les heures **écrites** sous le rail, bien plus rares que les graduations.
    ///
    /// Un axe sert à situer un bloc à vue de nez, pas à lire une heure exacte —
    /// pour ça il y a l'infobulle et le total. Trop d'heures écrites, et l'axe
    /// devient la chose la plus bruyante de l'écran, ce qui était le défaut de la
    /// version précédente.
    public func hourLabels() -> [Int] {
        let step: Int
        switch width {
        case ..<300: step = 12
        case ..<560: step = 8
        default: step = 6
        }
        return stride(from: 0, through: 24, by: step).map { $0 }
    }
}
