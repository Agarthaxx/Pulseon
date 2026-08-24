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
    /// Sert au fond, dont le halo est plus discret en apparence claire.
    @Environment(\.colorScheme) private var scheme
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
        // **La hauteur aussi, et alignée en haut.** Sans `maxHeight`, le fond
        // ne couvre que le contenu : sur la chronologie, dont la carte est
        // courte, la fenêtre affichait une bande blanche au-dessus et en
        // dessous. Invisible sur l'écran du jour, qui remplit sa hauteur —
        // trouvé en PNG le 2026-08-24, sur le seul écran assez court pour le
        // révéler.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PulseonBackground(palette: palette, scheme: scheme))
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
        VStack(alignment: .leading, spacing: PulseonEditorial.blockGap) {
            RingCard(day: day, palette: palette)
            if let anatomy = day.anatomy {
                DayAnatomyCard(anatomy: anatomy, day: day, palette: palette)
            }
            DayPulseCard(pulse: day.pulse, day: day, palette: palette)
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
        WeightedColumns(
            weights: [Self.leadingWeight, Self.trailingWeight], spacing: PulseonEditorial.blockGap
        ) {
            VStack(alignment: .leading, spacing: PulseonEditorial.blockGap) {
                RingCard(
                    day: day, palette: palette,
                    ringDiameter: Self.gridRingDiameter, isWide: true
                )
                .entrance(rank: 0)
                if let anatomy = day.anatomy {
                    DayAnatomyCard(anatomy: anatomy, day: day, palette: palette)
                        .entrance(rank: 2)
                }
                // **Ce qui comblait le vide, et pas avec du remplissage.** La
                // colonne gauche s'arrêtait ~290 points au-dessus de la droite,
                // sur la fenêtre d'Arthur. Un `Spacer` aurait aligné les bas
                // sans rien dire de plus ; le battement occupe la place en
                // répondant à la question du projet — *quand*.
                DayPulseCard(pulse: day.pulse, day: day, palette: palette)
                    .entrance(rank: 4)
            }

            VStack(alignment: .leading, spacing: PulseonEditorial.blockGap) {
                if !day.categories.isEmpty {
                    BreakdownCard(categories: day.categories, palette: palette)
                        .entrance(rank: 1)
                }
                devicesCard(day)
                    .entrance(rank: 3)
            }
        }
    }

    /// 57 / 43. Assez pour que la hiérarchie se voie au premier regard, assez
    /// peu pour que la colonne de droite garde des jauges lisibles.
    static let leadingWeight: CGFloat = 57
    static let trailingWeight: CGFloat = 43

    /// L'anneau en grille.
    ///
    /// Il valait 248 quand il était seul en tête d'une carte pleine largeur.
    /// Depuis qu'il partage la case avec les faits de la journée, cette taille
    /// le faisait toucher le retrait de la carte : à côté d'un texte, un anneau
    /// n'a pas besoin d'être plus gros qu'en colonne pour rester le premier
    /// élément lu — c'est sa position qui le dit, pas son diamètre.
    static let gridRingDiameter: CGFloat = 236

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
    /// Vrai en grille, où la carte occupe la colonne large.
    ///
    /// **C'est le vide qui a imposé cette bascule.** En fenêtre large, l'anneau
    /// de 248 points était centré dans une carte de ~1090 : ~420 points de vide
    /// de chaque côté, et une carte vide aux deux tiers est ce qui se lit le
    /// plus vite comme « pas fini ». Les faits qui l'accompagnaient — légende,
    /// simultanéité, comparaison — s'empilaient dessous alors qu'ils tiennent
    /// à côté.
    var isWide: Bool = false


    var body: some View {
        let lanes = day.digest.lanes.filter { $0.total > 0 }

        Card(palette: palette) {
            VStack(spacing: PulseonEditorial.blockGap) {
                if isWide {
                    HStack(alignment: .center, spacing: PulseonSpace.page) {
                        // Centré dans sa part plutôt que collé au bord : posé à
                        // gauche, l'anneau frôlait le retrait de la carte et on
                        // le lisait comme rogné.
                        ring(lanes)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, PulseonSpace.tight)

                        VStack(alignment: .leading, spacing: PulseonSpace.snug) {
                            if !lanes.isEmpty {
                                DeviceLegendColumn(lanes: lanes, palette: palette)
                            }
                            if let line = simultaneityLine {
                                Text(line)
                                    .font(PulseonTheme.caption)
                                    .foregroundStyle(palette.inkFaint)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let comparison = day.comparison {
                                DayComparisonView(comparison: comparison, palette: palette)
                            }
                        }
                        // **Bornée, et pas étirée.** Laissée libre, la colonne
                        // poussait les durées jusqu'au bord droit de la carte :
                        // on lisait « Mac » d'un côté et « 9h42 » de l'autre,
                        // séparés par 500 points de vide. Une paire libellé /
                        // valeur ne se lit que si les deux tiennent dans un même
                        // regard.
                        .frame(maxWidth: 340, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    narrowStack(lanes)
                }

                if !day.categories.isEmpty {
                    Divider()
                        .overlay(palette.hairline)
                        .padding(.horizontal, PulseonSpace.tight)

                    DayCategoryRings(categories: day.categories, palette: palette)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// La disposition d'origine, gardée telle quelle pour la colonne étroite :
    /// à moins de 980 points, il n'y a pas de vide à combler.
    @ViewBuilder
    private func narrowStack(_ lanes: [Lane]) -> some View {
        VStack(spacing: PulseonEditorial.blockGap) {
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
                ring(lanes)

                if !lanes.isEmpty {
                    DeviceLegend(lanes: lanes, palette: palette)
                }

                // **Le chiffre qui répond à la question là où elle se pose.**
                // Arthur, devant l'app le 2026-08-22 : « le rond indique 1h29
                // mais j'ai 1h29 de télé et de pc ? donc ça devrait me montrer
                // le double non ? ». La légende juste au-dessus affichait
                // « Mac 1h16 · TV 1h29 » — deux nombres qui ne font pas le
                // troisième, et rien pour dire pourquoi.
                //
                // La note qui l'expliquait existait, mais tout en bas de la
                // carte, en gris pâle, sous la rangée de catégories : trop loin
                // de la contradiction pour la résoudre. Elle disait de surcroît
                // une méthode de calcul (« écrans simultanés comptés deux
                // fois ») là où il fallait un fait de la soirée.
                if let line = simultaneityLine {
                    Text(line)
                        .font(PulseonTheme.caption)
                        .foregroundStyle(palette.inkFaint)
                }

                // La comparaison se lit juste sous le total, parce que c'est
                // là que la question se pose : « 9 h 39, c'est beaucoup ? ».
            if let comparison = day.comparison {
                DayComparisonView(comparison: comparison, palette: palette)
            }
        }
    }

    @ViewBuilder
    private func ring(_ lanes: [Lane]) -> some View {
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
    }

    /// « deux écrans à la fois pendant 1h15 », ou rien.
    ///
    /// **« deux » ou « plusieurs » selon ce qui a été mesuré** : écrire « deux »
    /// un jour où trois écrans tournaient ensemble sous-entendrait une mesure
    /// qu'on n'a pas faite. Et jamais « les deux », qui renverrait aux pastilles
    /// de la légende — or elle peut en porter une troisième, la PlayStation,
    /// dont on ignore justement les horaires.
    ///
    /// En dessous d'une minute, on se tait : deux sessions qui se frôlent à la
    /// seconde ne sont pas une soirée sur deux écrans.
    private var simultaneityLine: String? {
        let simultaneity = day.digest.simultaneity
        guard simultaneity.duration >= 60 else { return nil }
        let screens = simultaneity.peak > 2 ? "plusieurs" : "deux"
        return "\(screens) écrans à la fois pendant \(DurationFormat.compact(simultaneity.duration))"
    }
}

