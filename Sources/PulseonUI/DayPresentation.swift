import Foundation
import PulseonCore

/// Une journée prête à être dessinée.
///
/// Porte ce que `DayDigest` ne peut pas savoir : à quelle date il correspond
/// réellement, combien de temps cette journée-là a duré, et si elle est encore
/// en cours. Les vues n'interrogent donc jamais le calendrier elles-mêmes.
public struct DayPresentation: Sendable {
    public let digest: DayDigest
    public let dayStart: Date
    /// 86 400 s d'ordinaire, 23 ou 25 h les jours de changement d'heure.
    public let dayLength: TimeInterval
    /// L'instant courant, ou nil si la journée est passée. C'est ce qui décide
    /// de l'existence de la tête de lecture.
    public let now: Date?
    /// À quoi la journée a servi. Vide quand rien n'est classable — le
    /// classement se décide côté macOS, seul endroit qui sache lire la
    /// catégorie déclarée d'une app.
    public let categories: [CategoryTotal]
    /// Ce que cette journée vaut par rapport aux précédentes, ou nil quand il
    /// n'y a pas de quoi comparer honnêtement — moins de trois journées
    /// mesurées, ou une lecture qui a échoué.
    public let comparison: DayComparison?
    /// La forme de la journée — première et dernière minute d'écran, plus
    /// longue traite, coupures. Nil quand aucune source à intervalles n'a le
    /// moindre horaire ce jour-là : une journée sans horaire connu n'a pas
    /// d'anatomie, et surtout pas une anatomie à zéro.
    public let anatomy: DayAnatomy?

    public init(
        digest: DayDigest,
        dayStart: Date,
        dayLength: TimeInterval,
        now: Date?,
        categories: [CategoryTotal] = [],
        comparison: DayComparison? = nil,
        anatomy: DayAnatomy? = nil
    ) {
        self.digest = digest
        self.dayStart = dayStart
        self.dayLength = dayLength
        self.now = now
        self.categories = categories
        self.comparison = comparison
        self.anatomy = anatomy
    }

    /// L'heure qu'il était, pour un instant repéré en secondes depuis minuit.
    ///
    /// Passe par une vraie `Date` plutôt que par une division : les journées de
    /// changement d'heure ne font pas 24 h, et « 14 h après minuit » n'y tombe
    /// pas à 14:00.
    public func clockLabel(atOffset offset: TimeInterval) -> String {
        Self.clock.string(from: dayStart.addingTimeInterval(offset))
    }

    /// Où planter la tête de lecture, en secondes depuis minuit.
    public var nowOffset: TimeInterval? {
        guard let now else { return nil }
        let offset = now.timeIntervalSince(dayStart)
        guard offset >= 0, offset <= dayLength else { return nil }
        return offset
    }

    public var nowLabel: String {
        guard let now else { return "" }
        return Self.clock.string(from: now)
    }

    public var title: String {
        Self.title.string(from: dayStart)
    }

    /// Vrai quand rien n'a été enregistré : ni activité, ni source branchée.
    public var isEmpty: Bool {
        digest.lanes.allSatisfy { !$0.isConnected }
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let title: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter
    }()
}
