import PulseonCore
import SwiftUI

/// L'écran d'une semaine.
///
/// Reprend le vocabulaire de l'écran du jour — mêmes cartes, mêmes jauges,
/// mêmes couleurs d'appareil — parce qu'une même forme doit vouloir dire la
/// même chose d'un écran à l'autre. Ce n'est pas une direction visuelle de
/// plus : la maquette d'Arthur fait foi, et cet écran en applique le
/// vocabulaire à un pas de temps différent.
///
/// **Pas de graphique en colonnes**, écarté par Arthur le 2026-08-19 : « si
/// c'est en colonne, autant garder l'ancienne app temps d'écran macOS ». Le rond
/// est ce qui distingue Pulseon, et il tient les deux échelles — un grand pour
/// la semaine, sept petits pour les journées (voir `WeekRingRow`).
///
/// **Ce qu'il n'y a délibérément pas non plus :** aucune ligne d'objectif, ni
/// moyenne tracée en travers. Une moyenne à l'horizontale se lit comme une barre
/// à battre, et Pulseon ne dit pas si c'est bien. Elle est écrite en toutes
/// lettres.
public struct WeekDashboard: View {
    public enum Load: Sendable {
        case loaded(PeriodPresentation)
        /// La lecture a échoué. Distinct d'une semaine vide, et dit comme tel.
        case failed(String)
    }

    private let load: Load
    private let canGoForward: Bool
    private let onPrevious: () -> Void
    private let onNext: () -> Void
    private let onCurrent: () -> Void

    @Environment(\.colorScheme) private var scheme

    public init(
        load: Load,
        canGoForward: Bool,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onCurrent: @escaping () -> Void
    ) {
        self.load = load
        self.canGoForward = canGoForward
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onCurrent = onCurrent
    }

    public var body: some View {
        // Le contenu vit séparé du conteneur défilant : `ImageRenderer` ne rend
        // rien de l'intérieur d'un `ScrollView`.
        ScrollView {
            WeekDashboardContent(
                load: load,
                canGoForward: canGoForward,
                palette: PulseonTheme.palette(for: scheme),
                onPrevious: onPrevious,
                onNext: onNext,
                onCurrent: onCurrent
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PulseonTheme.palette(for: scheme).ground)
        .frame(minWidth: 560, minHeight: 560)
    }
}

/// Le contenu de l'écran, rendable seul — c'est ce que regarde la preview.
public struct WeekDashboardContent: View {
    let load: WeekDashboard.Load
    let canGoForward: Bool
    let palette: PulseonPalette
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onCurrent: () -> Void

    public init(
        load: WeekDashboard.Load,
        canGoForward: Bool,
        palette: PulseonPalette,
        onPrevious: @escaping () -> Void = {},
        onNext: @escaping () -> Void = {},
        onCurrent: @escaping () -> Void = {}
    ) {
        self.load = load
        self.canGoForward = canGoForward
        self.palette = palette
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onCurrent = onCurrent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch load {
            case .loaded(let period):
                header(title: period.title, isCurrent: period.isCurrent)
                WeekChartCard(period: period, palette: palette)
                if !period.categories.isEmpty {
                    BreakdownCard(categories: period.categories, palette: palette)
                }
                DevicesCard(
                    lanes: period.digest.lanes,
                    summedTotal: period.digest.summedTotal,
                    palette: palette
                )
            case .failed(let reason):
                header(title: "Semaine", isCurrent: false)
                FailureCard(reason: reason, palette: palette)
            }
        }
        .padding(22)
        // Même colonne bornée que l'écran du jour : sans elle, une fenêtre
        // large étire les jauges sur 1500 points et le dessin ne ressemble
        // plus à la maquette.
        .frame(maxWidth: DayDashboardContent.columnWidth)
        .frame(maxWidth: .infinity)
        .background(palette.ground)
    }

    @ViewBuilder
    private func header(title: String, isCurrent: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isCurrent ? "Cette semaine" : "Semaine")
                    .font(.system(size: 27, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(palette.ink)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.inkSoft)
            }

            Spacer()

            if canGoForward {
                Button("Cette semaine", action: onCurrent)
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

// MARK: - Le graphique

private struct WeekChartCard: View {
    let period: PeriodPresentation
    let palette: PulseonPalette

    var body: some View {
        let lanes = period.digest.lanes.filter { $0.total > 0 }

        Card(palette: palette) {
            VStack(spacing: 16) {
                // Le même anneau que l'écran du jour, à l'échelle de la
                // semaine : ses arcs sont des parts d'appareils, et il fait
                // toujours le tour — ce n'est pas une progression.
                ActivityRing(
                    segments: lanes.map {
                        .init(
                            id: $0.device.rawValue,
                            value: $0.total,
                            tones: PulseonTheme.ringTones(for: $0.device, in: palette)
                        )
                    },
                    total: period.isEmpty ? nil : period.digest.coveredTotal,
                    caption: period.isEmpty ? "rien de mesuré" : "devant un écran",
                    palette: palette,
                    diameter: 178
                )

                if !lanes.isEmpty {
                    DeviceLegend(lanes: lanes, palette: palette)
                }

                // La semaine jour par jour, en petit. C'est là que se lit
                // l'évolution : la taille du rond suit la longueur de la
                // journée, sa couleur dit par quel écran elle est passée.
                WeekRingRow(period: period, palette: palette)

                VStack(alignment: .leading, spacing: 4) {
                    averageLine

                    // La semaine en cours n'est pas comparable à une semaine
                    // entière, et le dire coûte une ligne.
                    if period.isCurrent {
                        Text("La journée en cours n'entre pas dans la moyenne.")
                            .font(PulseonTheme.caption)
                            .foregroundStyle(palette.inkFaint)
                    }

                    // Le second total ne s'affiche que s'il dit autre chose.
                    if period.digest.summedTotal - period.digest.coveredTotal > 60 {
                        Text(
                            "\(DurationFormat.compact(period.digest.summedTotal)) en cumulant les appareils, écrans simultanés comptés deux fois"
                        )
                        .font(PulseonTheme.caption)
                        .foregroundStyle(palette.inkFaint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// La moyenne, écrite et non tracée — voir l'en-tête de `WeekDashboard`.
    @ViewBuilder
    private var averageLine: some View {
        if let average = period.dailyAverage {
            let count = period.averagedDays.count
            Text(
                "Moyenne de \(DurationFormat.compact(average)) par jour, sur \(count) "
                    + (count > 1 ? "journées mesurées" : "journée mesurée")
            )
            .font(PulseonTheme.caption)
            .foregroundStyle(palette.inkSoft)
        } else {
            // Se taire plutôt qu'annoncer une moyenne qui n'existe pas — même
            // règle que la comparaison entre journées sous les trois jours.
            Text("Pas encore de moyenne : aucune journée mesurée et terminée.")
                .font(PulseonTheme.caption)
                .foregroundStyle(palette.inkFaint)
        }
    }
}
