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
        categories: categories
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
}
