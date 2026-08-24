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
/// Quatre couches, et chacune répond à un défaut constaté :
///
/// - **un dégradé vertical**, du plus clair en haut au plus profond en bas :
///   c'est lui qui donne au fond un haut et un bas, donc une page. Sans lui, le
///   clair se lisait « blanc blanc » (Arthur, 2026-08-24) et le sombre était un
///   aplat que seuls les halos venaient troubler ;
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

    /// L'intensité du fond.
    ///
    /// L'éditoriale s'appuie sur le vide, donc son fond est plus discret que
    /// celui des directions à cartes : sans cadre pour retenir le regard, un
    /// halo trop présent devient l'élément le plus visible de la page.
    private let depth: Double = 0.75

    public var body: some View {
        ZStack {
            // Le fond n'est pas une couleur mais une lumière : le dégradé
            // porte la variation, les halos ne font que la troubler.
            palette.groundGradient

            // Le halo derrière l'anneau : le héros de l'écran se détachait
            // sur un fond plat, donc il flottait au lieu d'être posé.
            //
            // **Il ne bat plus, et c'est une correction mesurée.** Il portait le
            // pouls de la marque, animé en boucle sans fin — invisible par
            // construction (« un halo qu'on remarque est un halo qui
            // distrait »), et il coûtait **la moitié d'un cœur en permanence**
            // dès qu'une fenêtre était ouverte : 47 % relevés sur l'app
            // installée le 2026-08-24, contre 2 % une fois l'animation retirée.
            //
            // La cause n'est ni ce dégradé ni la taille de l'écran, et les deux
            // ont été éliminés au banc (`Bench idle`) : isoler le halo dans sa
            // propre vue, figer son rayon, le passer en `drawingGroup` — aucun
            // effet. **Un point de 8 px animé seul dans une fenêtre vide coûte
            // le même cœur entier.** Ce qui coûte, c'est qu'une animation sans
            // fin tient le cycle d'affichage éveillé pour toujours.
            //
            // Même jugement que le `lastSeen` en base : aucun risque, mais
            // indéfendable pour un agent censé tourner discrètement toute la
            // journée. Une décoration qu'on ne voit pas ne vaut pas la moitié
            // d'un cœur.
            RadialGradient(
                colors: [
                    palette.navy.opacity((isDark ? 0.20 : 0.07) * depth),
                    palette.navy.opacity(0),
                ],
                center: UnitPoint(x: 0.5, y: 0.06),
                startRadius: 0,
                endRadius: 620
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


    init(_ text: String, palette: PulseonPalette) {
        self.text = text
        self.palette = palette
    }

    var body: some View {
        Text(text)
            .font(PulseonTheme.blockTitle)
            // Un titre gras et large se resserre : sans quoi il paraît étalé,
            // ce qui est exactement ce qui fait « gabarit » plutôt que « composé ».
            .tracking(-0.4)
            // Le titre porte l'or : sans cadre autour du bloc, c'est lui seul
            // qui dit « nouvelle rubrique ». L'or cesse d'être décoratif, il
            // structure.
            .foregroundStyle(palette.gold)
    }
}
