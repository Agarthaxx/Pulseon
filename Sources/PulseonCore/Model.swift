import Foundation

/// Ce qu'un appareil sait dire de lui-même.
///
/// La distinction n'est pas cosmétique : elle décide de ce qu'on a le droit
/// d'afficher. Une source `interval` connaît ses horaires et se place sur une
/// timeline. Une source `counter` ne connaît qu'un total cumulé relevé
/// périodiquement (la PlayStation), et son placement horaire est inconnu —
/// l'UI doit le dire au lieu de l'inventer.
public enum SourceKind: String, Codable, Sendable {
    case interval
    case counter
}

public enum Device: String, Codable, CaseIterable, Sendable {
    case mac
    case playstation
    case tv

    public var kind: SourceKind {
        switch self {
        case .mac, .tv: .interval
        case .playstation: .counter
        }
    }

    public var label: String {
        switch self {
        case .mac: "Mac"
        case .playstation: "PlayStation"
        case .tv: "TV"
        }
    }
}

/// Un intervalle d'activité continu. `entity` porte le contexte quand il
/// existe (l'app active sur le Mac), et reste nil quand la source ne mesure
/// qu'un état allumé/éteint (la TV).
public struct ActivitySession: Codable, Sendable, Identifiable {
    public let id: UUID
    public let device: Device
    public let entity: String?
    public let start: Date
    /// nil tant que la session est en cours.
    public let end: Date?

    public init(
        id: UUID = UUID(),
        device: Device,
        entity: String?,
        start: Date,
        end: Date? = nil
    ) {
        self.id = id
        self.device = device
        self.entity = entity
        self.start = start
        self.end = end
    }
}

/// Un relevé ponctuel d'un compteur cumulatif (le `playDuration` d'un jeu PSN
/// à l'instant du poll). Le temps joué se déduit par différence entre relevés.
public struct CounterSample: Codable, Sendable, Identifiable {
    public let id: UUID
    public let device: Device
    public let entity: String
    public let total: TimeInterval
    public let recordedAt: Date

    public init(
        id: UUID = UUID(),
        device: Device,
        entity: String,
        total: TimeInterval,
        recordedAt: Date
    ) {
        self.id = id
        self.device = device
        self.entity = entity
        self.total = total
        self.recordedAt = recordedAt
    }
}
