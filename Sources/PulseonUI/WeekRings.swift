import PulseonCore
import SwiftUI

/// La semaine en sept petits ronds, un par journée.
///
/// **Remplace un graphique en colonnes**, écarté par Arthur le 2026-08-19 :
/// « si c'est en colonne, autant garder l'ancienne app temps d'écran macOS ».
/// L'argument est produit autant qu'esthétique — le rond est ce qui distingue
/// Pulseon, et une rangée de camemberts se lit sans légende.
///
/// **Tous les ronds font la même taille**, comme ceux des catégories sur l'écran
/// du jour — décision d'Arthur le 2026-08-19, étendue ici à sa demande.
///
/// Le diamètre a d'abord encodé la durée (surface ∝ temps, donc diamètre en
/// racine carrée). C'était défendable — un anneau fait toujours le tour, donc la
/// taille était le seul canal restant — mais **la durée est déjà écrite au-dessus
/// de chaque rond**, et une rangée de ronds inégaux se lit moins bien qu'une
/// rangée régulière. Ce qui reste vrai, et qui vaut pour toute quantité future :
/// **jamais par le remplissage.** Un anneau rempli aux deux tiers se lirait
/// « objectif atteint à 66 % », or l'objectif quotidien a été retiré de la
/// maquette et la règle « aucune comparaison ne juge » l'interdit.
struct WeekRingRow: View {
    let period: PeriodPresentation
    let palette: PulseonPalette

    /// Le même pour toutes les journées, et le même que les ronds de catégories
    /// de l'écran du jour : deux rangées de petits ronds dans la même app n'ont
    /// aucune raison de ne pas se ressembler.
    private let diameter: CGFloat = 48

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(period.days) { day in
                DayRing(day: day, diameter: diameter, palette: palette)
            }
        }
    }
}

/// Une journée, dans l'un de ses quatre états.
///
/// **Quatre, pas deux**, et c'est la règle « pas encore branchée ≠ journée à
/// zéro » poussée jusqu'au bout sur une semaine en cours :
///
/// - une journée **mesurée avec du temps** : un anneau, ses arcs par appareil ;
/// - un **vrai zéro mesuré** : un point plein. On sait, il n'y a rien à montrer ;
/// - une journée **non mesurée** : un cercle **pointillé** vide. Le collecteur
///   était éteint, et le pointillé dit l'inconnu partout ailleurs dans l'app ;
/// - une journée **à venir** : rien du tout. Ni un zéro, ni un trou — elle n'a
///   pas eu lieu, et il n'y a rien à en dire.
private struct DayRing: View {
    let day: PeriodPresentation.Day
    let diameter: CGFloat
    let palette: PulseonPalette

    /// Le repère d'une journée non mesurée et celui d'un vrai zéro restent
    /// petits : ils ne portent pas de temps, donc ils ne doivent pas peser
    /// autant qu'un rond qui en porte.
    private static let emptyMarkDiameter: CGFloat = 18
    private static let zeroMarkDiameter: CGFloat = 9

    var body: some View {
        VStack(spacing: 7) {
            Text(valueLabel)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(day.isToday ? palette.gold : palette.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Hauteur fixe, contenu centré : c'est ce qui fait lire l'écart de
            // taille comme un écart de durée. Alignés par le bas, les ronds
            // paraîtraient posés sur une ligne et non comparés entre eux.
            ZStack {
                mark
            }
            .frame(height: diameter)

            VStack(spacing: 1) {
                Text(day.initial)
                    .font(.system(size: 11, weight: day.isToday ? .bold : .medium))
                    .foregroundStyle(labelColor)
                Text(day.dayNumber)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(palette.inkFaint.opacity(day.isFuture ? 0.5 : 1))
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var mark: some View {
        if day.isFuture {
            // Rien : cette journée n'a pas eu lieu.
            EmptyView()
        } else if !day.isMeasured {
            Circle()
                .strokeBorder(
                    palette.inkFaint.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
                .frame(width: Self.emptyMarkDiameter, height: Self.emptyMarkDiameter)
        } else if day.total <= 0 {
            // Plein parce qu'on sait, gris parce qu'il n'y a pas de temps à
            // montrer.
            Circle()
                .fill(palette.inkFaint)
                .frame(width: Self.zeroMarkDiameter, height: Self.zeroMarkDiameter)
        } else {
            CompositionRing(
                lanes: day.digest.lanes,
                diameter: diameter,
                palette: palette
            )
        }
    }

    private var valueLabel: String {
        if day.isFuture { return " " }
        if !day.isMeasured { return "—" }
        return DurationFormat.compact(day.total)
    }

    private var labelColor: Color {
        if day.isFuture { return palette.inkFaint.opacity(0.5) }
        return day.isToday ? palette.gold : palette.inkSoft
    }
}

/// Un rond de journée : les arcs de `Ring`, à petit diamètre.
///
/// `ActivityRing` porte un grand nombre en son cœur, ce qui n'a pas de sens à
/// dix-huit points de diamètre — d'où le passage direct par `Ring`, la brique
/// que les deux partagent. Le découpage est donc le même pour un petit rond et
/// pour un grand, plancher des parts minuscules compris.
private struct CompositionRing: View {
    let lanes: [Lane]
    let diameter: CGFloat
    let palette: PulseonPalette

    /// Proportionnelle au diamètre, pour qu'un petit rond reste un anneau et
    /// non un disque, mais jamais sous deux points : en dessous, le trait
    /// disparaît à l'écran.
    private var thickness: CGFloat { max(2.5, diameter * 0.24) }

    var body: some View {
        Ring(
            segments: lanes.filter { $0.total > 0 }.map {
                .init(
                    id: $0.device.rawValue,
                    value: $0.total,
                    tones: PulseonTheme.ringTones(for: $0.device, in: palette)
                )
            },
            thickness: thickness,
            track: palette.sunken,
            palette: palette
        )
        .frame(width: diameter, height: diameter)
    }
}
