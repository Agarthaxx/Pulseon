import PulseonCore
import SwiftUI

/// Le déroulé de la journée : ce qu'un total ne dira jamais.
///
/// C'est le parti pris du projet à l'échelle d'une carte. « Temps d'écran » dit
/// *combien*, l'anneau du dessus dit *de quoi c'est fait*, et ces quatre faits
/// disent **comment la journée s'est passée** : deux journées de 6 h n'ont rien
/// à voir selon qu'elles tiennent d'une traite le matin ou en vingt reprises
/// jusqu'à minuit.
///
/// **Quatre faits, et pas un de plus.** La tentation serait d'en ajouter — le
/// nombre de sessions, la durée moyenne d'une traite, l'heure la plus chargée.
/// Chacun demanderait une ligne à interpréter, or l'intérêt de cette carte est
/// qu'elle se lise d'un coup d'œil, comme la rangée de ronds.
struct DayAnatomyCard: View {
    let anatomy: DayAnatomy
    /// Pour traduire un décalage depuis minuit en heure lisible.
    let day: DayPresentation
    let palette: PulseonPalette

    /// Vrai quand la journée n'est pas finie : « dernier écran » veut alors dire
    /// « jusqu'ici », et le taire laisserait lire une fin de journée qui n'a pas
    /// eu lieu.
    private var isLive: Bool { day.now != nil }

    /// Une source à compteur n'a aucun horaire, donc elle n'entre pas dans le
    /// déroulé (règle 1). Le dire seulement les jours où elle a du temps : une
    /// mise en garde permanente sur une source inactive serait du bruit.
    private var hiddenCounters: [Device] {
        day.digest.lanes
            .filter { $0.kind == .counter && $0.total > 0 }
            .map(\.device)
    }

    var body: some View {
        Card(palette: palette) {
            VStack(alignment: .leading, spacing: 15) {
                CardTitle("Déroulé", palette: palette)

                // Une seule rangée tant qu'elle tient, deux ensuite — même
                // stratégie que la rangée de ronds, qui rétrécit plutôt que de
                // se replier n'importe comment.
                //
                // **Les faits sont à leur taille intrinsèque, et surtout pas en
                // `frame(maxWidth: .infinity)`.** Une vue extensible accepte
                // n'importe quelle largeur, donc `ViewThatFits` retient
                // toujours la première proposition : la rangée « tenait » en
                // fenêtre étroite et c'est le texte qui se faisait tronquer
                // (« la plus longue 54… »). Trouvé en PNG, invisible à la
                // compilation. Ce sont les `Spacer` qui écartent les colonnes,
                // pas les colonnes qui s'étirent.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        fact(facts: 0)
                        Spacer(minLength: 20)
                        fact(facts: 1)
                        Spacer(minLength: 20)
                        fact(facts: 2)
                        Spacer(minLength: 20)
                        fact(facts: 3)
                    }
                    Grid(alignment: .topLeading, horizontalSpacing: 24, verticalSpacing: 15) {
                        GridRow { fact(facts: 0); fact(facts: 1) }
                        GridRow { fact(facts: 2); fact(facts: 3) }
                    }
                }

                if !hiddenCounters.isEmpty {
                    Text(counterNotice)
                        .font(PulseonTheme.caption)
                        .foregroundStyle(palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var counterNotice: String {
        let names = hiddenCounters.map(\.label).joined(separator: " et ")
        let verb = hiddenCounters.count > 1 ? "n'ont" : "n'a"
        return "\(names) \(verb) pas d'horaire connu : ce déroulé ne parle que des autres écrans."
    }

    // MARK: Les quatre faits

    @ViewBuilder
    private func fact(facts index: Int) -> some View {
        switch index {
        case 0:
            Fact(
                label: "Premier écran",
                value: day.clockLabel(atOffset: anatomy.firstScreen),
                detail: "", palette: palette
            )
        case 1:
            Fact(
                label: "Dernier écran",
                value: day.clockLabel(atOffset: anatomy.lastScreen),
                // La journée n'est pas finie : ce n'est pas une fin, c'est un
                // état d'avancement.
                detail: isLive ? "jusqu'ici" : "",
                palette: palette
            )
        case 2:
            Fact(
                label: "Plus longue traite",
                value: DurationFormat.compact(anatomy.longestStretch.duration),
                detail: "de \(day.clockLabel(atOffset: anatomy.longestStretch.start))"
                    + " à \(day.clockLabel(atOffset: anatomy.longestStretch.end))",
                palette: palette
            )
        default:
            Fact(
                label: "Coupures",
                value: breakCount,
                detail: anatomy.longestBreak.map {
                    "la plus longue \(DurationFormat.compact($0.duration))"
                } ?? "",
                palette: palette
            )
        }
    }

    /// « Aucune » plutôt que « 0 » : c'est un fait mesuré, pas un compteur à
    /// zéro, et le lire en toutes lettres évite de le confondre avec une
    /// journée dont on ne saurait rien.
    private var breakCount: String {
        switch anatomy.breaks.count {
        case 0: "aucune"
        case 1: "1"
        default: "\(anatomy.breaks.count)"
        }
    }

    private struct Fact: View {
        let label: String
        let value: String
        let detail: String
        let palette: PulseonPalette

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(PulseonTheme.caption)
                    .foregroundStyle(palette.inkFaint)
                Text(value)
                    .font(PulseonTheme.readout(19))
                    .foregroundStyle(palette.ink)
                Text(detail)
                    .font(PulseonTheme.caption)
                    .foregroundStyle(palette.inkFaint)
                    // Réservée même vide : sans ça les quatre faits ne
                    // s'alignent plus dès que l'un d'eux n'a rien à préciser.
                    .opacity(detail.isEmpty ? 0 : 1)
                    .lineLimit(1)
                    // Ne propose jamais de se tronquer : c'est cette précision
                    // qui décide si la rangée tient. Sans elle, `ViewThatFits`
                    // croit que tout rentre et coupe le texte.
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}
