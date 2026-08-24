import Foundation
import Network
import PulseonCore

/// Ce que la télé a répondu quand on lui a demandé si son écran était allumé.
public enum TVReading: Sendable, Equatable {
    /// L'écran est allumé.
    case on
    /// L'écran est éteint, et on en est sûr.
    case off
    /// **On ne sait pas.** Le Mac n'a pas de réseau, ou la télé est injoignable
    /// pour une raison qui ne dit rien de son écran. Distinct de `off`, et l'UI
    /// comme le collecteur doivent traiter les deux différemment.
    case unknown
}

/// Comment on demande son état à la télé.
public protocol TVProbe: Sendable {
    func read() async -> TVReading
}

/// Interroge une télé Samsung, qui annonce son état d'alimentation en clair.
///
/// **Tout ce qui suit a été mesuré sur la télé d'Arthur** (Samsung
/// `TQ55S90CATXXC`, Tizen), le 2026-08-16, télé allumée puis éteinte — pas déduit
/// d'une documentation :
///
/// | Signal | Allumée | Éteinte | Verdict |
/// |---|---|---|---|
/// | Ping ICMP | répond | **répond aussi** | inutilisable |
/// | Annonce mDNS `_airplay._tcp` | présente | **présente aussi** | inutilisable |
/// | `GET :8001/api/v2/` | `PowerState: on` | connexion refusée en 1 s | **le bon signal** |
/// | Résolution `Samsung.local` | résout | **résout aussi** | pas besoin d'IP fixe |
///
/// Trois conséquences qu'il faut retenir avant de « simplifier » ce fichier :
///
/// - **le ping ne dit rien.** La puce réseau reste vivante en veille, donc une
///   détection au ping — l'idée de départ — aurait compté une télé éteinte toute
///   la nuit comme du temps d'écran ;
/// - **le nom mDNS ne dit rien non plus**, mais il *résout* en veille, ce qui est
///   précieux : on peut viser `Samsung.local` sans figer une IP que le DHCP
///   changera. Vérifié aussi qu'`URLSession` sait le résoudre (≈ 0,5 s au premier
///   appel, contre 0,02 s par IP) ;
/// - **la télé éteinte a deux comportements**, tous deux observés à une heure
///   d'intervalle sur la même télé : parfois le port 8001 **refuse la
///   connexion**, parfois il **répond `PowerState: standby`**. Sans doute selon la
///   profondeur du sommeil. Les deux valent « éteinte », et il faut donc traiter
///   les deux : ne garder qu'un seul cas laisserait l'autre compter du temps
///   d'écran ou en effacer.
///
/// Vérifié aussi, parce que ç'aurait été rédhibitoire : **interroger la télé ne
/// la rallume pas.** Une app qui allume la télé pour savoir si elle est allumée
/// n'aurait aucun sens.
///
/// L'API répond **sans authentification** en lecture, contrairement à la
/// PlayStation : rien à déposer dans le Trousseau.
public struct SamsungTVProbe: TVProbe {
    /// Le nom ou l'IP de la télé. Un nom mDNS (`Samsung.local`) est préférable :
    /// il survit à un changement d'adresse.
    private let host: String
    private let port: Int
    private let timeout: TimeInterval
    /// Vrai quand le Mac a un réseau. Sert à distinguer « éteinte » de
    /// « on ne sait pas ».
    private let hasNetwork: @Sendable () -> Bool

    public init(
        host: String,
        port: Int = 8001,
        timeout: TimeInterval = 4,
        hasNetwork: @escaping @Sendable () -> Bool
    ) {
        self.host = host
        self.port = port
        self.timeout = timeout
        self.hasNetwork = hasNetwork
    }

