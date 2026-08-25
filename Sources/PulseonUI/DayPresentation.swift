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
    /// Minuit de la journée en cours, pour situer celle qu'on regarde.
    ///
    /// **Distinct de `now`, qui ne vaut que sur la journée du jour.** Une
    /// journée passée a `now` nil par construction — c'est ce qui retire la
    /// tête de lecture — donc elle ne peut pas savoir seule si elle est celle
    /// d'hier ou celle d'il y a huit jours. Nil ici veut dire « aucun repère
    /// fourni » : l'écran s'en tient alors à la date, qui reste vraie.
    public let today: Date?

    public init(
        digest: DayDigest,
        dayStart: Date,
        dayLength: TimeInterval,
        now: Date?,
        categories: [CategoryTotal] = [],
        comparison: DayComparison? = nil,
        anatomy: DayAnatomy? = nil,
        today: Date? = nil
    ) {
        self.digest = digest
        self.dayStart = dayStart
        self.dayLength = dayLength
        self.now = now
        self.categories = categories
        self.comparison = comparison
        self.anatomy = anatomy
        self.today = today
    }

    /// Le battement de la journée, tranche par tranche.
    ///
    /// Calculé ici et non côté navigateur : c'est une dérivation pure du digest
    /// et de la longueur du jour, sans aucune lecture de base. Le sortir vers
    /// `DayBrowser` obligerait à le recalculer à chaque relecture minute pour
    /// une valeur qui ne dépend que de données déjà en main.
    public var pulse: DayPulse {
        DayPulseBuilder.build(lanes: digest.lanes, dayLength: dayLength)
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

    public var title: String {
        Self.title.string(from: dayStart)
    }

    /// La date, telle qu'elle s'écrit en tête d'écran : « Lundi 25 août ».
    ///
    /// **C'est elle le titre, et plus un mot générique.** L'en-tête annonçait
    /// « Journée » en 27 points avec la date en 12 dessous, et poussait le
    /// retour à aujourd'hui à droite sous forme de mot en or — de sorte qu'une
    /// journée passée affichait « Aujourd'hui » en gros plan visuel et sa vraie
    /// date en petit. Arthur, le 2026-08-25 : « c'est marqué aujourd'hui
    /// partout ». La date est un fait mesuré, le mot ne l'était pas.
    ///
    /// La capitale est posée à la main : `DateFormatter` rend « lundi 25 août »
    /// en français, et un titre d'écran ne commence pas en minuscule.
    public var headline: String {
        let name = title
        guard let first = name.first else { return name }
        return first.uppercased() + name.dropFirst()
    }

    /// À quelle distance d'aujourd'hui : « Aujourd'hui », « Hier », « il y a
    /// 4 jours ». Nil sans repère, ou pour une journée à venir.
    ///
    /// **Le calendrier, jamais une division par 86 400** : les jours de
    /// changement d'heure ne font pas 24 h, et « hier » n'est pas « il y a
    /// 86 400 secondes ».
    public func situation(calendar: Calendar = .current) -> String? {
        // La journée en cours se reconnaît à sa tête de lecture, sans repère à
        // fournir : `now` n'est non-nil que là.
        if now != nil { return "Aujourd'hui" }
        guard let today else { return nil }
        guard
            let days = calendar.dateComponents(
                [.day],
                from: dayStart,
                to: calendar.startOfDay(for: today)
            ).day,
            days > 0
        else { return nil }
        return days == 1 ? "Hier" : "il y a \(days) jours"
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
