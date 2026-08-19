import PulseonCore
import SwiftUI

/// L'écran d'une journée : ce qu'on voit en ouvrant Pulseon.
///
/// **Suit la maquette d'Arthur du 2026-08-17** — fond profond, cartes,
/// l'anneau en tête, puis la répartition, puis les appareils. Deux écarts
/// délibérés, tous deux demandés ou imposés par les règles du projet :
///
/// - **aucun objectif quotidien, aucun badge « On Track »**. La maquette en
///   portait ; Arthur a confirmé « on reste sur une application sans
///   jugement » en même temps qu'il validait le dessin. L'anneau garde donc sa
///   forme mais dit une composition, pas une progression (voir `RingLayout`) ;
/// - **la PlayStation n'apparaît sur aucune ligne de temps**. Elle ne connaît
///   pas ses horaires : elle a sa part dans l'anneau, qui n'est pas une
///   chronologie, et son total dans les listes.
public struct DayDashboard: View {
    public enum Load: Sendable {
        case loaded(DayPresentation)
        /// La lecture a échoué. Distinct d'une journée vide, et dit comme tel :
        /// afficher zéro serait affirmer une chose qu'on ne sait pas.
        case failed(String)
    }

    private let load: Load
    private let canGoForward: Bool
    private let onPrevious: () -> Void
    private let onNext: () -> Void
    private let onToday: () -> Void

    @Environment(\.colorScheme) private var scheme

