import Foundation

/// Un bloc d'activité placé sur la timeline d'une journée.
public struct TraceBlock: Sendable, Equatable {
    public let entity: String?
    /// Secondes écoulées depuis minuit local.
    public let startOffset: TimeInterval
    public let duration: TimeInterval

    public init(entity: String?, startOffset: TimeInterval, duration: TimeInterval) {
        self.entity = entity
        self.startOffset = startOffset
        self.duration = duration
    }
}

public struct EntityTotal: Sendable, Equatable {
    public let entity: String
    public let total: TimeInterval

    public init(entity: String, total: TimeInterval) {
        self.entity = entity
        self.total = total
    }
}

public struct Lane: Sendable, Equatable {
    public let device: Device
    public let total: TimeInterval
    public let blocks: [TraceBlock]
    public let topEntities: [EntityTotal]
    /// Faux quand la source n'a jamais rien écrit. Distingue "collecteur pas
    /// branché" de "journée à zéro", que l'UI ne doit pas confondre.
    public let isConnected: Bool

    public init(
        device: Device,
        total: TimeInterval,
        blocks: [TraceBlock],
        topEntities: [EntityTotal],
        isConnected: Bool
    ) {
        self.device = device
        self.total = total
        self.blocks = blocks
        self.topEntities = topEntities
        self.isConnected = isConnected
    }
}

/// Une journée agrégée, prête à afficher.
///
/// Deux totaux, parce qu'ils ne veulent pas dire la même chose :
///
/// - `summedTotal` additionne les appareils. Regarder la télé avec le Mac
///   allumé compte les deux, donc ce chiffre dépasse le temps réellement passé
///   devant un écran.
/// - `coveredTotal` fusionne les intervalles qui se chevauchent : c'est le
///   temps réel passé devant au moins un écran.
///
/// Le second est devenu simple le jour où le dernier appareil sans horaire est
/// parti. Il a porté une borne basse — `max(couverture, compteurs)` — parce
/// qu'on ignorait si le temps de PlayStation tombait ou non pendant qu'un autre
/// écran était allumé. Tous les appareils sachant désormais dire *quand*, la
/// fusion suffit et ne suppose plus rien.
public struct DayDigest: Sendable {
    public let date: DateComponents
    public let lanes: [Lane]
    public let summedTotal: TimeInterval
    public let coveredTotal: TimeInterval

    /// Vrai dès qu'une source a écrit quelque chose ce jour-là.
    ///
    /// Distingue « le collecteur était éteint » de « journée à zéro », ce que
    /// l'UI ne doit jamais confondre — et ce qui décide aussi des journées
    /// admises dans une moyenne.
    public var hasMeasuredSource: Bool { lanes.contains(where: \.isConnected) }

    /// Combien de temps plusieurs écrans étaient allumés en même temps.
    ///
    /// **Le chiffre qui manquait à l'écran**, et Arthur l'a repéré le
    /// 2026-08-22 devant l'app : le rond annonçait 1h30 alors que la légende
    /// juste dessous affichait « Mac 1h16 · TV 1h29 ». Deux nombres qui ne font
    /// pas le troisième, sans rien pour dire pourquoi — il a naturellement
    /// conclu à un bug. Il n'y en avait pas : il avait regardé la télé **en
    /// étant sur son Mac** pendant 1h15, et ces minutes-là sont les mêmes
    /// minutes.
    ///
    /// C'est un fait mesuré, pas une note de méthode, et c'est ce qu'un total
    /// ne dira jamais — exactement le parti pris du projet.
    ///
    /// **Calculé sur les blocs, jamais par `summedTotal - coveredTotal`** : voir
    /// `IntervalMath.simultaneity(of:)`. La soustraction rend le temps compté en
    /// trop par l'addition, pas le temps passé sur plusieurs écrans — à trois
    /// appareils allumés une heure ensemble elle donnerait deux heures, alors
    /// qu'on n'a vécu qu'une heure de simultanéité.
    public var simultaneity: Simultaneity {
        let (duration, peak) = IntervalMath.simultaneity(of: lanes.map(\.blocks))
        return Simultaneity(duration: duration, peak: peak)
    }

