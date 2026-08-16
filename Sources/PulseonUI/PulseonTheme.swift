import PulseonCore
import SwiftUI

/// L'identité visuelle, tenue en un seul endroit et partagée par les deux apps.
///
/// Parti pris : **le rack reste sombre, même en apparence claire.** Un appareil
/// de mesure ne change pas de couleur avec le papier peint, et surtout les
/// blocs d'activité ne se lisent qu'en couleur saturée sur fond sombre. Le
/// reste de la fenêtre, lui, suit le système comme n'importe quelle app native.
public enum PulseonTheme {
    // MARK: Le rack

    /// Le panneau qui porte les pistes.
    public static let rack = Color(red: 0.063, green: 0.075, blue: 0.094)
    /// Le fond d'une piste vide : la journée qu'on n'a pas passée là.
    public static let lane = Color(red: 0.090, green: 0.110, blue: 0.141)
    /// Les graduations horaires.
    public static let grid = Color(red: 0.239, green: 0.278, blue: 0.337)
    public static let rackText = Color(red: 0.902, green: 0.918, blue: 0.949)
    public static let rackTextMuted = Color(red: 0.494, green: 0.541, blue: 0.612)

    // MARK: Les appareils

    /// Une couleur par appareil, tenue partout : c'est la couleur qui dit de
    /// quel écran on parle, donc elle porte de l'information et ne se choisit
    /// pas à l'humeur.
    public static func color(for device: Device) -> Color {
        switch device {
        case .mac: Color(red: 0.353, green: 0.847, blue: 0.651)
        case .playstation: Color(red: 0.431, green: 0.561, blue: 1.0)
        case .steam: Color(red: 0.400, green: 0.780, blue: 0.898)
        case .tv: Color(red: 0.949, green: 0.651, blue: 0.353)
        }
    }

    /// Le rouge de la tête de lecture. Emprunté aux stations de travail audio,
    /// où c'est la couleur de l'enregistrement en cours — ici, la journée en
    /// train de s'écrire. Réservé à ça : aucun autre élément ne le porte.
    public static let playhead = Color(red: 1.0, green: 0.294, blue: 0.294)

    // MARK: Type

    /// Les grands nombres, en caractères comprimés et à chasse fixe.
    ///
    /// Comprimés parce que c'est le dessin des afficheurs d'instruments, et
    /// parce que ça laisse la place de dire une durée en entier sans la
    /// rapetisser. Chasse fixe pour que les chiffres ne tremblent pas quand ils
    /// défilent — un total qui gigote se lit mal et fait bon marché.
    public static func readout(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
            .width(.compressed)
            .monospacedDigit()
    }

    /// Les étiquettes de piste et la règle horaire : petites capitales espacées,
    /// le vocabulaire de la sérigraphie sur un boîtier.
    public static let stencil = Font.system(size: 10, weight: .semibold, design: .monospaced)
}
