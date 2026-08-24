import Foundation

/// L'intensité de la journée, tranche par tranche.
///
/// **C'est le motif de l'icône, fait de vraies données.** Pulseon porte un
/// battement dans sa marque et dans son symbole de barre de menu, et ne l'avait
/// nulle part dans ses écrans. Ce type le rend mesurable : pour chaque tranche
/// de la journée, quelle **part** de cette tranche s'est passée devant un écran.
///
/// Ce qu'il dit et ce qu'il ne dit pas :
///
/// - **Les appareils sont fusionnés, jamais additionnés.** Regarder la télé en
///   étant sur son Mac ne fait pas 200 % d'une tranche. C'est la même règle que
///   `coveredTotal` face à `summedTotal`, et celle qui a évité la journée de
///   51 heures : deux mesures d'un même instant restent un seul instant.
/// - **Une source à compteur est écartée** (règle 1). La PlayStation ne connaît
///   aucun horaire : la placer dans une tranche inventerait une heure. Son temps
///   n'apparaît donc pas dans le battement, et la carte doit le dire plutôt que
///   de laisser croire à un creux.
/// - **La longueur du jour est fournie**, jamais supposée égale à 86 400 : les
///   journées de changement d'heure font 23 ou 25 h, et une courbe calée sur 24
///   décalerait toutes ses tranches ce jour-là.
public struct DayPulse: Sendable, Equatable {
    /// La part couverte de chaque tranche, de 0 à 1, dans l'ordre du jour.
    public let intensities: [Double]
    /// La durée d'une tranche, en secondes.
    public let bucket: TimeInterval

    public init(intensities: [Double], bucket: TimeInterval) {
        self.intensities = intensities
        self.bucket = bucket
    }

    /// Vrai quand rien n'a été mesuré. **À distinguer d'une journée à zéro** :
    /// la carte ne doit pas dessiner une ligne plate là où le collecteur était
    /// éteint (règle 2).
    public var isSilent: Bool { intensities.allSatisfy { $0 <= 0 } }

    /// La tranche la plus chargée, ou nil si tout est vide.
    ///
    /// **Ne pas s'en servir pour désigner « le moment le plus dense » à
    /// l'écran** : une journée de travail met vingt tranches à 100 %, et « la
    /// plus haute » en désigne alors une au hasard. Constaté le 2026-08-24 —
    /// la carte annonçait « le plus dense vers 08:45 » pour une journée dont
    /// le cœur était l'après-midi. Utiliser `densestWindow(spanning:)`.
    public var peakIndex: Int? {
        guard let best = intensities.enumerated().max(by: { $0.element < $1.element }),
            best.element > 0
        else { return nil }
        return best.offset
    }

    /// La fenêtre continue la plus dense de la journée, en secondes depuis
    /// minuit.
    ///
    /// C'est la réponse à « quand la journée a-t-elle été la plus chargée ? »,
    /// là où `peakIndex` ne répond qu'à « où est le maximum ». Sur des égalités
    /// — le cas normal — la fenêtre la plus **précoce** l'emporte, ce qui est
    /// arbitraire mais stable : deux ouvertures de la même journée ne doivent
    /// pas afficher deux heures différentes.
    ///
    /// Rend nil quand rien n'est mesuré, ou quand la journée est trop courte
    /// pour contenir la fenêtre demandée.
    public func densestWindow(spanning span: TimeInterval) -> (start: TimeInterval, end: TimeInterval)? {
        let width = max(1, Int((span / bucket).rounded()))
        guard !isSilent, intensities.count >= width else { return nil }

        var runningTotal = intensities.prefix(width).reduce(0, +)
        var best = runningTotal
        var bestStart = 0

        for start in 1...(intensities.count - width) {
            runningTotal += intensities[start + width - 1] - intensities[start - 1]
            // Strictement supérieur : à égalité, on garde la plus précoce.
            if runningTotal > best {
                best = runningTotal
                bestStart = start
            }
        }

        guard best > 0 else { return nil }
        return (Double(bestStart) * bucket, Double(bestStart + width) * bucket)
    }

    /// L'instant du milieu d'une tranche, en secondes depuis minuit. Sert à
    /// écrire l'heure d'un pic sans avoir à la recalculer côté vue.
    public func offset(ofBucket index: Int) -> TimeInterval {
        (Double(index) + 0.5) * bucket
    }
}

public enum DayPulseBuilder {
    /// Un quart d'heure.
    ///
    /// Assez fin pour qu'une pause déjeuner se voie, assez large pour qu'une
    /// journée hachée ne devienne pas un peigne illisible — 96 tranches sur une
    /// journée, soit environ 5 points de large chacune dans la carte. Descendre
    /// à 5 min dessinerait le pas d'échantillonnage du collecteur plutôt que la
    /// journée, exactement comme le seuil de coupure de `DayAnatomy`.
    public static let defaultBucket: TimeInterval = 15 * 60

    /// - Parameters:
    ///   - lanes: toutes les pistes de la journée. Celles qui n'ont pas
    ///     d'horaire sont écartées ici plutôt que par l'appelant, pour qu'aucun
    ///     écran ne puisse l'oublier.
    ///   - dayLength: la vraie longueur du jour, changements d'heure compris.
    public static func build(
        lanes: [Lane],
        dayLength: TimeInterval,
        bucket: TimeInterval = defaultBucket
    ) -> DayPulse {
        let count = max(1, Int((dayLength / bucket).rounded(.up)))
        guard bucket > 0, dayLength > 0 else {
            return DayPulse(intensities: Array(repeating: 0, count: count), bucket: bucket)
        }

        // Fusionner **avant** de découper. Découper puis additionner compterait
        // deux fois une tranche où deux écrans étaient allumés ensemble.
        let runs = IntervalMath.mergedRuns(of: lanes.filter { $0.kind == .interval }.flatMap(\.blocks))

        var covered = Array(repeating: 0.0, count: count)
        for run in runs {
            let start = max(0, run.start)
            let end = min(dayLength, run.end)
            guard end > start else { continue }

            var index = Int(start / bucket)
            while index < count {
                let bucketStart = Double(index) * bucket
                let bucketEnd = bucketStart + bucket
                if bucketStart >= end { break }
                let overlap = min(end, bucketEnd) - max(start, bucketStart)
                if overlap > 0 { covered[index] += overlap }
                index += 1
            }
        }

        // Une tranche ne peut pas être couverte plus qu'elle ne dure. La borne
        // protège la dernière tranche des journées de 23 h, plus courte que les
        // autres.
        let intensities = covered.map { min(1, $0 / bucket) }
        return DayPulse(intensities: intensities, bucket: bucket)
    }
}
