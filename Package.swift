// swift-tools-version: 6.0
import PackageDescription

// Le cœur partagé entre l'app iOS et l'app macOS. Volontairement sans
// dépendance sur SwiftUI ni SwiftData : la logique d'agrégation est du Swift
// pur, donc testable en ligne de commande sans Xcode ni simulateur.
let package = Package(
    name: "PulseonCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "PulseonCore", targets: ["PulseonCore"]),
        .library(name: "PulseonUI", targets: ["PulseonUI"]),
        .executable(name: "PulseonMac", targets: ["PulseonMac"]),
    ],
    targets: [
        .target(name: "PulseonCore"),
        // Les vues, séparées des deux apps parce qu'elles sont *les mêmes* :
        // le jour où la cible iOS existera, elle consommera ce paquet sans
        // qu'une ligne de dessin soit réécrite. D'où l'interdiction d'y
        // toucher à AppKit, qui n'existe pas sur iPhone.
        .target(name: "PulseonUI", dependencies: ["PulseonCore"]),
        // Tout le code macOS sauf le point d'entrée. Une bibliothèque, et pas
        // l'exécutable, parce qu'un `@main` démarre l'app dans le processus de
        // test : la cible exécutable est donc réduite au strict minimum, et
        // tout ce qui mérite d'être testé vit ici.
        .target(name: "PulseonMacKit", dependencies: ["PulseonCore", "PulseonUI"]),
        .executableTarget(name: "PulseonMac", dependencies: ["PulseonMacKit", "PulseonUI"]),
        .testTarget(name: "PulseonCoreTests", dependencies: ["PulseonCore"]),
        .testTarget(name: "PulseonUITests", dependencies: ["PulseonUI"]),
        .testTarget(name: "PulseonMacKitTests", dependencies: ["PulseonMacKit"]),
    ]
)
