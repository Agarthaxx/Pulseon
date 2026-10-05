import SwiftUI

/// Le logo d'une app qui n'a **aucune icône à lire sur le Mac**.
///
/// Les icônes viennent d'ordinaire du disque : macOS les fournit pour toute app
/// installée. Une app de la télé n'est pas installée sur le Mac — et YouTube n'a
/// même pas d'app macOS — donc son rond retombait toujours sur le glyphe de sa
/// catégorie, alors qu'elle est la seule app de la télé à avoir jamais été
/// nommée.
///
/// **Dessiné, jamais téléchargé.** Demander un logo à un service public dirait
/// à un tiers ce qu'on regarde, ce qui détruit la promesse « rien ne sort de ta
/// machine ». Et dessiné plutôt qu'embarqué en PNG, pour la même raison que
/// `PulseonAppIcon` : la même vue rend net le rond de 48 points comme la puce
/// de 14 d'une liste, et elle sert telle quelle à l'app iOS.
///
/// La liste est courte exprès : on n'y ajoute un logo que pour une app que la
/// télé a vraiment nommée. Une app absente garde son glyphe, qui reste vrai.
public enum BrandLogo: String, CaseIterable, Sendable {
    case youtube

    @ViewBuilder
    public var view: some View {
        switch self {
        case .youtube: YouTubeLogo()
        }
    }

    /// Le logo rendu en image, pour passer par le même chemin qu'une icône lue
    /// sur le disque.
    ///
    /// Rendu une fois à 256 points, en double densité : une icône est
    /// toujours **réduite** à l'affichage, jamais agrandie, donc la plus grande
    /// taille utile suffit à toutes les autres.
    @MainActor
    public func cgImage(side: CGFloat = 256, scale: CGFloat = 2) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: side, height: side))
        renderer.scale = scale
        return renderer.cgImage
    }
}

/// Le bouton de lecture rouge sur fond blanc — l'icône d'app de YouTube.
///
/// Posé sur le même carré arrondi que les icônes du Mac, aux proportions
/// d'Apple (824 sur 1024, rayon 185,4) : à côté de Xcode ou de Safari dans une
/// rangée, il doit avoir la même taille apparente et la même marge.
struct YouTubeLogo: View {
    private static let red = Color(red: 1, green: 0, blue: 0)

    var body: some View {
        GeometryReader { geometry in
            let canvas = min(geometry.size.width, geometry.size.height)
            let tile = canvas * 824.0 / 1024.0
            let radius = tile * 185.4 / 824.0
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.white)
                .overlay {
                    // Sans liseré, un carré blanc n'a plus de bord sur le papier
                    // clair de l'app.
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.black.opacity(0.1), lineWidth: max(1, tile * 0.006))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: tile * 0.13, style: .continuous)
                        .fill(Self.red)
                        .frame(width: tile * 0.68, height: tile * 0.48)
                        .overlay {
                            PlayTriangle()
                                .fill(.white)
                                .frame(width: tile * 0.19, height: tile * 0.21)
                                // Le centre visuel d'un triangle est à droite de
                                // son cadre : sans ce décalage, il paraît
                                // poussé vers la gauche.
                                .offset(x: tile * 0.02)
                        }
                }
                .frame(width: tile, height: tile)
                .frame(width: canvas, height: canvas)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
