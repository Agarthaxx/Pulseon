import Foundation
import PulseonCore

/// Le temps de jeu Steam, par jeu, tel que Steam le compte.
///
/// C'est une source **à compteur** au sens strict du projet : l'API rend un
/// `playtime_forever` cumulatif par jeu et **aucun horaire**. On ne saura jamais
/// *quand* la partie a eu lieu, seulement que le total a monté entre deux
/// relevés — d'où la règle qui interdit de lui inventer une position dans la
/// journée.
///
/// Pourquoi Steam en premier alors que la PlayStation attend depuis plus
/// longtemps : c'est la seule source qui ne dépend ni d'un jeton bloqué ni de
/// matériel à acheter. Une clé d'API Steam est gratuite et se demande en une
/// minute, là où le `npsso` de Sony s'extrait à la main d'un navigateur — ce qui
/// est acceptable pour Arthur et rédhibitoire pour un inconnu qui téléchargerait
/// l'app.
public struct SteamSource: CounterSource {
    /// Comment on parle au réseau. Injecté pour que les tests n'appellent jamais
    /// Steam : ils rejouent des réponses enregistrées.
    public typealias Fetch = @Sendable (URL) async throws -> (Data, HTTPURLResponse)

    public struct Credentials: Sendable, Equatable {
        /// Clé d'API personnelle, obtenue sur `steamcommunity.com/dev/apikey`.
        public let apiKey: String
        /// L'identifiant à 17 chiffres du compte (SteamID64).
        public let steamID: String

        public init(apiKey: String, steamID: String) {
            self.apiKey = apiKey
            self.steamID = steamID
        }
    }

    public enum Failure: Error, LocalizedError, Equatable {
        /// Rien n'est déposé dans le Trousseau : la source n'est pas branchée.
        case missingCredentials
        /// Une clé ou un identifiant présent mais inutilisable.
        case malformedCredentials
        /// Statut HTTP inattendu. 403 signifie presque toujours une clé refusée.
        case http(Int)
        /// La réponse n'a pas la forme attendue.
        case malformed
        /// **Steam a répondu sans la liste des jeux.** C'est ce qu'il fait quand
        /// le détail des jeux du profil est privé : il ne renvoie pas d'erreur,
        /// juste un objet vide. Le confondre avec « rien joué » afficherait zéro
        /// alors qu'on ne sait pas.
        case detailsHidden
        /// Panne réseau. **Ne porte jamais l'erreur d'origine**, dont la
        /// description contient l'URL appelée — donc la clé d'API.
        case unreachable

        public var errorDescription: String? {
            switch self {
            case .missingCredentials: "Steam n'est pas branché"
            case .malformedCredentials: "Identifiants Steam inutilisables"
            case .http(let code): "Steam a répondu \(code)"
            case .malformed: "Réponse Steam incompréhensible"
            case .detailsHidden: "Le détail des jeux du profil Steam est privé"
            case .unreachable: "Steam injoignable"
            }
        }
    }

    public let device: Device = .steam

    /// Relus à chaque relevé, et non gardés en mémoire : déposer la clé dans le
    /// Trousseau doit suffire à brancher la source, sans relancer l'agent.
    private let credentials: @Sendable () throws -> Credentials
    private let fetch: Fetch

    public init(
        credentials: @escaping @Sendable () throws -> Credentials = SteamSource.storedCredentials,
        fetch: @escaping Fetch = SteamSource.urlSessionFetch
    ) {
        self.credentials = credentials
        self.fetch = fetch
    }

    public func readTotals() async throws -> [String: TimeInterval] {
        let credentials = try credentials()
        let url = try Self.url(for: credentials)

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await fetch(url)
        } catch {
            // **Ne jamais laisser fuir l'erreur d'origine.** La description d'une
            // erreur `URLSession` contient l'URL appelée, où la clé d'API est un
            // paramètre — et `CounterPoller.lastFailure` est affiché dans le
            // menu. Le secret sortirait par l'interface.
            throw Failure.unreachable
        }

        guard response.statusCode == 200 else { throw Failure.http(response.statusCode) }

        return try Self.parse(data)
    }

    // MARK: L'appel

    static func url(for credentials: Credentials) throws -> URL {
        let key = credentials.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = credentials.steamID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !id.isEmpty, id.allSatisfy(\.isNumber) else {
            throw Failure.malformedCredentials
        }

        var components = URLComponents(
            string: "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/"
        )
        components?.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "steamid", value: id),
            // Sans ça, la réponse ne contient que des identifiants numériques :
            // un dashboard qui affiche « 570 » plutôt que « Dota 2 » n'apprend
            // rien à personne.
            URLQueryItem(name: "include_appinfo", value: "1"),
            // Les jeux gratuits comptent comme du temps d'écran comme les autres.
            URLQueryItem(name: "include_played_free_games", value: "1"),
        ]

        guard let url = components?.url else { throw Failure.malformedCredentials }
        return url
    }

    public static let urlSessionFetch: Fetch = { url in
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw Failure.unreachable }
        return (data, http)
    }

    /// Lit les identifiants dans le Trousseau. Voir `Secrets` : le collecteur
    /// ignore où ils vivent.
    public static let storedCredentials: @Sendable () throws -> Credentials = {
        do {
            return Credentials(
                apiKey: try Secrets.read(
                    service: Secrets.Steam.service, account: Secrets.Steam.apiKey
                ),
                steamID: try Secrets.read(
                    service: Secrets.Steam.service, account: Secrets.Steam.steamID
                )
            )
        } catch Secrets.Failure.notFound {
            throw Failure.missingCredentials
        } catch {
            // Trousseau verrouillé ou accès refusé : on ne sait pas, ce n'est pas
            // « pas branché ». Et surtout, aucun secret dans le message.
            throw Failure.unreachable
        }
    }

    // MARK: La réponse

    private struct Payload: Decodable {
        struct Game: Decodable {
            let appid: Int
            let name: String?
            /// **En minutes**, et c'est le piège de cette API : la confondre avec
            /// des secondes fait une erreur d'un facteur 60 que rien ne signale.
            let playtimeForever: Int?

            enum CodingKeys: String, CodingKey {
                case appid
                case name
                case playtimeForever = "playtime_forever"
            }
        }

        struct Response: Decodable {
            /// Absent quand le détail des jeux du profil est privé — voir
            /// `Failure.detailsHidden`. Vide quand le compte n'a aucun jeu.
            let games: [Game]?
        }

        let response: Response
    }

    static func parse(_ data: Data) throws -> [String: TimeInterval] {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw Failure.malformed
        }

        // La distinction que le contrat `CounterSource` exige : « la source
        // répond, rien à déclarer » (liste vide) n'est pas « on ne sait pas »
        // (liste absente).
        guard let games = payload.response.games else { throw Failure.detailsHidden }

        var totals: [String: TimeInterval] = [:]
        for game in games {
            let minutes = game.playtimeForever ?? 0
            // Une bibliothèque contient des centaines de jeux jamais lancés :
            // les relever tous écrirait des centaines de lignes à zéro au premier
            // passage, pour une information qui n'existe pas.
            guard minutes > 0 else { continue }

            // Sans nom, on garde l'identifiant : c'est moins lisible mais ça
            // reste vrai. Inventer un titre serait pire.
            let name = game.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let entity = (name?.isEmpty == false ? name! : "Jeu \(game.appid)")

            // Deux jeux de même nom sont invraisemblables mais possibles ; les
            // additionner est le moins faux, et n'écrase rien en silence.
            totals[entity, default: 0] += TimeInterval(minutes) * 60
        }
        return totals
    }
}
