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
/// **Ce qu'il n'y a délibérément pas :** aucune ligne d'objectif en travers des
/// colonnes. Une moyenne tracée à l'horizontale se lit comme une barre à
/// battre, et Pulseon ne dit pas si c'est bien. La moyenne est donc écrite en
/// toutes lettres, jamais dessinée en travers du graphique.
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
        Card(palette: palette) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    if period.isEmpty {
                        // Rien de mesuré n'est pas zéro : un tiret, jamais un
                        // chiffre qu'on ne sait pas.
                        Text("—")
                            .font(PulseonTheme.readout(34))
                            .foregroundStyle(palette.inkFaint)
                    } else {
                        DurationReadout(
                            total: period.digest.coveredTotal, size: 34, palette: palette)
                    }
                    Text(period.isEmpty ? "rien de mesuré cette semaine" : "devant un écran")
                        .font(PulseonTheme.caption)
                        .foregroundStyle(palette.inkSoft)
                }

                WeekChart(period: period, palette: palette)

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
            }
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

/// Les colonnes de la semaine.
///
/// **Trois états, jamais deux.** Une colonne vide ne veut pas dire la même chose
/// selon qu'on n'a rien mesuré (le collecteur était éteint), qu'on a mesuré zéro
/// (vrai zéro), ou que la journée n'a pas encore eu lieu. Les confondre ferait
/// dire à l'écran une chose qu'on ne sait pas.
private struct WeekChart: View {
    let period: PeriodPresentation
    let palette: PulseonPalette

    /// Assez haut pour qu'un écart d'une heure se voie, assez bas pour que le
    /// graphique ne prenne pas tout l'écran devant les cartes qui le suivent.
    private let height: CGFloat = 132

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(period.days) { day in
                DayColumn(
                    day: day,
                    scale: period.scale,
                    height: height,
                    palette: palette
                )
            }
        }
    }
}

private struct DayColumn: View {
    let day: PeriodPresentation.Day
    let scale: TimeInterval
    let height: CGFloat
    let palette: PulseonPalette

    /// Une journée d'une minute sur une semaine à huit heures ferait 0,3 point
    /// de haut : invisible reviendrait à dire qu'elle n'a pas eu lieu. Même
    /// plancher que la jauge des lignes et que l'arc de l'anneau.
    private static let minimumBarHeight: CGFloat = 4

    var body: some View {
        VStack(spacing: 6) {
            Text(valueLabel)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(day.isToday ? palette.gold : palette.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            ZStack(alignment: .bottom) {
                // Le creux de la colonne : il donne la hauteur de référence,
                // sans quoi les jours courts flotteraient sans repère.
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(palette.sunken.opacity(day.isFuture ? 0.35 : 1))
                    .frame(height: height)

                bar
            }
            .frame(height: height)

            VStack(spacing: 1) {
                Text(day.initial)
                    .font(.system(size: 11, weight: day.isToday ? .bold : .medium))
                    .foregroundStyle(labelColor)
                Text(day.dayNumber)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(palette.inkFaint.opacity(day.isFuture ? 0.5 : 1))
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var bar: some View {
        if day.isFuture {
            // Rien du tout : cette journée n'a pas eu lieu. Ni un zéro, ni un
            // trou de mesure — il n'y a simplement rien à dire.
            EmptyView()
        } else if !day.isMeasured {
            // Le pointillé dit l'inconnu, là où le plein dit le mesuré. Même
            // convention que la ligne d'un appareil non branché.
            // Tracé en `inkFaint` et non en `hairline` : le filet, posé sur le
            // creux de la colonne, disparaissait en apparence claire — l'état
            // « on ne sait pas » devenait indiscernable d'une journée à zéro,
            // ce qui est exactement la confusion à empêcher. Vu en PNG.
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(
                    palette.inkFaint.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
                .frame(height: 14)
        } else if day.total <= 0 {
            // Un vrai zéro, mesuré : un trait plein et gris. Plein parce qu'on
            // sait, gris parce qu'il n'y a pas de temps à montrer.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(palette.inkFaint)
                .frame(height: 3)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(palette.goldGradient)
                .frame(height: barHeight)
        }
    }

    private var barHeight: CGFloat {
        let ratio = min(1, max(0, day.total / scale))
        return max(Self.minimumBarHeight, height * ratio)
    }

    /// Ce qui s'écrit au-dessus de la colonne. Le tiret d'une journée non
    /// mesurée n'est pas décoratif : c'est la différence entre « on ne sait
    /// pas » et « zéro ».
    private var valueLabel: String {
        if day.isFuture { return " " }
        if !day.isMeasured { return "—" }
        return DurationFormat.compact(day.total)
    }

    private var labelColor: Color {
        if day.isFuture { return palette.inkFaint.opacity(0.5) }
        return day.isToday ? palette.gold : palette.inkSoft
    }
}
