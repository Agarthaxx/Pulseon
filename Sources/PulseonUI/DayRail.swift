import PulseonCore
import SwiftUI

/// La journée sur un rail unique : l'élément signature de Pulseon.
///
/// « Temps d'écran » dit *combien*. Ceci dit **quand**, et montre ce qu'un total
/// ne dira jamais — les trous, et les moments où deux écrans tournaient
/// ensemble.
///
/// Remplace la version en multipiste (une piste par appareil), qui devenait
/// illisible dès le troisième écran. Voir `RailLayout` pour le pourquoi et le
/// comment du découpage.
public struct DayRail: View {
    private let day: DayPresentation

    /// Assez haut pour se diviser en trois sans que les bandes deviennent des
    /// cheveux, assez bas pour rester une ligne et non un graphique.
    private let railHeight: CGFloat = 46

    public init(day: DayPresentation) {
        self.day = day
    }

    private var segments: [RailSegment] { RailLayout.segments(from: day.digest.lanes) }

    /// Les sources qui ont du temps mais aucun horaire. Elles ne peuvent pas
    /// être sur le rail : y placer un bloc serait inventer une heure.
    private var unplaced: [Lane] {
        day.digest.lanes.filter { $0.kind == .counter && $0.isConnected && $0.total > 0 }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let geometry = TimelineGeometry(width: proxy.size.width, dayLength: day.dayLength)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: PulseonTheme.railRadius, style: .continuous)
                        .fill(PulseonTheme.surfaceSunken)

