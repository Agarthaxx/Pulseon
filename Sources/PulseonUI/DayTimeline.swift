import PulseonCore
import SwiftUI

/// La chronologie de la journée : l'écran 4 de la maquette.
///
/// **C'est le parti pris du projet rendu visible.** « Temps d'écran » dit
/// *combien* ; ceci dit **quand**, et montre ce qu'aucun total ne dira jamais —
/// les trous, et les moments où deux écrans tournaient ensemble.
///
/// Le dessin reprend celui de la PR #22, qui n'a jamais été mergée : son
/// raisonnement était juste, seule sa direction visuelle a été écartée. Il est
/// donc reporté ici sur la palette de la maquette d'Arthur.
///
/// **Un rail unique, jamais une piste par appareil** (voir `RailLayout`) : une
/// piste par appareil s'écroule au troisième écran, et c'est une règle
/// structurelle du projet, pas une préférence.
public struct DayTimeline: View {
    private let load: DayDashboard.Load
    private let canGoForward: Bool
    private let onPrevious: () -> Void
    private let onNext: () -> Void
    private let onToday: () -> Void

    @Environment(\.colorScheme) private var scheme

    public init(
        load: DayDashboard.Load,
        canGoForward: Bool,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onToday: @escaping () -> Void
    ) {
        self.load = load
        self.canGoForward = canGoForward
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onToday = onToday
    }

    public var body: some View {
        ScrollView {
            DayTimelineContent(
                load: load,
                canGoForward: canGoForward,
                palette: PulseonTheme.palette(for: scheme),
                onPrevious: onPrevious,
                onNext: onNext,
                onToday: onToday
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PulseonTheme.palette(for: scheme).ground)
        .frame(minWidth: 560, minHeight: 460)
    }
}

/// Le contenu, rendable seul — `ImageRenderer` ne rend rien de l'intérieur d'un
/// `ScrollView`.
public struct DayTimelineContent: View {
    let load: DayDashboard.Load
    let canGoForward: Bool
    let palette: PulseonPalette
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onToday: () -> Void

    public init(
        load: DayDashboard.Load,
        canGoForward: Bool,
        palette: PulseonPalette,
        onPrevious: @escaping () -> Void = {},
        onNext: @escaping () -> Void = {},
        onToday: @escaping () -> Void = {}
    ) {
        self.load = load
        self.canGoForward = canGoForward
        self.palette = palette
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onToday = onToday
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch load {
            case .loaded(let day):
                header(title: day.title, isLive: day.now != nil)
                RailCard(day: day, palette: palette)
            case .failed(let reason):
                header(title: "Chronologie", isLive: false)
                FailureCard(reason: reason, palette: palette)
            }
        }
        .padding(22)
        .frame(maxWidth: DayDashboardContent.columnWidth)
        .frame(maxWidth: .infinity)
        .background(palette.ground)
    }

    @ViewBuilder
    private func header(title: String, isLive: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Chronologie")
                    .font(.system(size: 27, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(palette.ink)
                Text(isLive ? "Aujourd'hui · \(title)" : title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.inkSoft)
            }

            Spacer()

            if canGoForward {
                Button("Aujourd'hui", action: onToday)
                    .buttonStyle(.plain)
                    .font(PulseonTheme.caption)
                    .foregroundStyle(palette.gold)
            }

            HStack(spacing: 2) {
                NavButton(symbol: "chevron.left", palette: palette, action: onPrevious)
                NavButton(
                    symbol: "chevron.right",
                    palette: palette,
                    isEnabled: canGoForward,
                    action: onNext
                )
            }
        }
    }
}

// MARK: - Le rail

private struct RailCard: View {
    let day: DayPresentation
    let palette: PulseonPalette

    /// Assez haut pour se diviser en trois sans que les bandes deviennent des
    /// cheveux, assez bas pour rester une ligne et non un graphique.
    private let railHeight: CGFloat = 46

    private var segments: [RailSegment] { RailLayout.segments(from: day.digest.lanes) }

    /// Les appareils qui ont du temps et des horaires : ceux qu'on peut placer.
    private var placed: [Lane] {
        day.digest.lanes.filter { $0.kind == .interval && $0.total > 0 }
    }

    /// Les sources qui ont du temps mais **aucun horaire**. Elles ne peuvent pas
    /// être sur le rail : y placer un bloc serait inventer une heure.
    private var unplaced: [Lane] {
        day.digest.lanes.filter { $0.kind == .counter && $0.isConnected && $0.total > 0 }
    }

