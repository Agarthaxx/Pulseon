import PulseonCore
import SwiftUI

/// À quoi la journée a servi, en un rond par catégorie.
///
/// **Même concept que la rangée de la semaine**, à un cran plus fin : là-bas un
/// rond par journée, ici un rond par catégorie. La différence tient à ce que la
/// taille encode : **rien, ici.** Tous les ronds sont identiques, et la durée
/// est écrite au-dessus de chacun. Le cœur porte le logo de l'app dominante, et
/// la carte « Répartition » juste en dessous garde les chiffres exacts.
///
/// **Ils ont remplacé un anneau intérieur concentrique, puis un second anneau
/// posé à côté.** Le concentrique demandait une légende pour être compris ; le
/// second anneau plein forçait à mettre un chiffre en son centre, alors que la
/// somme des catégories n'est pas comparable au total de la journée. Une rangée
/// de petits ronds ne pose ni l'un ni l'autre problème : chacun porte sa propre
/// durée écrite, et aucun ne prétend résumer les autres.
struct DayCategoryRings: View {
    let categories: [CategoryTotal]
    let palette: PulseonPalette

    /// **Tous les ronds font la même taille**, décision d'Arthur le
    /// 2026-08-19 : « je me fiche de la logique le rond grossit plus le temps
    /// est grand, laisse-les de la même taille ». Étendue le même jour à la
    /// rangée de la semaine, qui suit désormais la même règle.
    ///
    /// Le diamètre a d'abord encodé la durée, et c'était défendable — un anneau
    /// fait toujours le tour, donc la taille était le seul canal restant. Mais
    /// **la durée est déjà écrite au-dessus de chaque rond**, et une rangée de
    /// ronds inégaux se lit moins bien qu'une rangée régulière. Ce qui reste
    /// vrai pour toute quantité future : **jamais par le remplissage**, qui se
    /// lirait comme un objectif atteint.
    ///
    /// Nettement sous le diamètre de l'anneau principal : ces ronds détaillent
    /// la journée, ils ne la résument pas, et leur taille doit le dire avant
    /// qu'on ait lu quoi que ce soit.
    private let diameter: CGFloat = 48

    var body: some View {
        // Colonnes de largeur fixe et rangée centrée, plutôt que des colonnes
        // qui se partagent toute la largeur : à trois catégories — le cas
        // courant — elles s'étalaient sur 700 points et la rangée ne se lisait
        // plus comme un groupe.
        HStack(alignment: .top, spacing: 4) {
            ForEach(categories) { category in
                CategoryRing(
                    category: category,
                    diameter: diameter,
                    width: columnWidth,
                    palette: palette
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Assez large pour « Communication » réduit d'un cran, assez étroit pour
    /// que huit catégories tiennent encore dans la colonne de l'écran.
    private let columnWidth: CGFloat = 84
}

private struct CategoryRing: View {
    let category: CategoryTotal
    let diameter: CGFloat
    let width: CGFloat
    let palette: PulseonPalette

    @Environment(\.appIcons) private var icons

    private var tint: Color { PulseonTheme.color(for: category.category, in: palette) }

    /// L'app qui a occupé le plus de temps dans cette catégorie.
    ///
    /// `entities` est déjà classé du plus long au plus court par
    /// `CategoryDigestBuilder` : la première est la dominante, sans rien à
    /// recalculer ici.
    private var dominantApp: String? { category.entities.first?.entity }

    var body: some View {
        VStack(spacing: 6) {
            Text(DurationFormat.compact(category.total))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(palette.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            ZStack {
                Ring(
                    segments: [
                        .init(
                            id: category.category.rawValue,
                            value: category.total,
                            tones: PulseonTheme.ringTones(for: category.category, in: palette)
                        )
                    ],
                    thickness: max(3, diameter * 0.2),
                    // Pas de piste creuse : un rond de catégorie fait toujours
                    // le tour, donc la piste serait entièrement recouverte.
                    track: nil,
                    palette: palette
                )
                .frame(width: diameter, height: diameter)

                center
            }

            Text(category.category.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(width: width)
    }

    /// Ce qui occupe le cœur du rond : le logo de l'app dominante, ou le glyphe
    /// de la catégorie à défaut.
    ///
    /// **Rendre nil est une vraie réponse**, pas un échec à cacher : un jeu
    /// PlayStation n'a jamais eu d'icône côté Mac, une app désinstallée n'en a
    /// plus, et une app utilisée avant que `noteApp` ne tourne n'a aucun
    /// identifiant de bundle en base. Le repli n'est donc pas un cas rare à
    /// traiter par acquit de conscience — c'est le cas normal d'une catégorie
    /// entière, « Jeu » en tête. **Jamais de carré vide.**
    ///
    /// Le glyphe de repli reste celui de la pastille de la carte
    /// « Répartition », donc les deux formes disent la même chose.
    @ViewBuilder
    private var center: some View {
        if let dominantApp, let icon = icons.icon(for: dominantApp) {
            icon
                .resizable()
                .interpolation(.high)
                // Une icône d'app porte déjà sa propre marge interne : la
                // pousser jusqu'au bord du trou la ferait toucher l'anneau.
                .frame(width: diameter * 0.46, height: diameter * 0.46)
        } else {
            Image(systemName: PulseonTheme.symbol(for: category.category))
                .font(.system(size: diameter * 0.3, weight: .semibold))
                .foregroundStyle(tint)
        }
    }
}
