import AppKit
import PulseonCore
import PulseonUI
import SwiftUI

// Banc de mesure de la fermeture de fenêtre.
//
// Il ouvre puis ferme **la vraie vue du dashboard**, à la taille de la fenêtre
// d'Arthur, et mesure ce qui bloque le fil principal pendant l'animation. Un
// tick de 2 ms tourne en permanence : tout écart entre deux ticks est du temps
// où le fil principal n'a rien pu dessiner, et au-delà de 16,7 ms c'est une
// image perdue à 60 Hz.
//
// Trois modes, pour isoler la cause :
//   immediate — la politique d'activation retombe en `.accessory` dans
//               `willClose`, ce que fait `DockPresence` aujourd'hui ;
//   deferred  — elle retombe après l'animation ;
//   none      — aucune bascule pendant le cycle, mais l'app repasse en
//               `.accessory` entre deux cycles, comme aujourd'hui ;
//   sticky    — l'app devient `.regular` une fois pour toutes et n'en bouge
//               plus : le témoin qui dit si la bascule elle-même est en cause.

let mode = CommandLine.arguments.dropFirst().first ?? "immediate"
let iterations = Int(CommandLine.arguments.dropFirst(2).first ?? "6") ?? 6
let deferDelay = 0.25  // la même valeur que DockPresence.closeGrace

