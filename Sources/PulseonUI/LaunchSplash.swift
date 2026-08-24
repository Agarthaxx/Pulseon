import SwiftUI

/// L'écran de lancement : la marque, son nom, et une barre qui se remplit.
///
/// **Demandé par Arthur le 2026-08-24** — « ce serait cool au lancement de
/// l'app, une animation de chargement avec le logo et une barre de
/// chargement ».
///
/// **Il ne se joue pas au démarrage du processus, et c'est la seule place
/// possible.** Pulseon est un agent de barre de menu : il démarre à l'ouverture
/// de session, sans fenêtre, souvent des jours avant qu'on le regarde. Un
/// écran de lancement au démarrage du processus serait dessiné pour personne.
/// Le vrai lancement, du point de vue de celui qui s'en sert, c'est **l'instant
/// où la fenêtre s'ouvre** — et c'est aussi le moment où la journée se lit sur
/// le disque, donc le seul où il y a réellement quelque chose à couvrir.
///
/// **La barre ne mesure rien**, et il faut le savoir plutôt que de le
/// découvrir : elle suit une horloge, pas un travail. C'est la seule chose de
/// cette app qui bouge sans rien mesurer, et elle en tire deux contraintes —
/// elle ne porte **aucun chiffre** (un pourcentage serait un chiffre inventé,
/// ce que le projet s'interdit partout), et elle est **courte**.
///
/// **Elle porte les couleurs de la marque, jamais l'or.** L'or désigne du temps
/// mesuré ; une barre de chargement ne mesure justement pas de temps. Même
/// raisonnement que pour le battement du jour, où la forme de la marque
/// autorise ses couleurs : ici c'est la marque elle-même qui se montre.
public struct LaunchSplash: View {
    private let palette: PulseonPalette
    private let scheme: ColorScheme

    public init(palette: PulseonPalette, scheme: ColorScheme) {
        self.palette = palette
        self.scheme = scheme
    }

    /// L'avancement de la barre. **Part à zéro, mais est posé à 1 dès la
    /// première image quand le mouvement est éteint** — même discipline que
    /// `Entrance` : hors de la fenêtre de l'app, le repli est « tout est
    /// dessiné », jamais « rien n'est dessiné ». Sans ça une preview sortirait
    /// une barre vide, qu'on lirait comme un bug de dessin.
    @State private var progress: Double = 0
    @State private var markIn = false
    @Environment(\.pulseonMotion) private var motion

    private let barWidth: CGFloat = 180

    public var body: some View {
        ZStack {
            PulseonBackground(palette: palette, scheme: scheme)

            VStack(spacing: PulseonSpace.card) {
                PulseonMark()
                    .frame(width: 96, height: 96)
                    // La marque grandit d'un rien : c'est ce qui la fait
                    // *arriver* au lieu d'être déjà là. Le battement qu'elle
                    // porte est dessiné, pas animé — une icône qui s'agite
                    // devient un logo animé, ce qui date une app plus vite
                    // qu'autre chose.
                    .scaleEffect(markIn ? 1 : 0.9)
                    .opacity(markIn ? 1 : 0)

                Text("Pulseon")
                    .font(.system(size: 30, weight: .semibold))
                    // Le nom respire, à l'inverse des titres de rubrique qui se
                    // resserrent : eux structurent une page dense, lui est seul
                    // au milieu du vide.
                    .tracking(1.5)
                    .foregroundStyle(palette.ink)
                    .opacity(markIn ? 1 : 0)

                bar
            }
        }
        .onAppear {
            guard motion else {
                progress = 1
                markIn = true
                return
            }
            withAnimation(PulseonMotion.launchMark) { markIn = true }
            withAnimation(PulseonMotion.launchBar) { progress = 1 }
        }
        // Pas de libellé sonore « chargement à 40 % » : il n'y a pas de
        // pourcentage, et l'écran ne dure qu'une seconde.
        .accessibilityLabel("Pulseon démarre")
    }

    /// La barre : un creux, et un remplissage qui court dedans.
    ///
    /// Trois points d'épaisseur, comme les jauges de l'éditoriale
    /// (`PulseonEditorial.meterHeight`) — c'est la même famille d'objet, et une
    /// barre plus épaisse ici ferait mentir toutes les autres sur leur
    /// importance.
    private var bar: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(palette.sunken)
                .frame(width: barWidth, height: PulseonEditorial.meterHeight)

            Capsule()
                .fill(PulseonTheme.markPulse)
                .frame(
                    width: barWidth * progress,
                    height: PulseonEditorial.meterHeight
                )
        }
        .frame(width: barWidth, alignment: .leading)
    }
}
