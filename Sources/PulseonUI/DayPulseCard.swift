import PulseonCore
import SwiftUI

/// Le battement de la journée : quand l'écran a été dense, quand il s'est tu.
///
/// **C'est le motif de l'icône, fait de vraies données.** Pulseon porte un
/// battement dans sa marque et dans le symbole de sa barre de menu, et ne
/// l'avait nulle part dans ses écrans. La carte lui rend ce qu'il désignait, et
/// répond au parti pris du projet mieux qu'un total : « Temps d'écran » dit
/// *combien*, ceci dit **quand**.
///
/// **C'est le seul endroit où la palette de l'icône entre dans l'app**, et
/// c'est une exception raisonnée. Le bleu et le violet sont ailleurs réservés à
/// la marque, l'or au temps mesuré à l'intérieur des écrans (voir
/// `PulseonTheme.markPulse`). Ici la **forme** est celle de la marque, donc elle
/// en porte les couleurs : ce n'est pas une teinte de plus dans le vocabulaire
/// des données, c'est la marque qui se montre une fois.
///
/// Ce que la courbe ne dit pas, et que la carte doit dire :
///
/// - **la PlayStation n'y est pas** (règle 1). Sans horaire, elle ne peut
///   occuper aucune tranche, et son absence se lirait comme un creux ;
/// - **une journée sans mesure ne dessine pas un plat.** Une ligne à zéro
///   affirmerait « aucun écran » là où le collecteur était éteint (règle 2).
struct DayPulseCard: View {
    let pulse: DayPulse
    let day: DayPresentation
    let palette: PulseonPalette

    var body: some View {
        Card(palette: palette) {
            VStack(alignment: .leading, spacing: PulseonSpace.snug) {
                HStack(alignment: .firstTextBaseline) {
                    CardTitle("Le battement", palette: palette)
                    Spacer()
                    if let peak = peakLabel {
                        Text(peak)
                            .font(PulseonTheme.caption)
                            .foregroundStyle(palette.inkFaint)
                    }
                }

                if pulse.isSilent {
                    // Pas de ligne plate : « rien de mesuré » n'est pas « zéro ».
                    Text("Rien de mesuré ce jour-là.")
                        .font(PulseonTheme.caption)
                        .foregroundStyle(palette.inkFaint)
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                } else {
                    PulseCurve(
                        intensities: pulse.intensities,
                        progress: day.nowOffset.map { $0 / day.dayLength },
                        palette: palette
                    )
                    .frame(height: 96)

                    HourRule(dayLength: day.dayLength, palette: palette)
                }

                if hasCounterSource {
                    // Court, parce que la carte « Déroulé » dit déjà la même
                    // exclusion juste au-dessus : deux phrases longues empilées
                    // se lisent comme un bégaiement.
                    Text("Sans horaire connu, la PlayStation n'y figure pas.")
                        .font(PulseonTheme.caption)
                        .foregroundStyle(palette.inkFaint)
                }
            }
        }
    }

    /// « le plus dense de 14:00 à 16:00 », ou rien.
    ///
    /// **Une fenêtre, pas un maximum.** Le premier jet affichait la tranche la
    /// plus haute — or une journée de travail en met vingt à 100 %, et le
    /// rendu annonçait « le plus dense vers 08:45 » pour une journée dont le
    /// cœur était l'après-midi. Trouvé en PNG, comme d'habitude.
    ///
    /// **Un fait, pas un jugement** (règle 7) : on dit quand la journée a été la
    /// plus dense, jamais si c'est bien ou mal.
    private var peakLabel: String? {
        guard let window = pulse.densestWindow(spanning: 2 * 3600) else { return nil }
        return "le plus dense de \(day.clockLabel(atOffset: window.start))"
            + " à \(day.clockLabel(atOffset: window.end))"
    }

    private var hasCounterSource: Bool {
        day.digest.lanes.contains { $0.kind == .counter && $0.total > 0 }
    }
}

/// La courbe elle-même.
///
/// **Lissée, et bornée à un maximum de 1.** Une courbe en escalier dessinerait
/// le pas d'échantillonnage ; une courbe qui dépasserait son cadre laisserait
/// croire à une intensité supérieure à « l'écran était allumé tout le
/// quart d'heure », ce qui n'existe pas.
struct PulseCurve: View {
    let intensities: [Double]
    /// Où en est la journée, de 0 à 1, ou nil sur une journée passée.
    ///
    /// **La tête de lecture n'existe que sur aujourd'hui** (règle 5) : une
    /// journée passée est entièrement jouée.
    let progress: Double?
    let palette: PulseonPalette

