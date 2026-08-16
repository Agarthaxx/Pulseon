import Foundation
import PulseonCore
import Testing

@testable import PulseonMacKit

/// Le collecteur Steam, sans jamais appeler Steam : les réponses sont rejouées.
///
/// Deux catégories de test ici, et la seconde compte autant que la première :
/// ce que la source comprend, et ce qu'elle refuse de laisser fuir.
@Suite struct SteamSourceTests {
    private let credentials = SteamSource.Credentials(
        apiKey: "CLE-SECRETE-DE-TEST", steamID: "76561198000000000"
    )

    private func source(
        _ body: String,
        status: Int = 200,
        credentials: SteamSource.Credentials? = nil
    ) -> SteamSource {
        let fixed = credentials ?? self.credentials
        return SteamSource(
            credentials: { fixed },
            fetch: { url in
                (
                    Data(body.utf8),
                    HTTPURLResponse(
                        url: url, statusCode: status, httpVersion: nil, headerFields: nil
                    )!
                )
            }
        )
    }

    // MARK: Ce que la source comprend

    /// **Le piège numéro un de cette API** : `playtime_forever` est en *minutes*.
    /// Le prendre pour des secondes fait une erreur d'un facteur 60 que rien ne
    /// signale — ni le compilateur, ni l'API, ni l'affichage.
    @Test("Les minutes de Steam deviennent des secondes")
    func minutesBecomeSeconds() async throws {
        let totals = try await source(
            """
            {"response":{"game_count":2,"games":[
              {"appid":570,"name":"Dota 2","playtime_forever":120},
              {"appid":730,"name":"Counter-Strike","playtime_forever":45}
            ]}}
            """
        ).readTotals()

        #expect(totals["Dota 2"] == 7200)
        #expect(totals["Counter-Strike"] == 2700)
    }

    /// Une bibliothèque contient des centaines de jeux jamais lancés. Les relever
    /// écrirait des centaines de lignes à zéro au premier passage, pour une
    /// information qui n'existe pas.
    @Test("Un jeu jamais lancé n'est pas relevé")
    func neverPlayedGamesAreSkipped() async throws {
        let totals = try await source(
            """
            {"response":{"games":[
              {"appid":1,"name":"Joué","playtime_forever":30},
              {"appid":2,"name":"Jamais lancé","playtime_forever":0},
              {"appid":3,"name":"Sans compteur"}
            ]}}
            """
        ).readTotals()

        #expect(totals.count == 1)
        #expect(totals["Joué"] == 1800)
    }

    /// **La distinction qu'exige le contrat `CounterSource`.** Steam ne renvoie
    /// pas d'erreur quand le détail des jeux du profil est privé : il renvoie un
    /// objet vide. Le confondre avec « rien joué » afficherait un zéro alors
    /// qu'on ne sait rien.
    @Test("Un profil privé lève une erreur, il ne rend pas zéro")
    func hiddenDetailsThrows() async {
        await #expect(throws: SteamSource.Failure.detailsHidden) {
            try await source(#"{"response":{}}"#).readTotals()
        }
    }

    /// Et l'inverse : une liste vide est une vraie réponse — « la source répond,
    /// elle n'a rien à déclarer ».
    @Test("Un compte sans jeu répond, il n'échoue pas")
    func emptyLibraryAnswers() async throws {
        let totals = try await source(#"{"response":{"games":[]}}"#).readTotals()
        #expect(totals.isEmpty)
    }

    @Test("Un jeu sans nom garde son identifiant plutôt qu'un titre inventé")
    func namelessGameKeepsItsIdentifier() async throws {
        let totals = try await source(
            #"{"response":{"games":[{"appid":42,"playtime_forever":60}]}}"#
        ).readTotals()

        #expect(totals["Jeu 42"] == 3600)
    }

    @Test("Deux jeux de même nom sont additionnés, jamais écrasés")
    func duplicateNamesAreSummed() async throws {
        let totals = try await source(
            """
            {"response":{"games":[
              {"appid":1,"name":"Doublon","playtime_forever":60},
              {"appid":2,"name":"Doublon","playtime_forever":30}
            ]}}
            """
        ).readTotals()

        #expect(totals["Doublon"] == 5400)
    }

    @Test("Une réponse incompréhensible ne passe pas pour un zéro")
    func malformedBodyThrows() async {
        await #expect(throws: SteamSource.Failure.malformed) {
            try await source("pas du json").readTotals()
        }
    }

