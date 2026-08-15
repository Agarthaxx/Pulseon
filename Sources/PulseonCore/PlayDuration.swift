import Foundation

/// Lecture des durées ISO 8601, le format dans lequel l'API PlayStation rend
/// les temps de jeu cumulés (`"PT12H34M56S"`).
///
/// Écrit à la main plutôt que confié à `DateComponentsFormatter` : ce dernier
/// sait *produire* ces chaînes, pas les lire. Et le besoin est étroit — on ne
/// vise pas la conformité complète à la norme, seulement les formes que
/// l'API produit réellement, avec un refus net pour tout le reste.
///
/// Refuser plutôt que deviner : une durée mal lue deviendrait un temps de jeu
/// faux, et un temps de jeu faux est pire que pas de temps de jeu du tout.
public enum PlayDuration {
    /// - Returns: la durée en secondes, ou nil si la chaîne n'est pas une
    ///   durée ISO 8601 que l'on sait lire sans ambiguïté.
    public static func seconds(from text: String) -> TimeInterval? {
        var scanner = text[...]

        guard scanner.first == "P" else { return nil }
        scanner = scanner.dropFirst()

        var total: TimeInterval = 0
        var sawAnyComponent = false
        // Avant le "T" on lit des jours, après on lit heures/minutes/secondes.
        // La même lettre "M" signifie « mois » avant le T et « minutes »
        // après : sans ce drapeau, "P1M" et "PT1M" seraient confondus.
        var inTimeSection = false

        while let first = scanner.first {
            if first == "T" {
                guard !inTimeSection else { return nil }
                inTimeSection = true
                scanner = scanner.dropFirst()
                continue
            }

            let digits = scanner.prefix(while: \.isNumber)
            guard !digits.isEmpty, let value = TimeInterval(digits) else { return nil }
            scanner = scanner.dropFirst(digits.count)

            guard let unit = scanner.first else { return nil }
            scanner = scanner.dropFirst()

            let multiplier: TimeInterval?
            switch (unit, inTimeSection) {
            case ("D", false): multiplier = 86400
            case ("H", true): multiplier = 3600
            case ("M", true): multiplier = 60
            case ("S", true): multiplier = 1
            // Les mois et les années n'ont pas de durée fixe en secondes.
            // L'API ne les produit pas pour un temps de jeu ; si elle s'y
            // mettait, mieux vaut ne rien compter que compter faux.
            default: multiplier = nil
            }

            guard let multiplier else { return nil }
            total += value * multiplier
            sawAnyComponent = true
        }

        return sawAnyComponent ? total : nil
    }
}
