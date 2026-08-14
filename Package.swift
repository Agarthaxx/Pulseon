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
        .executable(name: "PulseonMac", targets: ["PulseonMac"]),
    ],
    targets: [
        .target(name: "PulseonCore"),
        .executableTarget(name: "PulseonMac", dependencies: ["PulseonCore"]),
        .testTarget(name: "PulseonCoreTests", dependencies: ["PulseonCore"]),
    ]