    public func read() async -> TVReading {
        guard let url = URL(string: "http://\(host):\(port)/api/v2/") else { return .unknown }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        // Aucune raison de servir une réponse en cache : on veut l'état de
        // l'écran maintenant, pas celui d'il y a dix minutes.
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .unknown }
            return Self.reading(from: data)
        } catch {
            // La connexion a échoué. Si le Mac a du réseau, c'est que la télé
            // refuse le port — donc elle est éteinte, ce qui est exactement ce
            // qu'on a mesuré. Sans réseau, on ne sait rien.
            return hasNetwork() ? .off : .unknown
        }
    }

    /// Fonction pure, testable sans réseau.
    static func reading(from data: Data) -> TVReading {
        struct Payload: Decodable {
            struct Device: Decodable {
                let powerState: String?

                enum CodingKeys: String, CodingKey {
                    case powerState = "PowerState"
                }
            }
            let device: Device
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
            let state = payload.device.powerState
        else {
            // La télé a répondu, mais pas ce qu'on attendait. Ne pas conclure
            // « éteinte » : une réponse incompréhensible n'est pas une réponse.
            return .unknown
        }
        return state.caseInsensitiveCompare("on") == .orderedSame ? .on : .off
    }
}

/// Témoin de l'état du réseau du Mac.
///
/// Sert uniquement à distinguer « la télé refuse la connexion, donc elle est
/// éteinte » de « le Mac n'a pas de réseau, donc on ne sait rien ». Sans lui, une
/// coupure Wi-Fi ressemblerait trait pour trait à une extinction de télé.
///
/// **Optimiste au démarrage** : avant la première mise à jour du chemin réseau on
/// répond « il y a du réseau ». Le pire cas est alors de conclure « éteinte »
/// alors qu'on ne sait pas — ce qui ferme la session au dernier instant observé,
/// c'est-à-dire dans le sens du sous-comptage. L'inverse aurait laissé une session
/// ouverte sur une supposition.
public final class NetworkWitness: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var satisfied = true

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.set(path.status == .satisfied)
        }
        monitor.start(queue: DispatchQueue(label: "com.arthurlanllier.pulseon.network"))
    }

    deinit { monitor.cancel() }

    public var hasNetwork: Bool {
        lock.lock()
        defer { lock.unlock() }
        return satisfied
    }

    private func set(_ value: Bool) {
        lock.lock()
        satisfied = value
        lock.unlock()
    }
}

/// Où l'on dit à Pulseon quelle télé regarder.
///
/// Un nom d'hôte n'est pas un secret : il vit dans les réglages de l'app, pas
/// dans le Trousseau. Depuis le 2026-08-24, il se dépose **depuis l'app** —
/// « Relier un appareil… » dans le menu, qui cherche la télé sur le réseau au
/// lieu de demander à Arthur de connaître son nom mDNS (voir
/// `DeviceDiscovery`). La ligne de commande reste équivalente :
///
/// ```
/// defaults write com.arthurlanllier.pulseon TVHost "Samsung.local"
/// ```
///
/// Préférer le nom mDNS à une IP : il survit à un changement d'adresse par le
/// DHCP, et il **résout même quand la télé est en veille** — vérifié.
public enum TVSettings {
    public static let hostKey = "TVHost"

    public static var host: String? {
        guard let value = UserDefaults.standard.string(forKey: hostKey) else { return nil }
        return normalized(value)
    }

    /// Relie une télé, ou délie celle qui l'était (`nil`).
    ///
    /// Écrire une chaîne vide **retire** le réglage plutôt que d'enregistrer un
    /// hôte vide : `startTV` ne teste que la présence, donc un hôte vide
    /// lancerait un collecteur qui échouerait toutes les trente secondes.
    public static func setHost(_ value: String?) {
        guard let value, let host = normalized(value) else {
            UserDefaults.standard.removeObject(forKey: hostKey)
            return
        }
        UserDefaults.standard.set(host, forKey: hostKey)
    }

