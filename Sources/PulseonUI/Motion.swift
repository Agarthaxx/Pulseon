import SwiftUI

/// Le mouvement de Pulseon, et **le sens dans lequel il a le droit d'échouer**.
///
/// Arthur, le 2026-08-24 : l'app « fait figé, pas fini ». C'était vrai au
/// pied de la lettre — pas une seule animation dans tout `PulseonUI`. Un anneau
/// apparaissait d'un bloc, une journée en remplaçait une autre par saut.
///
/// **La valeur par défaut est `false`, et c'est la décision qui compte ici.**
/// Une animation d'apparition part d'un état vide : anneau à zéro, chiffre à
/// zéro. Or `ImageRenderer` rend une image **synchrone**, sans faire avancer
/// une seule frame — donc une preview capturerait cet état de départ et
/// sortirait un anneau vide. On croirait à un bug de dessin alors que la vue
/// est simplement au premier instant de son animation, et on perdrait l'outil
/// qui trouve la plupart des vrais défauts de ce projet.
///
/// En partant de `false`, le repli est **« tout est dessiné »**, jamais
/// « rien n'est dessiné ». Même discipline que partout ailleurs : un doute se
/// résout du côté qui montre ce qui a été mesuré. Seule la fenêtre de l'app
/// allume le mouvement.
private struct MotionKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    /// Vrai quand les vues ont le droit de s'animer à l'apparition.
    ///
    /// Passe par l'environnement et non en paramètre : le mouvement concerne
    /// des vues imbriquées loin sous les écrans, et les traverser toutes avec
    /// un argument de plus rendrait chaque vue intermédiaire dépendante d'une
    /// chose qu'elle n'utilise pas — même raison que `appIcons`.
    public var pulseonMotion: Bool {
        get { self[MotionKey.self] }
        set { self[MotionKey.self] = newValue }
    }
}

public enum PulseonMotion {
    /// L'enroulement de l'anneau.
    ///
    /// Assez lent pour se voir, assez court pour ne pas retarder la lecture du
    /// chiffre : c'est une app qu'on ouvre pour savoir, pas pour regarder une
    /// animation. `easeOut` et non `easeInOut` — le tracé part vite et se pose,
    /// ce qui donne l'impression d'un geste et non d'une barre de chargement.
    public static let draw = Animation.easeOut(duration: 0.65)

    /// Le passage d'une journée à l'autre.
    public static let slide = Animation.easeInOut(duration: 0.28)

    /// Le tracé du battement, de la gauche vers la droite.
    ///
    /// Plus long que l'anneau, et c'est voulu : une courbe qui se révèle est
    /// une journée qui se rejoue, donc elle a le droit de prendre son temps.
    public static let trace = Animation.easeInOut(duration: 0.9)

    /// Le décompte des chiffres.
    ///
    /// **Plus court que le tracé, et volontairement.** Un compteur qui monte
    /// affiche des valeurs qui n'ont pas été mesurées — c'est acceptable le
    /// temps d'un geste, ça ne l'est plus si quelqu'un a le temps de lire un
    /// chiffre faux. Il n'est joué qu'à l'apparition, jamais sur les
    /// relectures : la barre de menu, elle, ne compte jamais.
    public static let count = Animation.easeOut(duration: 0.5)

    /// L'entrée en cascade des cartes.
    ///
    /// Chaque carte arrive légèrement après la précédente, en montant de
    /// quelques points. **C'est ce décalage qui se lit « haut de gamme »** : des
    /// cartes qui apparaissent toutes ensemble se lisent comme un écran qui se
    /// charge, des cartes qui arrivent l'une après l'autre se lisent comme un
    /// écran qui se compose.
    public static let entrance = Animation.spring(response: 0.5, dampingFraction: 0.85)

    /// Le retard ajouté par rang de carte.
    ///
    /// 60 ms : en dessous la cascade ne se perçoit plus, au-dessus la dernière
    /// carte se fait attendre. Bornée à six rangs — au-delà, l'écran met plus
    /// d'une demi-seconde à finir de se poser, et on attend l'app au lieu de la
    /// lire.
    public static func entranceDelay(rank: Int) -> Double { Double(min(rank, 6)) * 0.06 }

