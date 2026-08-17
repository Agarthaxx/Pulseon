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
}

public enum PulseonTheme {
    public static func palette(for scheme: ColorScheme) -> PulseonPalette {
        scheme == .dark ? dark : light
    }

    /// Le sombre de l'écran 5 de la maquette, et de l'icône : un bleu nuit
    /// presque noir, jamais un gris neutre.
    public static let dark = PulseonPalette(
        ground: Color(red: 0.043, green: 0.055, blue: 0.086),
        surface: Color(red: 0.078, green: 0.094, blue: 0.137),
        sunken: Color(red: 0.129, green: 0.153, blue: 0.204),
        hairline: Color(red: 0.169, green: 0.196, blue: 0.255),
        ink: Color(red: 0.965, green: 0.973, blue: 0.984),
        inkSoft: Color(red: 0.639, green: 0.678, blue: 0.745),
        inkFaint: Color(red: 0.435, green: 0.475, blue: 0.549),
        gold: Color(red: 0.831, green: 0.686, blue: 0.373),
        navy: Color(red: 0.353, green: 0.463, blue: 0.729)
    )

    public static let light = PulseonPalette(
        ground: Color(red: 0.949, green: 0.953, blue: 0.965),
        surface: .white,
        sunken: Color(red: 0.902, green: 0.914, blue: 0.937),
        hairline: Color(red: 0.851, green: 0.867, blue: 0.898),
        ink: Color(red: 0.055, green: 0.078, blue: 0.129),
        inkSoft: Color(red: 0.353, green: 0.396, blue: 0.463),
        inkFaint: Color(red: 0.529, green: 0.569, blue: 0.635),
        gold: Color(red: 0.663, green: 0.518, blue: 0.184),
        navy: Color(red: 0.114, green: 0.216, blue: 0.451)
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
        switch category {
        case .development: palette.navy
        case .web: Color(red: 0.345, green: 0.573, blue: 0.769)
        case .communication: Color(red: 0.522, green: 0.475, blue: 0.741)
        case .media: Color(red: 0.635, green: 0.435, blue: 0.639)
        case .creation: Color(red: 0.816, green: 0.545, blue: 0.451)
        case .productivity: Color(red: 0.427, green: 0.616, blue: 0.612)
        case .game: palette.gold
        case .other: palette.inkFaint
        }
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
