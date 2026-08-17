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
/// dans le Trousseau. À déposer une fois :
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
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
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

    public private(set) var lastReading: TVReading?
    /// Dernier instant où l'écran a été observé allumé. C'est lui qui borne la
    /// fermeture de session, jamais l'heure courante.
    public private(set) var lastSeenOn: Date?

    private let probe: TVProbe
    private let store: SessionStore
    private var timer: Timer?
    private var inFlight = false

    public init(probe: TVProbe, store: SessionStore) {
        self.probe = probe
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
            self.apply(reading, at: Date())
            self.inFlight = false
        }
    }

    /// Interne et non privée pour être testable avec une horloge fixe : ce qui
    /// se joue ici est l'honnêteté du comptage, pas de la plomberie.
    func apply(_ reading: TVReading, at now: Date) {
        lastReading = reading
        if reading == .on { lastSeenOn = now }

        let isOpen = store.hasOpenSession(for: .tv)
        switch TVDecision.next(
            reading: reading, isOpen: isOpen, now: now, lastSeenOn: lastSeenOn
        ) {
        case .open:
            // Pas d'entité : la télé ne dit pas ce qu'elle diffuse, et le
            // supposer serait une invention.
            store.openSession(device: .tv, entity: nil, at: now)
        case .close(let end):
            store.closeOpenSession(device: .tv, at: end)
            lastSeenOn = nil
        case .nothing:
            break
        }
    }
}
