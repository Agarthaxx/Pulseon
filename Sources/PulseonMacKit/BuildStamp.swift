import Foundation

/// De quand date le binaire qui tourne.
///
/// **Écrit après que l'app périmée a fait passer du travail réel pour des bugs,
/// deux fois.** Le 2026-08-18 : « je ne vois aucun changement ». Le 2026-09-01 :
/// « bah c'était ça plus ou moins, l'appli n'était pas à jour ! ». Les deux fois,
/// le binaire de `/Applications` datait d'avant la séance.
///
/// La leçon avait été consignée dès la première fois et **n'a pas suffi** : ce
/// n'est donc pas un défaut de mémoire mais de **vérifiabilité**. Rien dans
/// l'app ne disait de quand elle datait, donc « le correctif ne marche pas » et
/// « le correctif n'est pas là » — deux diagnostics opposés — se ressemblaient
/// trait pour trait. Le menu le dit maintenant, et ça se lit sans rien lancer.
///
/// **La date du *build*, jamais celle du lancement.** Un agent de barre de menu
/// vit des semaines sans redémarrer : afficher « lancée le 12 août » ne dirait
/// rien de la fraîcheur du code. Et pas la date de modification du binaire non
/// plus — une copie et une signature la réécrivent toutes les deux, donc elle
/// mesure la dernière manipulation du fichier, pas la compilation.
///
/// Elle est donc **estampillée dans l'`Info.plist` par `Scripts/build-app.sh`**,
/// au moment où le code devient ce binaire-là.
public enum BuildStamp {
    /// Les clés déposées par `Scripts/build-app.sh`. Nommées ici pour que le
    /// script et la lecture ne puissent pas diverger en silence.
    public static let dateKey = "PulseonBuildDate"
    public static let commitKey = "PulseonBuildCommit"

    /// Ce que le menu affiche.
    public static var current: String {
        label(
            rawDate: Bundle.main.object(forInfoDictionaryKey: dateKey) as? String,
            commit: Bundle.main.object(forInfoDictionaryKey: commitKey) as? String
        )
    }

    /// Fonction pure : c'est elle qui se teste, `current` ne faisant que lui
    /// passer ce que le bundle contient.
    ///
    /// - Parameters:
    ///   - rawDate: l'instant de compilation en ISO 8601, tel qu'estampillé.
    ///   - commit: le SHA court, suffixé d'un `+` si l'arbre était modifié.
    static func label(
        rawDate: String?,
        commit: String?,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        // **Sans estampille, on le dit.** Le cas n'est pas théorique : lancée
        // par `swift run`, l'app n'a pas de bundle, donc pas d'`Info.plist`.
        // Inventer une date — celle du lancement, celle du fichier — ferait
        // exactement ce que cette ligne existe pour empêcher : laisser croire
        // qu'on sait de quand date le code. Même règle que « une lecture qui
        // échoue se dit », et que le tiret de la barre de menu.
        guard let rawDate, let date = ISO8601DateFormatter().date(from: rawDate) else {
            return "Version inconnue — lancée hors bundle"
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        // Le SHA est facultatif, et son absence n'efface pas la date : c'est la
        // date qui répond à « est-ce à jour ? », le SHA à « laquelle ? ».
        guard let commit, !commit.isEmpty else {
            return "Compilée le \(formatter.string(from: date))"
        }
        return "Compilée le \(formatter.string(from: date)) · \(commit)"
    }
}