    var body: some View {
        Card(palette: palette) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Quand")
                    .font(PulseonTheme.sectionTitle)
                    .foregroundStyle(palette.inkSoft)

                if segments.isEmpty, unplaced.isEmpty {
                    EmptyDay(day: day, palette: palette)
                } else {
                    if !placed.isEmpty {
                        Legend(lanes: placed, palette: palette)
                    }

                    Rail(
                        day: day,
                        segments: segments,
                        railHeight: railHeight,
                        palette: palette
                    )
                    .frame(height: railHeight)

                    HourAxis(dayLength: day.dayLength, palette: palette)

                    if !unplaced.isEmpty {
                        UnplacedSection(
                            lanes: unplaced, dayLength: day.dayLength, palette: palette)
                    }
                }
            }
        }
    }
}

/// Le rail lui-même : un fond creux, et les segments posés dessus.
private struct Rail: View {
    let day: DayPresentation
    let segments: [RailSegment]
    let railHeight: CGFloat
    let palette: PulseonPalette

    var body: some View {
        GeometryReader { proxy in
            // La largeur vient du `GeometryReader` et jamais d'une constante :
            // un rectangle empilé sans largeur mesurée ne fait qu'un point de
            // large, piège déjà payé sur la première grille horaire.
            let geometry = TimelineGeometry(width: proxy.size.width, dayLength: day.dayLength)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.sunken)

                ForEach(segments) { segment in
                    SegmentView(
                        segment: segment,
                        geometry: geometry,
                        railHeight: railHeight,
                        palette: palette
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topLeading) {
                // **N'existe que sur aujourd'hui** : une journée passée est
                // entièrement jouée.
                if let offset = day.nowOffset {
                    NowMarker(height: railHeight, palette: palette)
                        .offset(x: geometry.x(atOffset: offset) - 0.75, y: -5)
                }
            }
        }
    }
}

/// Un morceau de journée, divisé en hauteur autant de fois qu'il y avait
/// d'appareils actifs.
///
/// C'est là que se lit une simultanéité : le rail est *divisé*, jamais la page
/// plus longue.
private struct SegmentView: View {
    let segment: RailSegment
    let geometry: TimelineGeometry
    let railHeight: CGFloat
    let palette: PulseonPalette

    /// Le bloc ne touche pas le bord du rail, sinon il se confond avec lui.
    private let inset: CGFloat = 4
    private let gap: CGFloat = 2

    var body: some View {
        let rect = geometry.rect(offset: segment.startOffset, duration: segment.duration)
        let count = CGFloat(segment.devices.count)
        let slot = (railHeight - inset * 2 - gap * (count - 1)) / count

        ForEach(Array(segment.devices.enumerated()), id: \.element) { index, device in
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                // En dégradé comme partout ailleurs : un aplat paraît imprimé.
                .fill(PulseonTheme.gradient(for: device, in: palette))
                .frame(width: rect.width, height: slot)
                .offset(x: rect.x, y: inset + (slot + gap) * CGFloat(index))
        }
    }
}

/// Un trait fin surmonté d'un point, et rien d'autre.
///
/// La première version portait un cartouche avec l'heure : elle attirait l'œil
/// avant la donnée. L'heure est déjà écrite en haut de l'écran.
private struct NowMarker: View {
    let height: CGFloat
    let palette: PulseonPalette

    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(palette.ink)
                .frame(width: 1.5, height: height + 10)

            Circle()
                .fill(palette.ink)
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
/// Graduer chaque piste faisait la moitié du bruit visuel de la première
/// version. L'axe est rare et gris : assez pour situer un bloc, pas assez pour
/// se faire remarquer.
private struct HourAxis: View {
    let dayLength: TimeInterval
    let palette: PulseonPalette

    private let tickWidth: CGFloat = 34

