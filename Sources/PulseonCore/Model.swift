import Foundation

/// Les appareils que Pulseon mesure.
///
/// **Tous savent dire *quand*, et c'est ce qui rend le projet simple.** Une
/// source qui ne rendrait qu'un total cumulé, sans horaire, demanderait tout un
/// vocabulaire à part et des précautions dans chaque vue pour ne jamais lui
/// inventer une place dans la journée — voir le `CLAUDE.md` avant d'en brancher
/// une. La règle, elle, tient toujours : **ne jamais inventer de placement
/// horaire**.
public enum Device: String, Codable, CaseIterable, Sendable, Identifiable {
    public var id: String { rawValue }

    case mac
    case tv

    public var label: String {
        switch self {
        case .mac: "Mac"
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
