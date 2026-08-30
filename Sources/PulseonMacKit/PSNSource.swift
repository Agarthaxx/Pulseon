import Foundation
import PulseonCore

/// Le temps de jeu PlayStation, par jeu, tel que Sony le compte.
///
/// C'est **la** source à compteur du projet, celle pour laquelle tout le
/// vocabulaire « compteur » a été écrit : l'API rend un `playDuration`
/// cumulatif par titre et **aucun horaire**. On ne saura jamais *quand* la
/// partie a eu lieu, seulement que le total a monté entre deux relevés — d'où
/// la règle qui interdit de lui inventer une position dans la journée.
///
/// ## Le trajet du jeton, en trois temps
///
/// Sony n'a pas d'API publique documentée : ce qui suit est constaté, pas lu
/// dans une spécification. Le `npsso` déposé au Trousseau ne sert jamais
/// directement — il s'échange, à chaque fois :
///
/// 1. `npsso` → **code d'autorisation**, par une redirection 302 dont
///    l'en-tête `location` porte le code ;
/// 2. code → **jeton d'accès**, qui vit une heure ;
/// 3. jeton d'accès → la liste des jeux.
///
/// Le jeton d'accès est gardé en mémoire jusqu'à son expiration
/// (`TokenVault`) : sans ça, chaque relevé referait les trois appels, soit
/// quatre-vingt-seize allers-retours par jour pour une information qui change
/// au mieux une fois par soirée.
///
/// ## Ce qu'il ne faut pas croire de cette source
///
/// **Le premier relevé d'un jeu ne compte jamais.** `DayDigestBuilder` exige
/// un relevé *antérieur* au jour pour calculer une différence, et c'est
/// délibéré : le total cumulé d'un jeu vu pour la première fois porte des
/// années de parties, pas la soirée d'hier. Conséquence à connaître avant de
/// crier au bug — **la PlayStation ne comptera rien le premier jour**, ni pour
/// un jeu lancé pour la première fois. Sous-compter est permis, inventer ne
/// l'est pas.
///
/// **Sony met ses totaux à jour avec du retard**, parfois plusieurs heures
/// après la fin d'une partie. Une soirée de jeu peut donc atterrir sur la
/// journée du lendemain. C'est une limite de la source, pas du calcul : elle
/// n'a aucun horaire à donner, et lui en fabriquer un serait précisément ce
/// que le projet s'interdit.
public struct PSNSource: CounterSource {
    /// Comment on parle au réseau. Injecté pour que les tests n'appellent
    /// jamais Sony : ils rejouent des réponses enregistrées.
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public enum Failure: Error, LocalizedError, Equatable {
        /// Rien dans le Trousseau : la source n'est pas branchée.
        case missingToken
        /// **Le jeton est là, mais macOS refuse de nous le donner.**
        ///
        /// Le cas normal, pas un accident : le jeton est déposé par
        /// `/usr/bin/security`, donc l'autorisation d'y accéder ne couvre pas
        /// Pulseon, et macOS demande confirmation à la première lecture. Et il
        /// la redemandera **après chaque réinstallation** — une signature
        /// ad-hoc change à chaque build, donc l'app n'a jamais deux fois la
        /// même identité aux yeux du Trousseau. Voir « Empaquetage ».
        ///
        /// Distinct de `missingToken`, et c'est tout l'intérêt : les deux
        /// disaient « la PlayStation n'est pas branchée », ce qui envoyait
        /// chercher un jeton absent alors qu'il fallait cliquer sur une
        /// fenêtre.
        case accessDenied
        /// **Le `npsso` n'est plus valable.** Il vit environ deux mois, et
        /// c'est la panne normale de cette source, pas un accident : il faudra
        /// en redéposer un. Distinct d'une panne réseau, parce que la conduite
        /// à tenir n'est pas la même — ici l'agent ne se réparera pas tout
        /// seul.
        case tokenRejected
        /// Statut HTTP inattendu.
        case http(Int)
        /// La réponse n'a pas la forme attendue.
        case malformed
        /// Panne réseau. **Ne porte jamais l'erreur d'origine** : la règle du
        /// projet est qu'aucune valeur de secret ne doit pouvoir sortir par un
        /// message, et `CounterPoller.lastFailure` s'affiche dans le menu. Ici
        /// le `npsso` voyage dans un en-tête et non dans l'URL, contrairement
        /// à la clé Steam — la discipline reste la même plutôt que de dépendre
        /// de ce détail.
        case unreachable

        public var errorDescription: String? {
            switch self {
            case .missingToken: "La PlayStation n'est pas branchée"
            case .accessDenied: "Trousseau : autoriser Pulseon à lire le jeton"
            case .tokenRejected: "Jeton PlayStation expiré — à redéposer"
            case .http(let code): "PlayStation a répondu \(code)"
            case .malformed: "Réponse PlayStation incompréhensible"
            case .unreachable: "PlayStation injoignable"
            }
        }
    }

