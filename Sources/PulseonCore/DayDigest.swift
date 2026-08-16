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

    public var kind: SourceKind { device.kind }

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
                        total: blocks.reduce(0) { $0 + $1.duration },
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
                lanes.append(
                    Lane(
                        device: device,
                        total: totals.reduce(0) { $0 + $1.total },
                        blocks: [],
                        topEntities: totals,
                        isConnected: !deviceSamples.isEmpty
                    )
                )
            }
        }

        let intervalBlocks = lanes.filter { $0.kind == .interval }.flatMap(\.blocks)
        let counterTotal = lanes.filter { $0.kind == .counter }.reduce(0) { $0 + $1.total }

        return DayDigest(
            date: calendar.dateComponents([.year, .month, .day], from: start),
            lanes: lanes,
            summedTotal: lanes.reduce(0) { $0 + $1.total },
            coveredTotal: union(of: intervalBlocks) + counterTotal
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

    /// Fusionne les intervalles qui se chevauchent pour ne compter le temps
    /// qu'une fois.
    private func union(of blocks: [TraceBlock]) -> TimeInterval {
        let ranges = blocks
            .map { ($0.startOffset, $0.startOffset + $0.duration) }
            .sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var current: (Double, Double)?
        for range in ranges {
            if var open = current, range.0 <= open.1 {
                open.1 = max(open.1, range.1)
                current = open
            } else {
                if let open = current { total += open.1 - open.0 }
                current = range
            }
        }
        if let open = current { total += open.1 - open.0 }
        return total
    }
}
