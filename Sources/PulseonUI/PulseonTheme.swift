import PulseonCore
import SwiftUI

/// L'identité visuelle, tenue en un seul endroit et partagée par les deux apps.
///
/// **Direction choisie par Arthur le 2026-08-16**, sur une référence qu'il a
/// apportée : fond noir, cartes flottantes à grand rayon, **un seul accent** vert
/// acide, grands nombres avec leur unité en petit, et la donnée dessinée en
/// signal. Elle remplace la direction « instrument de mesure » précédente —
/// sérigraphie, hachures, monospace partout, rouge d'alerte — jugée trop dure
/// (« le consommateur pète un plomb en voyant ça »).
///
/// **Pulseon est sombre tout le temps, y compris en apparence claire.** C'est un
/// choix, pas un oubli : les blocs d'activité ne se lisent qu'en couleur saturée
/// sur fond sombre, et l'app se regarde surtout le soir. L'ancienne règle ne
/// concernait que le rack ; elle s'étend maintenant à toute la fenêtre.
public enum PulseonTheme {
    // MARK: Les surfaces

    /// Le fond de la fenêtre. Presque noir plutôt que noir pur : les cartes ont
    /// besoin d'un fond dont elles puissent se détacher par le haut.
    public static let ground = Color(red: 0.043, green: 0.043, blue: 0.047)
    /// Une carte.
    public static let surface = Color(red: 0.086, green: 0.090, blue: 0.102)
    /// Un creux dans une carte : le rail vide, une pastille, un fond de barre.
    /// C'est « la journée qu'on n'a pas passée là ».
    public static let surfaceSunken = Color(red: 0.129, green: 0.137, blue: 0.153)
    public static let hairline = Color(red: 0.165, green: 0.176, blue: 0.196)

    // MARK: L'encre

    public static let ink = Color(red: 0.949, green: 0.957, blue: 0.969)
    public static let inkSoft = Color(red: 0.604, green: 0.627, blue: 0.663)
    public static let inkFaint = Color(red: 0.416, green: 0.439, blue: 0.471)

    // MARK: L'accent

    /// **Le seul accent de l'app.** Il ne désigne qu'une chose : du temps
    /// d'écran mesuré. Il ne décore pas un titre, ne souligne pas un bouton, ne
    /// remplit pas une icône pour faire joli.
    ///
    /// Un accent unique est ce qui fait tenir cette direction. Trois teintes
    /// saturées — une par appareil, comme dans la version précédente — et
    /// l'ensemble redevient un tableau de bord d'ingénieur.
    public static let accent = Color(red: 0.804, green: 0.961, blue: 0.294)

    /// L'instant courant. Le seul rouge de toute l'app, et il ne sert qu'à ça.
    ///
    /// Gardé malgré l'accent unique parce qu'il ne dit pas la même chose : le
    /// vert est du temps mesuré, le rouge est le bord vivant de la journée. Mais
    /// réduit à un trait fin surmonté d'un point — l'ancien cartouche rouge vif
    /// attaquait l'œil.
    public static let now = Color(red: 1.0, green: 0.271, blue: 0.227)

    // MARK: Les appareils

    /// Un vert d'eau, pour un **second** appareil actif en même temps que le
    /// premier. Adjacent à l'accent sur la roue et de luminosité voisine : les
    /// deux se lisent comme une paire, pas comme un arc-en-ciel.
    public static let accentSecondary = Color(red: 0.294, green: 0.890, blue: 0.765)

    /// La couleur d'un appareil.
    ///
    /// **Une teinte pour l'appareil principal, une seconde pour un appareil
    /// simultané, et la *forme* pour tout le reste** : une source sans horaire est
    /// un contour pointillé, un appareil non branché n'a pas de couleur du tout.
    ///
    /// La première version de cette refonte tenait un seul accent décliné en
    /// opacités. Théorie séduisante, **rendu raté, constaté en PNG** : de la
    /// couleur translucide sur un rail gris foncé donne un olive sale, qui se lit
    /// « sali » et non « différent ». D'où deux teintes solides — et deux
    /// seulement, parce que trois recommenceraient le tableau de bord
    /// d'ingénieur qu'on vient d'abandonner.
    ///
    /// Une différence de forme survit d'ailleurs au daltonisme, là où une
    /// différence de teinte non : c'est pourquoi elle porte l'information la plus
    /// importante — « cette durée n'a pas d'horaire ».
    public static func color(for device: Device) -> Color {
        switch device {
        case .mac: accent
        case .tv: accentSecondary
        case .playstation: accent
        }
    }

    // MARK: Le type

    /// Les grands nombres.
    ///
    /// **Plus de caractères comprimés** : c'était le dessin d'un afficheur
    /// d'instrument, et c'est précisément ce qui a été écarté. Restent la graisse
    /// et le crénage serré d'un chiffre qu'on veut lire de loin.
    ///
    /// La chasse fixe des chiffres reste, elle : un total qui défile à la seconde
    /// et dont les chiffres tremblent se lit mal et fait bon marché.
    public static func readout(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold).monospacedDigit()
    }

    /// L'unité collée au grand nombre — le « bpm » sous le « 94 ». Toujours plus
    /// petite et plus grise : c'est le chiffre qu'on lit, pas son unité.
    public static func unit(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium)
    }

    /// Un titre de section.
    public static let sectionTitle = Font.system(size: 14, weight: .semibold)
    /// Une ligne de liste.
    public static let row = Font.system(size: 14)
    /// Un commentaire sous un chiffre, une unité, une heure de la règle.
    public static let caption = Font.system(size: 12)
    /// Le plus petit texte admis. En dessous, ce n'est plus une information mais
    /// une décoration illisible.
    public static let footnote = Font.system(size: 11)

    // MARK: Les formes

    public static let cardRadius: CGFloat = 20
    public static let railRadius: CGFloat = 12
    public static let blockRadius: CGFloat = 3
}

/// Une carte : le seul conteneur de l'app.
///
/// Ni bordure ni ombre portée — c'est l'écart de gris avec le fond qui crée le
/// relief. Une ombre sur fond noir ne se voit pas et n'ajoute que du bruit.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                PulseonTheme.surface,
                in: RoundedRectangle(cornerRadius: PulseonTheme.cardRadius, style: .continuous)
            )
    }
}
