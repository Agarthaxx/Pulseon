import Foundation

/// Sortir ses données de Pulseon, dans un format qu'aucune app n'a besoin de
/// lire pour être utile.
///
/// C'est l'envers de la promesse « rien ne sort de ta machine » : rien n'en sort
/// **tout seul**, mais tout doit pouvoir en sortir sur demande. Une app de
/// mesure qui garde ses mesures prisonnières demande de lui faire confiance sans
/// contrepartie.
///
/// **On exporte le brut, jamais l'agrégat.** Un total par jour et par catégorie
/// serait plus commode à ouvrir dans un tableur, et ce serait **notre
/// interprétation** : le classement d'un navigateur, le seuil d'une coupure, la
/// fusion des intervalles sont tous des choix de Pulseon. Les sessions, elles,
/// sont ce qui a été mesuré. Même règle que la catégorie déclarée d'une app,
/// stockée brute pour que tout l'historique se reclasse si l'on change d'avis.
public enum DataExport {
    public enum Format: String, Sendable, CaseIterable {
        case csv
        case json

        public var fileExtension: String { rawValue }
    }

    /// **Toujours avec le décalage horaire**, jamais en UTC nu ni en heure
    /// locale muette.
    ///
    /// Une heure locale sans décalage est ambiguë deux fois par an : la nuit du
    /// passage à l'heure d'hiver contient deux fois 02:30, et une ligne
    /// d'export ne dirait pas laquelle. Un instant UTC, lui, est exact mais
    /// illisible — or le sujet ici est le temps d'écran, qu'on lit en heures de
    /// sa propre journée. Le décalage donne les deux.
    static func timestamp(_ date: Date, in zone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = zone
        return formatter.string(from: date)
    }

    // MARK: CSV

    /// Les colonnes, dans l'ordre. Le `kind` en tête parce que les deux natures
    /// de mesure du projet ne portent pas les mêmes champs : une source à
    /// intervalles a un début et une fin, une source à compteur n'a qu'un total
    /// relevé à un instant. Les mélanger sans le dire produirait un fichier où
    /// des colonnes vides ressembleraient à des zéros.
    static let columns = [
        "kind", "device", "entity", "start", "end", "duration_seconds",
        "recorded_at", "total_seconds",
    ]

    public static func csv(
        sessions: [ActivitySession],
        samples: [CounterSample] = [],
        timeZone: TimeZone = .current
    ) -> String {
        var lines = [columns.joined(separator: ",")]

        for session in sessions {
            lines.append(
                row([
                    "session",
                    session.device.rawValue,
                    session.entity ?? "",
                    timestamp(session.start, in: timeZone),
                    // **Une session ouverte n'a pas de fin, et on ne lui en
                    // invente pas.** Écrire l'heure courante ferait passer une
                    // session en cours pour une session terminée, dans un
                    // fichier que plus personne ne pourra recouper.
                    session.end.map { timestamp($0, in: timeZone) } ?? "",
                    session.end.map { seconds($0.timeIntervalSince(session.start)) } ?? "",
                    "", "",
                ])
            )
        }

        for sample in samples {
            lines.append(
                row([
                    "counter",
                    sample.device.rawValue,
                    sample.entity,
                    "", "", "",
                    timestamp(sample.recordedAt, in: timeZone),
                    seconds(sample.total),
                ])
            )
        }

        // Une ligne finale vide : c'est ce qu'attendent la plupart des outils,
        // et ça évite qu'une concaténation colle deux fichiers bout à bout.
        return lines.joined(separator: "\n") + "\n"
    }

    private static func seconds(_ value: TimeInterval) -> String {
        // Les durées sont des secondes entières : le collecteur ne mesure rien
        // de plus fin, et une décimale laisserait croire le contraire.
        String(Int(value.rounded()))
    }

    static func row(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }

