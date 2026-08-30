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
    /// Vide pour une source à compteur : son placement horaire est inconnu.
    public let blocks: [TraceBlock]
    public let topEntities: [EntityTotal]
    /// Faux quand la source n'a jamais rien écrit. Distingue "collecteur pas
    /// branché" de "journée à zéro", que l'UI ne doit pas confondre.
    public let isConnected: Bool

    /// **Un zéro qui n'est pas un zéro.**
    ///
    /// Vrai quand une source à compteur a bien parlé, mais qu'aucun de ses
    /// relevés ne précède la journée affichée : sans point de départ, une
    /// différence ne se calcule pas. Son total vaut alors `0` faute de mieux,
    /// et **ce zéro n'a rien de mesuré**.
    ///
    /// C'est le cas du premier jour d'une source à compteur, et il est arrivé
    /// pour de vrai le 2026-08-30 : Arthur a joué toute la soirée, la
    /// PlayStation venait d'être branchée, et la carte annonçait
    /// « PlayStation — 0 min ». Le calcul était juste ; l'écran, lui, affirmait
    /// une absence de jeu qui n'avait jamais été constatée. C'est exactement ce
    /// que `isConnected` existe pour empêcher côté intervalles — il manquait
    /// son équivalent côté compteurs.
    ///
    /// À ne pas confondre avec un vrai zéro : une fois un relevé de la veille
    /// en base, « le compteur n'a pas bougé » **est** une mesure, et se dit
    /// « 0 min ».
    public let awaitingBaseline: Bool

    public var kind: SourceKind { device.kind }

    public init(
        device: Device,
        total: TimeInterval,
        blocks: [TraceBlock],
        topEntities: [EntityTotal],
        isConnected: Bool,
        awaitingBaseline: Bool = false
    ) {
        self.device = device
        self.total = total
        self.blocks = blocks
        self.topEntities = topEntities
        self.isConnected = isConnected
        self.awaitingBaseline = awaitingBaseline
    }
}

