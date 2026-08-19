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
