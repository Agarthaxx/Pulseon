import Foundation

/// La fusion d'intervalles qui se chevauchent, en un seul endroit.
///
/// Elle vivait dans `DayDigestBuilder`, où elle servait à ne pas compter deux
/// fois le temps de deux appareils allumés en même temps. Le classement par
/// catégorie en a exactement le même besoin — deux apps de la même catégorie
/// peuvent se chevaucher — donc elle sort ici plutôt que d'être recopiée.
enum IntervalMath {
    /// Le temps couvert par au moins un bloc, chaque instant compté une fois.
    static func mergedDuration(of blocks: [TraceBlock]) -> TimeInterval {
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
