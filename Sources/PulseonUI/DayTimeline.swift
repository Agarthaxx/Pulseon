import PulseonCore
import SwiftUI

/// La journée en multipiste : une piste par appareil sur 24 h.
///
/// C'est l'élément signature de Pulseon. Le « Temps d'écran » d'Apple dit
/// *combien* ; ceci dit *quand*, et montre ce qu'un total en barres ne dira
/// jamais — les chevauchements, et les trous.
public struct DayTimeline: View {
    private let day: DayPresentation
    private let laneHeight: CGFloat = 34
    /// Assez large pour « PLAYSTATION » : une étiquette coupée en deux lignes
    /// casse l'alignement de toutes les pistes.
    private let labelWidth: CGFloat = 104

    public init(day: DayPresentation) {
        self.day = day
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { proxy in
                let geometry = TimelineGeometry(
                    width: proxy.size.width - labelWidth,
                    dayLength: day.dayLength
                )

                VStack(alignment: .leading, spacing: 0) {
                    HourRuler(geometry: geometry, labelWidth: labelWidth)

                    ForEach(day.digest.lanes, id: \.device) { lane in
                        LaneRow(
                            lane: lane,
                            geometry: geometry,
                            labelWidth: labelWidth,
                            height: laneHeight
                        )
                    }
                }
                .overlay(alignment: .topLeading) {
                    // La tête de lecture par-dessus toutes les pistes : c'est
                    // elle qui rend la journée *en cours* plutôt que finie.
                    if let offset = day.nowOffset {
                        Playhead(
                            x: labelWidth + geometry.x(atOffset: offset),
                            label: day.nowLabel,
                            height: rulerHeight + laneHeight * CGFloat(day.digest.lanes.count)
                        )
                    }
                }
            }
            .frame(height: rulerHeight + laneHeight * CGFloat(day.digest.lanes.count))
        }
        .padding(14)
        .background(PulseonTheme.rack)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private let rulerHeight: CGFloat = 22
}

// MARK: - La règle des heures

private struct HourRuler: View {
    let geometry: TimelineGeometry
    let labelWidth: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(geometry.hourTicks(), id: \.self) { hour in
                let x = geometry.x(atOffset: TimeInterval(hour) * 3600)
                // Largeur fixe et centrée : c'est ce qui garantit qu'une
                // graduation tombe pile au-dessus de son heure. Un alignement
                // dépendant de la largeur du texte décale « 8 » de « 10 ».
                Text("\(hour)")
                    .font(PulseonTheme.stencil)
                    .foregroundStyle(PulseonTheme.rackTextMuted)
                    .frame(width: tickWidth)
                    // Les extrémités rentrent dans le cadre au lieu de déborder.
                    .offset(x: labelWidth + x - tickWidth / 2 + edgeNudge(hour))
            }
        }
        .frame(height: 22, alignment: .top)
    }

    private let tickWidth: CGFloat = 22

    /// Rentre les deux graduations extrêmes dans le cadre.
    private func edgeNudge(_ hour: Int) -> CGFloat {
        if hour == 0 { return tickWidth / 2 }
        if hour == geometry.hourTicks().last { return -tickWidth / 2 }
        return 0
    }
}

// MARK: - Une piste

