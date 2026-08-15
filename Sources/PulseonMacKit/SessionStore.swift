import Foundation
import PulseonCore
import SwiftData

/// Les modèles persistés. Ils doublent les structures de `PulseonCore` à
/// dessein : le cœur reste du Swift pur, testable sans SwiftData, et c'est
/// ici qu'on paie le prix de la persistance.
@Model
public final class StoredSession {
    public var deviceRaw: String
    /// Le champ s'appelle `entity` partout dans `PulseonCore`, mais surtout pas
    /// ici : SwiftData s'appuie sur CoreData, et ces noms-là sont piégés.
    /// Constaté à l'exécution, les trois cas :
    ///
    /// - `entity` : plante au démarrage, « Could not cast NSEntityDescription
    ///   to NSString » — `NSManagedObject.entity` existe déjà.
    /// - `entityName` : **échoue en silence**. Ça compile, ça tourne, l'objet
    ///   en mémoire porte bien la valeur, et la colonne reste NULL. Aucune
    ///   erreur nulle part.
    /// - `appName` : fonctionne.
    ///
    /// Le cas du milieu est le vrai danger : une base de temps d'écran sans
    /// nom d'app se remplit sans rien signaler. La traduction se fait dans
    /// `asSession`, pour que `PulseonCore` garde son vocabulaire.
    public var appName: String?
    public var start: Date
    public var end: Date?

    public init(device: Device, entity: String?, start: Date, end: Date? = nil) {
        self.deviceRaw = device.rawValue
        self.appName = entity
        self.start = start
        self.end = end
    }

    public var device: Device { Device(rawValue: deviceRaw) ?? .mac }

    public var asSession: ActivitySession {
        ActivitySession(device: device, entity: appName, start: start, end: end)
    }
}

@Model
public final class StoredCounterSample {
    public var deviceRaw: String
    /// Voir `StoredSession.appName` : ni `entity` ni `entityName` ne sont
    /// utilisables comme noms de propriété dans un `@Model`.
    public var appName: String
    public var total: TimeInterval
    public var recordedAt: Date

    public init(device: Device, entity: String, total: TimeInterval, recordedAt: Date) {
        self.deviceRaw = device.rawValue
        self.appName = entity
        self.total = total
        self.recordedAt = recordedAt
    }

    public var device: Device { Device(rawValue: deviceRaw) ?? .playstation }

    public var asSample: CounterSample {
        CounterSample(
            device: device, entity: appName, total: total, recordedAt: recordedAt
        )
    }
}

/// Où vit la base. Un exécutable SwiftPM n'a pas de bundle identifier, et
/// SwiftData retombe alors sur `~/Library/Application Support/default.store` —
/// un chemin non-namespacé, partagé avec toute autre app dans le même cas.
/// Ça s'est vu en vrai : Pulseon a ouvert la base d'une autre app et a planté
/// au démarrage. On nomme donc le fichier explicitement.
public enum StoreLocation {
    public static var directory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pulseon", isDirectory: true)
    }

    public static var storeURL: URL {
        directory.appendingPathComponent("Pulseon.store")
    }

    /// Fichier vide dont seule la date de modification compte. Voir `Heartbeat`.
    public static var heartbeatURL: URL {
        directory.appendingPathComponent("heartbeat")
    }

    /// - Returns: le conteneur, et un message d'erreur si la persistance a
    ///   échoué. Dans ce cas le conteneur est en mémoire : l'agent continue de
    ///   tourner et affiche la panne, au lieu de mourir au lancement.
    @MainActor
    public static func makeContainer() -> (ModelContainer, String?) {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            let container = try ModelContainer(
                for: StoredSession.self, StoredCounterSample.self,
                configurations: ModelConfiguration(url: storeURL)
            )
            return (container, nil)
        } catch {
            // Un conteneur en mémoire ne peut échouer que si le schéma
            // lui-même est invalide — une erreur de programmation, qui doit
            // se voir tout de suite.
            let fallback = try! ModelContainer(
                for: StoredSession.self, StoredCounterSample.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            return (fallback, error.localizedDescription)
        }
    }
}

