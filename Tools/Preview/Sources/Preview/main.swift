import AppKit
import PulseonCore
import PulseonUI
import SwiftUI

// Rend les vues de Pulseon en PNG, sans lancer l'app.
//
// Deux raisons de ne pas simplement lancer l'app pour regarder : elle démarre
// le collecteur, qui écrirait dans la vraie base en parallèle de l'instance
// déjà en cours ; et une capture d'écran suppose que quelqu'un soit devant
// l'écran pour la prendre.

let day: TimeInterval = 86_400
let dayStart = Calendar.current.startOfDay(for: Date())
let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp"

// MARK: - Une journée de démonstration

private func block(_ startHour: Double, _ hours: Double, _ entity: String) -> TraceBlock {
    TraceBlock(entity: entity, startOffset: startHour * 3600, duration: hours * 3600)
}

/// Une journée plausible : matinée hachée, coupure du midi, après-midi dense,
/// film le soir, et une partie de PlayStation sans horaire connu. Les blocs
/// très courts sont là exprès — c'est le cas qui casse les mises en page.
let macBlocks: [TraceBlock] = [
    block(8.6, 0.4, "Mail"), block(9.1, 1.4, "Xcode"), block(10.6, 0.2, "Brave Browser"),
    block(10.9, 1.1, "Xcode"), block(12.2, 0.3, "Slack"),
    block(14.0, 2.3, "Xcode"), block(16.4, 0.6, "Brave Browser"), block(17.1, 1.2, "Ghostty"),
    block(21.0, 2.1, "IINA"),
    block(23.2, 0.05, "Ghostty"),
]

let macTotal = macBlocks.reduce(0) { $0 + $1.duration }
let psTotal: TimeInterval = 1.8 * 3600

let digest = DayDigest(
    date: Calendar.current.dateComponents([.year, .month, .day], from: dayStart),
    lanes: [
        Lane(
            device: .mac, total: macTotal, blocks: macBlocks,
            topEntities: [
                EntityTotal(entity: "Xcode", total: 4.8 * 3600),
                EntityTotal(entity: "Ghostty", total: 1.2 * 3600),
                EntityTotal(entity: "Brave Browser", total: 0.8 * 3600),
            ],
            isConnected: true
        ),
        Lane(
            device: .playstation, total: psTotal, blocks: [],
            topEntities: [EntityTotal(entity: "Elden Ring", total: psTotal)],
            isConnected: true
        ),
        Lane(device: .tv, total: 0, blocks: [], topEntities: [], isConnected: false),
    ],
    summedTotal: macTotal + psTotal,
    coveredTotal: macTotal
)

/// Une journée sans rien : aucune source branchée. L'état qu'on oublie de
/// dessiner, et celui qu'on voit le premier jour d'utilisation.
let emptyDigest = DayDigest(
    date: digest.date,
    lanes: Device.allCases.map {
        Lane(device: $0, total: 0, blocks: [], topEntities: [], isConnected: false)
    },
    summedTotal: 0, coveredTotal: 0
)

// MARK: - Rendu

@MainActor
func shoot(_ view: some View, size: CGSize, named name: String) {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    // 2× : on regarde le rendu de près, et l'anticrénelage cache les défauts
    // d'alignement d'un point.
    renderer.scale = 2

    guard let image = renderer.nsImage,
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        print("échec du rendu : \(name)")
        return
    }

    let path = "\(outputDirectory)/\(name).png"
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print(path)
    } catch {
        print("écriture impossible (\(name)) : \(error.localizedDescription)")
    }
}

/// **On rend `DayDashboardContent`, jamais `DayDashboard`.** Ce dernier enrobe
/// son contenu dans un `ScrollView`, dont `ImageRenderer` ne rend rien : la
/// sortie est alors un rectangle uni de la couleur du fond, et on croit à un
/// bug de dessin alors que la vue est simplement hors champ.
@MainActor
func dashboard(_ load: DayDashboard.Load, canGoForward: Bool, scheme: ColorScheme) -> some View {
    DayDashboardContent(
        load: load,
        canGoForward: canGoForward,
        palette: PulseonTheme.palette(for: scheme)
    )
    .environment(\.colorScheme, scheme)
    .environment(\.appIcons, demoIcons)
}

