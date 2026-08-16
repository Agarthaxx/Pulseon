import Foundation
import PulseonCore

/// Un morceau de journée pendant lequel **le même jeu d'appareils** était actif.
public struct RailSegment: Equatable, Sendable, Identifiable {
    public let startOffset: TimeInterval
    public let duration: TimeInterval
    /// Les appareils actifs, dans un ordre stable d'un segment à l'autre.
    public let devices: [Device]

    public var id: TimeInterval { startOffset }

    public init(startOffset: TimeInterval, duration: TimeInterval, devices: [Device]) {
        self.startOffset = startOffset
        self.duration = duration
        self.devices = devices
    }
}

/// Découpe la journée en un **rail unique** au lieu d'une piste par appareil.
///
/// C'est une correction de conception, pas un choix esthétique. Une piste par
/// appareil semble naturelle et s'écroule au troisième écran : l'écran s'allonge,
/// les étiquettes se répètent, et les simultanéités deviennent un mur — constaté
/// par Arthur sur la première version (« si j'ai en plus d'autres devices
/// simultanés c'est illisible »).
///
/// Le rail, lui, garde **une hauteur fixe** : un appareil seul l'occupe
/// entièrement, deux se partagent la hauteur en deux, trois en trois. Une
/// simultanéité se lit au fait que le rail est *divisé*, jamais au fait que la
/// page est plus longue.
///
/// Deux propriétés qui comptent pour l'œil :
///
/// - **l'ordre des couches est stable** (`Device.allCases`), donc le même
///   appareil occupe toujours la même position relative et une texture devient
///   reconnaissable d'un coup d'œil ;
/// - **les segments voisins identiques sont fusionnés**, sinon une journée
///   normale produirait des dizaines de segments collés que rien ne distingue,
///   et chaque jointure dessinerait un liseré parasite.
public enum RailLayout {
    /// - Parameter lanes: toutes les pistes de la journée. Les sources à
    ///   compteur sont **ignorées** : elles n'ont aucun horaire, donc aucune
    ///   place sur un axe de temps. Les dessiner ici serait inventer une heure.
    public static func segments(from lanes: [Lane]) -> [RailSegment] {
        let intervals = lanes
            .filter { $0.kind == .interval }
            .flatMap { lane in
                lane.blocks
                    .filter { $0.duration > 0 }
                    .map { (device: lane.device, start: $0.startOffset, end: $0.startOffset + $0.duration) }
            }
        guard !intervals.isEmpty else { return [] }

        // Balayage : un événement par frontière, puis on avance dans le temps en
        // maintenant qui est actif. Un comptage par appareil, et non un simple
        // ensemble, parce que deux blocs du même appareil peuvent se chevaucher.
        var events: [TimeInterval: [(device: Device, isStart: Bool)]] = [:]
        for interval in intervals {
            events[interval.start, default: []].append((interval.device, true))
            events[interval.end, default: []].append((interval.device, false))
        }

        let times = events.keys.sorted()
        var active: [Device: Int] = [:]
        var segments: [RailSegment] = []

        for (index, time) in times.enumerated() {
            for event in events[time] ?? [] {
                active[event.device, default: 0] += event.isStart ? 1 : -1
            }

            guard index + 1 < times.count else { break }
            let devices = Device.allCases.filter { (active[$0] ?? 0) > 0 }
            guard !devices.isEmpty else { continue }

            segments.append(
                RailSegment(
                    startOffset: time,
                    duration: times[index + 1] - time,
                    devices: devices
                )
            )
        }

        return merged(segments)
    }

    /// Recolle les segments contigus qui portent les mêmes appareils.
    private static func merged(_ segments: [RailSegment]) -> [RailSegment] {
        var merged: [RailSegment] = []
        for segment in segments {
            guard
                let previous = merged.last,
                previous.devices == segment.devices,
                previous.startOffset + previous.duration == segment.startOffset
            else {
                merged.append(segment)
                continue
            }
            merged[merged.count - 1] = RailSegment(
                startOffset: previous.startOffset,
                duration: previous.duration + segment.duration,
                devices: previous.devices
            )
        }
        return merged
    }
}