    public let device: Device = .playstation

    /// Relu à chaque échange, et non gardé en mémoire : déposer un jeton neuf
    /// dans le Trousseau doit suffire à réparer la source, sans relancer
    /// l'agent.
    private let npsso: @Sendable () throws -> String
    private let fetch: Fetch
    private let vault: TokenVault

    public init(
        npsso: @escaping @Sendable () throws -> String = PSNSource.storedToken,
        fetch: @escaping Fetch = PSNSource.urlSessionFetch
    ) {
        self.npsso = npsso
        self.fetch = fetch
        self.vault = TokenVault()
    }

    public static let storedToken: @Sendable () throws -> String = {
        do {
            return try Secrets.read(service: Secrets.PSN.service, account: Secrets.PSN.account)
        } catch {
            throw Self.failure(reading: error)
        }
    }

    /// Traduit une panne du Trousseau en panne de la source.
    ///
    /// Fonction à part et non un `catch` en ligne, pour la raison habituelle :
    /// `storedToken` lit le vrai Trousseau de la machine, donc rien de ce qu'il
    /// contient ne se teste. La traduction, elle, est le morceau qui compte.
    static func failure(reading error: Error) -> Failure {
        // Absent : il n'y a rien à lire, la source n'est pas branchée.
        if case Secrets.Failure.notFound = error { return .missingToken }
        // Refus, trousseau verrouillé, ou toute autre panne : le jeton existe
        // et on n'a pas pu le lire. Confondre ce cas avec « pas branchée »
        // enverrait chercher un jeton qui est déjà là.
        return .accessDenied
    }

    // MARK: Le relevé

    public func read() async throws -> CounterReading {
        let token = try await vault.access { try await mintAccessToken() }

        do {
            return try await titles(bearer: token)
        } catch Failure.http(401) {
            // Un jeton d'accès peut être révoqué avant son échéance. On ne
            // réessaie **qu'une fois** : boucler sur un compte désactivé
            // rejouerait l'échange à chaque relevé sans jamais aboutir.
            await vault.invalidate()
            let renewed = try await vault.access { try await mintAccessToken() }
            return try await titles(bearer: renewed)
        }
    }

    /// Refait les deux premiers temps : `npsso` → code → jeton d'accès.
    private func mintAccessToken() async throws -> (token: String, expiry: Date) {
        let code = try await authorizationCode(npsso: try npsso())
        return try await accessToken(code: code)
    }

    // MARK: 1. Le code d'autorisation

    private func authorizationCode(npsso: String) async throws -> String {
        var components = URLComponents(string: "\(Self.account)/authz/v3/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "psn:mobile.v2.core psn:clientapp"),
        ]
        guard let url = components.url else { throw Failure.malformed }

        var request = URLRequest(url: url)
        request.setValue("npsso=\(npsso)", forHTTPHeaderField: "Cookie")

        let (_, response) = try await send(request)

        // **La réponse utile est la redirection elle-même, pas ce qu'elle
        // pointe.** Elle vise `com.scee.psxandroid.scecompcall://redirect`,
        // un schéma que seule l'app mobile de Sony sait ouvrir : la suivre ne
        // mène nulle part. C'est son en-tête `location` qu'on lit, d'où le
        // refus de redirection dans `urlSessionFetch` — sans lui, `URLSession`
        // suit le 302 tout seul et le code disparaît.
        let location =
            (response.value(forHTTPHeaderField: "location")
                ?? response.value(forHTTPHeaderField: "Location")) ?? ""

        guard
            let query = URLComponents(string: location)?.queryItems,
            let code = query.first(where: { $0.name == "code" })?.value,
            !code.isEmpty
        else {
            // Pas de code veut dire une seule chose en pratique : le cookie
            // n'a pas été accepté. Sony répond alors 302 vers une page de
            // connexion, sans le moindre statut d'erreur — donc se fier au
            // code HTTP ferait passer un jeton mort pour un succès.
            throw Failure.tokenRejected
        }
        return code
    }