/// Les icônes de la journée de démonstration.
///
/// L'app, elle, trouve l'identifiant de bundle dans la base (`StoredApp`) ; ici
/// il n'y a pas de base, donc la correspondance est écrite à la main — c'est de
/// la donnée de démonstration, au même titre que les blocs de la journée.
///
/// **« Elden Ring » n'y figure pas exprès** : un jeu PlayStation n'a jamais eu
/// d'icône côté Mac, et c'est le cas qu'il faut regarder — la ligne doit rester
/// droite avec un nom sans image au milieu d'apps qui en ont une.
let demoBundleIDs = [
    "Mail": "com.apple.mail",
    "Xcode": "com.apple.dt.Xcode",
    "Brave Browser": "com.brave.Browser",
    "Slack": "com.tinyspeck.slackmacgap",
    "Ghostty": "com.mitchellh.ghostty",
    "IINA": "com.colliderli.iina",
    "Firefox Developer Edition": "org.mozilla.firefoxdeveloperedition",
    "Safari": "com.apple.Safari",
]

let demoIcons = AppIconSource { name in
    guard
        let bundleID = demoBundleIDs[name],
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    else { return nil }
    return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
}

/// À quoi la journée a servi. Calculé ici à la main : le classement réel vit
/// côté macOS, qui sait lire la catégorie déclarée d'une app.
let categories: [CategoryTotal] = [
    CategoryTotal(
        category: .development, total: 6 * 3600,
        entities: [
            EntityTotal(entity: "Xcode", total: 4.8 * 3600),
            EntityTotal(entity: "Ghostty", total: 1.2 * 3600),
        ]
    ),
    CategoryTotal(
        category: .media, total: 2.1 * 3600,
        entities: [EntityTotal(entity: "IINA", total: 2.1 * 3600)]
    ),
    CategoryTotal(
        category: .game, total: psTotal,
        entities: [EntityTotal(entity: "Elden Ring", total: psTotal)]
    ),
    CategoryTotal(
        category: .web, total: 0.8 * 3600,
        entities: [EntityTotal(entity: "Brave Browser", total: 0.8 * 3600)]
    ),
    // Volontairement minuscule : c'est le cas qui teste le plancher de
    // visibilité de l'anneau et de la jauge.
    CategoryTotal(
        category: .communication, total: 3 * 60,
        entities: [EntityTotal(entity: "Slack", total: 3 * 60)]
    ),
]

