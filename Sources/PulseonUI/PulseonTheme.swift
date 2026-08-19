import PulseonCore
import SwiftUI

/// La palette, résolue pour une apparence donnée.
///
/// Une **valeur** et non une collection de constantes globales, parce que la
/// maquette d'Arthur existe en clair *et* en sombre (écran 5). Une couleur en
/// `static let` ne peut pas suivre l'apparence du système, et `PulseonUI`
/// n'a pas le droit d'appeler AppKit pour la résoudre — ces vues doivent
/// compiler telles quelles pour l'app iOS.
public struct PulseonPalette: Sendable {
    /// Le fond de la fenêtre.
    public let ground: Color
    /// Une carte posée dessus.
    public let surface: Color
    /// Un creux : fond de jauge, piste vide de l'anneau.
    public let sunken: Color
    /// Un filet de séparation.
    public let hairline: Color

    public let ink: Color
    public let inkSoft: Color
    public let inkFaint: Color

    /// L'or de la maquette. Il ne décore pas : il désigne du temps mesuré.
    public let gold: Color
    /// Le bleu nuit qui lui répond dans l'anneau et l'icône.
    public let navy: Color

    /// Les deux bouts du dégradé d'or, celui de l'icône.
    ///
    /// **Une couleur unie n'a pas l'air métallique**, et c'est ce qui manquait
    /// à la première implémentation de la maquette : Arthur l'a vue « bien
    /// moins premium ». Un métal se lit à sa variation de clarté sur la
    /// surface, jamais à sa teinte moyenne.
    public let goldLight: Color
    public let goldDeep: Color
    public let navyLight: Color
    public let navyDeep: Color

    /// L'ombre portée des cartes. Elle est *portée par la profondeur*, pas
    /// décorative : c'est elle qui décolle une carte du fond, ce que l'écart de
    /// gris seul ne faisait pas assez sur un fond aussi sombre.
    public let shadow: Color

