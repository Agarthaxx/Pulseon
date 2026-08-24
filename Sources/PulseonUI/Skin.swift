import SwiftUI

/// La direction artistique de Pulseon, arrêtée le 2026-08-24.
///
/// **Choisie par Arthur sur planche** — trois directions rendues côte à côte sur
/// la même journée, à la taille de sa fenêtre : « la version editorial est
/// vraiment sympa ! j'adore la editorial sombre/light ».
///
/// Ce qu'elle est, et pourquoi chaque trait y est :
///
/// - **Pas de cartes.** Un filet fin annonce chaque bloc et le bord gauche
///   s'aligne sur la marge de la page. L'écran cesse d'être une grille de
///   boîtes et devient une page — c'est la direction de Notion Calendar, et la
///   suite logique de la référence qu'Arthur donnait dès le 2026-08-16 : **la
///   donnée est le design**.
/// - **Les titres portent l'or.** Sans cadre, c'est le titre seul qui dit
///   « nouvelle rubrique ». L'or cesse d'être décoratif, il structure.
/// - **Les jauges sont fines.** Sans cadre autour, une jauge épaisse redevient
///   l'élément le plus lourd de la page et vole la vedette au chiffre.
///
/// **Deux directions ont été rendues puis écartées le même jour**, et il ne faut
/// pas les reproposer :
///
/// | Direction | Ce qu'elle donnait | Pourquoi elle n'est pas retenue |
/// |---|---|---|
/// | **pleine** | ce qui existait : cartes pleines, filet, ombre portée | c'est elle qu'Arthur trouvait « trop simple » — un tableau de bord parmi d'autres |
/// | **verre** | surfaces translucides, champs de couleur, arêtes vives | plus séduisante au premier regard, mais c'est une mode, et une mode datée se voit plus vite qu'une composition sobre |
///
/// Le type `PulseonSkin` qui permettait de les rendre côte à côte **a été
/// supprimé** une fois le choix fait : une option qui survit à la décision
/// qu'elle servait devient une dette. Même leçon que `RingScale`, retiré le jour
/// où plus personne ne l'appelait.
public enum PulseonEditorial {
    /// Le retrait d'un bloc.
    ///
    /// Rien à gauche ni à droite : le bloc s'aligne sur la marge de la page, ce
    /// qui est exactement ce qui remplace le cadre. Du haut, pour dégager le
    /// filet qui l'annonce.
    public static let blockInsets = EdgeInsets(
        top: PulseonSpace.card, leading: 0, bottom: 0, trailing: 0)

    /// L'air entre deux blocs. Généreux : c'est lui qui sépare, faute de cadre.
    public static let blockGap: CGFloat = PulseonSpace.page + 8

    /// L'air entre deux lignes d'une liste.
    public static let rowGap: CGFloat = 22

    /// L'épaisseur d'une jauge.
    public static let meterHeight: CGFloat = 3

    /// Le côté d'une pastille.
    public static let chipSide: CGFloat = 38

    /// La taille du grand nombre au centre de l'anneau, en fraction du cœur.
    ///
    /// **C'est le levier le plus visible de tous.** À 30 % du cœur, le total se
    /// lit comme une étiquette ; à 38 % il devient le sujet de l'écran.
    public static let readoutScale: CGFloat = 0.38
}

/// Le filet qui annonce un bloc.
///
/// Remplace le fond des cartes : c'est lui qui dit « nouvelle rubrique » là où
/// les autres directions le disaient par un rectangle.
struct BlockRule: View {
    let palette: PulseonPalette

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(palette.hairline.opacity(0.55))
                .frame(height: 1)
            Spacer(minLength: 0)
        }
    }
}
