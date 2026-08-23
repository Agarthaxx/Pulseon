// swift-tools-version: 6.0
import PackageDescription

// Paquet séparé, et pas une cible du paquet principal : il ne sert qu'à
// regarder les vues et n'a rien à faire dans l'app livrée. Il dépend du dépôt
// par chemin relatif, donc il suit toujours le code du moment.
let package = Package(
    name: "Preview",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(
            name: "Preview",
            dependencies: [
                .product(name: "PulseonCore", package: "creation_project"),
                .product(name: "PulseonUI", package: "creation_project"),
            ]
        ),
        // Le banc de mesure des animations de fenêtre : il ouvre et ferme la
        // vraie vue du dashboard pour chronométrer ce qui bloque le fil
        // principal. Même raison d'être que la preview — un outil qui regarde
        // l'app, pas un morceau de l'app.
        .executableTarget(
            name: "Bench",
            dependencies: [
                .product(name: "PulseonCore", package: "creation_project"),
                .product(name: "PulseonUI", package: "creation_project"),
            ]
        ),
        // L'icône : même paquet, parce qu'elle rend elle aussi des vues hors
        // écran et n'a pas sa place dans l'app livrée.
        .executableTarget(
            name: "Icon",
            dependencies: [.product(name: "PulseonUI", package: "creation_project")]
        ),
    ]
)