    /// L'échappement de RFC 4180.
    ///
    /// Un nom d'app peut contenir n'importe quoi — « Spotify - Musique et
    /// podcasts » vient de la télé, et rien n'interdit une virgule ou un
    /// guillemet. Sans échappement, une seule app mal nommée décale toutes les
    /// colonnes de sa ligne, et le fichier ment sans prévenir.
    ///
    /// **Ce qu'on ne fait pas** : neutraliser les noms commençant par `=` ou
    /// `+`, qu'un tableur interprète comme des formules. Le préfixer d'une
    /// apostrophe protégerait le tableur en falsifiant le nom, ce qui est
    /// exactement ce que ce projet refuse ailleurs. Le fichier dit ce qui a été
    /// mesuré.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
        else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: JSON

    /// Le même contenu, structuré — et **avec le fuseau**, sans lequel les
    /// journées ne se redécoupent pas : « du 22 août » n'a de sens que dans un
    /// fuseau donné.
    public static func json(
        sessions: [ActivitySession],
        samples: [CounterSample] = [],
        generatedAt: Date,
        timeZone: TimeZone = .current
    ) throws -> Data {
        let payload = Payload(
            generatedAt: timestamp(generatedAt, in: timeZone),
            timeZone: timeZone.identifier,
            // Nommé, et pas `$0` : à l'intérieur d'un `map` sur `end`, `$0`
            // désigne la date de fin et non la session. Écrit ainsi, la durée
            // se calculait entre la fin et elle-même — zéro partout, et ça
            // compile sans un mot.
            sessions: sessions.map { session in
                Payload.Session(
                    device: session.device.rawValue,
                    entity: session.entity,
                    start: timestamp(session.start, in: timeZone),
                    end: session.end.map { timestamp($0, in: timeZone) },
                    durationSeconds: session.end.map {
                        Int($0.timeIntervalSince(session.start).rounded())
                    }
                )
            },
            counters: samples.map { sample in
                Payload.Counter(
                    device: sample.device.rawValue,
                    entity: sample.entity,
                    totalSeconds: Int(sample.total.rounded()),
                    recordedAt: timestamp(sample.recordedAt, in: timeZone)
                )
            }
        )

        let encoder = JSONEncoder()
        // Trié et indenté : un export se relit à l'œil et se compare d'une fois
        // sur l'autre. Un JSON d'une seule ligne ne se compare pas.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    struct Payload: Encodable {
        let generatedAt: String
        let timeZone: String
        let sessions: [Session]
        let counters: [Counter]

        /// **Les champs inconnus sortent en `null`, jamais absents.**
        ///
        /// `JSONEncoder` omet les optionnels nuls par défaut, et pour un export
        /// c'est le mauvais choix : une clé absente se lit « ce format n'a pas
        /// cette colonne », une clé à `null` se lit « on ne sait pas ». C'est la
        /// même distinction que « pas encore branchée ≠ journée à zéro »,
        /// portée jusque dans le fichier. D'où l'encodage écrit à la main.
        struct Session: Encodable {
            let device: String
            /// Nul quand l'appareil n'a pas dit ce qu'il affichait — une télé
            /// dont l'app n'est pas reconnue. Nul, et surtout pas « Autre » :
            /// c'est une absence de mesure, pas une valeur.
            let entity: String?
            let start: String
            /// Nul tant que la session est en cours.
            let end: String?
            let durationSeconds: Int?

            enum CodingKeys: String, CodingKey {
                case device, entity, start, end, durationSeconds
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(device, forKey: .device)
                // `encode` et non `encodeIfPresent` : c'est toute la différence.
                try container.encode(entity, forKey: .entity)
                try container.encode(start, forKey: .start)
                try container.encode(end, forKey: .end)
                try container.encode(durationSeconds, forKey: .durationSeconds)
            }
        }

        struct Counter: Encodable {
            let device: String
            let entity: String
            let totalSeconds: Int
            let recordedAt: String
        }
    }
}
