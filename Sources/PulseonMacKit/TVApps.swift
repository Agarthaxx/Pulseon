import Foundation
import PulseonCore

/// Une app de la télé, **telle que la télé la nomme**.
///
/// Le nom n'est jamais écrit par Pulseon : il vient du champ `name` de la
/// réponse, donc il est déjà localisé et déjà juste. Sur la télé d'Arthur,
/// l'identifiant `3201606009684` se présente « Spotify - Musique et podcasts »
/// et `3201910019420` « b.tv » — deux noms que personne n'aurait devinés depuis
/// un catalogue écrit à la main. On code en dur des identifiants, jamais des
/// libellés.
public struct TVApp: Sendable, Equatable {
    /// L'identifiant Tizen, seule chose que Pulseon connaisse d'avance.
    public let id: String
    /// Le nom donné par la télé.
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Ce que la télé a répondu quand on lui a demandé quelle app est à l'écran.
///
/// Trois états, comme `TVReading`, et pour la même raison : ne pas savoir n'est
/// pas une absence. Confondre les deux ferait basculer une soirée entière d'une
/// catégorie à l'autre sur une micro-coupure Wi-Fi.
public enum TVAppReading: Sendable, Equatable {
    /// Cette app est à l'écran.
    case app(TVApp)
    /// La télé a répondu pour **toutes** les apps du catalogue, et aucune n'est
    /// à l'écran. C'est le cas normal d'une entrée HDMI — la PS5 d'Arthur est
    /// branchée sur cette télé — et celui d'une app absente du catalogue.
    case noneVisible
    /// On n'a pas pu demander. Le nom précédent reste valable.
    case unknown
}

/// Comment on demande à la télé quelle app est à l'écran.
public protocol TVAppProbe: Sendable {
    /// - Parameter preferred: l'identifiant vu à l'écran au relevé précédent.
    ///   Le demander en premier fait tomber le cas courant — « rien n'a
    ///   changé » — à **une seule requête** au lieu d'un balayage complet.
    func visibleApp(preferring preferred: String?) async -> TVAppReading
}

/// Les apps que Pulseon sait reconnaître sur une télé Samsung, et à quoi leur
/// temps correspond.
///
/// **Le catalogue est une liste d'identifiants, et c'est une limite, pas un
/// oubli.** Mesuré sur la télé d'Arthur le 2026-08-22 : `/api/v2/applications/`
/// — le point d'entrée qui donnerait la liste installée — répond **404**.
/// Samsung a fermé la découverte sur ce millésime (S90C, 2023). L'API ne sait
/// répondre qu'à « cette app-ci tourne-t-elle ? », pour un identifiant qu'on lui
/// donne. La collecte est donc un **balayage aveugle** : une app hors catalogue
/// ne s'affiche pas sous un faux nom, elle ne s'affiche pas du tout, et son
/// temps reste du temps de « Télé ». C'est le repli honnête, jamais une
/// approximation.
///
/// La seule autre voie connue est le WebSocket `samsung.remote.control`, qui
/// donne la liste installée mais **exige un appairage** — un message
/// d'autorisation s'affiche sur la télé et rend un jeton, qui irait alors au
/// Trousseau comme celui de la PlayStation. Plus intrusif à installer ; à garder
/// pour le jour où le balayage montrera ses limites.
///
/// **Les catégories sont écrites au format d'Apple** (`public.app-category.…`)
/// et non sous forme de `AppCategory`. C'est volontaire, et c'est la même règle
/// que pour les apps du Mac : on stocke la catégorie **brute** dans `StoredApp`
/// et on l'interprète à la lecture, pour que tout l'historique se reclasse si la
/// table de correspondance change d'avis.
public enum TVAppCatalog {
    /// Les identifiants candidats, et la catégorie de leur contenu.
    ///
    /// Vérifié à la requête sur la télé d'Arthur le 2026-08-22 : les dix
    /// premières répondent 200 (installées), les autres 404. On garde les
    /// absentes — le catalogue vaut pour toute télé Samsung, pas seulement pour
    /// celle-là, et un 404 coûte une requête une seule fois (voir
    /// `SamsungTVAppProbe`, qui apprend les absentes et cesse de les demander).
    public static let categories: [String: String] = [
        // Installées sur la télé d'Arthur, mesurées.
        "111299001912": video,  // YouTube
        "3201907018807": video,  // Netflix
        "3201910019365": video,  // Prime Video
        "3201901017640": video,  // Disney+
        "3201807016597": video,  // Apple TV
        "3201511006428": video,  // Rakuten TV
        "3201910019420": video,  // b.tv
        "3202203026841": video,  // Twitch
        "3201606009684": music,  // Spotify
        "3201908019041": music,  // Apple Music

        // Absentes de cette télé, présentes ailleurs.
        "3201512006963": video,  // Plex
        "3201606009910": video,  // myCANAL
        "3201601007230": video,  // HBO Max
        "3201510005981": video,  // Samsung TV Plus
        "3201611011005": video,  // YouTube Kids
        "3201907018784": music,  // YouTube Music
        "3201608010191": music,  // Deezer
    ]

    private static let video = "public.app-category.video"
    private static let music = "public.app-category.music"

    public static var candidates: [String] { Array(categories.keys).sorted() }

    /// La catégorie brute d'une app de télé, à ranger telle quelle dans
    /// `StoredApp.declaredCategory`.
    ///
    /// Rendre nil pour un identifiant hors catalogue est une vraie réponse : on
    /// ne classe pas ce qu'on ne connaît pas.
    public static func declaredCategory(for id: String) -> String? {
        categories[id]
    }

