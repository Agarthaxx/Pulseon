import Foundation

/// Les appareils que Pulseon mesure.
///
/// **Tous savent dire *quand*, et c'est ce qui rend le projet simple.** Il a
/// existé un second genre de source — le « compteur », qui ne rend qu'un total
/// cumulé sans le moindre horaire — et tout un vocabulaire a été écrit pour lui
/// (`SourceKind`, `CounterSample`, `CounterPoller`), plus une série de
/// précautions dans les vues pour ne jamais lui inventer une place dans la
/// journée.
///
/// La PlayStation en a été l'unique exemple, et elle est partie le 2026-09-01.
/// La raison n'est pas technique — le collecteur tournait — mais mesurée :
/// **la PS5 est branchée sur la télé**, donc son temps est déjà compté par le
/// collecteur TV, avec de vrais horaires. Sur douze jours de base, la télé
/// porte 26 h 39 de temps anonyme contre 1 h 28 nommé : ces 26 h *sont* la
/// console. Deux collecteurs mesuraient le même écran.
///
/// Ce qui reste de l'épisode est une règle, pas du code : **ne jamais inventer
/// de placement horaire**. Elle n'a plus de source qui la mette à l'épreuve,
/// et elle vaut toujours pour la prochaine.
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
