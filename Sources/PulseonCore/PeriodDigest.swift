import Foundation

/// Plusieurs journées agrégées, prêtes à afficher.
///
/// `days` contient **toutes** les journées de la période, y compris celles
/// sans la moindre activité. C'est délibéré : une semaine où l'on n'a pas
/// touché au Mac le mercredi doit montrer un mercredi vide, pas sauter du
/// mardi au jeudi. Les trous font partie de ce qu'on a à dire.
public struct PeriodDigest: Sendable {
    /// De la plus ancienne à la plus récente, sans trou.
    public let days: [DayDigest]

    /// Totaux par appareil sur toute la période.
    ///
    /// `blocks` y est **toujours vide**, et ce n'est pas un oubli : un bloc
    /// porte une position dans une journée de 24 h. Sur sept jours, cette
    /// position ne veut plus rien dire. Pour dessiner une timeline, il faut
    /// passer par `days`.
    public let lanes: [Lane]

    /// Additionne les appareils, donc double-compte les écrans simultanés.
    public let summedTotal: TimeInterval

    /// Temps réel passé devant au moins un écran, sur la période.
    ///
    /// C'est la somme des `coveredTotal` journaliers, et c'est valide
    /// justement parce que deux journées ne se chevauchent jamais — là où
    /// deux appareils, eux, le peuvent.
    public let coveredTotal: TimeInterval

    /// Nombre de journées où quelque chose a été enregistré. À distinguer du
    /// nombre de journées de la période : une moyenne n'a pas le même sens
    /// selon qu'on divise par l'un ou par l'autre, et ce choix revient à l'UI.
    public let daysWithActivity: Int

    /// Construit une période de toutes pièces.
    ///
    /// `buildPeriod` reste le chemin normal ; cet initialiseur existe pour
    /// fabriquer une période de démonstration sans base de données — c'est ce
    /// dont la preview a besoin pour regarder l'écran de la semaine hors ligne.
    public init(
        days: [DayDigest],
        lanes: [Lane],
        summedTotal: TimeInterval,
        coveredTotal: TimeInterval,
        daysWithActivity: Int
    ) {
        self.days = days
        self.lanes = lanes
        self.summedTotal = summedTotal
        self.coveredTotal = coveredTotal
        self.daysWithActivity = daysWithActivity
    }
}

extension DayDigestBuilder {
    /// Agrège chaque journée de `from` à `through`, bornes incluses.
    ///
    /// - Parameter now: instant courant, qui borne les sessions encore
    ///   ouvertes. Injecté pour rendre les tests déterministes.
    public func buildPeriod(
        from: Date,
        through: Date,
        sessions: [ActivitySession],
        now: Date = Date()
    ) -> PeriodDigest {
        let firstDay = calendar.startOfDay(for: from)
        let lastDay = calendar.startOfDay(for: through)
        let dayCount =
            (calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0) + 1

        guard dayCount > 0 else {
            return PeriodDigest(
                days: [], lanes: [], summedTotal: 0, coveredTotal: 0, daysWithActivity: 0)
        }

        let buckets = bucket(sessions, dayCount: dayCount, firstDay: firstDay, now: now)

        var days: [DayDigest] = []
        days.reserveCapacity(dayCount)
        for index in 0..<dayCount {
            guard let day = calendar.date(byAdding: .day, value: index, to: firstDay) else {
                continue
            }
            days.append(
                build(day: day, sessions: buckets[index], now: now)
            )
        }

        return PeriodDigest(
            days: days,
            lanes: mergeLanes(of: days),
            summedTotal: days.reduce(0) { $0 + $1.summedTotal },
            coveredTotal: days.reduce(0) { $0 + $1.coveredTotal },
            daysWithActivity: days.count { $0.coveredTotal > 0 }
        )
    }

    /// Répartit chaque session dans les journées qu'elle touche.
    ///
    /// Sans ça, agréger un an demanderait de re-filtrer la liste entière pour
    /// chacun des 365 jours. Une session à cheval sur minuit appartient aux
    /// deux journées : c'est `build` qui la tronquera ensuite aux bornes de
    /// chacune.
    private func bucket(
        _ sessions: [ActivitySession],
        dayCount: Int,
        firstDay: Date,
        now: Date
    ) -> [[ActivitySession]] {
        // Les frontières de journées sont calculées **une fois**, puis les
        // sessions sont placées par simple comparaison de nombres.
        //
        // La version naïve demandait au calendrier l'index du jour pour chaque
        // session : deux opérations `Calendar` par session, soit 1,4 million
        // pour une année, et 11 secondes d'agrégation. Ici le calendrier est
        // sollicité `dayCount` fois — 365 fois pour un an — et le reste est
        // une recherche dichotomique sur des `Double`.
        //
        // Passer par des frontières explicites plutôt que par une
        // multiplication de 86 400 n'est pas un détail : les journées de
        // changement d'heure ne durent pas 24 h, et le calendrier est le seul
        // à le savoir.
        var boundaries: [TimeInterval] = []
        boundaries.reserveCapacity(dayCount + 1)
        for offset in 0...dayCount {
            guard let start = calendar.date(byAdding: .day, value: offset, to: firstDay) else {
                return [[ActivitySession]](repeating: [], count: dayCount)
            }
            boundaries.append(start.timeIntervalSinceReferenceDate)
        }

        /// Index de la journée contenant `time`, ou nil hors période.
        func dayIndex(containing time: TimeInterval) -> Int? {
            guard time >= boundaries[0], time < boundaries[dayCount] else { return nil }
            var low = 0
            var high = dayCount - 1
            while low < high {
                let middle = (low + high + 1) / 2
                if boundaries[middle] <= time { low = middle } else { high = middle - 1 }
            }
            return low
        }

        var buckets = [[ActivitySession]](repeating: [], count: dayCount)

        for session in sessions {
            let startTime = session.start.timeIntervalSinceReferenceDate
            let endTime = max(
                min(session.end ?? now, now).timeIntervalSinceReferenceDate, startTime)

            // Une session peut déborder de la période des deux côtés : on la
            // rabat sur la partie visible plutôt que de la jeter.
            guard endTime >= boundaries[0], startTime < boundaries[dayCount] else { continue }
            let lower = dayIndex(containing: startTime) ?? 0
            let upper = dayIndex(containing: endTime) ?? (dayCount - 1)
            guard lower <= upper else { continue }

            for index in lower...upper {
                buckets[index].append(session)
            }
        }
        return buckets
    }

    /// Cumule les pistes journalières en une piste par appareil.
    private func mergeLanes(of days: [DayDigest]) -> [Lane] {
        Device.allCases.map { device in
            let lanes = days.compactMap { day in day.lanes.first { $0.device == device } }

            var entityTotals: [String: TimeInterval] = [:]
            for lane in lanes {
                for entity in lane.topEntities {
                    entityTotals[entity.entity, default: 0] += entity.total
                }
            }

            return Lane(
                device: device,
                total: lanes.reduce(0) { $0 + $1.total },
                // Voir `PeriodDigest.lanes` : une position horaire n'a pas de
                // sens au-delà d'une journée.
                blocks: [],
                topEntities: entityTotals
                    .map { EntityTotal(entity: $0.key, total: $0.value) }
                    .sorted { $0.total > $1.total },
                // Branché si la source a écrit au moins une fois sur la
                // période : un jour sans donnée n'efface pas les autres.
                isConnected: lanes.contains(where: \.isConnected)
            )
        }
    }
}
