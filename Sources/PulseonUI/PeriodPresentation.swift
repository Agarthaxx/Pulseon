import Foundation
import PulseonCore

/// Une période prête à être dessinée.
///
/// Même rôle que `DayPresentation` un cran plus haut : `PeriodDigest` sait
/// agréger, mais il ignore à quelles dates ses journées correspondent, laquelle
/// est aujourd'hui, et lesquelles n'ont pas encore eu lieu. Les vues
/// n'interrogent donc jamais le calendrier elles-mêmes.
public struct PeriodPresentation: Sendable {
    /// Une journée de la période, avec ce qu'il faut pour la dessiner.
    ///
    /// **Trois états, pas deux**, et c'est la règle « pas encore branchée ≠
    /// journée à zéro » appliquée à une semaine en cours :
    ///
    /// - `isFuture` — la journée n'a pas eu lieu. Jeudi, quand on est mercredi.
    ///   Ce n'est ni un zéro ni un trou de mesure : il n'y a rien à dire du
    ///   tout, et la colonne doit rester vide plutôt que de valoir zéro ;
    /// - `isMeasured` faux — le collecteur était éteint. Un trou de mesure ;
    /// - `isMeasured` vrai avec un total nul — un vrai zéro, mesuré.
    public struct Day: Sendable, Identifiable {
        public let start: Date
        public let digest: DayDigest
        /// Vrai pour la journée en cours, qui n'est pas terminée.
        public let isToday: Bool
        /// Vrai pour une journée postérieure à aujourd'hui.
        public let isFuture: Bool

        public var id: Date { start }

        /// Le temps passé devant au moins un écran, ce jour-là.
        public var total: TimeInterval { digest.coveredTotal }

        /// Vrai quand au moins une source a écrit quelque chose. Faux veut dire
        /// « on ne sait pas », jamais « zéro ».
        public var isMeasured: Bool { digest.hasMeasuredSource }

        public init(start: Date, digest: DayDigest, isToday: Bool, isFuture: Bool) {
            self.start = start
            self.digest = digest
            self.isToday = isToday
            self.isFuture = isFuture
        }

        /// L'initiale du jour de la semaine, sous le rond.
        public var initial: String {
            let name = Self.weekday.string(from: start)
            return name.prefix(1).uppercased()
        }

        public var dayNumber: String {
            Self.dayNumber.string(from: start)
        }

        private static let weekday: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.setLocalizedDateFormatFromTemplate("EEEE")
            return formatter
        }()

        private static let dayNumber: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.setLocalizedDateFormatFromTemplate("d")
            return formatter
        }()
    }

    public let digest: PeriodDigest
    public let days: [Day]
    /// À quoi la période a servi, toutes journées confondues. Vide quand rien
    /// n'est classable — le classement se décide côté macOS.
    public let categories: [CategoryTotal]

    public init(digest: PeriodDigest, days: [Day], categories: [CategoryTotal] = []) {
        self.digest = digest
        self.days = days
        self.categories = categories
    }

    /// Vrai quand la période contient aujourd'hui : elle grandit encore.
    public var isCurrent: Bool { days.contains(where: \.isToday) }

    /// Les journées qui comptent dans une moyenne : mesurées et terminées.
    ///
    /// **Aujourd'hui en est exclue tant qu'elle est en cours**, et c'est la même
    /// règle que `DayComparison` : mêler une matinée à des journées entières
    /// tire la moyenne vers le bas pour une raison qui n'a rien à voir avec
    /// l'usage. Une journée non mesurée en est exclue aussi — elle dit « le
    /// collecteur était éteint », pas « zéro minute d'écran ».
    public var averagedDays: [Day] {
        days.filter { $0.isMeasured && !$0.isToday && !$0.isFuture }
    }

    /// Le temps moyen d'une journée terminée, ou nil quand il n'y a rien à
    /// moyenner.
    ///
    /// Nil et non zéro : le premier jour d'une semaine, il n'y a pas de moyenne
    /// à annoncer, et zéro serait une affirmation fausse. À l'appelant
    /// d'afficher un tiret.
    public var dailyAverage: TimeInterval? {
        let counted = averagedDays
        guard !counted.isEmpty else { return nil }
        return counted.reduce(0) { $0 + $1.total } / Double(counted.count)
    }

    /// Vrai quand aucune source n'a rien enregistré de toute la période.
    public var isEmpty: Bool {
        days.allSatisfy { !$0.isMeasured }
    }

    /// « 17 – 23 août », ou « 28 juil. – 3 août » à cheval sur deux mois.
    public var title: String {
        guard let first = days.first?.start, let last = days.last?.start else { return "" }
        return Self.range.string(from: first, to: last)
    }

    private static let range: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
