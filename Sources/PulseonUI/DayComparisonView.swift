import PulseonCore
import SwiftUI

/// Ce que la comparaison dit, en toutes lettres.
///
/// Séparé de la vue pour être testable sans simulateur — même raison que
/// `TimelineGeometry` et `RingLayout`. Ce sont des phrases, et une phrase qui
/// juge ou qui ment se corrige plus facilement quand un test la lit.
public enum DayComparisonPhrase {
    /// **Rien ici ne qualifie l'écart.** « De plus » et « de moins » décrivent,
    /// « trop » jugerait — et Pulseon mesure l'usage d'un appareil, il ne dit
    /// pas si c'est bien. C'est la même règle qui interdit de colorer un
    /// dépassement en rouge.
    public static func headline(_ comparison: DayComparison) -> String {
        // « À cette heure-ci » n'est pas une précision de confort : sans elle,
        // une journée en cours comparée à des journées entières se lirait
        // « en dessous de la normale » à 11 h du matin, ce qui est mécanique et
        // n'apprend rien.
        let moment = comparison.isPartial ? " à cette heure-ci" : ""

        if comparison.isTypical { return "comme d'habitude\(moment)" }

        let gap = DurationFormat.compact(abs(comparison.delta))
        let direction = comparison.delta > 0 ? "de plus" : "de moins"
        return "\(gap) \(direction) que d'habitude\(moment)"
    }

    /// Sur quoi la comparaison repose. Affiché, parce qu'une moyenne sur trois
    /// journées et une moyenne sur trente ne se valent pas — et que celui qui
    /// lit doit pouvoir en juger lui-même.
    public static func detail(_ comparison: DayComparison) -> String {
        let days = comparison.referenceDays
        return "moyenne de \(DurationFormat.compact(comparison.average)) sur \(days) jour\(days > 1 ? "s" : "") mesuré\(days > 1 ? "s" : "")"
    }
}

/// La comparaison sous l'anneau : « 9 h 39 » ne veut rien dire seul.
///
/// **Aucune couleur d'alerte, aucune flèche verte ou rouge.** Le seul signe
/// distinctif est un chevron gris qui dit la direction, à la même valeur de gris
/// dans les deux sens : un miroir ne félicite pas et ne gronde pas.
///
/// N'affiche rien quand il n'y a pas de quoi comparer — en dessous de trois
/// journées mesurées, `DayComparisonBuilder` rend nil, et se taire est plus
/// honnête qu'annoncer une tendance qui n'existe pas.
struct DayComparisonView: View {
    let comparison: DayComparison
    let palette: PulseonPalette

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                if !comparison.isTypical {
                    Image(systemName: comparison.delta > 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(DayComparisonPhrase.headline(comparison))
                    .font(PulseonTheme.caption)
            }
            .foregroundStyle(palette.inkSoft)

            Text(DayComparisonPhrase.detail(comparison))
                .font(PulseonTheme.caption)
                .foregroundStyle(palette.inkFaint)
        }
        .multilineTextAlignment(.center)
    }
}
