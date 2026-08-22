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

    /// Combien de temps **au moins deux appareils** étaient allumés au même
    /// instant, et combien il y en a eu au maximum à la fois.
    ///
    /// **Ce n'est pas `summedTotal - coveredTotal`**, et la différence n'est pas
    /// théorique. Cette soustraction donne le temps compté en trop par
    /// l'addition, pas le temps passé sur plusieurs écrans : à trois appareils
    /// allumés une heure ensemble, elle rend deux heures alors qu'on n'a vécu
    /// qu'une heure de simultanéité. Et surtout elle inclurait le total d'une
    /// source à compteur — la PlayStation n'a aucun horaire, donc on ne peut
    /// **pas** dire qu'elle tournait en même temps que la télé.
    ///
    /// - Parameter perDevice: les blocs de chaque appareil, séparément. Les
    ///   blocs d'un même appareil sont fusionnés d'abord : **un appareil ne peut
    ///   pas être allumé deux fois en même temps**, et l'oublier ferait passer
    ///   deux sessions voisines du même Mac pour une simultanéité. C'est la
    ///   leçon de la journée de 51 heures, appliquée ici.
    static func simultaneity(of perDevice: [[TraceBlock]]) -> (
        duration: TimeInterval, peak: Int
    ) {
        // +1 quand un appareil s'allume, -1 quand il s'éteint. La profondeur
        // courante est le nombre d'écrans allumés à cet instant.
        var events: [(at: TimeInterval, delta: Int)] = []
        for blocks in perDevice {
            for run in mergedRuns(of: blocks) where run.duration > 0 {
                events.append((run.start, 1))
                events.append((run.end, -1))
            }
        }
        guard !events.isEmpty else { return (0, 0) }

        // À instant égal, les fermetures d'abord : deux sessions qui se touchent
        // bout à bout ne sont pas une simultanéité d'une durée nulle, elles se
        // suivent.
        events.sort { $0.at == $1.at ? $0.delta < $1.delta : $0.at < $1.at }

        var duration: TimeInterval = 0
        var peak = 0
        var depth = 0
        var previous = events[0].at

        for event in events {
            if depth >= 2 { duration += event.at - previous }
            depth += event.delta
            peak = max(peak, depth)
            previous = event.at
        }
        return (duration, peak)
    }
}
