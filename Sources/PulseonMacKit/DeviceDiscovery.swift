import Foundation
import Network
import PulseonCore
import PulseonUI

/// Cherche sur le réseau local les appareils que Pulseon saurait mesurer, pour
/// remplacer le `defaults write ... TVHost` par une liste sur laquelle cliquer.
///
/// **Une annonce mDNS ne prouve rien, et c'est tout le sujet de ce fichier.**
/// C'est exactement la leçon du ping ICMP, payée le 2026-08-16 : un signal qui
/// existe, qu'on croit lire, et qui ne dit pas ce qu'on croit. Mesuré le
/// 2026-08-24 sur le réseau du bureau d'Arthur : le seul appareil annonçant
/// `_airplay._tcp` était **son propre MacBook**. Une découverte qui ferait
/// confiance au type de service lui aurait proposé son Mac comme télé.
///
/// D'où le trajet en deux temps, dont seul le second conclut :
///
/// 1. **mDNS trouve des candidats.** On balaie plusieurs types de service parce
///    que c'est gratuit et qu'aucun ne fait autorité de toute façon.
/// 2. **`GET :8001/api/v2/` tranche.** C'est le point d'entrée que le collecteur
///    interroge vraiment, et le champ `PowerState` est celui qu'il lit vraiment.
///    Un appareil qui y répond n'est pas « probablement une télé » : c'est un
///    appareil que Pulseon **sait mesurer**, ce qui est la seule question posée.
///
/// **Le nom affiché vient de la télé**, jamais du nom d'instance mDNS. Même
/// règle que pour les apps de la télé : on code en dur des points d'entrée,
/// jamais des libellés. Personne n'aurait deviné « [TV] Samsung S90C ».
@MainActor
@Observable
public final class DeviceDiscovery {
    public private(set) var state: DeviceSetup.State = .idle

    /// Les types de service balayés.
    ///
    /// `_airplay._tcp` est **mesuré** sur la télé d'Arthur (le 2026-08-16, et il
    /// s'annonce même en veille). Les deux autres sont des paris, et ils sont
    /// gratuits : un type qui ne trouve rien ne coûte rien, et un type qui
    /// trouverait un appareil hors sujet se ferait recaler à l'étape 2. C'est
    /// la même économie que le catalogue d'apps de la télé — élargir ne peut
    /// pas produire un faux positif, seulement rater moins.
    static let serviceTypes = [
        "_airplay._tcp",
        // Le service propre à Samsung. Non vérifié sur la télé d'Arthur, gardé
        // parce qu'une télé dont l'AirPlay est désactivé n'apparaîtrait pas
        // au-dessus.
        "_samsungmsf._tcp",
    ]

    /// Combien de temps on cherche avant de conclure.
    ///
    /// Un balayage mDNS n'a pas de fin : personne ne peut dire « il n'y a plus
    /// rien à trouver ». Sans échéance, la vue tournerait indéfiniment et ne
    /// dirait jamais « rien trouvé » — or ne rien dire est précisément ce que ce
    /// projet s'interdit.
    private let deadline: TimeInterval = 8

    private var browsers: [NWBrowser] = []
    private var resolvers: [HostResolver] = []
    /// Les noms d'hôte déjà vus. Un même appareil s'annonce une fois par
    /// interface — mesuré : le Mac d'Arthur est apparu trois fois (if 1, 13, 15).
    private var seen: Set<String> = []
    private var found: [DiscoveredDisplay] = []
    private var timeout: Task<Void, Never>?

    private let verify: @Sendable (String) async -> TVIdentity?

    public init(verify: @escaping @Sendable (String) async -> TVIdentity? = { host in
        await SamsungTVIdentityProbe().identity(of: host)
    }) {
        self.verify = verify
    }

    /// Le nom d'hôte actuellement relié, s'il y en a un.
    public var boundHost: String? { TVSettings.host }

    public func scan() {
        stop()
        seen = []
        found = []
        state = .scanning

        for type in Self.serviceTypes {
            let browser = NWBrowser(
                for: .bonjour(type: type, domain: "local."),
                using: .tcp
            )
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                let services = results.compactMap { result -> (String, String, String)? in
                    guard case let .service(name, type, domain, _) = result.endpoint else {
                        return nil
                    }
                    return (name, type, domain)
                }
                Task { @MainActor [weak self] in self?.consider(services) }
            }
            browser.stateUpdateHandler = { [weak self] browserState in
                guard case let .failed(error) = browserState else { return }
                Task { @MainActor [weak self] in self?.fail(error) }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }

        let deadline = deadline
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(deadline))
            guard !Task.isCancelled else { return }
            await self?.concludeScan()
        }
    }

    public func stop() {
        timeout?.cancel()
        timeout = nil
        browsers.forEach { $0.cancel() }
        browsers = []
        resolvers.forEach { $0.cancel() }
        resolvers = []
    }

    /// Relie la télé choisie, et rend la main au collecteur.
    ///
    /// Un nom d'hôte n'est pas un secret : il va dans les réglages, pas dans le
    /// Trousseau. Voir `TVSettings`.
    public func bind(_ display: DiscoveredDisplay) {
        TVSettings.setHost(display.host)
        state = .bound(display)
        stop()
    }

    public func unbind() {
        TVSettings.setHost(nil)
        state = .idle
    }

    private func consider(_ services: [(name: String, type: String, domain: String)]) {
        for service in services {
            let resolver = HostResolver(
                name: service.name,
                type: service.type,
                domain: service.domain
            )
            resolvers.append(resolver)
            resolver.resolve { [weak self] host in
                Task { @MainActor [weak self] in await self?.verifyHost(host) }
            }
        }
    }

    /// L'étape qui conclut. Tant qu'elle n'a pas répondu, on ne sait rien de cet
    /// appareil — surtout pas qu'il s'agit d'une télé.
    private func verifyHost(_ host: String) async {
        guard !seen.contains(host) else { return }
        seen.insert(host)

        guard let identity = await verify(host) else { return }

        let display = DiscoveredDisplay(
            host: host,
            name: identity.name,
            model: identity.model
        )
        guard !found.contains(where: { $0.host == display.host }) else { return }
        found.append(display)
        // On publie au fil de l'eau plutôt qu'à l'échéance : trouver sa télé en
        // deux secondes et attendre huit secondes de plus donnerait l'impression
        // que rien ne marche.
        state = .found(found)
    }

    private func concludeScan() {
        stop()
        // `found` non vide est déjà publié ; ne reste que le cas où l'on n'a
        // rien confirmé.
        if found.isEmpty { state = .nothingFound }
    }

    private func fail(_ error: NWError) {
        stop()
        // Le cas le plus probable sur macOS récent : l'autorisation « réseau
        // local » n'a pas été accordée. Le dire, parce qu'une liste vide se
        // lirait « tu n'as pas de télé ».
        state = .failed(String(describing: error))
    }
}

