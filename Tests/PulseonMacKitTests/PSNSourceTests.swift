import Foundation
import PulseonCore
import Testing

@testable import PulseonMacKit

/// Ce que l'API PlayStation dit, et ce qu'on refuse d'en déduire.
///
/// Aucun test ne touche au réseau : le réseau est injecté, et les réponses
/// rejouées ici ont la forme de celles que `Scripts/probe-psn.sh` relève sur le
/// vrai compte.
@Suite struct PSNSourceTests {

    // MARK: La lecture d'une page

    private static func page(_ json: String) -> Data { Data(json.utf8) }

    @Test("Un total ISO 8601 devient des secondes")
    func readsPlayDuration() throws {
        let page = try PSNSource.parse(
            Self.page(
                #"{"titles":[{"name":"ELDEN RING","playDuration":"PT12H34M56S"}]}"#
            )
        )
        let total = try #require(page.totals["ELDEN RING"])
        #expect(total == 12 * 3600 + 34 * 60 + 56)
    }

    @Test("Le nom localisé passe avant le nom interne — c'est celui de la console")
    func prefersLocalizedName() throws {
        let page = try PSNSource.parse(
            Self.page(
                #"""
                {"titles":[{"name":"Ghost of Tsushima","localizedName":"Ghost of Tsushima Director's Cut","playDuration":"PT2H"}]}
                """#
            )
        )
        #expect(page.totals["Ghost of Tsushima Director's Cut"] == 7200)
        #expect(page.totals["Ghost of Tsushima"] == nil)
    }

    /// **Le piège qui ferait osciller un total.** Un même jeu existe en version
    /// PS4 et PS5 : deux identifiants, un seul nom. Comme l'entité enregistrée
    /// est le nom, écraser ferait alterner le total entre deux valeurs à chaque
    /// relevé — donc des différences négatives ignorées d'un côté, et un bond
    /// inventé de l'autre.
    @Test("Deux titres de même nom s'additionnent au lieu de s'écraser")
    func sumsTitlesSharingAName() throws {
        let page = try PSNSource.parse(
            Self.page(
                #"""
                {"titles":[
                  {"titleId":"CUSA00900_00","name":"ELDEN RING","playDuration":"PT10H"},
                  {"titleId":"PPSA01284_00","name":"ELDEN RING","playDuration":"PT5H"}
                ]}
                """#
            )
        )
        // `try #require` et non `#expect` : la macro rapporte
        // « 54000.0 == 54000 » comme un échec quand un optionnel est comparé
        // à une expression arithmétique. Piège connu du projet.
        #expect(try #require(page.totals["ELDEN RING"]) == 15 * 3600)
    }

    /// Une bibliothèque en compte des centaines. Les relever écrirait autant de
    /// lignes qui n'apprennent rien.
    @Test("Un jeu jamais lancé n'entre pas dans les relevés")
    func skipsNeverPlayed() throws {
        let page = try PSNSource.parse(
            Self.page(
                #"""
                {"titles":[
                  {"name":"Jamais lancé","playDuration":"PT0S"},
                  {"name":"Sans durée"},
                  {"name":"Joué","playDuration":"PT1H"}
                ]}
                """#
            )
        )
        #expect(page.totals == ["Joué": 3600])
    }

    /// Refuser plutôt que deviner : une durée mal lue deviendrait un temps de
    /// jeu faux, et un temps de jeu faux est pire que pas de temps de jeu.
    @Test("Une durée illisible écarte le jeu, sans faire tomber la page")
    func skipsUnreadableDuration() throws {
        let page = try PSNSource.parse(
            Self.page(
                #"""
                {"titles":[
                  {"name":"Format inconnu","playDuration":"3h20"},
                  {"name":"Joué","playDuration":"PT1H"}
                ]}
                """#
            )
        )
        #expect(page.totals == ["Joué": 3600])
    }

    /// **La distinction qui empêche d'afficher un zéro qu'on n'a pas mesuré.**
    /// Une liste vide est une réponse : « le compte n'a rien joué ». Une liste
    /// absente n'en est pas une.
    @Test("Une liste vide est une réponse, une liste absente est une erreur")
    func emptyIsNotMissing() throws {
        #expect(try PSNSource.parse(Self.page(#"{"titles":[]}"#)).totals.isEmpty)
        #expect(throws: PSNSource.Failure.malformed) {
            try PSNSource.parse(Self.page(#"{"totalItemCount":0}"#))
        }
    }

    @Test("La page dit où continuer")
    func readsNextOffset() throws {
        #expect(
            try PSNSource.parse(Self.page(#"{"titles":[],"nextOffset":200}"#)).nextOffset == 200
        )
        #expect(try PSNSource.parse(Self.page(#"{"titles":[]}"#)).nextOffset == nil)
    }

    // MARK: Ce que Sony déclare de ses titres

    /// **Mesuré, pas supposé** : sur les 73 titres d'Arthur, Sony déclare
    /// `ps5_native_media_app` ou `ps5_web_based_media_app` pour les onze apps
    /// non-jeux, et `ps5_native_game` / `ps4_game` pour les autres. Personne
    /// n'a eu besoin d'écrire une liste de noms.
    @Test("La catégorie déclarée par Sony est lue, et gardée brute")
    func readsDeclaredCategory() throws {
        let page = try PSNSource.parse(
            Self.page(
                #"""
                {"titles":[
                  {"titleId":"PPSA01284_00","name":"ELDEN RING","playDuration":"PT1H","category":"ps5_native_game"},
                  {"titleId":"CUSA01015_00","name":"YouTube","playDuration":"PT2H","category":"ps5_native_media_app"}
                ]}
                """#
            )
        )
        #expect(page.declaredCategories["ELDEN RING"] == "ps5_native_game")
        #expect(page.declaredCategories["YouTube"] == "ps5_native_media_app")
        #expect(page.identifiers["ELDEN RING"] == "PPSA01284_00")
    }

    /// Deux titres additionnés sous un même nom n'ont plus d'identité propre :
    /// en garder une des deux la désignerait à tort.
    @Test("Un nom porté par deux titres perd son identifiant")
    func ambiguousNameHasNoIdentifier() throws {
        let page = try PSNSource.parse(
            Self.page(
                #"""
                {"titles":[
                  {"titleId":"CUSA00900_00","name":"Call of Duty®","playDuration":"PT10H","category":"ps4_game"},
                  {"titleId":"PPSA37414_00","name":"Call of Duty®","playDuration":"PT5H","category":"ps5_native_game"}
                ]}
                """#
            )
        )
        #expect(try #require(page.totals["Call of Duty®"]) == 15 * 3600)
        #expect(page.identifiers["Call of Duty®"] == nil)
        // La catégorie, elle, survit : deux versions du même jeu ne se
        // déclarent pas différemment.
        #expect(page.declaredCategories["Call of Duty®"] == "ps4_game")
    }

    // MARK: Le trajet complet

    /// Rejoue les trois temps de l'échange, en comptant ce qui est demandé.
    private actor Sony {
        private(set) var calls: [String] = []
        var authorizeLocation = "com.scee.psxandroid.scecompcall://redirect?code=v3.CODE"
        var titlesStatus = 200
        var pages: [String] = [#"{"titles":[{"name":"ELDEN RING","playDuration":"PT3H"}]}"#]
        var expiresIn: Double = 3600

        func setAuthorizeLocation(_ value: String) { authorizeLocation = value }
        func setTitlesStatus(_ value: Int) { titlesStatus = value }
        func setPages(_ value: [String]) { pages = value }
        func setExpiresIn(_ value: Double) { expiresIn = value }
        func count(of kind: String) -> Int { calls.filter { $0 == kind }.count }

        func answer(_ request: URLRequest) -> (Data, HTTPURLResponse) {
            let url = request.url!
            let path = url.path

            if path.hasSuffix("/authorize") {
                calls.append("authorize")
                return (
                    Data(),
                    HTTPURLResponse(
                        url: url, statusCode: 302, httpVersion: nil,
                        headerFields: ["location": authorizeLocation]
                    )!
                )
            }
            if path.hasSuffix("/token") {
                calls.append("token")
                let body = #"{"access_token":"JETON","expires_in":\#(expiresIn)}"#
                return (Data(body.utf8), Self.ok(url))
            }

            calls.append("titles")
            guard titlesStatus == 200 else {
                return (
                    Data(),
                    HTTPURLResponse(
                        url: url, statusCode: titlesStatus, httpVersion: nil, headerFields: nil
                    )!
                )
            }
            let offset =
                URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "offset" }?.value ?? "0"
            let index = (Int(offset) ?? 0) / PSNSource.pageSize
            let page = index < pages.count ? pages[index] : #"{"titles":[]}"#
            return (Data(page.utf8), Self.ok(url))
        }

        private static func ok(_ url: URL) -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        }
    }

    private func source(_ sony: Sony, npsso: String = "jeton-de-test") -> PSNSource {
        PSNSource(
            npsso: { npsso },
            fetch: { request in await sony.answer(request) }
        )
    }

    @Test("Le npsso s'échange en deux temps, puis les jeux arrivent")
    func fullExchange() async throws {
        let sony = Sony()
        let totals = try await source(sony).read().totals

        #expect(totals == ["ELDEN RING": 3 * 3600])
        #expect(await sony.calls == ["authorize", "token", "titles"])
    }

    /// Sans ça, chaque relevé referait les trois appels — quatre-vingt-seize
    /// allers-retours par jour pour une information qui change au mieux une
    /// fois par soirée.
    @Test("Le jeton d'accès est gardé d'un relevé à l'autre")
    func cachesAccessToken() async throws {
        let sony = Sony()
        let psn = source(sony)

        _ = try await psn.read()
        _ = try await psn.read()

        #expect(await sony.count(of: "authorize") == 1)
        #expect(await sony.count(of: "titles") == 2)
    }

    @Test("Un jeton d'accès périmé est refait au relevé suivant")
    func remintsExpiredToken() async throws {
        let sony = Sony()
        // Sony annonce une durée inférieure à la marge : le jeton est déjà
        // expiré au moment où on le range.
        await sony.setExpiresIn(0)
        let psn = source(sony)

        _ = try await psn.read()
        _ = try await psn.read()

        #expect(await sony.count(of: "authorize") == 2)
    }

    /// **La panne normale de cette source.** Le `npsso` vit environ deux mois,
    /// et Sony ne le dit pas par un statut d'erreur : il répond 302 vers une
    /// page de connexion, sans code. Se fier au statut HTTP ferait passer un
    /// jeton mort pour un succès.
    @Test("Une redirection sans code veut dire un npsso expiré")
    func expiredTokenIsNamed() async throws {
        let sony = Sony()
        await sony.setAuthorizeLocation("https://ca.account.sony.com/signin?e=1")

        await #expect(throws: PSNSource.Failure.tokenRejected) {
            try await source(sony).read()
        }
    }

    @Test("Un jeton d'accès rejeté est refait une fois, puis l'erreur remonte")
    func retriesOnceOn401() async throws {
        let sony = Sony()
        await sony.setTitlesStatus(401)

        await #expect(throws: PSNSource.Failure.http(401)) {
            try await source(sony).read()
        }
        // Deux échanges — le premier, puis celui de la seconde chance — et pas
        // une boucle.
        #expect(await sony.count(of: "authorize") == 2)
        #expect(await sony.count(of: "titles") == 2)
    }

    @Test("La liste pagine, et les pages se cumulent")
    func followsPages() async throws {
        let sony = Sony()
        await sony.setPages([
            #"{"titles":[{"name":"A","playDuration":"PT1H"}],"nextOffset":200}"#,
            #"{"titles":[{"name":"B","playDuration":"PT2H"}]}"#,
        ])

        let totals = try await source(sony).read().totals
        #expect(totals == ["A": 3600, "B": 7200])
    }

    /// Une pagination qui rendrait toujours le même offset ferait tourner
    /// l'agent en boucle, sans qu'aucun test ne le voie.
    @Test("Une pagination qui n'avance pas s'arrête")
    func stopsOnStalledPagination() async throws {
        let sony = Sony()
        await sony.setPages([#"{"titles":[{"name":"A","playDuration":"PT1H"}],"nextOffset":0}"#])

        let totals = try await source(sony).read().totals
        #expect(totals == ["A": 3600])
        #expect(await sony.count(of: "titles") == 1)
    }

    // MARK: Ce qui ne doit jamais sortir

    /// `CounterPoller.lastFailure` s'affiche dans le menu. Un message d'erreur
    /// qui porterait le jeton le ferait sortir par l'interface.
    @Test("Aucun message d'erreur ne porte le jeton")
    func failuresCarryNoSecret() {
        let secret = "npsso-ultra-secret-0123456789"
        let messages = [
            PSNSource.Failure.missingToken, .tokenRejected, .http(403), .malformed, .unreachable,
        ].compactMap(\.errorDescription)

        for message in messages {
            #expect(!message.contains(secret))
            #expect(!message.lowercased().contains("npsso"))
        }
    }

    /// Le réseau échoue en portant l'URL appelée dans sa description. On ne la
    /// laisse jamais remonter telle quelle.
    @Test("Une panne réseau devient « injoignable », sans détail")
    func networkErrorsAreFlattened() async throws {
        let psn = PSNSource(
            npsso: { "jeton-de-test" },
            fetch: { _ in throw URLError(.notConnectedToInternet) }
        )

        await #expect(throws: PSNSource.Failure.unreachable) {
            try await psn.read()
        }
    }

    /// **Deux pannes qui se ressemblaient et ne se réparent pas pareil.** Un
    /// jeton absent se dépose ; un jeton refusé se débloque en cliquant sur la
    /// fenêtre que macOS a fait surgir. Les afficher tous les deux comme « pas
    /// branchée » envoyait chercher au mauvais endroit — constaté à la première
    /// installation, le 2026-08-30 : le jeton était bien là.
    @Test("Un accès refusé ne se dit pas comme un jeton absent")
    func deniedIsNotMissing() throws {
        #expect(PSNSource.failure(reading: Secrets.Failure.denied) == .accessDenied)
        #expect(PSNSource.failure(reading: Secrets.Failure.keychain(-25308)) == .accessDenied)
        #expect(PSNSource.failure(reading: Secrets.Failure.notFound) == .missingToken)

        let messages = [PSNSource.Failure.missingToken, .accessDenied]
            .compactMap(\.errorDescription)
        #expect(Set(messages).count == 2)
    }

    @Test("Sans jeton au Trousseau, la source se dit débranchée")
    func missingTokenIsNamed() async throws {
        let psn = PSNSource(
            npsso: { throw PSNSource.Failure.missingToken },
            fetch: { _ in Issue.record("Aucun appel ne doit partir sans jeton"); throw PSNSource.Failure.unreachable }
        )

        await #expect(throws: PSNSource.Failure.missingToken) {
            try await psn.read()
        }
    }
}