    /// Le remplissage des jauges.
    public static let fill = Animation.easeOut(duration: 0.7)

    // MARK: L'écran de lancement

    /// La barre de chargement.
    ///
    /// **Elle ne mesure rien, et c'est précisément pour ça qu'elle dure peu.**
    /// Une barre qui prétend suivre un travail alors qu'elle suit une horloge
    /// serait un chiffre inventé, ce que ce projet s'interdit partout ailleurs.
    /// Ici elle n'annonce aucune quantité : elle occupe le temps que la fenêtre
    /// met à s'ouvrir et la journée à se lire, et rien de plus. `easeInOut`
    /// plutôt qu'`easeOut` — une barre part et se pose, contrairement au tracé
    /// de l'anneau, qui est un geste.
    public static let launchBar = Animation.easeInOut(duration: 0.95)

    /// L'arrivée de la marque : elle grandit d'un rien en apparaissant.
    public static let launchMark = Animation.spring(response: 0.55, dampingFraction: 0.82)

    /// Le fondu vers le dashboard.
    public static let launchFade = Animation.easeOut(duration: 0.35)

    /// Combien de temps l'écran de lancement reste avant de s'effacer.
    ///
    /// Un peu plus que la barre, pour qu'on la voie finir : une barre coupée
    /// avant son terme se lit comme un écran qui a sauté.
    public static let launchHold: TimeInterval = 1.1

    // **Aucune animation perpétuelle ici, et c'est une règle, pas un oubli.**
    // Le halo du fond battait en boucle (`repeatForever`) : ça coûtait la
    // moitié d'un cœur en permanence dès qu'une fenêtre était ouverte — 47 %
    // relevés sur l'app installée le 2026-08-24, 2 % une fois retiré. Le coût
    // ne vient pas de ce qui est animé (un point de 8 px seul dans une fenêtre
    // vide coûte autant) mais du fait qu'une animation sans fin tient le cycle
    // d'affichage éveillé pour toujours. **Tout mouvement de Pulseon se joue
    // une fois, à l'apparition, puis se tait.**
}

/// Un nombre qui monte jusqu'à sa valeur.
///
/// `Text` ne s'interpole pas tout seul — SwiftUI ne sait pas animer entre deux
/// chaînes. `Animatable` fait le travail : SwiftUI interpole `animatableData`
/// et redemande le corps à chaque image, ce qui reconstruit le texte.
struct AnimatedReadout: View, Animatable {
    var total: TimeInterval
    let size: CGFloat
    let palette: PulseonPalette

    // `nonisolated` : `View` porte l'isolation au fil principal, or SwiftUI
    // interpole `animatableData` depuis son propre moteur d'animation. Sans
    // ça, Swift 6 refuse la conformance à `Animatable`.
    nonisolated var animatableData: Double {
        get { total }
        set { total = newValue }
    }

    var body: some View {
        DurationReadout(total: total, size: size, palette: palette)
    }
}

/// L'entrée en cascade d'une carte.
///
/// Un modificateur plutôt qu'un état dans chaque vue : les cartes n'ont pas à
/// savoir qu'elles sont animées, ni à quel rang elles arrivent — c'est l'écran
/// qui compose, donc c'est lui qui numérote.
struct Entrance: ViewModifier {
    let rank: Int
    @State private var shown = false
    @Environment(\.pulseonMotion) private var motion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                // Sans mouvement, la carte est là dès la première image : le
                // repli est « tout est dessiné ». Voir `PulseonMotion`.
                guard motion else {
                    shown = true
                    return
                }
                withAnimation(PulseonMotion.entrance.delay(PulseonMotion.entranceDelay(rank: rank))) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Fait entrer la vue en cascade, à son rang dans l'écran.
    public func entrance(rank: Int) -> some View {
        modifier(Entrance(rank: rank))
    }
}

/// Vers où va la navigation, pour que la journée glisse **dans le sens du
/// geste**.
///
/// Sans direction, les deux sens produisent la même transition et on perd
/// l'information la plus utile de l'animation : est-ce que je recule ou est-ce
/// que j'avance ?
public enum SlideDirection: Sendable {
    case backward
    case forward

    public var transition: AnyTransition {
        switch self {
        case .backward:
            .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        case .forward:
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        }
    }
}