    /// L'identifiant de bundle attribué à une app de télé.
    ///
    /// Il n'en existe pas côté Samsung : celui-ci est fabriqué pour que la table
    /// `StoredApp` puisse distinguer une app de télé d'une app du Mac portant le
    /// même nom — « Apple TV » et « Spotify » existent des deux côtés. Il ne
    /// résout évidemment aucune icône sur le disque, et
    /// `AppRegistry.icon(ofApp:)` rendra nil : c'est le repli prévu, pas un
    /// échec.
    public static func bundleID(for id: String) -> String {
        "tv.samsung.app.\(id)"
    }
}

/// Demande à la télé quelle app est à l'écran, un identifiant à la fois.
///
/// **Seul `visible` compte, et `running` ment.** Mesuré le 2026-08-22 sur la
/// télé d'Arthur pendant qu'il regardait YouTube :
///
/// ```
/// YouTube      running: true   visible: true    ← à l'écran
/// Prime Video  running: true   visible: false   ← chargée, mais pas affichée
/// Apple TV     running: true   visible: false
/// Netflix      running: false  visible: false
/// ```
///
/// Trois apps « en cours d'exécution » pour un seul écran : compter `running`
/// aurait attribué la même soirée à trois apps à la fois. C'est la même famille
/// d'erreur que le ping ICMP pour l'état de l'écran — un signal qui existe,
/// qu'on croit lire, et qui ne dit pas ce qu'on croit.
///
/// **Un 404 veut dire « pas installée »**, et c'est une information qu'on
/// n'apprend qu'une fois : après un premier balayage complet, la sonde ne
/// redemande plus les absentes.
///
/// Coût mesuré sur le réseau d'Arthur, le 2026-08-22, télé allumée sur YouTube :
///
/// | Cas | Requêtes | Temps |
/// |---|---|---|
/// | L'app d'avant est encore à l'écran | 1 | **≈ 60 ms** |
/// | Rien de reconnu, premier balayage | 16 | 884 ms |
/// | Rien de reconnu, absentes apprises | 9 | 541 ms |
///
/// Le pire cas est le cas normal d'une entrée HDMI, et il tient en une demi-
/// seconde une fois par minute — voir `TVMonitor.appInterval`. C'est ce qui
/// permet de garder un catalogue large sans le payer : les identifiants absents
/// d'une télé donnée ne coûtent qu'un seul aller-retour dans sa vie.
public actor SamsungTVAppProbe: TVAppProbe {
    private let host: String
    private let port: Int
    private let timeout: TimeInterval
    private let candidates: [String]

    /// Les identifiants qui ont répondu autre chose qu'un 404. Nil tant que le
    /// premier balayage complet n'a pas abouti : on ne fige pas une liste
    /// apprise à travers une panne réseau.
    private var installed: [String]?

    public init(
        host: String,
        port: Int = 8001,
        timeout: TimeInterval = 4,
        candidates: [String] = TVAppCatalog.candidates
    ) {
        self.host = host
        self.port = port
        self.timeout = timeout
        self.candidates = candidates
    }

    public func visibleApp(preferring preferred: String?) async -> TVAppReading {
        // Le raccourci. Si l'app d'avant est encore à l'écran, on a fini.
        if let preferred {
            switch await state(of: preferred) {
            case .installed(let name, true): return .app(TVApp(id: preferred, name: name))
            case .unreachable: return .unknown
            case .installed, .absent: break
            }
        }

        let toScan = installed ?? candidates
        var reachable: [String] = []

        for id in toScan where id != preferred {
            switch await state(of: id) {
            case .installed(let name, let visible):
                reachable.append(id)
                // On ne s'arrête pas au premier `visible` quand la liste des
                // installées n'est pas encore connue : couper le balayage
                // laisserait la découverte à moitié faite, et on la
                // recommencerait à chaque relevé.
                if visible {
                    if installed != nil { return .app(TVApp(id: id, name: name)) }
                    installed = learned(reachable, scanned: toScan, upTo: id)
                    return .app(TVApp(id: id, name: name))
                }
            case .absent:
                break
            case .unreachable:
                // Une app qu'on n'a pas pu interroger est peut-être celle qui
                // est à l'écran. Conclure « aucune » ici ferait basculer la
                // soirée en « Télé » sur une seule requête perdue.
                return .unknown
            }
        }

        installed = reachable
        return .noneVisible
    }

    /// Le balayage s'est arrêté en cours de route : on ne connaît les absentes
    /// que jusqu'à `id`. On garde les installées vues, plus tout ce qui n'a pas
    /// encore été demandé — mieux vaut redemander une absente que d'oublier une
    /// installée.
    private func learned(_ reachable: [String], scanned: [String], upTo id: String) -> [String] {
        guard let cut = scanned.firstIndex(of: id) else { return reachable }
        return reachable + scanned[scanned.index(after: cut)...]
    }

    enum AppState: Equatable {
        case installed(name: String, visible: Bool)
        /// 404 : la télé connaît la question et répond que l'app n'est pas là.
        case absent
        case unreachable
    }

    private func state(of id: String) async -> AppState {
        guard let url = URL(string: "http://\(host):\(port)/api/v2/applications/\(id)") else {
            return .unreachable
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            if status == 404 { return .absent }
            guard status == 200 else { return .unreachable }
            return Self.state(from: data)
        } catch {
            return .unreachable
        }
    }

    /// Fonction pure, testable sans réseau.
    nonisolated static func state(from data: Data) -> AppState {
        struct Payload: Decodable {
            let name: String
            let visible: Bool
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            // La télé a répondu 200, mais pas ce qu'on attendait. Ne pas
            // conclure « pas à l'écran » : un changement de firmware ne doit pas
            // effacer le nom d'une app en cours.
            return .unreachable
        }
        return .installed(name: payload.name, visible: payload.visible)
    }
}