struct ProbeDot: View {
    @State private var on = false
    var body: some View {
        Circle().fill(.red).frame(width: 8, height: 8).opacity(on ? 0.2 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

// MARK: - Une journée de démonstration, la même que la preview

let day: TimeInterval = 86_400
let dayStart = Calendar.current.startOfDay(for: Date())

private func block(_ startHour: Double, _ hours: Double, _ entity: String) -> TraceBlock {
    TraceBlock(entity: entity, startOffset: startHour * 3600, duration: hours * 3600)
}

let macBlocks: [TraceBlock] = [
    block(8.6, 0.4, "Mail"), block(9.1, 1.4, "Xcode"), block(10.6, 0.2, "Brave Browser"),
    block(10.9, 1.1, "Xcode"), block(12.2, 0.3, "Slack"),
    block(14.0, 2.3, "Xcode"), block(16.4, 0.6, "Brave Browser"), block(17.1, 1.2, "Ghostty"),
    block(21.0, 2.1, "IINA"), block(23.2, 0.05, "Ghostty"), block(13.05, 0.05, "Pixelmator"),
]
let tvBlocks: [TraceBlock] = [
    TraceBlock(entity: nil, startOffset: 19.0 * 3600, duration: 8 * 60),
    TraceBlock(entity: "YouTube", startOffset: 19.16 * 3600, duration: 164 * 60),
]
let macTotal = macBlocks.reduce(0) { $0 + $1.duration }
let tvTotal = tvBlocks.reduce(0) { $0 + $1.duration }

let digest = DayDigest(
    date: Calendar.current.dateComponents([.year, .month, .day], from: dayStart),
    lanes: [
        Lane(
            device: .mac, total: macTotal, blocks: macBlocks,
            topEntities: [
                EntityTotal(entity: "Xcode", total: 4.8 * 3600),
                EntityTotal(entity: "Ghostty", total: 1.2 * 3600),
                EntityTotal(entity: "Brave Browser", total: 0.8 * 3600),
            ], isConnected: true),
        Lane(
            device: .tv, total: tvTotal, blocks: tvBlocks,
            topEntities: [EntityTotal(entity: "YouTube", total: 164 * 60)], isConnected: true),
    ],
    summedTotal: macTotal + tvTotal,
    coveredTotal: macTotal + tvTotal - 53 * 60
)

// MARK: - Mesure

final class Ticker {
    private(set) var stamps: [CFAbsoluteTime] = []
    private var timer: Timer?
    func start() {
        stamps.reserveCapacity(500_000)
        let t = Timer(timeInterval: 0.002, repeats: true) { [self] _ in
            stamps.append(CFAbsoluteTimeGetCurrent())
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    /// Les écarts entre deux ticks, avec l'instant où chacun s'ouvre, compté
    /// depuis l'événement. Sans cet instant on sait qu'il y a eu un trou, pas
    /// s'il tombe pendant l'animation ou bien après.
    func gaps(from: CFAbsoluteTime, to: CFAbsoluteTime) -> [(gap: Double, at: Double)] {
        var out: [(gap: Double, at: Double)] = []
        guard stamps.count > 1 else { return out }
        for i in 1..<stamps.count where stamps[i] >= from && stamps[i] <= to {
            out.append((stamps[i] - stamps[i - 1], stamps[i - 1] - from))
        }
        return out
    }
}

func pump(_ seconds: Double) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

/// Le coût du dernier basculement, déposé ici parce que la mesure traverse une
/// notification et un `asyncAfter` : tout se passe sur le fil principal, d'où
/// le `nonisolated(unsafe)` qui dit au compilateur ce que le runloop garantit.
nonisolated(unsafe) var lastSwitchCost = 0.0

@discardableResult
func policy(_ p: NSApplication.ActivationPolicy) -> Double {
    guard NSApp.activationPolicy() != p else { return 0 }
    let t0 = CFAbsoluteTimeGetCurrent()
    NSApp.setActivationPolicy(p)
    return (CFAbsoluteTimeGetCurrent() - t0) * 1000
}

func stats(_ xs: [Double]) -> String {
    let s = xs.sorted()
    guard !s.isEmpty else { return "—" }
    return String(format: "médiane %.1f ms · min %.1f · max %.1f", s[s.count / 2], s.first!, s.last!)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let now = dayStart.addingTimeInterval(23.4 * 3600)
    let presentation = DayPresentation(
        digest: digest, dayStart: dayStart, dayLength: day, now: now,
        categories: CategoryDigestBuilder(classify: { _, _ in .other }).build(from: digest),
        comparison: DayComparison(
            subject: macTotal, average: macTotal - 4_800, referenceDays: 7, isPartial: true),
        anatomy: DayAnatomyBuilder().build(from: digest)
    )

    let ticker = Ticker()
    ticker.start()
    pump(0.5)

    var closeGaps: [Double] = []
    var closeDropped: [Int] = []
    var miniGaps: [Double] = []
    var miniDropped: [Int] = []
    var switchCosts: [Double] = []
    var buildTimes: [Double] = []
    var closeAt: [Double] = []
    var miniAt: [Double] = []
    var restoreGaps: [Double] = []

    // MARK: Mode « repos » — ce que coûte une fenêtre simplement ouverte
    //
    // Ajouté le 2026-08-24 : l'app installée consommait ~47 % de CPU en
    // continu, fenêtre ouverte, sans que personne ne touche à rien. Le profil
    // ne montrait que du cycle d'affichage AppKit, donc quelque chose
    // redessinait sans arrêt. Ce mode isole la seule chose qui tourne pour
    // toujours : le halo qui bat (`PulseonMotion.breath`).
    //
    //   swift run Bench idle 8 motion   → mouvement allumé, comme l'app
    //   swift run Bench idle 8 still    → mouvement éteint, le témoin
    if mode == "idle" {
        let seconds = Double(iterations)
        let motion = (CommandLine.arguments.dropFirst(3).first ?? "motion") == "motion"

        policy(.regular)
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1512, height: 949),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Pulseon"

        // Le point qui bat, SEUL dans la fenêtre : si l'animation coûte un cœur
        // même sans dashboard, ce n'est pas la taille de l'arbre qui multiplie.
        if ProcessInfo.processInfo.environment["PULSEON_ALONE"] != nil {
            window.contentView = NSHostingView(
                rootView: ZStack { Color.white; ProbeDot() }
                    .frame(minWidth: 720, minHeight: 560))
            window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
            pump(3.0)
            var u0 = rusage(); getrusage(RUSAGE_SELF, &u0)
            let c0 = Double(u0.ru_utime.tv_sec) + Double(u0.ru_utime.tv_usec) / 1e6
                + Double(u0.ru_stime.tv_sec) + Double(u0.ru_stime.tv_usec) / 1e6
            pump(Double(iterations))
            var u1 = rusage(); getrusage(RUSAGE_SELF, &u1)
            let c1 = Double(u1.ru_utime.tv_sec) + Double(u1.ru_utime.tv_usec) / 1e6
                + Double(u1.ru_stime.tv_sec) + Double(u1.ru_stime.tv_usec) / 1e6
            print("POINT SEUL : \(String(format: "%.1f", (c1 - c0) / Double(iterations) * 100)) %% d'un cœur")
            exit(0)
        }

        window.contentView = NSHostingView(
            rootView: DayDashboard(
                load: .loaded(presentation), canGoForward: false,
                onPrevious: {}, onNext: {}, onToday: {}
            )
            .frame(minWidth: 720, minHeight: 560)
            .environment(\.pulseonMotion, motion)
            .overlay(alignment: .topTrailing) {
                // Sonde : une animation perpétuelle *indépendante* du
                // dashboard. Si elle coûte autant que le halo, ce n'est pas le
                // halo qui est en cause — c'est le fait d'animer quoi que ce
                // soit dans cette fenêtre.
                if ProcessInfo.processInfo.environment["PULSEON_PROBE"] != nil {
                    ProbeDot()
                }
            }
        )
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)

        // Les animations d'entrée doivent être finies : on mesure le repos,
        // pas l'ouverture.
        pump(3.0)

        func cpuSeconds() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
                + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        }

        let cpu0 = cpuSeconds()
        let wall0 = CFAbsoluteTimeGetCurrent()
        pump(seconds)
        let used = cpuSeconds() - cpu0
        let elapsed = CFAbsoluteTimeGetCurrent() - wall0

        print(
            """

            MODE idle — fenêtre 1512 × 949 ouverte, personne n'y touche
            mouvement : \(motion ? "allumé (comme l'app)" : "éteint (témoin)")
            \(String(format: "%.1f", elapsed)) s de mur → \(String(format: "%.2f", used)) s de CPU
            = \(String(format: "%.1f", used / elapsed * 100)) %% d'un cœur
            """)
        exit(0)
    }

    if mode == "sticky" { policy(.regular); pump(0.5) }

    for i in 0..<iterations {
        policy(.regular)  // comme `prepareForWindow`

        let t0 = CFAbsoluteTimeGetCurrent()
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1512, height: 949),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Pulseon"
        window.animationBehavior = .documentWindow
        window.contentView = NSHostingView(
            rootView: DayDashboard(
                load: .loaded(presentation), canGoForward: false,
                onPrevious: {}, onNext: {}, onToday: {}
            ).frame(minWidth: 720, minHeight: 560)
        )
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        buildTimes.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        pump(1.0)

        // --- Réduction (⌘M) : aucune bascule de politique n'est en jeu ici,
        // c'est le témoin de ce que coûte l'animation elle-même.
        let tMini = CFAbsoluteTimeGetCurrent()
        window.miniaturize(nil)
        pump(1.0)
        let gm = ticker.gaps(from: tMini, to: tMini + 1.0)
        let worstMini = gm.max { $0.gap < $1.gap } ?? (gap: 0, at: 0)
        miniGaps.append(worstMini.gap * 1000)
        miniAt.append(worstMini.at * 1000)
        miniDropped.append(gm.filter { $0.gap > 1.0 / 60.0 }.count)

        let tRestore = CFAbsoluteTimeGetCurrent()
        window.deminiaturize(nil)
        pump(1.0)
        let gr = ticker.gaps(from: tRestore, to: tRestore + 1.0)
        restoreGaps.append((gr.max { $0.gap < $1.gap }?.gap ?? 0) * 1000)

        // --- Fermeture (⌘W)
        lastSwitchCost = 0
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            switch mode {
            case "immediate": lastSwitchCost = policy(.accessory)
            case "deferred":
                DispatchQueue.main.asyncAfter(deadline: .now() + deferDelay) {
                    lastSwitchCost = policy(.accessory)
                }
            default: break
            }
        }

        let tClose = CFAbsoluteTimeGetCurrent()
        window.performClose(nil)  // exactement ce que fait ⌘W
        pump(1.2)
        NotificationCenter.default.removeObserver(observer)

        let gc = ticker.gaps(from: tClose, to: tClose + 1.0)
        let worstClose = gc.max { $0.gap < $1.gap } ?? (gap: 0, at: 0)
        closeGaps.append(worstClose.gap * 1000)
        closeAt.append(worstClose.at * 1000)
        closeDropped.append(gc.filter { $0.gap > 1.0 / 60.0 }.count)
        switchCosts.append(lastSwitchCost)

        FileHandle.standardError.write(
            "  \(i + 1) : construction \(String(format: "%.0f", buildTimes[i])) ms · "
                .appending("réduction \(String(format: "%.1f", miniGaps[i])) ms à +\(String(format: "%.0f", miniAt[i])) ms (\(miniDropped[i]) img) · ")
                .appending("restauration \(String(format: "%.1f", restoreGaps[i])) ms · ")
                .appending("fermeture \(String(format: "%.1f", closeGaps[i])) ms à +\(String(format: "%.0f", closeAt[i])) ms (\(closeDropped[i]) img)\n")
                .data(using: .utf8)!)

        if mode != "sticky" { policy(.accessory) }
        pump(0.5)
    }

    // La première itération porte les coûts de démarrage (première connexion au
    // Dock, première construction de la barre de menus, premier rendu SwiftUI).
    print("""

        MODE \(mode) — \(iterations) cycles, fenêtre 1512 × 949, vraie vue DayDashboard
          FERMETURE  trou fil principal : \(stats(Array(closeGaps.dropFirst())))   [1er cycle : \(String(format: "%.1f ms", closeGaps[0]))]
                     images perdues     : \(closeDropped.dropFirst().map(String.init).joined(separator: ", "))   [1er : \(closeDropped[0])]
          RÉDUCTION  trou fil principal : \(stats(Array(miniGaps.dropFirst())))   [1er cycle : \(String(format: "%.1f ms", miniGaps[0]))]
                     images perdues     : \(miniDropped.dropFirst().map(String.init).joined(separator: ", "))   [1er : \(miniDropped[0])]
          RESTAURATION trou fil principal: \(stats(Array(restoreGaps.dropFirst())))
          setActivationPolicy           : \(stats(Array(switchCosts.dropFirst())))
          construction de la fenêtre    : \(stats(Array(buildTimes.dropFirst())))   [1er : \(String(format: "%.0f ms", buildTimes[0]))]
        """)
    exit(0)
}