    static func normalized(_ value: String) -> String? {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Le point final d'un nom pleinement qualifié, tel que le rend
        // `NetService`. Inoffensif pour `URLSession`, mais il se retrouverait
        // sous les yeux d'Arthur dans le menu.
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Décide quoi écrire en base à partir de ce que la télé a répondu.
///
/// Fonction pure et séparée du réseau, pour la même raison
/// qu'`ActivityMonitor.endOfActivity` : c'est là que se joue l'honnêteté du
/// comptage, donc c'est là qu'il faut des tests.
public enum TVDecision {
    public enum Action: Sendable, Equatable {
        case open
        /// Fermer la session à cet instant — **jamais à `now`**.
        case close(at: Date)
        case nothing
    }

    /// Combien de temps on tolère de ne rien savoir avant de clore la session.
    ///
    /// Sans tolérance, une micro-coupure Wi-Fi découperait une soirée de film en
    /// confettis. Avec une tolérance infinie, une panne réseau d'une nuit
    /// laisserait la session ouverte et compterait huit heures de télé qui n'ont
    /// pas eu lieu. Deux minutes est le même ordre de grandeur que le seuil
    /// d'inactivité du Mac.
    public static let unknownGrace: TimeInterval = 2 * 60

    /// - Parameters:
    ///   - lastSeenOn: dernier instant où l'écran a été **observé** allumé.
    ///   - isOpen: une session TV est-elle en cours ?
    public static func next(
        reading: TVReading,
        isOpen: Bool,
        now: Date,
        lastSeenOn: Date?,
        grace: TimeInterval = unknownGrace
    ) -> Action {
        switch reading {
        case .on:
            return isOpen ? .nothing : .open

        case .off:
            // On est sûr, donc on ferme tout de suite — mais **au dernier instant
            // observé allumé**, pas maintenant. Entre deux relevés, on ignore à
            // quelle seconde l'écran s'est éteint : sous-compter d'un intervalle
            // est permis, inventer ne l'est pas.
            guard isOpen else { return .nothing }
            return .close(at: lastSeenOn ?? now)

        case .unknown:
            guard isOpen, let lastSeenOn else { return .nothing }
            guard now.timeIntervalSince(lastSeenOn) >= grace else { return .nothing }
            return .close(at: lastSeenOn)
        }
    }
}

/// Le collecteur TV : une source à **intervalles**, comme le Mac.
///
/// Elle sait dire *quand* l'écran était allumé, contrairement à une source à
/// compteur — donc elle ouvre et ferme de vraies sessions, et sa place sur la
/// timeline n'est pas inventée.
///
/// Ce qu'elle mesure, exactement : **l'écran de la télé était allumé**. Pas que
/// quelqu'un regardait. C'est la même honnêteté que pour le Mac, où « regarder un
/// film » compte sans qu'on sache si tu t'es endormi devant.
@MainActor
public final class TVMonitor {
    /// Un relevé toutes les trente secondes. Le prix d'une erreur est borné : on
    /// sous-compte d'au plus un intervalle à l'extinction, jamais plus. Aller
    /// plus vite ne gagnerait que des secondes, pour un aller-retour HTTP de plus
    /// sur le réseau local.
    public var interval: TimeInterval = 30

    /// À quelle fréquence on redemande **quelle app** est à l'écran.
    ///
    /// Plus lent que le relevé d'alimentation, et pour une raison de coût : là
    /// où l'état de l'écran tient en une requête, le nom de l'app peut en
    /// demander une par app du catalogue quand rien n'est reconnu. Se tromper
    /// d'une minute sur la frontière entre deux apps ne change pas le total de
    /// la soirée — se tromper d'une minute sur l'extinction, si.
    public var appInterval: TimeInterval = 60

    public private(set) var lastReading: TVReading?
    /// Dernier instant où l'écran a été observé allumé. C'est lui qui borne la
    /// fermeture de session, jamais l'heure courante.
    public private(set) var lastSeenOn: Date?
    /// L'app vue à l'écran au dernier relevé, si la télé a su la nommer.
    public private(set) var currentApp: TVApp?

    private let probe: TVProbe
    private let appProbe: TVAppProbe?
    private let store: SessionStore
    private var timer: Timer?
    private var inFlight = false
    private var lastAppScan: Date?

    /// - Parameter appProbe: nil quand on ne cherche pas à nommer l'app. Le
    ///   collecteur reste alors exactement celui d'avant : « la télé était
    ///   allumée », sans entité.
    public init(probe: TVProbe, appProbe: TVAppProbe? = nil, store: SessionStore) {
        self.probe = probe
        self.appProbe = appProbe
        self.store = store
    }

    public func start() {
        stop()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.pollNow() }
        }
        // Laisse macOS regrouper ce réveil avec ceux des autres processus au lieu
        // d'en provoquer un pour nous seuls.
        timer.tolerance = interval / 4
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        pollNow()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func pollNow() {
        guard !inFlight else { return }
        inFlight = true

        Task { [weak self] in
            guard let self else { return }
            let reading = await self.probe.read()
            let now = Date()
            let app = await self.readApp(given: reading, at: now)
            self.apply(reading, app: app, at: now)
            self.inFlight = false
        }
    }

    /// N'interroge les apps que quand l'écran est allumé, et au plus une fois
    /// par `appInterval`.
    ///
    /// Demander le nom de l'app d'une télé éteinte n'apprendrait rien et
    /// réveillerait le réseau pour rien.
    private func readApp(given reading: TVReading, at now: Date) async -> TVAppReading {
        guard let appProbe, reading == .on else { return .unknown }
        if let last = lastAppScan, now.timeIntervalSince(last) < appInterval { return .unknown }
        lastAppScan = now
        return await appProbe.visibleApp(preferring: currentApp?.id)
    }

    /// Interne et non privée pour être testable avec une horloge fixe : ce qui
    /// se joue ici est l'honnêteté du comptage, pas de la plomberie.
    func apply(_ reading: TVReading, app: TVAppReading = .unknown, at now: Date) {
        lastReading = reading
        if reading == .on { lastSeenOn = now }
        note(app, at: now)

        let isOpen = store.hasOpenSession(for: .tv)
        switch TVDecision.next(
            reading: reading, isOpen: isOpen, now: now, lastSeenOn: lastSeenOn
        ) {
        case .open:
            // L'entité est le nom que **la télé** a donné, ou rien. Rien est
            // une vraie réponse : entrée HDMI (la PS5 d'Arthur est branchée
            // sur cette télé), ou app absente du catalogue. Dans les deux cas
            // on ne sait qu'une chose de cet écran, et c'est déjà écrit.
            store.openSession(device: .tv, entity: currentApp?.name, at: now)
        case .close(let end):
            store.closeOpenSession(device: .tv, at: end)
            lastSeenOn = nil
            currentApp = nil
        case .nothing:
            // La session tourne et l'écran est allumé : si l'app a changé, il
            // faut couper ici. `openSession` ne fait rien quand l'entité est la
            // même, donc le cas courant ne coûte pas une écriture.
            //
            // La coupure est datée de **maintenant** et non du dernier instant
            // où l'ancienne app a été vue, contrairement à une extinction. La
            // différence n'est pas un relâchement : l'écran, lui, a été observé
            // allumé sans interruption des deux côtés de la bascule. Reculer la
            // coupure creuserait un trou dans du temps mesuré. Seul le partage
            // entre deux apps est approché, à un `appInterval` près.
            if reading == .on, isOpen {
                store.openSession(device: .tv, entity: currentApp?.name, at: now)
            }
        }
    }

    /// Retient l'app vue, et son identité en base.
    ///
    /// **`.unknown` garde le nom précédent.** Ne pas avoir pu demander n'est pas
    /// « plus aucune app » : confondre les deux ferait basculer une soirée de
    /// Netflix en « Télé » sur une seule requête perdue.
    private func note(_ app: TVAppReading, at now: Date) {
        switch app {
        case .app(let seen):
            currentApp = seen
            // `noteApp` n'écrit rien si rien n'a changé, donc ce passage est
            // gratuit tant que la même app reste à l'écran.
            store.noteApp(
                name: seen.name,
                device: .tv,
                bundleID: TVAppCatalog.bundleID(for: seen.id),
                declaredCategory: TVAppCatalog.declaredCategory(for: seen.id),
                at: now
            )
        case .noneVisible:
            currentApp = nil
        case .unknown:
            break
        }
    }
}