    // MARK: 2. Le jeton d'accès

    private func accessToken(code: String) async throws -> (token: String, expiry: Date) {
        var request = URLRequest(url: URL(string: "\(Self.account)/authz/v3/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("Basic \(Self.basicAuth)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"
        )

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: Self.redirect),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "token_format", value: "jwt"),
        ]
        request.httpBody = Data((body.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await send(request)
        guard response.statusCode == 200 else {
            // 400 ici signifie un code refusé, donc un `npsso` qui vient d'être
            // accepté à l'étape d'avant et rejeté à celle-ci — en pratique un
            // jeton en fin de vie.
            throw response.statusCode == 400 ? Failure.tokenRejected : Failure.http(response.statusCode)
        }

        struct Grant: Decodable {
            let access_token: String
            let expires_in: Double?
        }
        guard let grant = try? JSONDecoder().decode(Grant.self, from: data) else {
            throw Failure.malformed
        }

        // Une minute de marge : un jeton qui expire pendant qu'on s'en sert
        // coûterait un aller-retour de plus et une erreur dans le menu, pour
        // rien. Et un défaut prudent quand Sony ne dit pas la durée.
        let lifetime = (grant.expires_in ?? 3600) - 60
        return (grant.access_token, Date().addingTimeInterval(max(lifetime, 0)))
    }

    // MARK: 3. Les jeux

    private func titles(bearer: String) async throws -> CounterReading {
        var totals: [String: TimeInterval] = [:]
        var declared: [String: String] = [:]
        var identifiers: [String: String] = [:]
        /// Les noms portés par plus d'un titre : leur identifiant est écarté.
        var ambiguous: Set<String> = []
        var offset = 0

        // La liste pagine. La borne n'est pas une élégance : une pagination
        // qui rendrait toujours le même `nextOffset` ferait tourner l'agent
        // en boucle, sans qu'aucun test ne le voie.
        for _ in 0..<Self.pageLimit {
            var components = URLComponents(string: "\(Self.gamelist)/users/me/titles")!
            components.queryItems = [
                URLQueryItem(name: "limit", value: String(Self.pageSize)),
                URLQueryItem(name: "offset", value: String(offset)),
            ]
            guard let url = components.url else { throw Failure.malformed }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await send(request)
            guard response.statusCode == 200 else { throw Failure.http(response.statusCode) }

            let page = try Self.parse(data)
            // `uniquingKeysWith: +` et non un écrasement : voir `parse`.
            totals.merge(page.totals) { $0 + $1 }
            declared.merge(page.declaredCategories) { first, _ in first }
            for (name, id) in page.identifiers {
                if identifiers.updateValue(id, forKey: name) != nil { ambiguous.insert(name) }
            }
            ambiguous.formUnion(page.ambiguousNames)

            guard let next = page.nextOffset, next > offset else { break }
            offset = next
        }

        for name in ambiguous { identifiers[name] = nil }

        return CounterReading(
            totals: totals, declaredCategories: declared, identifiers: identifiers
        )
    }

    // MARK: La lecture de la réponse

    struct Page: Equatable {
        let totals: [String: TimeInterval]
        /// Ce que Sony déclare du titre : `ps5_native_game`,
        /// `ps5_native_media_app`… Stocké brut, jamais interprété ici.
        let declaredCategories: [String: String]
        let identifiers: [String: String]
        /// Les noms portés par plusieurs titres dans cette page.
        let ambiguousNames: Set<String>
        let nextOffset: Int?
    }

    static func parse(_ data: Data) throws -> Page {
        struct Response: Decodable {
            struct Title: Decodable {
                let titleId: String?
                let name: String?
                let localizedName: String?
                let playDuration: String?
                let category: String?
            }
            let titles: [Title]?
            let nextOffset: Int?
        }

        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw Failure.malformed
        }
        // Une liste absente n'est pas une liste vide : la première veut dire
        // que la réponse n'a pas la forme attendue, la seconde que le compte
        // n'a rien joué. Les confondre afficherait zéro là où on ne sait pas.
        guard let titles = response.titles else { throw Failure.malformed }

        var totals: [String: TimeInterval] = [:]
        var declared: [String: String] = [:]
        var identifiers: [String: String] = [:]
        var ambiguous: Set<String> = []

        for title in titles {
            // Le nom localisé d'abord : c'est celui que la console affiche.
            guard let name = (title.localizedName ?? title.name)?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !name.isEmpty else { continue }

            // Un jeu sans durée lisible est écarté plutôt que compté zéro :
            // un format qu'on ne sait pas lire n'est pas une absence de jeu.
            guard let seconds = title.playDuration.flatMap(PlayDuration.seconds(from:)),
                seconds > 0
            else { continue }

            // **Additionner, jamais écraser.** Un même jeu existe souvent en
            // deux titres — la version PS4 et la version PS5 portent le même
            // nom et deux identifiants. Or l'entité enregistrée est le nom :
            // écraser ferait osciller le total entre deux valeurs à chaque
            // relevé, donc des différences négatives ignorées d'un côté et un
            // bond inventé de l'autre. La somme de deux compteurs cumulés
            // reste un compteur cumulé, et c'est bien le même jeu.
            totals[name, default: 0] += seconds

            // La catégorie du premier titre rencontré fait foi. Deux titres de
            // même nom sont le même produit — la version PS4 et la version PS5
            // ne se déclarent pas différemment.
            if declared[name] == nil { declared[name] = title.category }
            if let id = title.titleId {
                if identifiers.updateValue(id, forKey: name) != nil { ambiguous.insert(name) }
            }
        }

        // Un nom porté par deux titres n'a pas d'identifiant : les deux totaux
        // sont additionnés sous ce nom, donc aucun des deux ne le désigne. En
        // garder un serait inventer une identité — et c'est mesuré, pas
        // théorique : « Call of Duty® », « Battlefield™ 6 » et « FAR CRY®6 »
        // sont chacun deux titres dans la bibliothèque d'Arthur.
        for name in ambiguous { identifiers[name] = nil }

        return Page(
            totals: totals,
            declaredCategories: declared,
            identifiers: identifiers,
            ambiguousNames: ambiguous,
            nextOffset: response.nextOffset
        )
    }

    // MARK: Le réseau

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await fetch(request)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.unreachable
        }
    }

    /// Ces deux valeurs sont celles de l'app mobile PlayStation officielle.
    /// Elles ne sont pas des secrets — n'importe quel client les envoie en
    /// clair, et elles sont identiques pour tout le monde. Le secret, c'est le
    /// `npsso`, et lui seul vit dans le Trousseau.
    static let clientID = "09515159-7237-4370-9b40-3806e67c0891"
    static let basicAuth = "MDk1MTUxNTktNzIzNy00MzcwLTliNDAtMzgwNmU2N2MwODkxOnVjUGprYTV0bnRCMktxc1A="
    static let redirect = "com.scee.psxandroid.scecompcall://redirect"
    static let account = "https://ca.account.sony.com/api"
    static let gamelist = "https://m.np.playstation.com/api/gamelist/v2"
    static let pageSize = 200
    static let pageLimit = 10

    public static let urlSessionFetch: Fetch = { request in
        let (data, response) = try await URLSession.shared.data(
            for: request, delegate: RedirectRefusal.shared
        )
        guard let http = response as? HTTPURLResponse else { throw Failure.malformed }
        return (data, http)
    }
}

/// Empêche `URLSession` de suivre les redirections.
///
/// Sans ça, l'étape 1 est perdue : `URLSession` suit le 302 tout seul, vers un
/// schéma applicatif que rien ne sait ouvrir, et le code d'autorisation part
/// avec l'en-tête qu'on cherchait à lire. Le symptôme est trompeur — une
/// erreur réseau, là où le serveur a parfaitement répondu.
private final class RedirectRefusal: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = RedirectRefusal()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Garde le jeton d'accès jusqu'à son échéance.
///
/// Un acteur, et non une simple propriété : `CounterSource` est `Sendable` et
/// le relevé est asynchrone, donc deux relevés peuvent se croiser. Sans
/// sérialisation, ils referaient l'échange chacun de leur côté.
private actor TokenVault {
    private var token: String?
    private var expiry: Date?

    func access(
        now: Date = Date(),
        mint: () async throws -> (token: String, expiry: Date)
    ) async throws -> String {
        if let token, let expiry, expiry > now { return token }
        let fresh = try await mint()
        token = fresh.token
        expiry = fresh.expiry
        return fresh.token
    }

    func invalidate() {
        token = nil
        expiry = nil
    }
}
