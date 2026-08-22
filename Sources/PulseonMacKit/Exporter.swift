import Foundation
import PulseonCore

/// Écrit l'export sur le disque, et rien de plus.
///
/// Séparé de `DataExport`, qui ne sait que fabriquer du texte : le cœur reste
/// pur et testable sans toucher au disque, et c'est ici — du côté qui connaît la
/// machine — qu'on ouvre un fichier.
@MainActor
public enum Exporter {
    /// Un nom de fichier qui se range tout seul dans un dossier de
    /// téléchargements : la date en tête, au format qui trie correctement.
    public static func suggestedName(for format: DataExport.Format, on date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "pulseon-\(formatter.string(from: date)).\(format.fileExtension)"
    }

    /// - Returns: le nombre de sessions et de relevés écrits, de quoi dire à
    ///   l'utilisateur ce qu'il vient d'obtenir. Un export silencieux ne
    ///   distingue pas « tout est là » de « le fichier est vide ».
    @discardableResult
    public static func write(
        _ format: DataExport.Format,
        from store: SessionStore,
        to url: URL,
        now: Date = Date()
    ) throws -> (sessions: Int, samples: Int) {
        let sessions = try store.allSessions()
        let samples = try store.allSamples()

        let data: Data
        switch format {
        case .csv:
            data = Data(DataExport.csv(sessions: sessions, samples: samples).utf8)
        case .json:
            data = try DataExport.json(sessions: sessions, samples: samples, generatedAt: now)
        }

        try data.write(to: url, options: .atomic)
        return (sessions.count, samples.count)
    }
}
