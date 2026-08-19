import PulseonCore
import SwiftUI

/// L'anneau de la journée : de quoi le temps était fait.
///
/// **Ce n'est pas un anneau de progression.** Il ne se remplit pas vers un
/// objectif — il fait toujours le tour, et ses arcs sont des parts. La maquette
/// d'Arthur portait un « / 5h Daily Goal » et un badge « On Track » ; ils ont
/// été retirés à sa demande, la règle « aucune comparaison ne juge » ayant été
/// confirmée en même temps que la direction visuelle. Le dessin est gardé, le
/// jugement non.
public struct ActivityRing: View {
    public struct Segment: Identifiable {
        public let id: String
        public let value: TimeInterval
        /// Les teintes de l'arc, de la plus claire à la plus sombre.
        ///
        /// **Un dégradé *angulaire*, pas linéaire.** Un dégradé linéaire ne se
        /// voit que d'un arc à l'autre : sur une journée à un seul appareil —
        /// le cas normal chez Arthur — l'anneau redevenait un aplat uni. Le
        /// dégradé suit maintenant la courbe, donc il balaie même un cercle
        /// entier d'une seule couleur.
        public let tones: [Color]

        public init(id: String, value: TimeInterval, tones: [Color]) {
            self.id = id
            self.value = value
            self.tones = tones
        }
    }

    private let segments: [Segment]
    /// Un second anneau, à l'intérieur du premier. Vide par défaut.
    ///
    /// **Deux lectures du même temps dans une seule forme** : l'extérieur dit
    /// *sur quel écran*, l'intérieur dit *à quoi*. Le même instant se lit « sur
    /// le Mac » et « à coder » sans changer d'objet à l'écran.
    private let innerSegments: [Segment]
    private let total: TimeInterval?
    private let caption: String
    private let palette: PulseonPalette
    private let diameter: CGFloat

    /// - Parameter total: nil quand la lecture a échoué. Le centre affiche
    ///   alors un tiret : zéro serait une affirmation, et on ne sait pas.
    public init(
        segments: [Segment],
        total: TimeInterval?,
        caption: String,
        palette: PulseonPalette,
        diameter: CGFloat = 208,
        innerSegments: [Segment] = []
    ) {
        self.segments = segments
        self.innerSegments = innerSegments
        self.total = total
        self.caption = caption
        self.palette = palette
        self.diameter = diameter
    }

    private var thickness: CGFloat { diameter * 0.125 }

    /// L'écart entre les deux anneaux. Il ne décore pas : collés, les deux se
    /// lisent comme un seul anneau épais à deux tons, et la double lecture
    /// disparaît.
    private var gap: CGFloat { thickness * 0.34 }

    private var innerDiameter: CGFloat { diameter - 2 * thickness - 2 * gap }

    /// Plus fin que l'extérieur : c'est ce qui dit lequel des deux est le
    /// premier niveau de lecture. Deux anneaux de même épaisseur se
    /// concurrenceraient.
    private var innerThickness: CGFloat { innerDiameter * 0.105 }

    /// Ce qu'il reste au centre pour écrire, une fois les deux anneaux posés.
    private var coreDiameter: CGFloat {
        innerSegments.isEmpty ? diameter - 2 * thickness : innerDiameter - 2 * innerThickness
    }

    public var body: some View {
        ZStack {
            // La piste : la journée reste lisible même quand rien n'a été
            // mesuré, au lieu d'un vide qu'on prendrait pour un bug
            // d'affichage.
            Ring(
                segments: segments,
                thickness: thickness,
                track: palette.sunken,
                palette: palette
            )

            if !innerSegments.isEmpty {
                Ring(
                    segments: innerSegments,
                    thickness: innerThickness,
                    // Pas de piste creuse pour l'anneau intérieur : deux
                    // creux concentriques feraient une cible, et le fond
                    // suffit à le poser.
                    track: nil,
                    palette: palette
                )
                .frame(width: innerDiameter, height: innerDiameter)
            }

            center
        }
        .frame(width: diameter, height: diameter)
        // L'ombre ne décore pas : elle décolle l'anneau de la carte, sans quoi
        // les deux se lisent comme un seul aplat.
        .shadow(color: palette.shadow.opacity(0.5), radius: 18, y: 6)
    }