/// Écrit les sessions, en garantissant qu'il n'y en a jamais deux ouvertes
/// pour le même appareil.
@MainActor
public final class SessionStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Ferme les sessions qu'un arrêt brutal a laissées ouvertes.
    ///
    /// Sans ça, la première activation venue les fermerait à l'instant présent
    /// et attribuerait à une app tout le temps machine éteinte — une nuit
    /// entière compterait comme du temps d'écran.
    ///
    /// - Parameter date: dernier signe de vie du collecteur (voir `Heartbeat`).
    ///   Si nil — aucune trace, donc rien d'observé —, la session est fermée
    ///   sur son propre début : durée nulle plutôt qu'une fin inventée.
    /// - Returns: le nombre de sessions réparées.
    @discardableResult
    public func closeDanglingSessions(at date: Date?) -> Int {
        var repaired = 0
        for device in Device.allCases {
            if let session = openSession(for: device) {
                close(session, at: date ?? session.start)
                repaired += 1
            }
        }
        if repaired > 0 { save() }
        return repaired
    }

    /// Ouvre une session, sauf si la même est déjà en cours — sinon un simple
    /// aller-retour entre deux fenêtres de la même app fragmenterait la
    /// journée en dizaines de sessions.
    public func openSession(device: Device, entity: String?, at date: Date) {
        if let current = openSession(for: device) {
            guard current.appName != entity else { return }
            close(current, at: date)
        }
        context.insert(StoredSession(device: device, entity: entity, start: date))
        save()
    }

    public func closeOpenSession(at date: Date) {
        for device in Device.allCases {
            if let current = openSession(for: device) {
                close(current, at: date)
            }
        }
        save()
    }

    /// Les sessions qui chevauchent la fenêtre `[from, to)`.
    ///
    /// Les **deux** bornes sont dans le prédicat, donc dans SQLite. La version
    /// précédente ne bornait que le haut et filtrait le bas en Swift : pour
    /// afficher aujourd'hui, elle chargeait tout l'historique depuis le
    /// premier jour, puis en jetait l'essentiel. Invisible avec une journée de
    /// données, ruineux avec six mois.
    ///
    /// Une session encore ouverte n'a pas de fin : elle chevauche la fenêtre
    /// dès lors qu'elle a commencé avant `to`. D'où l'horizon, qui remplace le
    /// `nil` le temps de la comparaison.
    ///
    /// Écrit avec `??` et surtout pas avec `session.end! > from` : SwiftData
    /// **refuse le déballage forcé** dans un prédicat. Ça compile, puis ça
    /// lève à l'exécution — et si l'erreur est avalée, la requête rend une
    /// liste vide impossible à distinguer d'une journée sans activité.
    public func sessions(from: Date, to: Date) throws -> [ActivitySession] {
        let horizon = Date.distantFuture
        let descriptor = FetchDescriptor<StoredSession>(
            predicate: #Predicate { session in
                session.start < to && (session.end ?? horizon) > from
            },
            sortBy: [SortDescriptor(\.start)]
        )
        return try context.fetch(descriptor).map(\.asSession)
    }

    /// Enregistre un relevé de compteur, **sauf s'il n'apprend rien**.
    ///
    /// Les sources à compteur se relèvent périodiquement, et la plupart des
    /// relevés retournent le même total : on ne joue pas toute la journée.
    /// Réécrire ce total à chaque passage referait exactement l'erreur du
    /// `lastSeen` en base — des centaines de mégaoctets par jour pour ne rien
    /// apprendre. Voir `Heartbeat`.
    ///
    /// Sauter les doublons ne perturbe pas l'agrégation : `DayDigestBuilder`
    /// cherche « le dernier relevé antérieur au jour », et un relevé plus
    /// ancien fait tout aussi bien l'affaire tant que le total n'a pas bougé.
    ///
    /// Un total qui *baisse* est écrit quand même. C'est ce que la source a
    /// dit, et on ne réécrit pas ce qu'on observe ; c'est à l'agrégation de
    /// refuser les deltas négatifs, ce qu'elle fait déjà.
    ///
    /// - Returns: vrai si le relevé a été écrit.
    @discardableResult
    public func record(
        device: Device, entity: String, total: TimeInterval, at date: Date
    ) -> Bool {
        if let last = lastSample(device: device, entity: entity), last.total == total {
            return false
        }
        context.insert(
            StoredCounterSample(device: device, entity: entity, total: total, recordedAt: date)
        )
        save()
        return true
    }

    private func lastSample(device: Device, entity: String) -> StoredCounterSample? {
        let raw = device.rawValue
        let name = entity
        let descriptor = FetchDescriptor<StoredCounterSample>(
            predicate: #Predicate { $0.deviceRaw == raw && $0.appName == name },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        return try? context.fetch(descriptor).first
    }

    /// Les relevés de compteur antérieurs à `before`.
    ///
    /// Pas de borne basse ici, et c'est voulu : le calcul d'un temps de jeu
    /// exige le dernier relevé *antérieur* à la journée, qui peut dater de
    /// plusieurs jours si on n'a pas joué entre-temps. Les relevés sont rares
    /// — un par quart d'heure au plus, et seulement quand un total bouge.
    public func samples(before: Date) throws -> [CounterSample] {
        let descriptor = FetchDescriptor<StoredCounterSample>(
            predicate: #Predicate { $0.recordedAt < before },
            sortBy: [SortDescriptor(\.recordedAt)]
        )
        return try context.fetch(descriptor).map(\.asSample)
    }

    private func openSession(for device: Device) -> StoredSession? {
        let raw = device.rawValue
        let descriptor = FetchDescriptor<StoredSession>(
            predicate: #Predicate { $0.deviceRaw == raw && $0.end == nil },
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        )
        return try? context.fetch(descriptor).first
    }

    /// Une fermeture antérieure au début produirait une durée négative : on
    /// préfère une session de longueur nulle, quitte à ce qu'elle disparaisse
    /// des agrégats.
    private func close(_ session: StoredSession, at date: Date) {
        session.end = max(date, session.start)
    }

    private func save() {
        try? context.save()
    }
}