    public var goldGradient: LinearGradient {
        LinearGradient(
            colors: [goldLight, gold, goldDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var navyGradient: LinearGradient {
        LinearGradient(
            colors: [navyLight, navy, navyDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Le léger éclaircissement du haut d'une carte. Une carte parfaitement
    /// uniforme paraît imprimée ; un dégradé d'un pour cent lui donne une
    /// surface.
    public var surfaceGradient: LinearGradient {
        LinearGradient(
            colors: [surfaceTop, surface],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public let surfaceTop: Color
}

public enum PulseonTheme {
    public static func palette(for scheme: ColorScheme) -> PulseonPalette {
        scheme == .dark ? dark : light
    }

    /// Le sombre de l'écran 5 de la maquette, et de l'icône : un bleu nuit
    /// presque noir, jamais un gris neutre.
    public static let dark = PulseonPalette(
        ground: Color(red: 0.035, green: 0.045, blue: 0.075),
        surface: Color(red: 0.075, green: 0.090, blue: 0.133),
        sunken: Color(red: 0.129, green: 0.153, blue: 0.204),
        hairline: Color(red: 0.180, green: 0.208, blue: 0.271),
        ink: Color(red: 0.973, green: 0.980, blue: 0.992),
        inkSoft: Color(red: 0.655, green: 0.694, blue: 0.761),
        inkFaint: Color(red: 0.435, green: 0.475, blue: 0.549),
        gold: Color(red: 0.839, green: 0.690, blue: 0.361),
        navy: Color(red: 0.322, green: 0.435, blue: 0.718),
        goldLight: Color(red: 0.949, green: 0.859, blue: 0.612),
        goldDeep: Color(red: 0.639, green: 0.478, blue: 0.180),
        navyLight: Color(red: 0.482, green: 0.588, blue: 0.851),
        navyDeep: Color(red: 0.157, green: 0.243, blue: 0.510),
        shadow: Color.black.opacity(0.55),
        surfaceTop: Color(red: 0.098, green: 0.118, blue: 0.169)
    )

    public static let light = PulseonPalette(
        ground: Color(red: 0.945, green: 0.949, blue: 0.961),
        surface: .white,
        sunken: Color(red: 0.898, green: 0.910, blue: 0.933),
        hairline: Color(red: 0.859, green: 0.875, blue: 0.902),
        ink: Color(red: 0.043, green: 0.063, blue: 0.114),
        inkSoft: Color(red: 0.341, green: 0.384, blue: 0.451),
        inkFaint: Color(red: 0.529, green: 0.569, blue: 0.635),
        gold: Color(red: 0.694, green: 0.541, blue: 0.176),
        navy: Color(red: 0.106, green: 0.204, blue: 0.435),
        goldLight: Color(red: 0.859, green: 0.729, blue: 0.365),
        goldDeep: Color(red: 0.522, green: 0.384, blue: 0.098),
        navyLight: Color(red: 0.216, green: 0.353, blue: 0.620),
        navyDeep: Color(red: 0.059, green: 0.129, blue: 0.302),
        shadow: Color(red: 0.055, green: 0.078, blue: 0.129).opacity(0.13),
        surfaceTop: .white
    )

    // MARK: Les appareils

    /// Une couleur par appareil, tenue partout : c'est elle qui dit de quel
    /// écran on parle, donc elle porte de l'information et ne se choisit pas à
    /// l'humeur. Les trois se lisent aussi en niveaux de gris — un anneau dont
    /// les arcs ne se distinguent que par la teinte serait illisible pour un
    /// œil daltonien.
    public static func color(for device: Device, in palette: PulseonPalette) -> Color {
        switch device {
        case .mac: palette.navy
        case .playstation: palette.gold
        case .tv: Color(red: 0.427, green: 0.616, blue: 0.612)
        }
    }

    /// Une couleur par catégorie, dérivée du même axe bleu nuit → or que la
    /// maquette. **Aucune n'est rouge** : le rouge dirait « trop », et Pulseon
    /// ne juge pas.
    public static func color(for category: AppCategory, in palette: PulseonPalette) -> Color {
        tones(for: category, in: palette).base
    }

    /// La teinte claire et la teinte de base d'une catégorie.
    ///
    /// **Écrites en clair, jamais dérivées par opacité.** Éclaircir une couleur
    /// en la rendant translucide la fait « salir » vers le fond — sur un fond
    /// sombre, un vert translucide donne un olive sale, constaté en PNG. Et
    /// `Color.mix(with:by:)`, qui ferait le travail proprement, n'existe qu'à
    /// partir de macOS 15, au-dessus de la cible du projet.
    private static func tones(
        for category: AppCategory, in palette: PulseonPalette
    ) -> (light: Color, base: Color) {
        switch category {
        case .development: (palette.navyLight, palette.navy)
        case .game: (palette.goldLight, palette.gold)
        case .web:
            (Color(red: 0.529, green: 0.741, blue: 0.910), Color(red: 0.286, green: 0.518, blue: 0.741))
        case .communication:
            (Color(red: 0.686, green: 0.643, blue: 0.878), Color(red: 0.478, green: 0.427, blue: 0.722))
        case .media:
            (Color(red: 0.780, green: 0.596, blue: 0.788), Color(red: 0.588, green: 0.388, blue: 0.596))
        case .creation:
            (Color(red: 0.925, green: 0.706, blue: 0.612), Color(red: 0.784, green: 0.494, blue: 0.396))
        case .productivity:
            (Color(red: 0.573, green: 0.769, blue: 0.765), Color(red: 0.365, green: 0.573, blue: 0.569))
        case .other: (palette.inkSoft, palette.inkFaint)
        }
    }

    private static func deviceTones(
        for device: Device, in palette: PulseonPalette
    ) -> (light: Color, base: Color, deep: Color) {
        switch device {
        case .mac: (palette.navyLight, palette.navy, palette.navyDeep)
        case .playstation: (palette.goldLight, palette.gold, palette.goldDeep)
        case .tv:
            (
                Color(red: 0.573, green: 0.769, blue: 0.765),
                Color(red: 0.427, green: 0.616, blue: 0.612),
                Color(red: 0.243, green: 0.400, blue: 0.396)
            )
        }
    }

    /// La même couleur, en dégradé, pour tout ce qui a de la surface : un arc
    /// d'anneau, une jauge. **Un aplat de couleur paraît imprimé** ; c'est la
    /// variation de clarté qui donne du relief, et c'est ce qui séparait la
    /// première implémentation de la maquette — « bien moins premium ».
    public static func gradient(for device: Device, in palette: PulseonPalette) -> LinearGradient {
        let tones = deviceTones(for: device, in: palette)
        return LinearGradient(
            colors: [tones.light, tones.base, tones.deep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Les teintes d'un appareil pour un dégradé qui suit une courbe.
    ///
    /// L'ordre part du sombre pour que le haut de l'anneau — là où commence le
    /// premier arc — soit la partie claire, comme sur la maquette.
    public static func ringTones(for device: Device, in palette: PulseonPalette) -> [Color] {
        let tones = deviceTones(for: device, in: palette)
        return [tones.base, tones.light, tones.base, tones.deep]
    }

    /// Les teintes d'une catégorie pour un dégradé qui suit une courbe.
    ///
    /// Une catégorie n'a que deux tons écrits (clair et base), là où un appareil
    /// en a trois : le balayage part donc de la base, passe par le clair et y
    /// revient. Assez pour que l'arc ne paraisse pas imprimé, sans inventer une
    /// teinte sombre qui salirait la couleur — c'est déjà la raison pour
    /// laquelle les tons sont écrits en clair et non dérivés par opacité.
    public static func ringTones(
        for category: AppCategory, in palette: PulseonPalette
    ) -> [Color] {
        let tones = tones(for: category, in: palette)
        return [tones.base, tones.light, tones.base, tones.base]
    }

    public static func gradient(
        for category: AppCategory, in palette: PulseonPalette
    ) -> LinearGradient {
        let tones = tones(for: category, in: palette)
        return LinearGradient(
            colors: [tones.light, tones.base],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// L'icône d'une catégorie, en symbole système : la maquette pose une
    /// pastille colorée devant chaque ligne, et un glyphe s'y lit plus vite
    /// qu'un aplat.
    public static func symbol(for category: AppCategory) -> String {
        switch category {
        case .development: "chevron.left.forwardslash.chevron.right"
        case .web: "globe"
        case .communication: "bubble.left.and.bubble.right.fill"
        case .media: "play.rectangle.fill"
        case .creation: "paintbrush.fill"
        case .productivity: "checkmark.circle.fill"
        case .game: "gamecontroller.fill"
        case .other: "square.grid.2x2.fill"
        }
    }

    public static func symbol(for device: Device) -> String {
        switch device {
        case .mac: "laptopcomputer"
        case .playstation: "gamecontroller.fill"
        case .tv: "tv.inset.filled"
        }
    }

    // MARK: Type

    /// Les grands nombres.
    ///
    /// **Plus de caractères comprimés** : c'était le dessin d'un afficheur
    /// d'instrument, direction abandonnée. La chasse fixe des chiffres reste,
    /// pour qu'un total qui défile ne tremble pas.
    public static func readout(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold).monospacedDigit()
    }

    /// L'unité collée au grand nombre, plus petite et plus grise.
    ///
    /// Elle a besoin d'un `baselineOffset` à l'usage : partageant la ligne de
    /// base des grands chiffres, elle tombe sinon tout en bas et se lit comme
    /// un indice de formule chimique.
    public static func unit(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium)
    }

    public static let sectionTitle = Font.system(size: 12, weight: .semibold)
    public static let row = Font.system(size: 13, weight: .medium)
    public static let caption = Font.system(size: 11)
}

// MARK: - La marque

extension PulseonTheme {
    /// Les couleurs de l'icône, d'après la référence d'Arthur du 2026-08-19.
    ///
    /// **Elles ne dépendent pas de l'apparence système**, contrairement à tout
    /// le reste du thème : une icône d'app est la même en clair et en sombre,
    /// puisqu'elle vit dans le Dock et le Finder, pas dans nos fenêtres. D'où
    /// des `static let` ici — la seule exception assumée à la règle « une
    /// palette est une valeur résolue depuis `colorScheme` ».
    ///
    /// **Le bleu et le violet ne sont pas l'or du dashboard**, et c'est
    /// délibéré : l'or *désigne du temps mesuré* à l'intérieur de l'app, où il
    /// s'oppose au fond. Une icône n'a rien à désigner, elle doit se
    /// reconnaître dans une rangée d'autres icônes.

    /// Le fond de l'icône : le bleu nuit de la maquette, pas un gris neutre.
    public static let markGround = LinearGradient(
        colors: [
            Color(red: 0.086, green: 0.106, blue: 0.169),
            Color(red: 0.043, green: 0.055, blue: 0.098),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Le liseré du carré, qui décolle l'icône d'un fond sombre. Sans lui, sur
    /// un Dock sombre, le carré n'a plus de bord.
    public static let markEdge = Color.white.opacity(0.07)

    /// L'anneau. Un dégradé **angulaire** : la teinte tourne avec l'arc, donc
    /// le bleu occupe la droite et le violet la gauche. Un dégradé linéaire
    /// donnerait deux moitiés franches coupées à la diagonale.
    public static let markRing = AngularGradient(
        stops: [
            .init(color: Color(red: 0.322, green: 0.663, blue: 1.000), location: 0.00),
            .init(color: Color(red: 0.325, green: 0.596, blue: 0.996), location: 0.16),
            .init(color: Color(red: 0.435, green: 0.451, blue: 0.965), location: 0.34),
            .init(color: Color(red: 0.529, green: 0.373, blue: 0.945), location: 0.47),
            .init(color: Color(red: 0.541, green: 0.408, blue: 0.949), location: 0.58),
            .init(color: Color(red: 0.427, green: 0.549, blue: 0.988), location: 0.76),
            .init(color: Color(red: 0.373, green: 0.678, blue: 1.000), location: 0.90),
            .init(color: Color(red: 0.322, green: 0.663, blue: 1.000), location: 1.00),
        ],
        center: .center
    )

    /// Le battement, du violet à gauche vers le bleu à droite — il reprend la
    /// route de l'anneau qu'il traverse, au lieu de lui répondre par une
    /// troisième teinte.
    public static let markPulse = LinearGradient(
        colors: [
            Color(red: 0.529, green: 0.396, blue: 0.945),
            Color(red: 0.400, green: 0.545, blue: 0.988),
            Color(red: 0.361, green: 0.686, blue: 1.000),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Les repères du cadran, plus clairs que l'anneau : ils sont petits, et
    /// une teinte identique les ferait disparaître.
    public static let markTick = Color(red: 0.514, green: 0.702, blue: 1.000)
}
