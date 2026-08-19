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
                    BreakdownCard(categories: day.categories, palette: palette)
                }
                DevicesCard(
                    lanes: day.digest.lanes,
                    summedTotal: day.digest.summedTotal,
                    palette: palette
                )
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

    /// Deux anneaux côte à côte, et non deux couronnes concentriques.
    ///
    /// Le double anneau — appareils dehors, catégories dedans — a vécu une
    /// session : Arthur, devant l'app installée, a demandé « à quoi correspond
    /// le deuxième anneau ? ». **C'est la question qui est le résultat.** Sur sa
    /// machine un seul appareil est branché, donc la couronne extérieure est un
    /// cercle uni pendant que l'intérieure est bariolée : au premier regard,
    /// c'est la petite qui a l'air d'être le graphique. Séparés, chacun porte
    /// son titre et il n'y a plus rien à deviner — « c'est plus lisible et tu as
    /// la place ».
    private var diameter: CGFloat { 168 }

    var body: some View {
        Card(palette: palette) {
            VStack(spacing: 12) {
                // Côte à côte quand la fenêtre le permet, l'un sous l'autre
                // sinon : à 560 points de large, deux anneaux de 168 se
                // chevaucheraient. `ViewThatFits` choisit sans qu'aucune vue
                // ait à mesurer quoi que ce soit.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 28) {
                        rings
                    }
                    VStack(spacing: 22) {
                        rings
                    }
                }

                // La comparaison se lit juste sous les anneaux, parce que c'est
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

    @ViewBuilder
    private var rings: some View {
        let lanes = day.digest.lanes.filter { $0.total > 0 }

        // Sur quel écran. Porte le total de la journée, qui reste le premier
        // chiffre de l'app.
        TitledRing(
            title: "Appareils",
            segments: lanes.map {
                .init(
                    id: $0.device.rawValue,
                    value: $0.total,
                    tones: PulseonTheme.ringTones(for: $0.device, in: palette)
                )
            },
            total: day.isEmpty ? nil : day.digest.coveredTotal,
            caption: day.isEmpty ? "rien de branché" : "devant un écran",
            diameter: diameter,
            palette: palette
        )

        // À quoi. **Son centre ne porte pas de total**, et c'est délibéré :
        // deux catégories simultanées comptent chacune leur temps, donc leur
        // somme peut dépasser le temps passé devant un écran. Deux grands
        // nombres côte à côte inviteraient à les comparer, et l'un des deux
        // paraîtrait faux. Le centre nomme donc la catégorie dominante, qui est
        // un fait et non une somme.
        if let first = day.categories.first {
            TitledRing(
                title: "Répartition",
                segments: day.categories.map {
                    .init(
                        id: $0.category.rawValue,
                        value: $0.total,
                        tones: PulseonTheme.ringTones(for: $0.category, in: palette)
                    )
                },
                total: first.total,
                caption: first.category.label,
                diameter: diameter,
                palette: palette
            )
        }
    }
}

/// Un anneau surmonté de son titre.
///
/// Le titre reprend **mot pour mot** celui de la carte correspondante plus bas —
/// « Appareils », « Répartition ». C'est ce qui relie une couleur d'arc à une
/// ligne chiffrée sans avoir à poser une légende de plus sur l'écran.
private struct TitledRing: View {
    let title: String
    let segments: [ActivityRing.Segment]
    let total: TimeInterval?
    let caption: String
    let diameter: CGFloat
    let palette: PulseonPalette

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(PulseonTheme.sectionTitle)
                .foregroundStyle(palette.inkSoft)

            ActivityRing(
                segments: segments,
                total: total,
                caption: caption,
                palette: palette,
                diameter: diameter
            )
        }
    }
}