MainActor.assumeIsolated {
    let now = dayStart.addingTimeInterval(19.4 * 3600)
    let today = DayPresentation(
        digest: digest, dayStart: dayStart, dayLength: day, now: now,
        categories: categories,
        // Une journée en cours : la comparaison s'arrête donc à la même heure
        // dans les journées de référence, et la phrase doit le dire.
        comparison: DayComparison(
            subject: macTotal, average: macTotal - 4_800, referenceDays: 7, isPartial: true
        )
    )

    shoot(
        dashboard(.loaded(today), canGoForward: false, scheme: .dark),
        size: CGSize(width: 860, height: 900), named: "pulseon-dark"
    )
    shoot(
        dashboard(.loaded(today), canGoForward: true, scheme: .light),
        size: CGSize(width: 860, height: 900), named: "pulseon-light"
    )

    // Une journée passée et vide : pas de tête de lecture, rien de branché.
    let empty = DayPresentation(
        digest: emptyDigest, dayStart: dayStart.addingTimeInterval(-3 * day),
        dayLength: day, now: nil
    )
    shoot(
        dashboard(.loaded(empty), canGoForward: true, scheme: .dark),
        size: CGSize(width: 860, height: 700), named: "pulseon-empty"
    )

    // L'échec de lecture, qui ne doit pas ressembler à une journée à zéro.
    shoot(
        dashboard(.failed("Base introuvable"), canGoForward: true, scheme: .dark),
        size: CGSize(width: 860, height: 400), named: "pulseon-failed"
    )

    // Une fenêtre étroite : la règle horaire doit s'alléger, les étiquettes
    // tenir, et rien ne doit déborder.
    shoot(
        dashboard(.loaded(today), canGoForward: false, scheme: .dark),
        size: CGSize(width: 560, height: 900), named: "pulseon-narrow"
    )

    // **Le cas réel d'Arthur : un seul appareil branché.** C'est la journée
    // normale sur sa machine, et c'est celle qui montrait un anneau d'un bleu
    // uni — le dégradé linéaire ne se voyait qu'entre deux arcs.
    let macOnlyDigest = DayDigest(
        date: digest.date,
        lanes: [
            Lane(
                device: .mac, total: macTotal, blocks: macBlocks,
                topEntities: [EntityTotal(entity: "Firefox Developer Edition", total: 2.1 * 3600)],
                isConnected: true
            ),
            Lane(device: .playstation, total: 0, blocks: [], topEntities: [], isConnected: false),
            Lane(device: .tv, total: 0, blocks: [], topEntities: [], isConnected: false),
        ],
        summedTotal: macTotal, coveredTotal: macTotal
    )
    shoot(
        dashboard(
            .loaded(
                DayPresentation(
                    digest: macOnlyDigest, dayStart: dayStart, dayLength: day, now: now,
                    categories: Array(categories.prefix(3)),
                    // L'autre cas de la comparaison : un écart si faible qu'il
                    // ne distingue rien, et qui ne doit donc pas s'annoncer
                    // comme un écart.
                    comparison: DayComparison(
                        subject: macTotal, average: macTotal - 120, referenceDays: 5,
                        isPartial: true
                    )
                )
            ),
            canGoForward: false, scheme: .dark
        ),
        size: CGSize(width: 1000, height: 900), named: "pulseon-mac-only"
    )

    // **La vraie fenêtre d'Arthur fait 1512 points de large.** Ne regarder que
    // des rendus étroits avait laissé passer une mise en page étirée, où
    // l'anneau se perd au milieu d'une carte immense.
    shoot(
        dashboard(.loaded(today), canGoForward: false, scheme: .dark),
        size: CGSize(width: 1512, height: 949), named: "pulseon-wide"
    )
}

// MARK: - La semaine

/// Une journée de démonstration réduite à son total.
///
/// Les trois états d'une colonne y sont représentés, parce que ce sont eux qui
/// se confondent si on les dessine mal : une journée **non mesurée** (le
/// collecteur était éteint), un **vrai zéro** mesuré, et une journée **qui n'a
/// pas encore eu lieu**.
private func weekDay(
    mac: Double, tv: Double = 0, playstation: Double = 0, measured: Bool = true
) -> DayDigest {
    let hour: TimeInterval = 3600
    return DayDigest(
        date: DateComponents(),
        lanes: [
            Lane(
                device: .mac, total: mac * hour, blocks: [], topEntities: [],
                isConnected: measured
            ),
            Lane(
                device: .playstation, total: playstation * hour, blocks: [], topEntities: [],
                isConnected: measured && playstation > 0
            ),
            Lane(
                device: .tv, total: tv * hour, blocks: [], topEntities: [],
                isConnected: measured && tv > 0
            ),
        ],
        summedTotal: (mac + tv + playstation) * hour,
        // Aucun chevauchement dans cette démo : les journées y sont simples.
        coveredTotal: (mac + tv + playstation) * hour
    )
}