    var body: some View {
        GeometryReader { proxy in
            let geometry = TimelineGeometry(width: proxy.size.width, dayLength: dayLength)
            let hours = geometry.hourTicks()

            ZStack(alignment: .topLeading) {
                ForEach(hours, id: \.self) { hour in
                    // Largeur fixe et centrée : un alignement dépendant de la
                    // largeur du texte décalerait « 6 h » de « 18 h ».
                    Text(hour == 0 ? "0 h" : "\(hour) h")
                        .font(PulseonTheme.caption)
                        .foregroundStyle(palette.inkFaint)
                        .frame(width: tickWidth)
                        .offset(x: x(hour, in: geometry, last: hours.last))
                }
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    /// Rentre les deux extrémités dans le cadre plutôt que de les laisser
    /// déborder de la carte.
    private func x(_ hour: Int, in geometry: TimelineGeometry, last: Int?) -> CGFloat {
        if hour == 0 { return 0 }
        if hour == last { return geometry.width - tickWidth }
        return geometry.x(atOffset: TimeInterval(hour) * 3600) - tickWidth / 2
    }
}

// MARK: - Ce qui n'a pas d'heure

/// Les durées dont on ne connaît **que** la quantité.
///
/// Règle non négociable du projet : **ne jamais inventer de placement
/// horaire.** La largeur reste proportionnelle au temps, seule chose qu'on
/// sache ; tout le reste doit dire l'ignorance.
///
/// **Centrer le bloc ne suffit pas**, et ça s'était vu en PNG : centré juste
/// sous un axe des heures, il tombait pile sous « 12 h » et se lisait « joué
/// vers midi ». D'où trois précautions cumulées — un filet et un titre qui
/// coupent le lien avec l'axe, le bloc et son libellé centrés, et un contour
/// pointillé plutôt qu'un bloc plein.
private struct UnplacedSection: View {
    let lanes: [Lane]
    let dayLength: TimeInterval
    let palette: PulseonPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle()
                .fill(palette.hairline)
                .frame(height: 1)
                .padding(.top, 4)

            Text("Sans horaire connu")
                .font(PulseonTheme.caption)
                .foregroundStyle(palette.inkFaint)

            ForEach(lanes, id: \.device) { lane in
                UnplacedBar(lane: lane, dayLength: dayLength, palette: palette)
            }
        }
    }
}

private struct UnplacedBar: View {
    let lane: Lane
    let dayLength: TimeInterval
    let palette: PulseonPalette

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let geometry = TimelineGeometry(width: proxy.size.width, dayLength: dayLength)
                let rect = geometry.rect(offset: 0, duration: lane.total)
                let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)

                shape
                    // Fond neutre et non une teinte translucide : de la couleur
                    // à 18 % sur une carte sombre donne un olive sale.
                    .fill(palette.sunken)
                    .overlay {
                        shape.strokeBorder(
                            PulseonTheme.color(for: lane.device, in: palette),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                    }
                    .frame(width: rect.width, height: 18)
                    // Centré, et jamais aligné à gauche : un bord gauche se
                    // lirait comme une heure de début.
                    .offset(x: (geometry.width - rect.width) / 2)
            }
            .frame(height: 18)

            Text("\(lane.device.label) · \(DurationFormat.compact(lane.total))")
                .font(PulseonTheme.caption)
                .foregroundStyle(palette.inkFaint)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Briques de l'écran

/// Ce que le rail montre, appareil par appareil. Sans elle, les couleurs du
/// rail ne veulent rien dire : c'est la seule légende de l'écran.
private struct Legend: View {
    let lanes: [Lane]
    let palette: PulseonPalette

    var body: some View {
        HStack(spacing: 14) {
            ForEach(lanes, id: \.device) { lane in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(PulseonTheme.gradient(for: lane.device, in: palette))
                        .frame(width: 10, height: 10)
                    Text(lane.device.label)
                        .font(PulseonTheme.caption)
                        .foregroundStyle(palette.inkSoft)
                    Text(DurationFormat.compact(lane.total))
                        .font(PulseonTheme.caption.monospacedDigit())
                        .foregroundStyle(palette.inkFaint)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Une journée sans rien à placer.
///
/// « Pas encore branchée » et « journée à zéro » ne se disent pas pareil : la
/// première n'affirme rien, la seconde affirme.
private struct EmptyDay: View {
    let day: DayPresentation
    let palette: PulseonPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.isEmpty ? "Rien de mesuré ce jour-là" : "Aucun écran allumé ce jour-là")
                .font(PulseonTheme.row)
                .foregroundStyle(palette.inkSoft)
            Text(
                day.isEmpty
                    ? "Aucune source n'a écrit : le collecteur ne tournait pas."
                    : "Le collecteur tournait, il n'a simplement rien vu passer."
            )
            .font(PulseonTheme.caption)
            .foregroundStyle(palette.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }
}