    @Test("Une clé refusée se dit avec son statut")
    func rejectedKeyReportsStatus() async {
        await #expect(throws: SteamSource.Failure.http(403)) {
            try await source(#"{"response":{"games":[]}}"#, status: 403).readTotals()
        }
    }

    @Test("Des identifiants inutilisables sont refusés avant tout appel")
    func malformedCredentialsAreRejected() async {
        await #expect(throws: SteamSource.Failure.malformedCredentials) {
            try await source(
                #"{"response":{"games":[]}}"#,
                credentials: SteamSource.Credentials(apiKey: "cle", steamID: "pas-un-nombre")
            ).readTotals()
        }
        await #expect(throws: SteamSource.Failure.malformedCredentials) {
            try await source(
                #"{"response":{"games":[]}}"#,
                credentials: SteamSource.Credentials(apiKey: "  ", steamID: "76561198000000000")
            ).readTotals()
        }
    }

    // MARK: Ce que la source refuse de laisser fuir

    /// La clé d'API voyage dans l'URL. Or `CounterPoller.lastFailure` est
    /// **affiché dans le menu**, et la description d'une erreur `URLSession`
    /// contient l'URL appelée. Sans conversion, le secret sortirait par
    /// l'interface.
    @Test("Une panne réseau ne laisse jamais fuir la clé d'API")
    func transportFailureNeverLeaksTheKey() async throws {
        let leaky = URL(string: "https://api.steampowered.com/x?key=CLE-SECRETE-DE-TEST")!
        let source = SteamSource(
            credentials: { self.credentials },
            fetch: { _ in
                throw NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorTimedOut,
                    userInfo: [
                        NSLocalizedDescriptionKey: "La requête vers \(leaky) a expiré",
                        NSURLErrorFailingURLStringErrorKey: leaky.absoluteString,
                    ]
                )
            }
        )

        do {
            _ = try await source.readTotals()
            Issue.record("la panne réseau aurait dû lever une erreur")
        } catch let failure as SteamSource.Failure {
            #expect(failure == .unreachable)
            let message = failure.errorDescription ?? ""
            #expect(!message.contains("CLE-SECRETE-DE-TEST"))
            #expect(!message.contains("key="))
        }
    }

    /// L'URL, elle, doit bien porter la clé — c'est ainsi que Steam authentifie.
    /// Ce test existe pour que personne ne « corrige » l'un en cassant l'autre.
    @Test("L'URL porte la clé, l'identifiant et les options nécessaires")
    func urlCarriesWhatSteamNeeds() throws {
        let url = try SteamSource.url(for: credentials).absoluteString

        #expect(url.contains("key=CLE-SECRETE-DE-TEST"))
        #expect(url.contains("steamid=76561198000000000"))
        // Sans `include_appinfo`, la réponse ne contient que des identifiants
        // numériques : le dashboard afficherait « 570 » au lieu de « Dota 2 ».
        #expect(url.contains("include_appinfo=1"))
        #expect(url.contains("include_played_free_games=1"))
    }

    @Test("Une source Steam est bien une source à compteur")
    func steamIsACounterSource() {
        #expect(SteamSource(credentials: { self.credentials }, fetch: { _ in
            (Data(), HTTPURLResponse())
        }).device == .steam)
        #expect(Device.steam.kind == .counter)
    }
}
