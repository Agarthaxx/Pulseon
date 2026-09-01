import Foundation
import PulseonCore
import PulseonUI

/// Choisit la semaine affichée et va la chercher.
///
/// Pendant exact de `DayBrowser` un cran plus haut, et pour les mêmes raisons :
/// la navigation a des règles qui se testent, et c'est cette classe qu'on
/// remplacera pour l'app iOS — pas le dessin.
///
/// **La semaine est celle du calendrier**, pas « les sept derniers jours ».
/// Naviguer de semaine en semaine suppose des bornes stables : sur une fenêtre
/// glissante, reculer d'un cran redécouperait chaque fois des journées
/// différentes, et deux visites du même écran ne montreraient pas la même
/// chose. C'est aussi le calendrier qui décide du premier jour de la semaine,
/// lundi ou dimanche selon la région.
@MainActor
@Observable
public final class PeriodBrowser {
    /// Le premier jour de la semaine affichée, à minuit.
    public private(set) var weekStart: Date
    public private(set) var load: WeekDashboard.Load

    private let store: SessionStore
    private let calendar: Calendar
    /// Injecté pour que les tests ne dépendent pas de l'heure qu'il est.
    private let clock: @Sendable () -> Date
    private let registry: AppRegistry?

    /// De quoi afficher les icônes des apps, comme sur l'écran du jour.
    public var appIcons: AppIconSource { registry?.iconSource ?? .unavailable }

    public init(
        store: SessionStore,
        registry: AppRegistry? = nil,
        calendar: Calendar = .current,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.registry = registry
        self.calendar = calendar
        self.clock = clock
        self.weekStart = Self.startOfWeek(containing: clock(), in: calendar)
        self.load = .failed("Pas encore chargé")
        reload()
    }

    /// Vrai tant qu'il reste une semaine à voir après celle-ci. Aucune donnée
    /// ne peut exister la semaine prochaine.
    public var canGoForward: Bool {
        weekStart < Self.startOfWeek(containing: clock(), in: calendar)
    }

    public func goToPreviousWeek() {
        move(by: -1)
    }

    public func goToNextWeek() {
        guard canGoForward else { return }
        move(by: 1)
    }

    public func goToCurrentWeek() {
        weekStart = Self.startOfWeek(containing: clock(), in: calendar)
        reload()
    }

    /// Relit la semaine affichée. Appelée à l'ouverture de la fenêtre et à
    /// chaque minute : la semaine en cours grandit pendant qu'on la regarde.
    public func reload() {
        let now = clock()
        // Jamais `+ 7 × 86 400` : la semaine d'un changement d'heure ne fait pas
        // 168 heures, et le calendrier est le seul à le savoir.
        guard
            let lastDay = calendar.date(byAdding: .day, value: 6, to: weekStart),
            let weekEnd = calendar.date(byAdding: .day, value: 1, to: lastDay)
        else {
            load = .failed("Semaine impossible à situer dans le calendrier")
            return
        }

        do {
            let digest = DayDigestBuilder(calendar: calendar).buildPeriod(
                from: weekStart,
                through: lastDay,
                sessions: try store.sessions(from: weekStart, to: weekEnd),
                now: now
            )

            let today = calendar.startOfDay(for: now)
            var days: [PeriodPresentation.Day] = []
            days.reserveCapacity(digest.days.count)

            for (index, dayDigest) in digest.days.enumerated() {
                guard let start = calendar.date(byAdding: .day, value: index, to: weekStart)
                else { continue }
                days.append(
                    PeriodPresentation.Day(
                        start: start,
                        digest: dayDigest,
                        isToday: start == today,
                        // Une journée qui n'a pas encore eu lieu n'est ni un
                        // zéro ni un trou de mesure, et l'écran doit pouvoir
                        // faire la différence.
                        isFuture: start > today
                    )
                )
            }

            load = .loaded(
                PeriodPresentation(
                    digest: digest,
                    days: days,
                    categories: categories(of: digest.days),
                    // Même repère que pour la journée : il permet d'écrire
                    // « La semaine dernière » au lieu d'une plage de dates
                    // seule.
                    today: now
                )
            )
        } catch {
            // Une lecture qui échoue se dit. Afficher une semaine vide ferait
            // croire à zéro minute d'écran alors qu'on ne sait pas.
            load = .failed(error.localizedDescription)
        }
    }

    /// À quoi la semaine a servi.
    ///
    /// Chaque journée est classée séparément puis les totaux sont cumulés : le
    /// classement se décide côté macOS, seul endroit qui sache lire la
    /// catégorie déclarée d'une app, et `CategoryDigestBuilder` travaille sur
    /// une journée. Sommer ensuite est licite parce que deux journées ne se
    /// chevauchent jamais.
    private func categories(of days: [DayDigest]) -> [CategoryTotal] {
        guard let registry else { return [] }
        return CategoryTotal.merged(
            days.map { day in
                let assignment = registry.assignment(for: day)
                return CategoryDigestBuilder(classify: assignment.category(for:entity:))
                    .build(from: day)
            }
        )
    }

    private func move(by weeks: Int) {
        guard
            let target = calendar.date(byAdding: .weekOfYear, value: weeks, to: weekStart)
        else { return }
        weekStart = target
        reload()
    }

    /// Le premier jour de la semaine contenant `date`.
    ///
    /// Passe par `dateInterval(of:)` plutôt que par un calcul sur le numéro de
    /// jour : c'est le calendrier qui sait si la semaine commence le lundi ou
    /// le dimanche, et le supposer casserait l'écran hors d'Europe.
    private static func startOfWeek(containing date: Date, in calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }
}
