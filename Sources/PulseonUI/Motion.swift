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

    /// Le décompte des chiffres.
    ///
    /// **Plus court que le tracé, et volontairement.** Un compteur qui monte
    /// affiche des valeurs qui n'ont pas été mesurées — c'est acceptable le
    /// temps d'un geste, ça ne l'est plus si quelqu'un a le temps de lire un
    /// chiffre faux. Il n'est joué qu'à l'apparition, jamais sur les
    /// relectures : la barre de menu, elle, ne compte jamais.
    public static let count = Animation.easeOut(duration: 0.5)
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