/// Une journée agrégée, prête à afficher.
///
/// Deux totaux, parce qu'ils ne veulent pas dire la même chose :
///
/// - `summedTotal` additionne les appareils. Jouer sur la PlayStation avec le
///   Mac allumé compte les deux, donc ce chiffre dépasse le temps réellement
///   passé devant un écran.
/// - `coveredTotal` fusionne les intervalles qui se chevauchent : c'est le
///   temps réel passé devant au moins un écran. Les sources à compteur y sont
///   ajoutées telles quelles faute d'horaires — on ne peut pas savoir si
///   elles chevauchent le reste, et le supposer serait une invention.
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
    /// `IntervalMath.simultaneity(of:)` pour les deux raisons, dont celle qui
    /// compte le plus ici — une source à compteur n'a aucun horaire, donc on ne
    /// peut pas affirmer qu'elle tournait en même temps qu'une autre.
    public var simultaneity: Simultaneity {
        let (duration, peak) = IntervalMath.simultaneity(
            of: lanes.filter { $0.kind == .interval }.map(\.blocks)
        )
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
        samples: [CounterSample],
        now: Date = Date()
    ) -> DayDigest {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let horizon = min(now, end)

        var lanes: [Lane] = []

        for device in Device.allCases {
            switch device.kind {
            case .interval:
                let deviceSessions = sessions.filter { $0.device == device }
                let blocks = clampedBlocks(
                    deviceSessions, dayStart: start, horizon: horizon
                )
                lanes.append(
                    Lane(
                        device: device,
                        // Fusionné, jamais additionné : **un appareil ne peut
                        // pas être allumé deux fois en même temps.** Le
                        // chevauchement a du sens entre appareils — c'est tout
                        // l'objet de `summedTotal` — mais à l'intérieur d'un
                        // seul il ne peut venir que d'un défaut d'écriture, et
                        // c'est arrivé : deux collecteurs concurrents ont donné
                        // « Mac : 51 h » sur une journée de 2 h. L'écran
                        // n'aurait jamais dû pouvoir l'afficher, quelle que
                        // soit la cause en amont.
                        total: IntervalMath.mergedDuration(of: blocks),
                        blocks: blocks,
                        topEntities: rank(blocks),
                        isConnected: !deviceSessions.isEmpty
                    )
                )
            case .counter:
                let deviceSamples = samples.filter { $0.device == device }
                let totals = counterDeltas(
                    deviceSamples, dayStart: start, dayEnd: end
                )
                // Sans relevé **antérieur** à la journée, aucune différence ne
                // se calcule : le total tombe à zéro par manque de point de
                // départ, pas par absence d'usage. Voir `awaitingBaseline`.
                let hasBaseline = deviceSamples.contains { $0.recordedAt < start }
                lanes.append(
                    Lane(
                        device: device,
                        total: totals.reduce(0) { $0 + $1.total },
                        blocks: [],
                        topEntities: totals,
                        isConnected: !deviceSamples.isEmpty,
                        awaitingBaseline: !deviceSamples.isEmpty && !hasBaseline
                    )
                )
            }
        }

        let intervalBlocks = lanes.filter { $0.kind == .interval }.flatMap(\.blocks)
        let intervalCoverage = IntervalMath.mergedDuration(of: intervalBlocks)
        let counterTotals = lanes.filter { $0.kind == .counter }.map(\.total)

        return DayDigest(
            date: calendar.dateComponents([.year, .month, .day], from: start),
            lanes: lanes,
            summedTotal: lanes.reduce(0) { $0 + $1.total },
            // **La borne basse, jamais la somme.** Une source à compteur n'a
            // aucun horaire : on ignore si ses heures tombent pendant qu'un
            // autre écran était allumé. La couverture réelle est donc quelque
            // part entre `max(...)` — tout le temps de jeu tombe dans du temps
            // déjà couvert — et la somme — il n'en recouvre rien. On prend la
            // borne basse, parce que **sous-compter est permis et inventer ne
            // l'est pas**, la même règle qui ferme une session au dernier
            // instant *observé* plutôt qu'à l'heure courante.
            //
            // Ce n'était pas une erreur tant que la PlayStation était le seul
            // compteur et la télé pas encore mesurée. Ça l'est devenu le jour
            // où les deux ont tourné ensemble : la PS5 d'Arthur est branchée
            // sur cette télé, donc une soirée de 3 h s'annonçait 5 h 30 —
            // additionnée avec elle-même, en somme. Et la ligne « deux écrans
            // à la fois » ne pouvait pas l'expliquer, puisqu'elle écarte les
            // compteurs faute d'horaires.
            coveredTotal: ([intervalCoverage] + counterTotals).max() ?? 0
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

    /// Le compteur est cumulatif : le temps du jour est la progression entre
    /// le dernier relevé d'avant minuit et le dernier relevé du jour. Sans
    /// relevé antérieur on ne peut rien conclure — on ne compte rien plutôt
    /// que de prendre le total cumulé pour du temps du jour.
    private func counterDeltas(
        _ samples: [CounterSample],
        dayStart: Date,
        dayEnd: Date
    ) -> [EntityTotal] {
        Dictionary(grouping: samples, by: \.entity)
            .compactMap { entity, samples -> EntityTotal? in
                let sorted = samples.sorted { $0.recordedAt < $1.recordedAt }
                guard
                    let baseline = sorted.last(where: { $0.recordedAt < dayStart }),
                    let latest = sorted.last(where: {
                        $0.recordedAt >= dayStart && $0.recordedAt < dayEnd
                    })
                else { return nil }
                let delta = latest.total - baseline.total
                guard delta > 0 else { return nil }
                return EntityTotal(entity: entity, total: delta)
            }
            .sorted { $0.total > $1.total }
    }

    private func rank(_ blocks: [TraceBlock]) -> [EntityTotal] {
        Dictionary(grouping: blocks.filter { $0.entity != nil }, by: { $0.entity! })
            .map { EntityTotal(entity: $0.key, total: $0.value.reduce(0) { $0 + $1.duration }) }
            .sorted { $0.total > $1.total }
    }

}
