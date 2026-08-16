import Foundation
import PulseonCore
import PulseonUI

/// Choisit la journée affichée par le dashboard et va la chercher.
///
/// Vit ici plutôt que dans la vue pour deux raisons : la navigation entre les
/// jours a des règles (on ne va pas dans le futur, minuit fait avancer la
/// journée courante) et une règle se teste ; et le jour où l'app iOS existera,
/// c'est cette classe qu'on remplacera — pas le dessin.
@MainActor
@Observable
public final class DayBrowser {
    /// La journée affichée, à minuit.
    public private(set) var dayStart: Date
    public private(set) var load: DayDashboard.Load

    private let store: SessionStore
    private let calendar: Calendar
    /// Injecté pour que les tests ne dépendent pas de l'heure qu'il est.
    private let clock: @Sendable () -> Date

    public init(
        store: SessionStore,
        calendar: Calendar = .current,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.calendar = calendar
        self.clock = clock
        self.dayStart = calendar.startOfDay(for: clock())
        self.load = .failed("Pas encore chargé")
        reload()
    }

    /// Vrai tant qu'il reste une journée à voir après celle-ci. Aucune donnée
    /// ne peut exister demain : y naviguer ne montrerait qu'une page vide.
    public var canGoForward: Bool {
        dayStart < calendar.startOfDay(for: clock())
    }

    public func goToPreviousDay() {
        move(by: -1)
    }

    public func goToNextDay() {
        guard canGoForward else { return }
        move(by: 1)
    }

    public func goToToday() {
        dayStart = calendar.startOfDay(for: clock())
        reload()
    }

    /// Relit la journée affichée. Appelée à l'ouverture de la fenêtre et à
    /// chaque minute : une journée en cours grandit pendant qu'on la regarde.
    public func reload() {
        let now = clock()
        // La journée suivante, jamais `+ 86 400` : les jours de changement
        // d'heure font 23 ou 25 heures, et une timeline décalée d'une heure
        // toute la soirée est un bug qu'on ne voit que deux fois par an.
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            load = .failed("Journée impossible à situer dans le calendrier")
            return
        }

        do {
            let digest = DayDigestBuilder(calendar: calendar).build(
                day: dayStart,
                sessions: try store.sessions(from: dayStart, to: nextDay),
                samples: try store.samples(before: nextDay),
                now: now
            )
            load = .loaded(
                DayPresentation(
                    digest: digest,
                    dayStart: dayStart,
                    dayLength: nextDay.timeIntervalSince(dayStart),
                    // La tête de lecture n'a de sens que sur la journée en
                    // cours : une journée passée est entièrement jouée.
                    now: calendar.isDate(dayStart, inSameDayAs: now) ? now : nil
                )
            )
        } catch {
            // Une lecture qui échoue se dit. Afficher une journée vide ferait
            // croire à zéro minute d'écran alors qu'on ne sait pas.
            load = .failed(error.localizedDescription)
        }
    }

    private func move(by days: Int) {
        guard let target = calendar.date(byAdding: .day, value: days, to: dayStart) else { return }
        dayStart = target
        reload()
    }
}
