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
    public struct Segment: Identifiable, Sendable {
        public let id: String
        public let value: TimeInterval
        public let color: Color

        public init(id: String, value: TimeInterval, color: Color) {
            self.id = id
            self.value = value
            self.color = color
        }
    }

    private let segments: [Segment]
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
        diameter: CGFloat = 208
    ) {
        self.segments = segments
        self.total = total
        self.caption = caption
        self.palette = palette
        self.diameter = diameter
    }

    private var thickness: CGFloat { diameter * 0.105 }

    public var body: some View {
        ZStack {
            // La piste : la journée reste lisible même quand rien n'a été
            // mesuré, au lieu d'un vide qu'on prendrait pour un bug d'affichage.
            Circle()
                .stroke(palette.sunken, lineWidth: thickness)

            let arcs = RingLayout.arcs(for: segments.map(\.value))
            ForEach(Array(zip(segments, arcs)), id: \.0.id) { segment, arc in
                if let arc {
                    Circle()
                        .trim(from: arc.start, to: arc.end)
                        .stroke(
                            segment.color,
                            style: StrokeStyle(lineWidth: thickness, lineCap: .butt)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }

            center
        }
        .frame(width: diameter, height: diameter)
    }

    @ViewBuilder
    private var center: some View {
        VStack(spacing: 3) {
            if let total {
                DurationReadout(total: total, size: diameter * 0.185, palette: palette)
            } else {
                Text("—")
                    .font(PulseonTheme.readout(diameter * 0.185))
                    .foregroundStyle(palette.inkFaint)
            }
            Text(caption)
                .font(PulseonTheme.caption)
                .foregroundStyle(palette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, thickness * 1.4)
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
