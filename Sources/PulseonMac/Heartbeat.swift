import Foundation

/// La trace de vie du collecteur, volontairement tenue **hors de la base**.
///
/// Elle ne sert qu'à une chose : réparer au démarrage les sessions qu'un
/// arrêt brutal a laissées ouvertes, en les fermant au dernier instant où le
/// collecteur était vivant.
///
/// Ce n'est pas de la donnée métier, c'est l'état d'un processus — et la
/// distinction n'est pas théorique. Écrire cette date dans SwiftData à chaque
/// tick coûtait **78 Ko par écriture** (journal SQLite + historique CoreData),
/// soit environ 450 Mo par jour pour une information de 8 octets. Mesuré, pas
/// estimé.
///
/// Ici, l'horodatage *est* la date de modification d'un fichier vide : marquer
/// ne touche qu'une métadonnée, sans écrire le moindre octet de contenu, et
/// aucun arrêt brutal ne peut laisser un fichier à moitié écrit.
public final class Heartbeat {
    /// Fréquence d'écriture. Découplée du tick de vérification (15 s), qui doit
    /// rester réactif : la seule chose en jeu ici est la précision de la
    /// réparation après un crash, et une minute suffit largement pour un
    /// événement aussi rare.
    private let interval: TimeInterval = 60

    private let url: URL
    private let fileManager: FileManager
    private var lastWritten: Date?

    public init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    /// Date du dernier signe de vie, ou nil si le collecteur n'a jamais tourné.
    public func lastMark() -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        else { return nil }
        return attributes[.modificationDate] as? Date
    }

    /// - Parameter force: écrit sans attendre `interval`. Utilisé au démarrage,
    ///   pour qu'un crash survenant dans la première minute ne retombe pas sur
    ///   une trace périmée.
    public func mark(_ date: Date, force: Bool = false) {
        if !force, let last = lastWritten, date.timeIntervalSince(last) < interval {
            return
        }
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        try? fileManager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        lastWritten = date
    }
}