MainActor.assumeIsolated {
    let calendar = Calendar.current
    let weekStart = calendar.dateInterval(of: .weekOfYear, for: dayStart)?.start ?? dayStart

    /// Volontairement contrastée, et **à plusieurs appareils** : c'est la
    /// composition par couleur qu'il faut pouvoir juger sur un petit rond, pas
    /// seulement la taille. Une journée non mesurée, un vrai zéro, une soirée
    /// PlayStation, et le week-end qui n'a pas eu lieu.
    let totals: [(mac: Double, tv: Double, ps: Double, measured: Bool)] = [
        (5.4, 0.8, 0, true),
        (0, 0, 0, false),
        (7.1, 1.5, 0, true),
        (0, 0, 0, true),
        (2.3, 0.8, 1.8, true),
        (0, 0, 0, true),
        (0, 0, 0, true),
    ]
    let todayIndex = 4

    let days = totals.enumerated().map { index, day in
        PeriodPresentation.Day(
            start: calendar.date(byAdding: .day, value: index, to: weekStart) ?? weekStart,
            digest: weekDay(
                mac: day.mac, tv: day.tv, playstation: day.ps, measured: day.measured),
            isToday: index == todayIndex,
            isFuture: index > todayIndex
        )
    }

    let weekTotal = totals.reduce(0) { $0 + ($1.mac + $1.tv + $1.ps) * 3600 }
    let macTotalWeek = totals.reduce(0) { $0 + $1.mac * 3600 }
    let tvTotalWeek = totals.reduce(0) { $0 + $1.tv * 3600 }
    let psTotalWeek = totals.reduce(0) { $0 + $1.ps * 3600 }

    let weekDigest = PeriodDigest(
        days: days.map(\.digest),
        lanes: [
            Lane(
                device: .mac, total: macTotalWeek, blocks: [],
                topEntities: [
                    EntityTotal(entity: "Xcode", total: 9 * 3600),
                    EntityTotal(entity: "Ghostty", total: 4.2 * 3600),
                    EntityTotal(entity: "Brave Browser", total: 2.4 * 3600),
                ],
                isConnected: true
            ),
            Lane(
                device: .playstation, total: psTotalWeek, blocks: [],
                topEntities: [EntityTotal(entity: "Elden Ring", total: psTotalWeek)],
                isConnected: true
            ),
            Lane(
                device: .tv, total: tvTotalWeek, blocks: [], topEntities: [],
                isConnected: true
            ),
        ],
        summedTotal: weekTotal,
        coveredTotal: weekTotal,
        daysWithActivity: totals.count { $0.mac + $0.tv + $0.ps > 0 }
    )

    let weekCategories: [CategoryTotal] = [
        CategoryTotal(
            category: .development, total: 13.2 * 3600,
            entities: [
                EntityTotal(entity: "Xcode", total: 9 * 3600),
                EntityTotal(entity: "Ghostty", total: 4.2 * 3600),
            ]
        ),
        CategoryTotal(
            category: .media, total: 3.4 * 3600,
            entities: [EntityTotal(entity: "IINA", total: 3.4 * 3600)]
        ),
        CategoryTotal(
            category: .web, total: 2.4 * 3600,
            entities: [EntityTotal(entity: "Brave Browser", total: 2.4 * 3600)]
        ),
        // Minuscule exprès : le cas qui teste le « < 1 % » et le plancher de la
        // jauge.
        CategoryTotal(
            category: .communication, total: 4 * 60,
            entities: [EntityTotal(entity: "Slack", total: 4 * 60)]
        ),
    ]

    let week = PeriodPresentation(
        digest: weekDigest, days: days, categories: weekCategories)

    @MainActor
    func weekView(_ load: WeekDashboard.Load, canGoForward: Bool, scheme: ColorScheme)
        -> some View
    {
        WeekDashboardContent(
            load: load,
            canGoForward: canGoForward,
            palette: PulseonTheme.palette(for: scheme)
        )
        .environment(\.colorScheme, scheme)
        .environment(\.appIcons, demoIcons)
    }

    shoot(
        weekView(.loaded(week), canGoForward: false, scheme: .dark),
        size: CGSize(width: 860, height: 1180), named: "pulseon-week-dark"
    )
    shoot(
        weekView(.loaded(week), canGoForward: true, scheme: .light),
        size: CGSize(width: 860, height: 1180), named: "pulseon-week-light"
    )

    // Une semaine dont rien n'a été mesuré : elle ne doit pas se lire « zéro ».
    let emptyWeek = PeriodPresentation(
        digest: PeriodDigest(
            days: [],
            lanes: Device.allCases.map {
                Lane(device: $0, total: 0, blocks: [], topEntities: [], isConnected: false)
            },
            summedTotal: 0, coveredTotal: 0, daysWithActivity: 0
        ),
        days: days.map {
            PeriodPresentation.Day(
                start: $0.start, digest: weekDay(mac: 0, measured: false),
                isToday: $0.isToday, isFuture: $0.isFuture
            )
        }
    )
    shoot(
        weekView(.loaded(emptyWeek), canGoForward: true, scheme: .dark),
        size: CGSize(width: 860, height: 620), named: "pulseon-week-empty"
    )

    // La vraie fenêtre d'Arthur : 1512 points de large.
    shoot(
        weekView(.loaded(week), canGoForward: false, scheme: .dark),
        size: CGSize(width: 1512, height: 949), named: "pulseon-week-wide"
    )
}

