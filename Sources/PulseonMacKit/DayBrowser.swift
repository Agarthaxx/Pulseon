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

    /// Ce que vaut la journée affichée par rapport aux précédentes, ou nil quand
    /// il n'y a pas de quoi comparer honnêtement.
    public private(set) var comparison: DayComparison?

    private let store: SessionStore
    private let calendar: Calendar
    /// Injecté pour que les tests ne dépendent pas de l'heure qu'il est.
    private let clock: @Sendable () -> Date

    /// Sur combien de journées précédentes on compare.
    ///
    /// Sept : assez pour lisser un jour creux, assez peu pour rester « ces
    /// derniers temps » et non « depuis toujours ». Une semaine couvre aussi un
    /// week-end complet, ce qui évite qu'un samedi soit comparé à cinq jours de
    /// travail.
    private let referenceWindow = 7

    /// Quand la comparaison a été calculée pour la dernière fois, et pour quelle
    /// journée.
    ///
    /// La journée affichée est relue chaque minute, mais recalculer la
    /// comparaison à chaque fois ferait quatorze requêtes par minute pour un
    /// chiffre qui bouge d'une minute. Les journées passées, elles, ne changent
    /// jamais.
    private var comparedDay: Date?
    private var comparedAt: Date?
    private let comparisonStaleness: TimeInterval = 5 * 60

    /// Sait classer une app par catégorie. Optionnel : sans lui, la journée
    /// s'affiche quand même, simplement sans sa répartition — c'est le cas des
    /// tests, qui n'ont pas de registre d'apps.
    private let registry: AppRegistry?

    /// De quoi afficher les icônes des apps de la journée.
    ///
    /// Passe par le browser parce que c'est déjà lui que la fenêtre tient, et
    /// que c'est lui qu'on remplacera pour iOS : le jour venu, l'écran demandera
    /// ses icônes au même endroit, et c'est la source dessous qui changera.
    /// Sans registre — le cas des tests — personne n'a d'icône, ce qui reste une
    /// réponse valable.
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
            let isToday = calendar.isDate(dayStart, inSameDayAs: now)
            // Avant de bâtir la présentation, et non après : c'est elle qui
            // porte la comparaison jusqu'à l'écran. Le calcul reste rare — la
            // méthode garde la valeur en cache et ne la refait qu'au changement
            // de journée, ou toutes les cinq minutes sur la journée en cours.
            refreshComparison(for: digest, isToday: isToday, now: now)
            load = .loaded(
                DayPresentation(
                    digest: digest,
                    dayStart: dayStart,
                    dayLength: nextDay.timeIntervalSince(dayStart),
                    // La tête de lecture n'a de sens que sur la journée en
                    // cours : une journée passée est entièrement jouée.
                    now: isToday ? now : nil,
                    categories: categories(of: digest),
                    comparison: comparison,
                    // Du calcul pur sur un agrégat déjà en mémoire : rien à
                    // relire, donc rien à mettre en cache. Contrairement à la
                    // comparaison, qui coûte quatorze requêtes.
                    anatomy: DayAnatomyBuilder().build(from: digest)
                )
            )
        } catch {
            // Une lecture qui échoue se dit. Afficher une journée vide ferait
            // croire à zéro minute d'écran alors qu'on ne sait pas.
            load = .failed(error.localizedDescription)
            comparison = nil
        }
    }

    /// À quoi la journée a servi.
    ///
    /// Le classement se décide ici et non dans le cœur : `PulseonCore` ne sait
    /// pas ce qu'est un navigateur et n'a pas à le savoir. Il reçoit une
    /// fonction de classement, que seul le côté macOS peut fournir.
    private func categories(of digest: DayDigest) -> [CategoryTotal] {
        guard let registry else { return [] }
        let assignment = registry.assignment(for: digest)
        return CategoryDigestBuilder(classify: assignment.category(for:entity:))
            .build(from: digest)
    }

    // MARK: La comparaison

    /// Recalcule la comparaison, mais pas à chaque relecture.
    private func refreshComparison(for digest: DayDigest, isToday: Bool, now: Date) {
        let isSameDay = comparedDay == dayStart
        let isFresh = comparedAt.map { now.timeIntervalSince($0) < comparisonStaleness } ?? false
        // Une journée passée ne bougera plus : une fois comparée, c'est fini.
        if isSameDay, !isToday { return }
        if isSameDay, isFresh { return }

        comparedDay = dayStart
        comparedAt = now

        // **Comparer une matinée à des journées entières n'aurait aucun sens** :
        // à 11 h, on serait toujours « en dessous de sa moyenne », ce qui ne dit
        // rien. Les journées de référence sont donc arrêtées à la même heure du
        // jour tant que la journée affichée est en cours.
        let elapsed = isToday ? now.timeIntervalSince(dayStart) : nil

        do {
            comparison = DayComparisonBuilder.compare(
                subject: digest,
                against: try referenceDigests(before: dayStart, elapsed: elapsed),
                isPartial: elapsed != nil
            )
        } catch {
            // Ne rien dire, comme quand il y a trop peu de journées mesurées.
            // C'est le comportement honnête ici : l'échec de la lecture
            // principale, lui, est déjà signalé à l'écran — celui-ci ne prive que
            // d'un complément.
            comparison = nil
        }
    }

    /// Les journées précédant celle affichée, chacune arrêtée à `elapsed` si
    /// fourni, à sa propre fin sinon.
    ///
    /// Limite connue et assumée : une **source à compteur** n'a pas d'horaires,
    /// donc son total du jour ne peut pas être coupé à une heure précise. Sur une
    /// comparaison partielle elle est donc comptée en entier des deux côtés — ce
    /// qui reste cohérent, le total d'aujourd'hui étant lui aussi « ce qui s'est
    /// accumulé jusqu'ici ».
    private func referenceDigests(before day: Date, elapsed: TimeInterval?) throws -> [DayDigest] {
        let builder = DayDigestBuilder(calendar: calendar)
        var digests: [DayDigest] = []
        digests.reserveCapacity(referenceWindow)

        for offset in 1...referenceWindow {
            // Jamais `- 86 400 × n` : les jours de changement d'heure font 23 ou
            // 25 heures, et le calendrier est le seul à le savoir.
            guard
                let start = calendar.date(byAdding: .day, value: -offset, to: day),
                let end = calendar.date(byAdding: .day, value: 1, to: start)
            else { continue }

            digests.append(
                builder.build(
                    day: start,
                    sessions: try store.sessions(from: start, to: end),
                    samples: try store.samples(before: end),
                    now: elapsed.map { start.addingTimeInterval($0) } ?? end
                )
            )
        }
        return digests
    }

    private func move(by days: Int) {
        guard let target = calendar.date(byAdding: .day, value: days, to: dayStart) else { return }
        dayStart = target
        reload()
    }
}