private struct LaneRow: View {
    let lane: Lane
    let geometry: TimelineGeometry
    let labelWidth: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Text(lane.device.label.uppercased())
                .font(PulseonTheme.stencil)
                .tracking(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(
                    lane.isConnected ? PulseonTheme.rackText : PulseonTheme.rackTextMuted
                )
                .frame(width: labelWidth, alignment: .leading)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(PulseonTheme.lane)
                    // Pas de graduations sous une source sans horaire : une
                    // grille horaire donnerait un sens à une position qui n'en
                    // a aucun.
                    .overlay { if lane.kind == .interval { HourGrid(geometry: geometry) } }

                content
            }
            .frame(height: height - 6)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var content: some View {
        if !lane.isConnected {
            // « Pas encore branchée » n'est pas « journée à zéro », et l'UI ne
            // doit jamais laisser confondre les deux.
            Text("pas encore branchée")
                .font(PulseonTheme.stencil)
                .foregroundStyle(PulseonTheme.rackTextMuted)
                .padding(.leading, 8)
        } else if lane.kind == .counter {
            CounterBlock(lane: lane, geometry: geometry)
        } else {
            ForEach(Array(lane.blocks.enumerated()), id: \.offset) { _, block in
                let rect = geometry.rect(
                    offset: block.startOffset, duration: block.duration
                )
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(PulseonTheme.color(for: lane.device))
                    .frame(width: rect.width)
                    .offset(x: rect.x)
            }
        }
    }

    private var accessibilityText: String {
        guard lane.isConnected else { return "\(lane.device.label), pas encore branchée" }
        return "\(lane.device.label), \(DurationFormat.long(lane.total))"
    }
}

/// Les graduations, tracées dans la piste et pas au-dessus : on situe un bloc
/// dans sa journée sans avoir à remonter à la règle.
private struct HourGrid: View {
    let geometry: TimelineGeometry

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(geometry.hourTicks().dropFirst().dropLast(), id: \.self) { hour in
                Rectangle()
                    .fill(PulseonTheme.grid)
                    .frame(width: 1)
                    .offset(x: geometry.x(atOffset: TimeInterval(hour) * 3600))
            }
        }
        // Sans ça, la grille est fausse et rien ne le signale : un ZStack de
        // rectangles d'un point ne mesure qu'un point de large, et l'`overlay`
        // le centre dans la piste. Les graduations partaient donc de midi, et
        // toute la matinée n'en avait aucune.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Une source à compteur : la quantité est connue, l'heure ne l'est pas.
///
/// Règle non négociable du projet — **ne jamais inventer de placement
/// horaire**. La largeur reste proportionnelle au temps joué, seule chose
/// qu'on sache, mais tout le reste dit l'ignorance :
///
/// - **le bloc est centré**, jamais calé à gauche. Collé au bord, il se lisait
///   « joué de minuit à 1 h 48 » — une invention pure, et la première version
///   de cette vue la commettait ;
/// - les hachures le distinguent d'un bloc horodaté ;
/// - le libellé le dit en toutes lettres, à côté du bloc plutôt que dedans
///   pour rester lisible même quand le temps joué est court.
private struct CounterBlock: View {
    let lane: Lane
    let geometry: TimelineGeometry

    var body: some View {
        let rect = geometry.rect(offset: 0, duration: lane.total)
        HStack(spacing: 8) {
            Hatching(color: PulseonTheme.color(for: lane.device))
                .frame(width: rect.width)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))

            Text("heure inconnue")
                .font(PulseonTheme.stencil)
                .foregroundStyle(PulseonTheme.rackTextMuted)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct Hatching: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(0.22)))
            let step: CGFloat = 7
            var x: CGFloat = -size.height
            while x < size.width {
                var line = Path()
                line.move(to: CGPoint(x: x, y: size.height))
                line.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(line, with: .color(color.opacity(0.85)), lineWidth: 2)
                x += step
            }
        }
        .drawingGroup()
    }
}

// MARK: - La tête de lecture

/// L'heure courante, traversant toutes les pistes.
///
/// Elle n'apparaît que sur aujourd'hui : une journée passée est entièrement
/// jouée, y planter une tête de lecture ne voudrait rien dire.
private struct Playhead: View {
    let x: CGFloat
    let label: String
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(PulseonTheme.playhead)
                .frame(width: 1.5, height: height)

            Text(label)
                .font(PulseonTheme.stencil)
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(PulseonTheme.playhead, in: RoundedRectangle(cornerRadius: 3))
                .fixedSize()
        }
        .offset(x: x - 0.75)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