    public struct Simultaneity: Sendable, Equatable {
        /// Le temps où **au moins deux** écrans étaient allumés ensemble.
        public let duration: TimeInterval
        /// Le plus grand nombre d'écrans allumés au même instant. Sert à
        /// choisir entre « les deux » et « plusieurs » : dire « deux » quand il
        /// y en avait trois serait sous-entendre une mesure qu'on n'a pas faite.
        public let peak: Int

        public init(duration: TimeInterval, peak: Int) {
            self.duration = duration
            self.peak = peak
        }
    }

    public init(
        date: DateComponents,
        lanes: [Lane],
        summedTotal: TimeInterval,
        coveredTotal: TimeInterval
    ) {
        self.date = date
        self.lanes = lanes
        self.summedTotal = summedTotal
        self.coveredTotal = coveredTotal
    }
}

public struct DayDigestBuilder: Sendable {
    let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// - Parameter now: instant courant, injecté pour rendre les tests
    ///   déterministes. Borne les sessions encore ouvertes, sinon une journée
    ///   en cours afficherait du temps pas encore écoulé.
    public func build(
        day: Date,
        sessions: [ActivitySession],
        now: Date = Date()
    ) -> DayDigest {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let horizon = min(now, end)

        var lanes: [Lane] = []

        for device in Device.allCases {
            let deviceSessions = sessions.filter { $0.device == device }
            let blocks = clampedBlocks(
                deviceSessions, dayStart: start, horizon: horizon
            )
            lanes.append(
                Lane(
                    device: device,
                    // Fusionné, jamais additionné : **un appareil ne peut pas
                    // être allumé deux fois en même temps.** Le chevauchement a
                    // du sens entre appareils — c'est tout l'objet de
                    // `summedTotal` — mais à l'intérieur d'un seul il ne peut
                    // venir que d'un défaut d'écriture, et c'est arrivé : deux
                    // collecteurs concurrents ont donné « Mac : 51 h » sur une
                    // journée de 2 h. L'écran n'aurait jamais dû pouvoir
                    // l'afficher, quelle que soit la cause en amont.
                    total: IntervalMath.mergedDuration(of: blocks),
                    blocks: blocks,
                    topEntities: rank(blocks),
                    isConnected: !deviceSessions.isEmpty
                )
            )
        }

        return DayDigest(
            date: calendar.dateComponents([.year, .month, .day], from: start),
            lanes: lanes,
            summedTotal: lanes.reduce(0) { $0 + $1.total },
            coveredTotal: IntervalMath.mergedDuration(
                of: lanes.flatMap(\.blocks)
            )
        )
    }

    /// Tronque aux bornes du jour et borne les sessions ouvertes à `horizon`.
    private func clampedBlocks(
        _ sessions: [ActivitySession],
        dayStart: Date,
        horizon: Date
    ) -> [TraceBlock] {
        sessions.compactMap { session in
            let from = max(session.start, dayStart)
            let to = min(session.end ?? horizon, horizon)
            let duration = to.timeIntervalSince(from)
            guard duration > 0 else { return nil }
            return TraceBlock(
                entity: session.entity,
                startOffset: from.timeIntervalSince(dayStart),
                duration: duration
            )
        }
        .sorted { $0.startOffset < $1.startOffset }
    }

    private func rank(_ blocks: [TraceBlock]) -> [EntityTotal] {
        Dictionary(grouping: blocks.filter { $0.entity != nil }, by: { $0.entity! })
            .map { EntityTotal(entity: $0.key, total: $0.value.reduce(0) { $0 + $1.duration }) }
            .sorted { $0.total > $1.total }
    }

}
