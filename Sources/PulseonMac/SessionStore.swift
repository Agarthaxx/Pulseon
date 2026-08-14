import Foundation
import PulseonCore
import SwiftData

/// Les modèles persistés. Ils doublent les structures de `PulseonCore` à
/// dessein : le cœur reste du Swift pur, testable sans SwiftData, et c'est
/// ici qu'on paie le prix de la persistance.
@Model
public final class StoredSession {
    public var deviceRaw: String
    public var entity: String?
    public var start: Date
    public var end: Date?

    public init(device: Device, entity: String?, start: Date, end: Date? = nil) {
        self.deviceRaw = device.rawValue
        self.entity = entity
        self.start = start
        self.end = end
    }

    public var device: Device { Device(rawValue: deviceRaw) ?? .mac }

    public var asSession: ActivitySession {
        ActivitySession(device: device, entity: entity, start: start, end: end)
    }
}

@Model
public final class StoredCounterSample {
    public var deviceRaw: String
    public var entity: String
    public var total: TimeInterval
    public var recordedAt: Date

    public init(device: Device, entity: String, total: TimeInterval, recordedAt: Date) {
        self.deviceRaw = device.rawValue
        self.entity = entity
        self.total = total
        self.recordedAt = recordedAt
    }

    public var device: Device { Device(rawValue: deviceRaw) ?? .playstation }

    public var asSample: CounterSample {
        CounterSample(device: device, entity: entity, total: total, recordedAt: recordedAt)
    }
}

/// Écrit les sessions, en garantissant qu'il n'y en a jamais deux ouvertes
/// pour le même appareil.
@MainActor
public final class SessionStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Ouvre une session, sauf si la même est déjà en cours — sinon un simple
    /// aller-retour entre deux fenêtres de la même app fragmenterait la
    /// journée en dizaines de sessions.
    public func openSession(device: Device, entity: String?, at date: Date) {
        if let current = openSession(for: device) {
            guard current.entity != entity else { return }
            close(current, at: date)
        }
        context.insert(StoredSession(device: device, entity: entity, start: date))
        save()
    }

    public func closeOpenSession(at date: Date) {
        for device in Device.allCases {
            if let current = openSession(for: device) {
                close(current, at: date)
            }
        }
        save()
    }

    public func sessions(from: Date, to: Date) -> [ActivitySession] {
        let descriptor = FetchDescriptor<StoredSession>(
            predicate: #Predicate { $0.start < to },
            sortBy: [SortDescriptor(\.start)]
        )
        return ((try? context.fetch(descriptor)) ?? [])
            // Une session ouverte n'a pas de fin : elle appartient au jour dès
            // lors qu'elle a commencé avant sa borne haute.
            .filter { ($0.end ?? .distantFuture) > from }
            .map(\.asSession)
    }

    public func samples(before: Date) -> [CounterSample] {
        let descriptor = FetchDescriptor<StoredCounterSample>(
            predicate: #Predicate { $0.recordedAt < before },
            sortBy: [SortDescriptor(\.recordedAt)]
        )
        return ((try? context.fetch(descriptor)) ?? []).map(\.asSample)
    }

    private func openSession(for device: Device) -> StoredSession? {
        let raw = device.rawValue
        let descriptor = FetchDescriptor<StoredSession>(
            predicate: #Predicate { $0.deviceRaw == raw && $0.end == nil },
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        )
        return try? context.fetch(descriptor).first
    }

    /// Une fermeture antérieure au début produirait une durée négative : on
    /// préfère une session de longueur nulle, quitte à ce qu'elle disparaisse
    /// des agrégats.
    private func close(_ session: StoredSession, at date: Date) {
        session.end = max(date, session.start)
    }

    private func save() {
        try? context.save()
    }
}
