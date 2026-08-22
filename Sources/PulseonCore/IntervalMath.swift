import Foundation

/// La fusion d'intervalles qui se chevauchent, en un seul endroit.
///
/// Elle vivait dans `DayDigestBuilder`, où elle servait à ne pas compter deux
/// fois le temps de deux appareils allumés en même temps. Le classement par
/// catégorie en a exactement le même besoin — deux apps de la même catégorie
/// peuvent se chevaucher — donc elle sort ici plutôt que d'être recopiée.
enum IntervalMath {
    /// Un intervalle de la journée, en secondes depuis minuit local.
    struct Run: Sendable, Equatable {
        var start: TimeInterval
        var end: TimeInterval

        var duration: TimeInterval { end - start }
    }

    /// Les blocs fondus en traites continues, dans l'ordre.
    ///
    /// C'est la brique commune : le total n'en est que la somme des durées, et
    /// l'anatomie de la journée a besoin des bornes elles-mêmes. Extraire les
    /// traites plutôt que de recopier la boucle évite qu'un jour les deux se
    /// mettent à répondre des choses différentes sur les mêmes données.
    static func mergedRuns(of blocks: [TraceBlock]) -> [Run] {
        let ranges = blocks
            .map { Run(start: $0.startOffset, end: $0.startOffset + $0.duration) }
            .sorted { $0.start < $1.start }

        var runs: [Run] = []
        var current: Run?

        for range in ranges {
            if var open = current, range.start <= open.end {
                open.end = max(open.end, range.end)
                current = open
            } else {
                if let open = current { runs.append(open) }
                current = range
            }
        }
        if let open = current { runs.append(open) }
        return runs
    }

    /// Le temps couvert par au moins un bloc, chaque instant compté une fois.
    static func mergedDuration(of blocks: [TraceBlock]) -> TimeInterval {
        mergedRuns(of: blocks).reduce(0) { $0 + $1.duration }
    }
}
