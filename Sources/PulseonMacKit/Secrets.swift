import Foundation
import Security

/// Le seul endroit du projet qui sait où vivent les secrets.
///
/// Isolé volontairement : le collecteur PlayStation ne saura jamais si le
/// jeton vient du Trousseau, d'un fichier ou d'ailleurs. Changer de mécanisme
/// se fait en réécrivant ce fichier, sans toucher au reste.
///
/// Le Trousseau plutôt qu'un `.env` pour une raison qui n'est pas la
/// paranoïa : un jeton PSN appartient à **l'utilisateur**, pas au code. Un
/// secret de déploiement (mot de passe de base de données) se livre avec le
/// service et un `.env` lui va très bien. Ici, chaque personne qui
/// installerait Pulseon aurait le sien, saisi à l'exécution — c'est
/// exactement ce à quoi le Trousseau sert.
///
/// **Aucune valeur lue ou écrite ici ne doit finir dans un log**, pas même
/// tronquée, pas même dans un message d'erreur. Les fonctions ne rendent que
/// des statuts, jamais le secret dans une description d'erreur.
public enum Secrets {
    /// Le jeton de session Sony, déposé par l'utilisateur avec :
    /// `security add-generic-password -s "<service>" -a "npsso" -U -w`
    public enum PSN {
        public static let service = "com.arthurlanllier.pulseon.psn"
        public static let account = "npsso"
    }

    public enum Failure: Error, Equatable {
        /// Rien n'est rangé sous cette étiquette.
        case notFound
        /// L'utilisateur a refusé l'accès, ou le trousseau est verrouillé.
        case denied
        /// Autre erreur du Trousseau, avec son code brut — jamais le secret.
        case keychain(OSStatus)
    }

    public static func read(service: String, account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                let value = String(data: data, encoding: .utf8),
                !value.isEmpty
            else { throw Failure.notFound }
            return value
        case errSecItemNotFound:
            throw Failure.notFound
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
            throw Failure.denied
        default:
            throw Failure.keychain(status)
        }
    }

    public static func write(_ value: String, service: String, account: String) throws {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let data = Data(value.utf8)

        let update = SecItemUpdate(
            identity as CFDictionary, [kSecValueData as String: data] as CFDictionary
        )
        if update == errSecSuccess { return }

        guard update == errSecItemNotFound else {
            throw Failure.keychain(update)
        }

        var creation = identity
        creation[kSecValueData as String] = data
        let add = SecItemAdd(creation as CFDictionary, nil)
        guard add == errSecSuccess else { throw Failure.keychain(add) }
    }
}
