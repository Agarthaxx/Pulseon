import SwiftUI

/// La **peau** de l'app : ce qui se voit avant qu'on lise quoi que ce soit.
///
/// Arthur, le 2026-08-24, devant la version « réglée » : « tu m'as rajouté une
/// feature ok mais qu'en est-il du design de l'app ? le front n'a pas bougé ? ».
/// Il avait raison — les marges, les titres et la disposition avaient changé,
/// mais le **langage visuel** était le même : mêmes cartes pleines, même
/// typographie système à petite taille, même palette. Ce n'est pas une
/// direction artistique, c'est du réglage.
///
/// Ce type existe pour que deux directions puissent être **rendues côte à
/// côte** sur la même journée, plutôt que décrites. Il ne touche à aucune
/// donnée : ce qui est affiché ne change pas, seulement la façon dont c'est
/// posé.
///
/// **Ce n'est pas un réglage utilisateur.** Une fois qu'Arthur aura choisi, la
/// peau perdante part et le type avec — comme `RingScale` a disparu le jour où
/// plus personne ne l'appelait. Une option qui survit à la décision qu'elle
/// servait devient une dette.
public enum PulseonSkin: String, Sendable, CaseIterable {
    /// Ce qui existe aujourd'hui : cartes pleines, filet, ombre portée.
    case solid

    /// **Éditorial.** Plus de cartes du tout : de grandes plages d'air, des
    /// filets fins pour séparer, et une typographie franche qui porte seule la
    /// hiérarchie. C'est la direction de Notion Calendar et de Linear, et c'est
    /// la plus proche de la référence qu'Arthur citait déjà le 2026-08-16 —
    /// « la donnée est le design ». Le risque est qu'elle paraisse nue.
    case editorial

    /// **Verre.** Des surfaces translucides posées sur un fond riche, un bord
    /// clair qui attrape la lumière, un grand rayon. C'est la direction
    /// qu'Apple pousse depuis visionOS, et probablement ce qu'« app haut de
    /// gamme 2026 » veut dire. Le risque est l'illisibilité : du texte sur du
    /// translucide passe mal si le fond derrière est chargé.
    case glass

    /// Le rayon des surfaces.
    var radius: CGFloat {
        switch self {
        case .solid: 20
        case .editorial: 0
        case .glass: 26
        }
    }

    /// Le retrait intérieur.
    ///
    /// L'éditorial n'a pas de carte à remplir : son air vient de l'espace entre
    /// les blocs, pas d'un cadre autour.
    var inset: CGFloat {
        switch self {
        case .solid: PulseonSpace.card
        case .editorial: 0
        case .glass: PulseonSpace.card + 4
        }
    }

    /// L'espace entre deux blocs.
    var gap: CGFloat {
        switch self {
        case .solid: PulseonSpace.base
        case .editorial: PulseonSpace.page + 8
        case .glass: PulseonSpace.card
        }
    }

    /// La taille du grand nombre au centre de l'anneau, en fraction du cœur.
    ///
    /// **C'est le levier le plus visible de tous.** Un total à 30 % du cœur se
    /// lit comme une étiquette ; à 38 % il devient le sujet de l'écran.
    var readoutScale: CGFloat {
        switch self {
        case .solid: 0.30
        case .editorial: 0.38
        case .glass: 0.34
        }
    }

    /// Le titre d'un bloc.
    ///
    /// L'éditorial n'ayant pas de cadre, c'est le titre qui doit dire « nouveau
    /// bloc » — donc il est nettement plus gros, et il porte l'or.
    var blockTitle: Font {
        switch self {
        case .solid: .system(size: 15, weight: .semibold)
        case .editorial: .system(size: 20, weight: .bold)
        case .glass: .system(size: 16, weight: .semibold)
        }
    }

    var titleIsAccented: Bool { self == .editorial }
}

private struct SkinKey: EnvironmentKey {
    /// La peau actuelle de l'app, tant qu'Arthur n'a pas tranché.
    static var defaultValue: PulseonSkin { .solid }
}

extension EnvironmentValues {
    public var pulseonSkin: PulseonSkin {
        get { self[SkinKey.self] }
        set { self[SkinKey.self] = newValue }
    }
}

/// La surface d'un bloc, selon la peau.
///
/// Remplace le fond de `Card` sans toucher à son contenu : c'est le seul point
/// où les trois directions divergent vraiment, et le tenir en un seul endroit
/// évite que deux blocs se mettent à diverger.
struct SkinSurface: View {
    let skin: PulseonSkin
    let palette: PulseonPalette
    let scheme: ColorScheme

    var body: some View {
        switch skin {
        case .solid:
            RoundedRectangle(cornerRadius: skin.radius, style: .continuous)
                .fill(palette.surfaceGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: skin.radius, style: .continuous)
                        .strokeBorder(palette.hairline.opacity(0.6), lineWidth: 0.5)
                )
                .shadow(color: palette.shadow, radius: 16, y: 8)

        case .editorial:
            // Rien. C'est le fond de la fenêtre qu'on voit, et l'air autour du
            // bloc qui le sépare du suivant.
            Color.clear

        case .glass:
            // **Pas de `Material`.** `ImageRenderer` ne le rend pas — la carte
            // sortirait en aplat opaque et la preview mentirait sur la
            // direction qu'on est en train de juger. Un translucide explicite
            // dit la même chose et se rend partout, iOS compris.
            RoundedRectangle(cornerRadius: skin.radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: scheme == .dark
                            ? [Color.white.opacity(0.075), Color.white.opacity(0.028)]
                            : [Color.white.opacity(0.72), Color.white.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    // Le bord clair en haut à gauche : c'est lui qui fait
                    // « verre » plutôt que « rectangle gris translucide ».
                    RoundedRectangle(cornerRadius: skin.radius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: scheme == .dark
                                    ? [
                                        Color.white.opacity(0.30),
                                        Color.white.opacity(0.05),
                                    ]
                                    : [
                                        Color.white.opacity(0.95),
                                        Color.white.opacity(0.35),
                                    ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: palette.shadow.opacity(0.8), radius: 28, y: 14)
        }
    }
}