    /// Assez grand pour rester le premier élément lu, assez petit pour ne pas
    /// toucher l'anneau qui l'entoure — d'où un calcul sur la place libre et
    /// non sur le diamètre total.
    private var readoutSize: CGFloat { coreDiameter * 0.30 }

    @ViewBuilder
    private var center: some View {
        VStack(spacing: 3) {
            if let total {
                DurationReadout(total: total, size: readoutSize, palette: palette)
            } else {
                Text("—")
                    .font(PulseonTheme.readout(readoutSize))
                    .foregroundStyle(palette.inkFaint)
            }
            Text(caption)
                .font(PulseonTheme.caption)
                .foregroundStyle(palette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: coreDiameter * 0.92)
    }
}

/// Une durée en grand, l'unité en petit et en gris.
///
/// C'est le traitement de la maquette (« 3h 42m »), et il demande un
/// `baselineOffset` : partageant la ligne de base des grands chiffres, l'unité
/// tomberait sinon tout en bas et se lirait comme un indice de formule
/// chimique.
public struct DurationReadout: View {
    private let total: TimeInterval
    private let size: CGFloat
    private let palette: PulseonPalette

    public init(total: TimeInterval, size: CGFloat, palette: PulseonPalette) {
        self.total = total
        self.size = size
        self.palette = palette
    }

    public var body: some View {
        // Tronqué, jamais arrondi : afficher 1 h à 59 min 40 annoncerait du
        // temps qui n'a pas eu lieu.
        let seconds = Int(max(0, total))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        HStack(alignment: .firstTextBaseline, spacing: 1) {
            if hours > 0 {
                number(hours)
                unit("h")
                if minutes > 0 { number(minutes, padded: true) }
            } else {
                number(minutes)
                unit("m")
            }
        }
    }

    private func number(_ value: Int, padded: Bool = false) -> some View {
        Text(padded ? String(format: "%02d", value) : String(value))
            .font(PulseonTheme.readout(size))
            .foregroundStyle(palette.ink)
    }

    private func unit(_ symbol: String) -> some View {
        Text(symbol)
            .font(PulseonTheme.unit(size * 0.42))
            .baselineOffset(size * 0.06)
            .foregroundStyle(palette.inkSoft)
            .padding(.trailing, 2)
    }
}

/// Un anneau d'arcs, sans centre écrit.
///
/// Extrait pour servir les deux couronnes du double anneau : le même découpage
/// (`RingLayout`), les mêmes précautions de dessin, à deux diamètres. Les
/// recopier aurait fait diverger deux dessins censés être le même.
private struct Ring: View {
    let segments: [ActivityRing.Segment]
    let thickness: CGFloat
    /// La piste creuse derrière les arcs, ou nil pour ne pas en poser. La
    /// journée reste ainsi lisible même quand rien n'a été mesuré, au lieu d'un
    /// vide qu'on prendrait pour un bug d'affichage.
    let track: Color?
    let palette: PulseonPalette

    var body: some View {
        ZStack {
            if let track {
                Circle().stroke(track, lineWidth: thickness)
            }

            let arcs = RingLayout.arcs(for: segments.map(\.value))

            // Les arcs sont posés du dernier au premier pour que l'extrémité
            // arrondie de chacun passe **sous** son voisin de gauche : dessinés
            // dans l'ordre, les capuchons se chevaucheraient à l'endroit et
            // chaque jointure porterait une bosse.
            ForEach(Array(zip(segments, arcs)).reversed(), id: \.0.id) { segment, arc in
                if let arc {
                    Circle()
                        .trim(from: arc.start, to: arc.end)
                        .stroke(
                            // Le dégradé est calé sur le tour entier, pas sur
                            // l'arc : deux arcs voisins de la même couleur se
                            // raccordent sans marche, et le balayage reste
                            // continu quel que soit le découpage.
                            AngularGradient(
                                gradient: Gradient(colors: segment.tones + [segment.tones[0]]),
                                center: .center
                            ),
                            style: StrokeStyle(
                                lineWidth: thickness,
                                // Arrondi, comme la maquette. Sur un arc unique
                                // qui fait tout le tour, `.round` n'a aucun
                                // effet visible.
                                lineCap: .round
                            )
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
        }
    }
}