    @State private var drawn: Double = 1
    @Environment(\.pulseonMotion) private var motion

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let path = curve(in: size)

            ZStack(alignment: .leading) {
                // L'aire sous la courbe, qui donne du corps au trait. Sans
                // elle, une journée creuse ressemble à un fil perdu au milieu
                // d'une carte vide.
                area(in: size)
                    .fill(
                        LinearGradient(
                            colors: [
                                PulseonTheme.markViolet.opacity(0.38),
                                PulseonTheme.markBlue.opacity(0.05),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                path.stroke(
                    PulseonTheme.markPulse,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )

                if let progress {
                    // La tête de lecture, en `ink` et non en couleur d'accent :
                    // les teintes de la courbe portent la marque, celle-ci ne
                    // doit pas entrer en concurrence avec elles.
                    Rectangle()
                        .fill(palette.ink.opacity(0.35))
                        .frame(width: 1)
                        .offset(x: size.width * min(1, max(0, progress)))
                }
            }
            // Le tracé se révèle de la gauche vers la droite, dans le sens où
            // la journée s'est déroulée.
            .mask(alignment: .leading) {
                Rectangle().frame(width: size.width * drawn)
            }
        }
        .onAppear {
            guard motion else { return }
            drawn = 0
            withAnimation(PulseonMotion.trace) { drawn = 1 }
        }
    }

    /// Les points, lissés par des courbes cubiques dont les tangentes sont
    /// horizontales : le trait passe exactement par chaque valeur mesurée, sans
    /// jamais dépasser au-dessus d'un pic ni en dessous d'un creux — un lissage
    /// naïf inventerait des sommets qui n'ont pas eu lieu.
    private func curve(in size: CGSize) -> Path {
        Path { path in
            let points = self.points(in: size)
            guard let first = points.first else { return }
            path.move(to: first)
            for index in 1..<points.count {
                let previous = points[index - 1]
                let current = points[index]
                let midX = (previous.x + current.x) / 2
                path.addCurve(
                    to: current,
                    control1: CGPoint(x: midX, y: previous.y),
                    control2: CGPoint(x: midX, y: current.y)
                )
            }
        }
    }

    private func area(in size: CGSize) -> Path {
        var path = curve(in: size)
        guard let last = points(in: size).last, let first = points(in: size).first else {
            return path
        }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.addLine(to: CGPoint(x: first.x, y: size.height))
        path.closeSubpath()
        return path
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard intensities.count > 1 else { return [] }
        let step = size.width / CGFloat(intensities.count - 1)
        // Un plancher de deux points : une tranche non nulle mais minuscule
        // doit rester visible, sinon on affirme qu'elle n'a pas eu lieu. Même
        // raisonnement que le plancher des arcs de l'anneau.
        let floor: CGFloat = 2
        return intensities.enumerated().map { index, value in
            let height = value > 0 ? max(floor, CGFloat(value) * size.height) : 0
            return CGPoint(x: CGFloat(index) * step, y: size.height - height)
        }
    }
}

/// Les heures sous la courbe.
///
/// **Trois heures de pas**, comme la chronologie : une graduation à l'heure
/// donnerait vingt-quatre étiquettes dans une carte de 600 points, illisibles.
private struct HourRule: View {
    let dayLength: TimeInterval
    let palette: PulseonPalette

    private let step: TimeInterval = 3 * 3600

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(marks, id: \.self) { offset in
                    Text(label(offset))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(palette.inkFaint)
                        .fixedSize()
                        .alignmentGuide(.leading) { dimension in
                            // Les étiquettes des bords rentrent au lieu de
                            // déborder : « 00 » calé à gauche et « 21 » à
                            // droite, les autres centrées sur leur heure.
                            let fraction = offset / dayLength
                            return -geometry.size.width * fraction + dimension.width * fraction
                        }
                }
            }
        }
        .frame(height: 13)
    }

    private var marks: [TimeInterval] {
        stride(from: 0, to: dayLength, by: step).map { $0 }
    }

    private func label(_ offset: TimeInterval) -> String {
        String(format: "%02d", Int(offset) / 3600)
    }
}