// MARK: - La chronologie

MainActor.assumeIsolated {
    @MainActor
    func timeline(_ load: DayDashboard.Load, canGoForward: Bool, scheme: ColorScheme)
        -> some View
    {
        DayTimelineContent(
            load: load,
            canGoForward: canGoForward,
            palette: PulseonTheme.palette(for: scheme)
        )
        .environment(\.colorScheme, scheme)
    }

    let now = dayStart.addingTimeInterval(19.4 * 3600)

    // **Le cas qui teste le rail : deux écrans en même temps.** Le film du soir
    // recouvre une session Mac, donc le rail doit se diviser en hauteur — c'est
    // là que se voit ce qu'un total ne dira jamais.
    // Sans entité : une télé allumée ne dit pas ce qu'elle diffuse.
    let tvBlocks: [TraceBlock] = [
        TraceBlock(entity: nil, startOffset: 21.4 * 3600, duration: 1.4 * 3600),
        TraceBlock(entity: nil, startOffset: 13.0 * 3600, duration: 0.6 * 3600),
    ]
    let tvTotal = tvBlocks.reduce(0) { $0 + $1.duration }

    let mixed = DayDigest(
        date: digest.date,
        lanes: [
            Lane(
                device: .mac, total: macTotal, blocks: macBlocks,
                topEntities: [EntityTotal(entity: "Xcode", total: 4.8 * 3600)],
                isConnected: true
            ),
            Lane(
                device: .playstation, total: psTotal, blocks: [],
                topEntities: [EntityTotal(entity: "Elden Ring", total: psTotal)],
                isConnected: true
            ),
            Lane(device: .tv, total: tvTotal, blocks: tvBlocks, topEntities: [], isConnected: true),
        ],
        summedTotal: macTotal + psTotal + tvTotal,
        coveredTotal: macTotal + tvTotal
    )

    let mixedDay = DayPresentation(
        digest: mixed, dayStart: dayStart, dayLength: day, now: now)

    shoot(
        timeline(.loaded(mixedDay), canGoForward: false, scheme: .dark),
        size: CGSize(width: 860, height: 340), named: "pulseon-timeline-dark"
    )
    shoot(
        timeline(.loaded(mixedDay), canGoForward: true, scheme: .light),
        size: CGSize(width: 860, height: 340), named: "pulseon-timeline-light"
    )

    // Une journée passée : aucune tête de lecture, elle est entièrement jouée.
    let pastDay = DayPresentation(
        digest: digest, dayStart: dayStart.addingTimeInterval(-2 * day),
        dayLength: day, now: nil
    )
    shoot(
        timeline(.loaded(pastDay), canGoForward: true, scheme: .dark),
        size: CGSize(width: 860, height: 340), named: "pulseon-timeline-past"
    )

    // Rien de mesuré : ça ne doit pas se lire « journée à zéro ».
    let emptyDay = DayPresentation(
        digest: emptyDigest, dayStart: dayStart.addingTimeInterval(-3 * day),
        dayLength: day, now: nil
    )
    shoot(
        timeline(.loaded(emptyDay), canGoForward: true, scheme: .dark),
        size: CGSize(width: 860, height: 260), named: "pulseon-timeline-empty"
    )

    // Étroite : la règle horaire doit s'alléger au lieu de s'empiler.
    shoot(
        timeline(.loaded(mixedDay), canGoForward: false, scheme: .dark),
        size: CGSize(width: 560, height: 340), named: "pulseon-timeline-narrow"
    )
}
