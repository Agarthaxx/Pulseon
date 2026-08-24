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

    /// Le retrait intérieur, côté par côté.
    ///
    /// **L'éditorial n'a pas de cadre à remplir** : son air vient de l'espace
    /// *entre* les blocs, et son bord gauche s'aligne sur la marge de la page,
    /// pas sur un retrait de carte. Il garde du haut pour dégager le filet qui
    /// annonce le bloc.
    var insets: EdgeInsets {
        switch self {
        case .solid:
            EdgeInsets(
                top: PulseonSpace.card, leading: PulseonSpace.card,
                bottom: PulseonSpace.card, trailing: PulseonSpace.card)
        case .editorial:
            EdgeInsets(top: PulseonSpace.card, leading: 0, bottom: 0, trailing: 0)
        case .glass:
            EdgeInsets(top: 28, leading: 28, bottom: 28, trailing: 28)
        }
    }

    /// L'éditorial annonce chaque bloc par un filet, faute de cadre.
    var hasTopRule: Bool { self == .editorial }

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
        case .editorial: .system(size: 21, weight: .bold)
        case .glass: .system(size: 17, weight: .semibold)
        }
    }

    /// L'espacement des lettres du titre.
    ///
    /// Un titre gras et large se resserre : sans quoi il paraît étalé, ce qui
    /// est exactement ce qui fait « gabarit » plutôt que « composé ».
    var blockTitleTracking: CGFloat {
        switch self {
        case .solid: 0
        case .editorial: -0.4
        case .glass: -0.2
        }
    }

    var titleIsAccented: Bool { self == .editorial }

    /// Le libellé d'une ligne de liste.
    ///
    /// **C'est le second levier le plus visible après le grand nombre.** Des
    /// lignes à 13 points se lisent « tableau de bord » ; à 16 elles se lisent
    /// « page ».
    var rowLabel: Font {
        switch self {
        case .solid: .system(size: 13, weight: .medium)
        case .editorial: .system(size: 16, weight: .semibold)
        case .glass: .system(size: 14, weight: .medium)
        }
    }

    /// La durée d'une ligne de liste.
    var rowValue: Font {
        switch self {
        case .solid: .system(size: 15, weight: .semibold).monospacedDigit()
        case .editorial: .system(size: 18, weight: .bold).monospacedDigit()
        case .glass: .system(size: 16, weight: .semibold).monospacedDigit()
        }
    }

    /// L'air entre deux lignes d'une liste.
    var rowGap: CGFloat {
        switch self {
        case .solid: 15
        case .editorial: 22
        case .glass: 18
        }
    }

    /// L'épaisseur d'une jauge.
    ///
    /// L'éditorial l'affine : sans cadre autour, une jauge épaisse redevient
    /// l'élément le plus lourd de la page et vole la vedette au chiffre.
    var meterHeight: CGFloat {
        switch self {
        case .solid: 6
        case .editorial: 3
        case .glass: 7
        }
    }

    /// Le côté d'une pastille de catégorie.
    var chipSide: CGFloat {
        switch self {
        case .solid: 34
        case .editorial: 38
        case .glass: 36
        }
    }

    /// Ce que le fond doit porter derrière les surfaces.
    ///
    /// **Le verre n'existe que s'il y a quelque chose derrière lui.** Un fond
    /// plat sous une surface translucide donne un gris sale, pas du verre —
    /// même piège que l'accent unique décliné en opacités, qui donnait un olive
    /// sali plutôt qu'une nuance.
    var backgroundDepth: Double {
        switch self {
        case .solid: 1
        case .editorial: 0.75
        case .glass: 2.1
        }
    }

    /// Le verre pose en plus deux champs de couleur, sans quoi il n'a rien à
    /// réfracter.
    var hasColorFields: Bool { self == .glass }
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
            // Pas de cadre : un filet en tête, et le fond de la fenêtre pour
            // tout le reste. C'est le filet qui dit « nouveau bloc », là où les
            // autres peaux le disent par un rectangle.
            VStack(spacing: 0) {
                Rectangle()
                    .fill(palette.hairline.opacity(0.55))
                    .frame(height: 1)
                Spacer(minLength: 0)
            }

        case .glass:
            // **Pas de `Material`.** `ImageRenderer` ne le rend pas — la carte
            // sortirait en aplat opaque et la preview mentirait sur la
            // direction qu'on est en train de juger. Un translucide explicite
            // dit la même chose et se rend partout, iOS compris.
            //
            // Trois couches, et **aucune n'est facultative** : au premier jet
            // le verre ressemblait tellement à la peau pleine qu'Arthur ne
            // l'aurait pas distingué. Ce qui manquait n'était pas la
            // transparence, c'était le **bord** et le **reflet** — un verre se
            // reconnaît à ses arêtes, pas à son fond.
            let shape = RoundedRectangle(cornerRadius: skin.radius, style: .continuous)

            shape
                .fill(
                    LinearGradient(
                        colors: scheme == .dark
                            ? [Color.white.opacity(0.11), Color.white.opacity(0.035)]
                            : [Color.white.opacity(0.80), Color.white.opacity(0.42)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    // Le reflet : une bande claire qui court sur le haut de la
                    // surface, comme la lumière sur une vitre inclinée.
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(
                                    color: Color.white.opacity(scheme == .dark ? 0.10 : 0.5),
                                    location: 0),
                                .init(color: Color.white.opacity(0), location: 0.42),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                )
                .overlay(
                    // L'arête. Vive en haut à gauche, éteinte en bas à droite :
                    // c'est cette asymétrie qui donne une épaisseur au bord, là
                    // où un contour uniforme donne un simple cadre.
                    shape.strokeBorder(
                        LinearGradient(
                            stops: scheme == .dark
                                ? [
                                    .init(color: Color.white.opacity(0.55), location: 0),
                                    .init(color: Color.white.opacity(0.14), location: 0.35),
                                    .init(color: Color.white.opacity(0.05), location: 1),
                                ]
                                : [
                                    .init(color: Color.white.opacity(1), location: 0),
                                    .init(color: Color.white.opacity(0.55), location: 0.35),
                                    .init(color: Color.white.opacity(0.25), location: 1),
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
                .shadow(color: palette.shadow.opacity(0.9), radius: 34, y: 18)
        }
    }
}
