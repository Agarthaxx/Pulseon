import Foundation

/// Mise en forme des durées, partagée par les deux apps.
///
/// Écrit à la main plutôt que confié à `DateComponentsFormatter` : on veut un
/// contrôle exact sur le zéro initial et sur le point de bascule entre les
/// deux formes, et surtout des tests qui ne dépendent pas de la langue du
/// système.
public enum DurationFormat {
    /// Forme resserrée, pour la barre de menu : `3h07`, `42 min`.
    ///
    /// La barre de menu est un espace partagé avec toutes les autres apps :
    /// chaque caractère y coûte, d'où l'absence d'espaces autour du `h`.
    public static func compact(_ seconds: TimeInterval) -> String {
        let (hours, minutes) = split(seconds)
        if hours == 0 { return "\(minutes) min" }
        return "\(hours)h\(pad(minutes))"
    }

    /// Forme vivante, pour un compteur qui défile : `3h07:12`, `7m12`, `42s`.
    ///
    /// L'unité (`h`, `m`, `s`) est ce qui distingue une *durée* de l'horloge
    /// juste à côté : `3h07:12` ne peut pas se lire comme sept heures du matin.
    /// Le dernier segment est toujours les secondes, d'où sa largeur fixe.
    ///
    /// Le palier suit la durée : afficher `0h00:42` au réveil ferait ressembler
    /// un compteur qui monte à un minuteur en panne.
    public static func live(_ seconds: TimeInterval) -> String {
        let (hours, minutes, secs) = splitFull(seconds)
        if hours > 0 { return "\(hours)h\(pad(minutes)):\(pad(secs))" }
        if minutes > 0 { return "\(minutes)m\(pad(secs))" }
        return "\(secs)s"
    }

    /// Forme longue, pour le menu déroulant : `3 h 07`, `42 min`.
    public static func long(_ seconds: TimeInterval) -> String {
        let (hours, minutes) = split(seconds)
        if hours == 0 { return "\(minutes) min" }
        return "\(hours) h \(pad(minutes))"
    }

    /// Les minutes sont **tronquées**, jamais arrondies : afficher 1 h alors
    /// que 59 min 40 se sont écoulées annoncerait du temps qui n'a pas eu
    /// lieu. Même règle que partout ailleurs — sous-compter est permis,
    /// inventer ne l'est pas.
    ///
    /// Une durée négative n'a pas de sens ici et vaut zéro : `DayDigest` ne
    /// peut pas en produire, mais mieux vaut `0 min` que `-1h59`.
    private static func split(_ seconds: TimeInterval) -> (hours: Int, minutes: Int) {
        guard seconds > 0, seconds.isFinite else { return (0, 0) }
        let total = Int(seconds)
        return (total / 3600, (total % 3600) / 60)
    }

    /// Même troncature que `split`, poussée jusqu'aux secondes.
    private static func splitFull(
        _ seconds: TimeInterval
    ) -> (hours: Int, minutes: Int, seconds: Int) {
        guard seconds > 0, seconds.isFinite else { return (0, 0, 0) }
        let total = Int(seconds)
        return (total / 3600, (total % 3600) / 60, total % 60)
    }

    private static func pad(_ minutes: Int) -> String {
        minutes < 10 ? "0\(minutes)" : "\(minutes)"
    }
}