/// Ce que la télé dit d'elle-même quand on lui demande.
public struct TVIdentity: Sendable, Equatable {
    /// Le nom que la télé se donne, par exemple « [TV] Samsung S90C ».
    public let name: String
    /// Son modèle, quand elle le donne — « QE55S90C ».
    public let model: String?

    public init(name: String, model: String?) {
        self.name = name
        self.model = model
    }
}

/// Demande à un hôte s'il est une télé que Pulseon sait mesurer.
///
/// **La preuve retenue n'est pas « ça ressemble à une télé »**, c'est « cet
/// appareil répond au point d'entrée que le collecteur interroge, avec le champ
/// que le collecteur lit ». Un `PowerState` absent fait échouer la
/// vérification même si le reste ressemble à une télé : sans lui, `TVMonitor`
/// n'aurait rien à mesurer et l'app promettrait un suivi qu'elle ne peut pas
/// tenir.
public struct SamsungTVIdentityProbe: Sendable {
    private let port: Int
    private let timeout: TimeInterval

    public init(port: Int = 8001, timeout: TimeInterval = 3) {
        self.port = port
        self.timeout = timeout
    }

    public func identity(of host: String) async -> TVIdentity? {
        guard let url = URL(string: "http://\(host):\(port)/api/v2/") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return Self.identity(from: data)
        } catch {
            // Le cas courant, et il n'est pas une erreur : la plupart des
            // appareils du réseau n'ont rien sur ce port. Une télé en veille
            // profonde refuse aussi la connexion — voir `DeviceSetup.State`,
            // qui doit le dire plutôt que d'afficher une liste vide.
            return nil
        }
    }

    /// Fonction pure, testable sans réseau.
    public static func identity(from data: Data) -> TVIdentity? {
        struct Payload: Decodable {
            struct Device: Decodable {
                let name: String?
                let modelName: String?
                let powerState: String?

                enum CodingKeys: String, CodingKey {
                    case name
                    case modelName
                    case powerState = "PowerState"
                }
            }
            let device: Device
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
            let name = payload.device.name,
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            // Sans `PowerState`, rien à mesurer : ce n'est pas une source.
            payload.device.powerState != nil
        else { return nil }

        let model = payload.device.modelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return TVIdentity(name: name, model: (model?.isEmpty ?? true) ? nil : model)
    }
}

/// Traduit une annonce Bonjour en **nom d'hôte**, pas en adresse IP.
///
/// Mesuré le 2026-08-24 : `NWBrowser` ne rend que le nom d'instance du service
/// (« MacBook Pro de Arthur »), qui n'est pas joignable. Seul `NetService`
/// rend le nom d'hôte — « MacBook-Pro-de-Arthur.local. », point final compris.
///
/// **On garde ce nom plutôt que l'IP**, et c'est une règle du projet vérifiée à
/// la mesure : `Samsung.local` résout même quand la télé est en veille, là où
/// une IP serait figée jusqu'au prochain bail DHCP.
final class HostResolver: NSObject, NetServiceDelegate {
    private let service: NetService
    private var onResolve: ((String) -> Void)?

    init(name: String, type: String, domain: String) {
        self.service = NetService(domain: domain, type: type, name: name)
        super.init()
        service.delegate = self
    }

    func resolve(timeout: TimeInterval = 4, then onResolve: @escaping (String) -> Void) {
        self.onResolve = onResolve
        service.resolve(withTimeout: timeout)
    }

    func cancel() {
        onResolve = nil
        service.stop()
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let hostName = sender.hostName else { return }
        // Le point final d'un nom pleinement qualifié. `URLSession` s'en
        // accommode, mais il se retrouverait tel quel dans les réglages et sous
        // les yeux d'Arthur.
        var host = hostName
        if host.hasSuffix(".") { host.removeLast() }
        onResolve?(host)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        // Un appareil qui ne se résout pas n'est pas une erreur à afficher :
        // c'est un candidat de moins, parmi des candidats qui ne prouvaient
        // rien de toute façon.
    }
}