    public init(
        load: Load,
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
        // Le contenu vit séparé du conteneur défilant : `ImageRenderer` ne rend
        // rien de l'intérieur d'un `ScrollView`, donc une vue défilante d'un
        // seul tenant serait invisible à la preview.
        ScrollView {
            DayDashboardContent(
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
        .frame(minWidth: 560, minHeight: 560)
    }
}

/// Le contenu du dashboard, rendable seul — c'est ce que regarde la preview.
public struct DayDashboardContent: View {
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
                RingCard(day: day, palette: palette)
                if !day.categories.isEmpty {
                    BreakdownCard(day: day, palette: palette)
                }
                DevicesCard(day: day, palette: palette)
            case .failed(let reason):
                header(title: "Journée", isLive: false)
                FailureCard(reason: reason, palette: palette)
            }
        }
        .padding(22)
        // **La maquette est une colonne, pas une surface à remplir.** Sans
        // cette borne, une fenêtre large étire les jauges sur 1500 points et
        // l'anneau se perd au milieu d'une carte vide : à l'écran ça ne
        // ressemblait plus du tout à la maquette, alors que le rendu à 860
        // paraissait juste. Le second `frame` centre la colonne dans ce qui
        // reste.
        .frame(maxWidth: Self.columnWidth)
        .frame(maxWidth: .infinity)
        .background(palette.ground)
    }

    /// Assez large pour qu'une ligne porte libellé, durée, part et détail sans
    /// se serrer ; assez étroite pour qu'une jauge reste lisible d'un coup
    /// d'œil au lieu de traverser l'écran.
    static let columnWidth: CGFloat = 720

    @ViewBuilder
    private func header(title: String, isLive: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isLive ? "Aujourd'hui" : "Journée")
                    // Grand et resserré : la hiérarchie de la maquette est
                    // franche, sans taille intermédiaire qui aplatirait tout.
                    .font(.system(size: 27, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(palette.ink)
                Text(title)
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

            // `.buttonStyle(.plain)` n'est pas cosmétique : avec le style par
            // défaut, `ImageRenderer` sort des carrés jaunes à la place des
            // chevrons et la preview devient illisible.
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

// MARK: - L'anneau

private struct RingCard: View {
    let day: DayPresentation
    let palette: PulseonPalette

    var body: some View {
        let lanes = day.digest.lanes.filter { $0.total > 0 }

        Card(palette: palette) {
            VStack(spacing: 12) {
                ActivityRing(
                    segments: lanes.map {
                        .init(
                            id: $0.device.rawValue,
                            value: $0.total,
                            tones: PulseonTheme.ringTones(for: $0.device, in: palette)
                        )
                    },
                    total: day.isEmpty ? nil : day.digest.coveredTotal,
                    caption: day.isEmpty ? "rien de branché" : "devant un écran",
                    palette: palette
                )

                // La comparaison se lit juste sous le total, parce que c'est
                // là que la question se pose : « 9 h 39, c'est beaucoup ? ».
                if let comparison = day.comparison {
                    DayComparisonView(comparison: comparison, palette: palette)
                }

                // Le second total ne s'affiche que s'il dit autre chose : sans
                // chevauchement, répéter le même chiffre sous un autre nom ne
                // fait qu'embrouiller.
                if day.digest.summedTotal - day.digest.coveredTotal > 60 {
                    Text(
                        "\(DurationFormat.compact(day.digest.summedTotal)) en cumulant les appareils, écrans simultanés comptés deux fois"
                    )
                    .font(PulseonTheme.caption)
                    .foregroundStyle(palette.inkFaint)
                    .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - La répartition

private struct BreakdownCard: View {
    let day: DayPresentation
    let palette: PulseonPalette

    var body: some View {
        // Les parts se calculent sur la somme des catégories, pas sur le total
        // de la journée : deux catégories simultanées comptent chacune leur
        // temps, donc leur somme peut dépasser le temps passé devant un écran.
        // Rapporter au `coveredTotal` afficherait des pourcentages dépassant
        // 100 %.
        let sum = day.categories.reduce(0) { $0 + $1.total }

        Card(palette: palette) {
            VStack(alignment: .leading, spacing: 15) {
                Text("Répartition")
                    .font(PulseonTheme.sectionTitle)
                    .foregroundStyle(palette.inkSoft)
                    .padding(.bottom, 2)

                ForEach(day.categories) { category in
                    MeterRow(
                        symbol: PulseonTheme.symbol(for: category.category),
                        tint: PulseonTheme.color(for: category.category, in: palette),
                        fill: PulseonTheme.gradient(for: category.category, in: palette),
                        label: category.category.label,
                        apps: category.entities.prefix(3).map(\.entity),
                        total: category.total,
                        share: sum > 0 ? category.total / sum : 0,
                        palette: palette
                    )
                }
            }
        }
    }
}

// MARK: - Les appareils

private struct DevicesCard: View {
    let day: DayPresentation
    let palette: PulseonPalette

    var body: some View {
        let sum = day.digest.summedTotal

        Card(palette: palette) {
            VStack(alignment: .leading, spacing: 15) {
                Text("Appareils")
                    .font(PulseonTheme.sectionTitle)
                    .foregroundStyle(palette.inkSoft)
                    .padding(.bottom, 2)

                ForEach(day.digest.lanes, id: \.device) { lane in
                    if lane.isConnected {
                        MeterRow(
                            symbol: PulseonTheme.symbol(for: lane.device),
                            tint: PulseonTheme.color(for: lane.device, in: palette),
                            fill: PulseonTheme.gradient(for: lane.device, in: palette),
                            label: lane.device.label,
                            // Sa part de l'anneau est honnête, sa place dans
                            // la journée est inconnue — et doit se dire.
                            detail: lane.kind == .counter ? "horaires inconnus" : "",
                            apps: lane.kind == .counter
                                ? []
                                : lane.topEntities.prefix(3).map(\.entity),
                            total: lane.total,
                            share: sum > 0 ? lane.total / sum : 0,
                            palette: palette
                        )
                    } else {
                        // « Pas encore branchée » n'est pas « journée à zéro ».
                        // Zéro est une affirmation ; ici on n'a rien mesuré.
                        UnpluggedRow(device: lane.device, palette: palette)
                    }
                }
            }
        }
    }
}
