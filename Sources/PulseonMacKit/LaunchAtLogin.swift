import Foundation

/// Le lancement à l'ouverture de session.
///
/// ## Pourquoi pas `SMAppService`
///
/// L'API moderne (macOS 13+) serait le bon choix, et c'est ce vers quoi il
/// faudra revenir. Elle est inutilisable ici, vérifié à l'exécution : elle
/// exige une **vraie signature**, et une signature ad-hoc n'en est pas une.
/// Depuis `/Applications`, lancée par LaunchServices, bundle identifier
/// correct, `SMAppService.mainApp.status` renvoie quand même `notFound` — la
/// machine n'a aucune identité de signature (`security find-identity` : zéro).
///
/// Obtenir une identité suppose au minimum un compte Apple relié à Xcode, et
/// une identité *distribuable* suppose l'Apple Developer Program payant — le
/// même prérequis que CloudKit. Faire dépendre le simple démarrage automatique
/// de 99 €/an serait absurde.
///
/// ## Ce qu'on fait à la place
///
/// Un `LaunchAgent` : un fichier `.plist` déposé dans
/// `~/Library/LaunchAgents`, que launchd lit à chaque ouverture de session.
/// C'est le mécanisme historique d'Apple, il ne demande aucune signature,
/// aucun compte, et aucun privilège administrateur.
///
/// Volontairement sans sous-processus : écrire le fichier suffit, launchd le
/// découvre seul à la prochaine ouverture de session. Rien à charger, rien à
/// décharger, donc rien qui puisse échouer à moitié.
///
/// `KeepAlive` reste à faux, pour que « Quitter Pulseon » quitte vraiment au
/// lieu d'être ressuscité dans la seconde.
@MainActor
public enum LaunchAtLogin {
    public enum State: Equatable {
        case enabled
        case disabled
        /// L'app ne tourne pas depuis un `.app` installé : le chemin visé
        /// serait un dossier de build, qui peut disparaître au prochain
        /// `swift build`. Voir `Scripts/build-app.sh`.
        case unavailable
    }

    static let label = "com.arthurlanllier.pulseon"

    static var plistURL: URL {
        FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LaunchAgents/\(label).plist")
    }

    /// Chemin de l'exécutable, uniquement s'il vit dans un vrai bundle.
    static var installedExecutable: String? {
        let bundle = Bundle.main
        guard bundle.bundlePath.hasSuffix(".app"), let path = bundle.executablePath
        else { return nil }
        return path
    }

    public static var state: State {
        guard installedExecutable != nil else { return .unavailable }
        return FileManager.default.fileExists(atPath: plistURL.path) ? .enabled : .disabled
    }

    /// - Returns: nil si tout s'est bien passé, sinon un message affichable.
    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> String? {
        guard let executable = installedExecutable else {
            return "Pulseon doit être installé dans Applications pour démarrer tout seul."
        }
        let url = plistURL
        do {
            if enabled {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try plist(for: executable).write(to: url, atomically: true, encoding: .utf8)
            } else if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private static func plist(for executable: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executable)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """
    }
}
