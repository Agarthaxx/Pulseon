import SwiftUI

/// La marque de Pulseon : un anneau et un battement.
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
    /// Les formes en concurrence, le temps qu'Arthur tranche.
    ///
    /// **À réduire à une seule une fois le choix fait** : une variante que
    /// personne ne demande est exactement le genre d'API qui ressemble à une
    /// feature livrée.
    public enum Variant: String, CaseIterable, Sendable {
        /// Le cadran de la référence : anneau coupé, battement traversant,
        /// repères à 12 h, 3 h et 6 h.
        case dial
        /// Le même sans les repères. Le battement traverse alors de part en
        /// part, symétrique.
        case pure
        /// Anneau fermé, battement **contenu** à l'intérieur. Rien ne dépasse.
        case contained
        /// L'anneau du dashboard : découpé en parts, comme une journée l'est
        /// entre ses appareils. Battement contenu.
        case composition
    }

    public let variant: Variant

    /// L'épaisseur du trait, en fraction du côté.
    public let weight: CGFloat

    public init(
        _ variant: Variant = .dial,
        weight: CGFloat = PulseonMark.defaultWeight
    ) {
        self.variant = variant
        self.weight = weight
    }

    public var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                ring(side)
                if variant == .dial { ticks(side) }
                pulse(side)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: L'anneau

    /// Les arcs qui composent l'anneau, en tours. Deux arcs pour le cadran :
    /// les coupures tombent sur l'axe du battement, sans quoi la ligne
    /// semblerait posée *par-dessus* le cercle au lieu de le percer.
    private var arcs: [ClosedRange<Double>] {
        switch variant {
        case .dial, .pure:
            let gap = 0.021
            return [gap...(0.5 - gap), (0.5 + gap)...(1 - gap)]
        case .contained:
            return [0...1]
        case .composition:
            // Trois parts inégales : une journée ne se partage pas en tiers.
            let gap = 0.011
            return [
                (0.0 + gap)...(0.54 - gap),
                (0.54 + gap)...(0.82 - gap),
                (0.82 + gap)...(1.0 - gap),
            ]
        }
    }

    private func ring(_ side: CGFloat) -> some View {
        let width = side * weight
        return ZStack {
            ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                Circle()
                    .inset(by: width / 2)
                    .trim(from: arc.lowerBound, to: arc.upperBound)
                    .stroke(style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
        .frame(width: side * PulseonMark.ringDiameter, height: side * PulseonMark.ringDiameter)
        .foregroundStyle(PulseonTheme.markRing)
    }

    // MARK: Les repères

    /// Trois repères, à 12 h, 3 h et 6 h. **Celui de 9 h est absent exprès** :
    /// c'est par là qu'entre le battement, et l'y dessiner ferait deux traits
    /// qui se chevauchent.
    ///
    /// Ils ne mesurent rien — ni heure, ni quantité. Ils disent « ceci est un
    /// cadran », ce qui est exactement ce que l'app mesure : du temps.
    ///
    /// Leur taille suit l'épaisseur du trait : fixes, ils passeraient de
    /// discrets à envahissants dès que l'anneau maigrit.
    private func ticks(_ side: CGFloat) -> some View {
        let thickness = side * weight * 0.48
        let length = side * weight
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

    /// Le tracé, en coordonnées propres : `x` de 0 à 1 sur sa propre longueur,
    /// `y` en fraction du côté.
    ///
    /// **L'amplitude du pic est bornée à un quart de tour de part et d'autre
    /// de l'axe.** Un premier jet le faisait monter jusqu'à l'anneau : croisé
    /// avec la ligne horizontale, le dessin devenait un **réticule de visée**.
    /// Un battement doit rester contenu *dans* le cadran, pas le traverser.
    private static let trace: [CGPoint] = [
        CGPoint(x: 0.000, y: 0.500),
        CGPoint(x: 0.344, y: 0.500),
        CGPoint(x: 0.391, y: 0.452),
        CGPoint(x: 0.438, y: 0.500),
        CGPoint(x: 0.533, y: 0.252),
        CGPoint(x: 0.614, y: 0.766),
        CGPoint(x: 0.678, y: 0.428),
        CGPoint(x: 0.735, y: 0.528),
        CGPoint(x: 0.783, y: 0.500),
        CGPoint(x: 1.000, y: 0.500),
    ]

    /// De où à où le battement s'étend, et de combien son amplitude est
    /// réduite.
    ///
    /// Sur le cadran il **dépasse à gauche** : une ligne qui s'arrêterait pile
    /// aux bords se lirait comme un diamètre, pas comme un signal qui passe.
    /// Et il s'arrête avant le repère de 3 h, sinon les deux se touchent et
    /// forment un trait unique.
    private var span: (start: CGFloat, end: CGFloat, amplitude: CGFloat) {
        switch variant {
        case .dial: (0.010, 0.772, 1.0)
        case .pure: (0.010, 0.990, 1.0)
        case .contained, .composition: (0.175, 0.825, 0.82)
        }
    }

    private func pulse(_ side: CGFloat) -> some View {
        let span = span
        return Path { path in
            let points = PulseonMark.trace.map { point in
                CGPoint(
                    x: (span.start + point.x * (span.end - span.start)) * side,
                    y: (0.5 + (point.y - 0.5) * span.amplitude) * side
                )
            }
            path.addLines(points)
        }
        .stroke(
            PulseonTheme.markPulse,
            style: StrokeStyle(lineWidth: side * weight, lineCap: .round, lineJoin: .round)
        )
        .frame(width: side, height: side)
    }

    public static let defaultWeight: CGFloat = 0.048
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
    public let variant: PulseonMark.Variant
    public let weight: CGFloat

    public init(
        _ variant: PulseonMark.Variant = .dial,
        weight: CGFloat = PulseonMark.defaultWeight
    ) {
        self.variant = variant
        self.weight = weight
    }

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
                    PulseonMark(variant, weight: weight)
                        .frame(width: tile * 0.66, height: tile * 0.66)
                }
                .frame(width: tile, height: tile)
                .frame(width: canvas, height: canvas)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