                    ForEach(segments) { segment in
                        SegmentView(segment: segment, geometry: geometry, railHeight: railHeight)
                    }
                }
                .clipShape(
                    RoundedRectangle(cornerRadius: PulseonTheme.railRadius, style: .continuous)
                )
                .overlay(alignment: .topLeading) {
                    // Le marqueur dépasse volontairement du rail : c'est ce qui
                    // le rend visible sans avoir besoin d'être épais.
                    if let offset = day.nowOffset {
                        NowMarker(height: railHeight)
                            .offset(x: geometry.x(atOffset: offset) - 0.75, y: -5)
                    }
                }
            }
            .frame(height: railHeight)

            HourAxis(dayLength: day.dayLength)

            if !unplaced.isEmpty {
                UnplacedSection(lanes: unplaced, dayLength: day.dayLength)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Un segment du rail

/// Un morceau de journée, divisé en hauteur autant de fois qu'il y avait
/// d'appareils actifs.
private struct SegmentView: View {
    let segment: RailSegment
    let geometry: TimelineGeometry
    let railHeight: CGFloat

    /// Marge haut/bas : le bloc ne touche pas le bord du rail, sinon il se
    /// confond avec lui.
    private let inset: CGFloat = 4
    private let gap: CGFloat = 2

    var body: some View {
        let rect = geometry.rect(offset: segment.startOffset, duration: segment.duration)
        let count = CGFloat(segment.devices.count)
        let slot = (railHeight - inset * 2 - gap * (count - 1)) / count

        ForEach(Array(segment.devices.enumerated()), id: \.element) { index, device in
            RoundedRectangle(cornerRadius: PulseonTheme.blockRadius, style: .continuous)
                .fill(PulseonTheme.color(for: device))
                .frame(width: rect.width, height: slot)
                .offset(x: rect.x, y: inset + (slot + gap) * CGFloat(index))
        }
    }
}

// MARK: - L'instant courant

/// Un trait fin surmonté d'un point, et rien d'autre.
///
/// L'ancienne tête de lecture portait un cartouche rouge vif avec l'heure : elle
/// attirait l'œil avant la donnée elle-même. L'heure est déjà écrite en haut de
/// l'écran, la répéter ici ne servait qu'à faire du bruit.
///
/// N'existe que sur aujourd'hui — une journée passée est entièrement jouée.
private struct NowMarker: View {
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(PulseonTheme.now)
                .frame(width: 1.5, height: height + 10)

            Circle()
                .fill(PulseonTheme.now)
                .frame(width: 5, height: 5)
                .offset(y: -2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Les heures

/// Les heures, écrites **une seule fois** sous le rail.
///
/// L'ancienne version graduait chaque piste : c'était la moitié du bruit visuel
/// de l'écran. Ici l'axe est rare et gris — assez pour situer un bloc, pas assez
/// pour se faire remarquer.
private struct HourAxis: View {
    let dayLength: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            let geometry = TimelineGeometry(width: proxy.size.width, dayLength: dayLength)
            ZStack(alignment: .topLeading) {
                ForEach(geometry.hourLabels(), id: \.self) { hour in
                    // Largeur fixe et centrée : un alignement dépendant de la
                    // largeur du texte décalerait « 6 h » de « 18 h ».
                    Text(label(hour))
                        .font(PulseonTheme.footnote)
                        .foregroundStyle(PulseonTheme.inkFaint)
                        .frame(width: tickWidth)
                        .offset(x: x(hour, in: geometry))
                }
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    private let tickWidth: CGFloat = 34

    private func label(_ hour: Int) -> String {
        hour == 0 ? "0 h" : "\(hour) h"
    }

    /// Rentre les deux extrémités dans le cadre plutôt que de les laisser
    /// déborder de la carte.
    private func x(_ hour: Int, in geometry: TimelineGeometry) -> CGFloat {
        let center = geometry.x(atOffset: TimeInterval(hour) * 3600) - tickWidth / 2
        if hour == 0 { return 0 }
        if hour == geometry.hourLabels().last { return geometry.width - tickWidth }
        return center
    }
}

// MARK: - Une source sans horaire

/// Les durées dont on ne connaît **que** la quantité.
///
/// Règle non négociable du projet : **ne jamais inventer de placement
/// horaire.** La largeur reste proportionnelle au temps, seule chose qu'on
/// sache ; tout le reste doit dire l'ignorance.
///
/// **Centrer le bloc ne suffit pas**, et ça s'est vu en PNG : centré juste sous
/// un axe des heures, il tombait pile sous « 12 h » et se lisait « joué vers
/// midi ». La position mentait quand même. D'où trois précautions cumulées :
///
/// - un **filet** et un **titre de section** qui coupent explicitement le lien
///   avec l'axe au-dessus ;
/// - le bloc **centré**, et son libellé centré *dessous* — jamais aligné sur un
///   bord, qui se lirait comme une heure de début ;
/// - un **contour pointillé** plutôt qu'un bloc plein, qui remplace les hachures
///   de la version précédente : même message, sans le vacarme des rayures.
private struct UnplacedSection: View {
    let lanes: [Lane]
    let dayLength: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle()
                .fill(PulseonTheme.hairline)
                .frame(height: 1)
                .padding(.top, 4)

            Text("Sans horaire connu")
                .font(PulseonTheme.footnote)
                .foregroundStyle(PulseonTheme.inkFaint)

            ForEach(lanes, id: \.device) { lane in
                UnplacedBar(lane: lane, dayLength: dayLength)
            }
        }
    }
}

private struct UnplacedBar: View {
    let lane: Lane
    let dayLength: TimeInterval

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let geometry = TimelineGeometry(width: proxy.size.width, dayLength: dayLength)
                let rect = geometry.rect(offset: 0, duration: lane.total)
                let shape = RoundedRectangle(
                    cornerRadius: PulseonTheme.blockRadius + 1, style: .continuous
                )

                shape
                    // Fond neutre et non une teinte translucide : de la couleur
                    // à 18 % sur une carte sombre donne un olive sale, le même
                    // défaut que l'échelle d'opacité entre appareils.
                    .fill(PulseonTheme.surfaceSunken)
                    .overlay {
                        shape.strokeBorder(
                            PulseonTheme.color(for: lane.device),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                    }
                    .frame(width: rect.width)
                    .offset(x: (geometry.width - rect.width) / 2)
            }
            .frame(height: 22)

            Text("\(lane.device.label) · \(DurationFormat.long(lane.total)) · heure inconnue")
                .font(PulseonTheme.footnote)
                .foregroundStyle(PulseonTheme.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(lane.device.label), \(DurationFormat.long(lane.total)), heure inconnue"
        )
    }
}
