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

// MARK: - Fabrique de journées

private func block(_ startHour: Double, _ hours: Double, _ entity: String?) -> TraceBlock {
    TraceBlock(entity: entity, startOffset: startHour * 3600, duration: hours * 3600)
}

private func intervalLane(_ device: Device, _ blocks: [TraceBlock], top: [EntityTotal] = []) -> Lane {
    Lane(
        device: device,
        total: blocks.reduce(0) { $0 + $1.duration },
        blocks: blocks,
        topEntities: top,
        isConnected: !blocks.isEmpty
    )
}

private func counterLane(_ device: Device, _ entity: String, _ hours: Double) -> Lane {
    Lane(
        device: device, total: hours * 3600, blocks: [],
        topEntities: [EntityTotal(entity: entity, total: hours * 3600)],
        isConnected: true
    )
}

private func unplugged(_ device: Device) -> Lane {
    Lane(device: device, total: 0, blocks: [], topEntities: [], isConnected: false)
}

/// Assemble un digest en recalculant les deux totaux comme le vrai agrégateur,
/// pour que la maquette ne mente pas sur des chiffres qu'on va regarder.
private func digest(_ lanes: [Lane]) -> DayDigest {
    let intervals = lanes.filter { $0.kind == .interval }.flatMap(\.blocks)
    let counters = lanes.filter { $0.kind == .counter }.reduce(0) { $0 + $1.total }

    let ranges = intervals
        .map { ($0.startOffset, $0.startOffset + $0.duration) }
        .sorted { $0.0 < $1.0 }
    var covered: TimeInterval = 0
    var open: (Double, Double)?
    for range in ranges {
        if var current = open, range.0 <= current.1 {
            current.1 = max(current.1, range.1)
            open = current
        } else {
            if let current = open { covered += current.1 - current.0 }
            open = range
        }
    }
    if let current = open { covered += current.1 - current.0 }

    return DayDigest(
        date: Calendar.current.dateComponents([.year, .month, .day], from: dayStart),
        lanes: lanes,
        summedTotal: lanes.reduce(0) { $0 + $1.total },
        coveredTotal: covered + counters
    )
}

// MARK: - Les journées de démonstration

/// Une journée plausible : matinée hachée, coupure du midi, après-midi dense,
/// film le soir, et une partie de PlayStation sans horaire connu. Les blocs très
/// courts sont là exprès — c'est le cas qui casse les mises en page.
let macBlocks: [TraceBlock] = [
    block(8.6, 0.4, "Mail"), block(9.1, 1.4, "Xcode"), block(10.6, 0.2, "Brave Browser"),
    block(10.9, 1.1, "Xcode"), block(12.2, 0.3, "Slack"),
    block(14.0, 2.3, "Xcode"), block(16.4, 0.6, "Brave Browser"), block(17.1, 1.2, "Ghostty"),
    block(21.0, 2.1, "IINA"),
    block(23.2, 0.05, "Ghostty"),
]

let macTop = [
    EntityTotal(entity: "Xcode", total: 4.8 * 3600),
    EntityTotal(entity: "Ghostty", total: 1.2 * 3600),
]

let today = digest([
    intervalLane(.mac, macBlocks, top: macTop),
    counterLane(.playstation, "Elden Ring", 1.8),
    unplugged(.tv),
])

/// **Le cas qui a motivé le rail unique** : deux appareils allumés en même
/// temps. Le rail doit se diviser en hauteur, et sa hauteur ne doit pas changer.
let simultaneous = digest([
    intervalLane(.mac, macBlocks, top: macTop),
    intervalLane(
        .tv,
        [block(17.0, 1.5, nil), block(19.5, 3.2, nil)],
        top: []
    ),
    counterLane(.playstation, "Elden Ring", 1.8),
])

/// Une journée sans rien : aucune source branchée. L'état qu'on oublie de
/// dessiner, et celui qu'on voit le premier jour d'utilisation.
let emptyDay = digest(Device.allCases.map(unplugged))

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

/// On rend `DayDashboardContent` et non `DayDashboard` : **`ImageRenderer` ne
/// rend pas le contenu d'un `ScrollView`** — la première version de la refonte
/// est sortie en PNG entièrement noir à cause de ça.
///
/// Pulseon est sombre en toute circonstance, donc il n'y a plus de variante
/// claire à rendre : c'est un choix de direction, pas un oubli. Le fond doit être
/// peint ici, `ImageRenderer` ne peignant pas celui de la fenêtre.
@MainActor
func dashboard(_ load: DayDashboard.Load, canGoForward: Bool) -> some View {
    DayDashboardContent(
        load: load, canGoForward: canGoForward,
        onPrevious: {}, onNext: {}, onToday: {}
    )
    .environment(\.colorScheme, .dark)
    .background(PulseonTheme.ground)
}

MainActor.assumeIsolated {
    let now = dayStart.addingTimeInterval(19.4 * 3600)

    let presentation = DayPresentation(
        digest: today, dayStart: dayStart, dayLength: day, now: now
    )
    shoot(
        dashboard(.loaded(presentation), canGoForward: false),
        size: CGSize(width: 860, height: 620), named: "pulseon-today"
    )

    shoot(
        dashboard(
            .loaded(
                DayPresentation(digest: simultaneous, dayStart: dayStart, dayLength: day, now: now)
            ),
            canGoForward: false
        ),
        size: CGSize(width: 860, height: 620), named: "pulseon-simultaneous"
    )

    // Une journée passée et vide : pas de marqueur d'instant courant, rien de
    // branché. Doit rester visuellement distinct d'une journée à zéro.
    shoot(
        dashboard(
            .loaded(
                DayPresentation(
                    digest: emptyDay, dayStart: dayStart.addingTimeInterval(-3 * day),
                    dayLength: day, now: nil
                )
            ),
            canGoForward: true
        ),
        size: CGSize(width: 860, height: 480), named: "pulseon-empty"
    )

    shoot(
        dashboard(.failed("Base introuvable"), canGoForward: true),
        size: CGSize(width: 860, height: 420), named: "pulseon-failed"
    )

    // Une fenêtre étroite : l'axe des heures doit s'alléger, les lignes tenir,
    // et rien ne doit déborder.
    shoot(
        dashboard(.loaded(presentation), canGoForward: false),
        size: CGSize(width: 600, height: 620), named: "pulseon-narrow"
    )
}
