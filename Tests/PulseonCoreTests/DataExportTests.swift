import Foundation
import Testing

@testable import PulseonCore

/// Sortir ses données : ce que le fichier doit dire, et ce qu'il ne doit
/// surtout pas inventer.
@Suite("L'export des données")
struct DataExportTests {
    private let paris = TimeZone(identifier: "Europe/Paris")!
    private let start = Date(timeIntervalSince1970: 1_770_213_600)

    private func session(
        _ device: Device = .mac, _ entity: String? = "Xcode", from: Double = 0, to: Double? = 3600
    ) -> ActivitySession {
        ActivitySession(
            device: device, entity: entity,
            start: start.addingTimeInterval(from),
            end: to.map { start.addingTimeInterval($0) }
        )
    }

    private func lines(_ csv: String) -> [String] {
        csv.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    // MARK: L'entête et les lignes

    @Test("L'entête nomme toutes les colonnes")
    func headerNamesEveryColumn() {
        let csv = DataExport.csv(sessions: [], timeZone: paris)
        #expect(lines(csv).first == DataExport.columns.joined(separator: ","))
    }

    @Test("Une session sort avec ses bornes et sa durée")
    func sessionRow() throws {
        let csv = DataExport.csv(sessions: [session()], timeZone: paris)
        let row = try #require(lines(csv).dropFirst().first)
        let fields = row.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(fields[0] == "mac")
        #expect(fields[1] == "Xcode")
        #expect(fields[4] == "3600")
    }

    /// **Le test central.** Écrire l'heure courante à la place ferait passer une
    /// session en cours pour une session terminée, dans un fichier que plus
    /// personne ne pourra recouper avec la base.
    @Test("Une session ouverte n'a pas de fin, et on ne lui en invente pas")
    func openSessionHasNoEnd() throws {
        let csv = DataExport.csv(sessions: [session(to: nil)], timeZone: paris)
        let row = try #require(lines(csv).dropFirst().first)
        let fields = row.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        // Ni fin, ni durée : les deux se déduisent l'une de l'autre, et une
        // session en cours n'a ni l'une ni l'autre.
        #expect(fields[3] == "")
        #expect(fields[4] == "")
    }

    /// Une télé dont l'app n'est pas reconnue n'a pas d'entité. Le champ est
    /// vide — pas « Autre », qui serait une valeur là où il n'y a pas de mesure.
    @Test("Une session sans entité laisse la colonne vide")
    func missingEntityStaysEmpty() throws {
        let csv = DataExport.csv(sessions: [session(.tv, nil)], timeZone: paris)
        let row = try #require(lines(csv).dropFirst().first)
        #expect(row.split(separator: ",", omittingEmptySubsequences: false)[1] == "")
    }

    // MARK: L'échappement

    /// Sans échappement, une seule app mal nommée décale toutes les colonnes de
    /// sa ligne — et le fichier ment sans prévenir.
    @Test("Une virgule dans un nom d'app ne décale pas les colonnes")
    func commaInNameIsQuoted() throws {
        let csv = DataExport.csv(sessions: [session(.tv, "Spotify, Musique")], timeZone: paris)
        let row = try #require(lines(csv).dropFirst().first)
        #expect(row.contains("\"Spotify, Musique\""))
        // Huit colonnes, malgré la virgule dans le nom.
        #expect(row.split(separator: "\"").count > 1)
    }

    @Test("Un guillemet est doublé, comme le veut RFC 4180")
    func quoteIsDoubled() {
        #expect(DataExport.escape("a\"b") == "\"a\"\"b\"")
        #expect(DataExport.escape("simple") == "simple")
        #expect(DataExport.escape("deux\nlignes") == "\"deux\nlignes\"")
    }

    // MARK: Les instants

    /// Une heure locale sans décalage est ambiguë deux fois par an : la nuit du
    /// changement d'heure contient deux fois 02:30, et rien ne dirait laquelle.
    @Test("Chaque instant porte son décalage horaire")
    func timestampsCarryTheirOffset() {
        let stamp = DataExport.timestamp(start, in: paris)
        #expect(stamp.hasSuffix("+01:00") || stamp.hasSuffix("+02:00"))
    }

    // MARK: JSON

    @Test("Le JSON porte le fuseau, sans lequel les journées ne se redécoupent pas")
    func jsonCarriesTheTimeZone() throws {
        let data = try DataExport.json(
            sessions: [session()], generatedAt: start, timeZone: paris
        )
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"timeZone\" : \"Europe/Paris\""))
    }

    /// La durée se calcule entre le début et la fin. Écrite avec `$0` à
    /// l'intérieur d'un `map` sur `end`, elle valait la fin moins elle-même —
    /// zéro partout, et ça compilait sans un mot.
    @Test("La durée JSON est bien celle de la session")
    func jsonDurationIsTheSessionDuration() throws {
        let data = try DataExport.json(
            sessions: [session(from: 0, to: 5400)], generatedAt: start, timeZone: paris
        )
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"durationSeconds\" : 5400"))
    }

    @Test("Une session ouverte sort avec une fin nulle en JSON")
    func jsonOpenSessionHasNullEnd() throws {
        let data = try DataExport.json(
            sessions: [session(to: nil)], generatedAt: start, timeZone: paris
        )
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"end\" : null"))
        #expect(text.contains("\"durationSeconds\" : null"))
    }
}
