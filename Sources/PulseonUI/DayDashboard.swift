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
                // **Une grille dès qu'il y a la place, une colonne sinon.**
                // Demande d'Arthur le 2026-08-22 : « je voudrais que quand
                // l'appli desktop est ouverte, on ne doive pas scroller, genre
                // en grille de 4 cases ». Sur sa fenêtre (1512 × 949), tout
                // tient sans défilement ; en dessous, deux colonnes écraseraient
                // les jauges et la rangée de ronds, donc on revient à la
                // colonne unique — qui, elle, défile.
                //
                // `ViewThatFits` compare la largeur **idéale** de chaque
                // proposition à la place disponible. La grille annonce la
                // sienne par un `minWidth` explicite : sans ça elle serait
                // extensible, donc toujours retenue, et se ferait écraser au
                // lieu de céder la place. C'est exactement le piège payé sur la
                // carte « Déroulé » le même jour.
                ViewThatFits(in: .horizontal) {
                    grid(day).frame(minWidth: Self.gridMinimumWidth)
                    column(day).frame(maxWidth: Self.columnWidth)
                }
            case .failed(let reason):
                header(title: "Journée", isLive: false)
                FailureCard(reason: reason, palette: palette)
                    .frame(maxWidth: Self.columnWidth)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(palette.ground)
    }

    /// Assez large pour qu'une ligne porte libellé, durée, part et détail sans
    /// se serrer ; assez étroite pour qu'une jauge reste lisible d'un coup
    /// d'œil au lieu de traverser l'écran.
    ///
    /// **La maquette est une colonne, pas une surface à remplir** : sans cette
    /// borne, une fenêtre large étirait les jauges sur 1500 points et l'anneau
    /// se perdait au milieu d'une carte vide. Elle ne vaut plus que pour le
    /// repli en colonne — la grille, elle, occupe toute la largeur, et c'est
    /// justement ce qu'on lui demande.
    static let columnWidth: CGFloat = 720

    /// En dessous, la grille cède la place à la colonne.
    ///
    /// Deux colonnes de 470 points : assez pour qu'une jauge et sa ligne de
    /// détail restent lisibles de chaque côté. Plus bas, on obtiendrait deux
    /// colonnes illisibles au lieu d'une colonne lisible — le défilement est un
    /// moindre mal que l'écrasement.
    static let gridMinimumWidth: CGFloat = 980

    // MARK: Les deux dispositions

    /// La colonne d'origine : tout à la suite, dans l'ordre de lecture.
    @ViewBuilder
    private func column(_ day: DayPresentation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            RingCard(day: day, palette: palette)
            if let anatomy = day.anatomy {
                DayAnatomyCard(anatomy: anatomy, day: day, palette: palette)
            }
            if !day.categories.isEmpty {
                BreakdownCard(categories: day.categories, palette: palette)
            }
            devicesCard(day)
        }
    }

    /// La grille : quatre cases, et **toutes ne pèsent pas le même poids**.
    ///
    /// L'anneau porte le total de la journée, sa composition par appareil, la
    /// comparaison aux journées précédentes et la rangée de catégories : il
    /// mérite la colonne large. La répartition, le déroulé et les appareils sont
    /// du détail, à droite et en dessous.
    ///
    /// Les cases absentes ne laissent pas de trou : sans anatomie la colonne
    /// gauche n'a qu'une carte, sans répartition la droite n'en a qu'une. C'est
    /// le cas normal d'une journée vide ou du premier jour d'utilisation.
    @ViewBuilder
    private func grid(_ day: DayPresentation) -> some View {
        WeightedColumns(weights: [Self.leadingWeight, Self.trailingWeight], spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                RingCard(day: day, palette: palette, ringDiameter: Self.gridRingDiameter)
                if let anatomy = day.anatomy {
                    DayAnatomyCard(anatomy: anatomy, day: day, palette: palette)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                if !day.categories.isEmpty {
                    BreakdownCard(categories: day.categories, palette: palette)
                }
                devicesCard(day)
            }
        }
    }

    /// 57 / 43. Assez pour que la hiérarchie se voie au premier regard, assez
    /// peu pour que la colonne de droite garde des jauges lisibles.
    static let leadingWeight: CGFloat = 57
    static let trailingWeight: CGFloat = 43

    /// L'anneau grossit en grille : c'est la case principale, et une case
    /// principale qui porterait le même anneau qu'en colonne étroite ne dirait
    /// pas qu'elle est principale.
    static let gridRingDiameter: CGFloat = 248

    @ViewBuilder
    private func devicesCard(_ day: DayPresentation) -> some View {
        DevicesCard(
            lanes: day.digest.lanes,
            summedTotal: day.digest.summedTotal,
            palette: palette
        )
    }

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
    /// Nil pour la taille par défaut de `ActivityRing`. La grille le grossit :
    /// voir `DayDashboardContent.gridRingDiameter`.
    var ringDiameter: CGFloat?

    var body: some View {
        let lanes = day.digest.lanes.filter { $0.total > 0 }

        Card(palette: palette) {
            VStack(spacing: 14) {
                // L'anneau principal : les appareils, et le total de la journée
                // en son centre.
                //
                // **Il est seul en tête**, après deux tentatives écartées le
                // 2026-08-19 : une couronne intérieure concentrique, qui
                // demandait une légende pour qu'on sache laquelle disait quoi ;
                // puis un second anneau plein à côté, qui obligeait à écrire un
                // chiffre en son centre alors que la somme des catégories n'est
                // pas comparable au total de la journée. Les catégories sont
                // désormais une rangée de petits ronds, en dessous.
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
                    palette: palette,
                    diameter: ringDiameter ?? ActivityRing.defaultDiameter
                )

                if !lanes.isEmpty {
                    DeviceLegend(lanes: lanes, palette: palette)
                }

                // La comparaison se lit juste sous le total, parce que c'est
                // là que la question se pose : « 9 h 39, c'est beaucoup ? ».
                if let comparison = day.comparison {
                    DayComparisonView(comparison: comparison, palette: palette)
                }

                if !day.categories.isEmpty {
                    Divider()
                        .overlay(palette.hairline)
                        .padding(.horizontal, 8)

                    DayCategoryRings(categories: day.categories, palette: palette)
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

