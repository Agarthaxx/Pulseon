import SwiftUI

/// La marque de Pulseon : un cadran percé par un battement.
///
/// **Dessinée, pas importée.** Un PNG embarqué serait flou au premier écran
/// Retina venu et ne saurait pas se redessiner en 16 points pour une liste du
/// Finder ; un chemin vectoriel est net à toutes les tailles et se rend hors
/// écran par `ImageRenderer` — c'est ce qui fabrique l'`.icns`.
///
/// Elle vit dans `PulseonUI` et non dans l'app macOS : c'est du SwiftUI pur,
/// sans AppKit, donc l'app iOS la réutilisera telle quelle.
///
/// Toutes les mesures sont des **fractions du côté**, jamais des points : la
/// même vue sert au 1024 de l'icône et au 24 d'un en-tête.
public struct PulseonMark: View {
    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                ring(side)
                ticks(side)
                pulse(side)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: L'anneau

    /// Deux arcs et non un cercle : la moitié basse part du 3 h vers le 9 h,
    /// la moitié haute revient, et les deux coupures tombent exactement sur
    /// l'axe du battement. Sans ces trous, la ligne semblerait posée
    /// *par-dessus* le cercle au lieu de le percer.
    private func ring(_ side: CGFloat) -> some View {
        let width = side * PulseonMark.weight
        let gap = 0.021
        return ZStack {
            arc(from: gap, to: 0.5 - gap, width: width)
            arc(from: 0.5 + gap, to: 1 - gap, width: width)
        }
        .frame(width: side * PulseonMark.ringDiameter, height: side * PulseonMark.ringDiameter)
        .foregroundStyle(PulseonTheme.markRing)
    }

    private func arc(from: Double, to: Double, width: CGFloat) -> some View {
        Circle()
            .inset(by: width / 2)
            .trim(from: from, to: to)
            .stroke(style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    // MARK: Les repères

    /// Trois repères, à 12 h, 3 h et 6 h. **Celui de 9 h est absent exprès** :
    /// c'est par là qu'entre le battement, et l'y dessiner ferait deux traits
    /// qui se chevauchent.
    ///
    /// **Ils disparaissent en dessous de 48 points**, et c'est assumé : à
    /// cette taille ils ne pèsent plus qu'un pixel, alors que le cercle et le
    /// pic, eux, tiennent. Une marque doit se dégrader en perdant son détail,
    /// pas sa silhouette.
    ///
    /// Ils ne mesurent rien — ni heure, ni quantité — et **ne doivent jamais
    /// devenir une graduation** : Pulseon n'affiche pas un horaire qu'il n'a
    /// pas mesuré, jusque dans son icône.
    ///
    /// Leur taille suit l'épaisseur du trait : fixes, ils passeraient de
    /// discrets à envahissants dès que l'anneau maigrit.
    private func ticks(_ side: CGFloat) -> some View {
        let thickness = side * PulseonMark.weight * 0.48
        let length = side * PulseonMark.weight
        let radius = side * 0.334
        return ZStack {
            tick(width: thickness, height: length).offset(y: -radius)
            tick(width: thickness, height: length).offset(y: radius)
            tick(width: length, height: thickness).offset(x: radius)
        }
    }

    private func tick(width: CGFloat, height: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(PulseonTheme.markTick)
            .frame(width: width, height: height)
    }

    // MARK: Le battement

    /// Le tracé **dépasse à gauche** : une ligne qui s'arrêterait pile aux
    /// bords se lirait comme un diamètre, pas comme un signal qui passe. Il
    /// s'arrête en revanche avant le repère de 3 h, sinon les deux se touchent
    /// et forment un trait unique.
    ///
    /// **L'amplitude du pic est bornée à un quart de tour de part et d'autre
    /// de l'axe.** Un premier jet le faisait monter jusqu'à l'anneau : croisé
    /// avec la ligne horizontale, le dessin devenait un **réticule de visée**.
    /// Un battement doit rester contenu *dans* le cadran, pas le traverser.
    private static let trace: [CGPoint] = [
        CGPoint(x: 0.010, y: 0.500),
        CGPoint(x: 0.272, y: 0.500),
        CGPoint(x: 0.308, y: 0.452),
        CGPoint(x: 0.344, y: 0.500),
        CGPoint(x: 0.416, y: 0.252),
        CGPoint(x: 0.478, y: 0.766),
        CGPoint(x: 0.527, y: 0.428),
        CGPoint(x: 0.570, y: 0.528),
        CGPoint(x: 0.607, y: 0.500),
        CGPoint(x: 0.772, y: 0.500),
    ]

    private func pulse(_ side: CGFloat) -> some View {
        Path { path in
            path.addLines(PulseonMark.trace.map { CGPoint(x: $0.x * side, y: $0.y * side) })
        }
        .stroke(
            PulseonTheme.markPulse,
            style: StrokeStyle(
                lineWidth: side * PulseonMark.weight,
                lineCap: .round,
                lineJoin: .round
            )
        )
        .frame(width: side, height: side)
    }

    /// L'épaisseur du trait, en fraction du côté.
    ///
    /// **Choisie sur planche, pas à l'estime** : à 0,062 (le premier jet) le
    /// trait est lourd en grand ; en dessous de 0,040 l'anneau devient fragile
    /// dès 32 points et le pic se casse.
    private static let weight: CGFloat = 0.048
    private static let ringDiameter: CGFloat = 0.885
}

/// L'icône complète : la marque posée sur son carré arrondi.
///
/// **Les proportions sont celles d'Apple**, pas des valeurs choisies à l'œil :
/// sur une toile de 1024, le carré occupe 824 points et son rayon vaut 185,4.
/// Une icône dessinée bord à bord paraît trop grosse à côté de toutes les
/// autres du Dock, et une icône trop petite paraît timide.
///
/// Elle ne suit **pas** l'apparence système : une icône d'app est la même en
/// clair et en sombre, et c'est le bleu nuit de la maquette qui fait foi.
public struct PulseonAppIcon: View {
    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            let canvas = min(geometry.size.width, geometry.size.height)
            let tile = canvas * 824.0 / 1024.0
            let radius = tile * 185.4 / 824.0
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(PulseonTheme.markGround)
                .overlay {
                    // Sans ce liseré, sur un Dock sombre, le carré n'a plus de
                    // bord.
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(PulseonTheme.markEdge, lineWidth: max(1, tile * 0.004))
                }
                .overlay {
                    PulseonMark().frame(width: tile * 0.66, height: tile * 0.66)
                }
                .frame(width: tile, height: tile)
                .frame(width: canvas, height: canvas)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
