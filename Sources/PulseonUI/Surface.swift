import SwiftUI

/// Le rythme des espacements.
///
/// Arthur, le 2026-08-24 : « un beau fond + des belles rubriques card bien
/// taillée bien responsive, typique d'une app Tesla/Apple ». Le relevé sur sa
/// fenêtre a montré des espacements de 3, 5, 6, 7, 8, 11, 12, 16 et 18 points,
/// choisis un par un au fil des écrans. **Aucun n'est faux isolément, et
/// l'ensemble n'a pas de rythme** — c'est ce qui se lit « bricolé » sans qu'on
/// sache dire pourquoi.
///
/// Une échelle sur une base de 4 : l'œil reconnaît la régularité même quand il
/// ne la mesure pas, et deux marges voisines qui diffèrent d'un point passent
/// pour une erreur plutôt que pour une intention.
public enum PulseonSpace {
    /// Entre deux éléments collés — un chiffre et son unité.
    public static let hair: CGFloat = 4
    /// Entre deux lignes d'un même bloc.
    public static let tight: CGFloat = 8
    /// Entre deux blocs d'une même carte.
    public static let snug: CGFloat = 12
    /// La respiration standard.
    public static let base: CGFloat = 16
    /// Entre deux cartes, et le retrait intérieur d'une carte.
    public static let card: CGFloat = 24
    /// La marge de la fenêtre.
    public static let page: CGFloat = 32

    /// Le rayon des cartes, celui de la maquette.
    public static let radius: CGFloat = 20
}

/// Le fond de la fenêtre.
///
/// **Un aplat uniforme est ce qui trahit le plus vite une app faite à la
/// main.** Le fond de Pulseon était une couleur unie ; aucune app de la
/// référence qu'Arthur cite n'en a une. Ce qu'elles ont toutes, c'est une
/// variation de lumière assez faible pour ne jamais se remarquer, et assez
/// présente pour que la surface ait une épaisseur.
///
/// Trois couches, et chacune répond à un défaut constaté :
///
/// - **un halo haut**, centré là où vit l'anneau : le héros de l'écran se
///   détachait sur du noir plat, donc il flottait au lieu d'être posé ;
/// - **une teinte d'or très diluée en bas**, qui rappelle l'accent du projet
///   sans jamais désigner quoi que ce soit — l'or *désigne du temps mesuré*
///   partout ailleurs, donc il ne doit rien affirmer ici : d'où une opacité
///   assez basse pour qu'on ne puisse pas la confondre avec une donnée ;
/// - **une vignette**, qui referme les bords et empêche la fenêtre de « fuir »
///   dans l'écran.
///
/// **Rien de tout ça ne porte d'information**, et c'est délibéré : c'est la
/// seule décoration que ce projet s'autorise, parce qu'elle ne peut rien
/// affirmer de faux.
public struct PulseonBackground: View {
    private let palette: PulseonPalette
    private let scheme: ColorScheme

    public init(palette: PulseonPalette, scheme: ColorScheme) {
        self.palette = palette
        self.scheme = scheme
    }

    /// Le fond est plus discret en clair : sur une surface lumineuse, la même
    /// intensité de halo se lit comme une tache.
    private var isDark: Bool { scheme == .dark }

    /// L'amplitude du battement du halo. **Vaut 1 au repos**, donc une preview
    /// rend le fond à sa pleine intensité — le repli est « tout est dessiné ».
    @State private var breath: Double = 1
    @Environment(\.pulseonMotion) private var motion
    @Environment(\.pulseonSkin) private var skin

    /// Le verre n'existe que s'il y a quelque chose derrière lui. Un fond plat
    /// sous une surface translucide donne un gris sale, pas du verre — c'est le
    /// même piège que l'accent unique décliné en opacités, qui donnait un olive
    /// sali au lieu d'une nuance.
    private var depth: Double { skin == .glass ? 1.9 : 1 }

    public var body: some View {
        ZStack {
            palette.ground

            // Le halo derrière l'anneau. **Il bat**, très lentement et de très
            // peu : c'est le pouls de la marque, rendu au fond de l'écran. Un
            // halo qu'on remarque est un halo qui distrait, et cet écran sert à
            // lire des chiffres.
            RadialGradient(
                colors: [
                    palette.navy.opacity((isDark ? 0.20 : 0.07) * breath * depth),
                    palette.navy.opacity(0),
                ],
                center: UnitPoint(x: 0.5, y: 0.06),
                startRadius: 0,
                endRadius: 620 * (0.94 + 0.06 * breath)
            )

            // Le rappel d'or, en bas, très dilué.
            RadialGradient(
                colors: [
                    palette.gold.opacity((isDark ? 0.07 : 0.05) * depth),
                    palette.gold.opacity(0),
                ],
                center: UnitPoint(x: 0.88, y: 1.0),
                startRadius: 0,
                endRadius: 560
            )

            // La vignette : les bords se referment.
            RadialGradient(
                colors: [
                    Color.black.opacity(0),
                    Color.black.opacity(isDark ? 0.35 : 0.05),
                ],
                center: .center,
                startRadius: 340,
                endRadius: 1100
            )
        }
        .ignoresSafeArea()
        .onAppear {
            guard motion else { return }
            withAnimation(PulseonMotion.breath) { breath = 0.72 }
        }
    }
}

/// Le titre d'une carte.
///
/// Il était au même poids que le texte courant, donc les cartes n'avaient pas
/// de tête : on lisait une liste de lignes sans savoir où commençait chaque
/// rubrique. Les capitales espacées sont écartées — la skill de dessin les
/// range parmi les tentations « pour faire technique » qui ont déjà été
/// rejetées une fois.
struct CardTitle: View {
    let text: String
    let palette: PulseonPalette

    @Environment(\.pulseonSkin) private var skin

    init(_ text: String, palette: PulseonPalette) {
        self.text = text
        self.palette = palette
    }

    var body: some View {
        Text(text)
            .font(skin.blockTitle)
            // En éditorial, le titre porte l'or : sans cadre autour du bloc,
            // c'est lui seul qui dit « nouvelle rubrique ».
            .foregroundStyle(skin.titleIsAccented ? palette.gold : palette.ink)
    }
}
