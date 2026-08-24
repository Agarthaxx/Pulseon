import PulseonCore
import SwiftUI

// Les briques de dessin communes aux écrans.
//
// Elles vivaient dans `DayDashboard`, seul écran de l'app. L'écran de la
// semaine réutilise exactement la même carte, la même jauge et la même
// pastille : les recopier aurait fait diverger deux dessins censés être le
// même, et « la donnée est le design » suppose qu'une même forme veuille
// toujours dire la même chose.

// MARK: - Briques

struct MeterRow: View {
    let symbol: String
    let tint: Color
    let fill: LinearGradient
    let label: String
    /// Ce qu'il y a à dire quand il n'y a pas d'apps à montrer — le cas d'une
    /// source à compteur, qui connaît son total mais aucun horaire.
    var detail: String = ""
    /// Les apps de la ligne, affichées derrière leurs icônes.
    var apps: [String] = []
    let total: TimeInterval
    let share: Double
    let palette: PulseonPalette


    /// Trois minutes dans une journée font 0,4 % : tronqué à l'entier, ça
    /// s'affichait « 0 % » juste à côté d'une durée non nulle. Zéro est une
    /// affirmation, et celle-ci était fausse.
    static func percentage(_ share: Double) -> String {
        let percent = share * 100
        if percent > 0, percent < 1 { return "< 1 %" }
        return "\(Int(percent)) %"
    }

    var body: some View {
        HStack(spacing: 11) {
            Chip(symbol: symbol, tint: tint, palette: palette)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(label)
                        .font(PulseonTheme.rowLabel)
                        .foregroundStyle(palette.ink)
                    Spacer(minLength: 6)
                    Text(DurationFormat.compact(total))
                        .font(PulseonTheme.rowValue)
                        .foregroundStyle(palette.ink)
                    Text(Self.percentage(share))
                        .font(PulseonTheme.caption.monospacedDigit())
                        .foregroundStyle(palette.inkFaint)
                        .frame(width: 42, alignment: .trailing)
                }

                Meter(share: share, fill: fill, palette: palette)

                if !apps.isEmpty {
                    AppTrail(apps: Array(apps))
                        .font(PulseonTheme.caption)
                        .foregroundStyle(palette.inkFaint)
                } else if !detail.isEmpty {
                    Text(detail)
                        .font(PulseonTheme.caption)
                        .foregroundStyle(palette.inkFaint)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct Meter: View {
    let share: Double
    let fill: LinearGradient
    let palette: PulseonPalette


    /// La part effectivement dessinée. **Part à sa valeur finale**, donc une
    /// preview rend la jauge pleine : le repli est « tout est dessiné ». Voir
    /// `PulseonMotion`.
    @State private var drawn: Double?
    @Environment(\.pulseonMotion) private var motion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.sunken)
                Capsule()
                    .fill(fill)
                    // Une part minuscule doit rester visible : à 0,5 % la jauge
                    // ferait 0,3 point de large et se lirait « rien ».
                    .frame(
                        width: max(
                            3,
                            geometry.size.width * min(1, max(0, drawn ?? share))
                        )
                    )
            }
        }
        .frame(height: PulseonEditorial.meterHeight)
        .onAppear {
            guard motion else { return }
            drawn = 0
            withAnimation(PulseonMotion.fill) { drawn = share }
        }
        // La jauge suit sa donnée quand la journée change sous elle, au lieu de
        // rester figée sur la valeur qu'elle avait à son apparition.
        .onChange(of: share) { _, new in
            withAnimation(motion ? PulseonMotion.fill : nil) { drawn = new }
        }
    }
}

struct Chip: View {
    let symbol: String
    let tint: Color
    let palette: PulseonPalette


    var body: some View {
        let side = PulseonEditorial.chipSide
        RoundedRectangle(cornerRadius: side * 0.29, style: .continuous)
            .fill(tint.opacity(0.18))
            .frame(width: side, height: side)
            .overlay(
                RoundedRectangle(cornerRadius: side * 0.29, style: .continuous)
                    .strokeBorder(tint.opacity(0.28), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: side * 0.41, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}

struct UnpluggedRow: View {
    let device: Device
    let palette: PulseonPalette

    var body: some View {
        HStack(spacing: 11) {
            Chip(symbol: PulseonTheme.symbol(for: device), tint: palette.inkFaint, palette: palette)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.label)
                    .font(PulseonTheme.row)
                    .foregroundStyle(palette.inkSoft)
                Text("pas encore branchée")
                    .font(PulseonTheme.caption)
                    .foregroundStyle(palette.inkFaint)
            }
            Spacer()
            // Le pointillé dit l'inconnu, là où le plein dit le mesuré.
            Capsule()
                .strokeBorder(
                    palette.hairline,
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
                .frame(width: 54, height: 5)
        }
    }
}

/// Une carte flottante.
///
/// Trois couches, et aucune n'est décorative : un **dégradé** très léger pour
/// que la surface ne paraisse pas imprimée, un **filet** clair sur le bord haut
/// pour attraper la lumière, et une **ombre portée** pour la décoller du fond.
/// Sans elles, la carte et le fond se lisaient comme un seul aplat — c'est ce
/// qui faisait « bien moins premium » que la maquette.
struct Card<Content: View>: View {
    let palette: PulseonPalette
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
            .padding(PulseonEditorial.blockInsets)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BlockRule(palette: palette))
    }
}

struct NavButton: View {
    let symbol: String
    let palette: PulseonPalette
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? palette.inkSoft : palette.inkFaint.opacity(0.4))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.sunken)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct FailureCard: View {
    let reason: String
    let palette: PulseonPalette

    var body: some View {
        Card(palette: palette) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Lecture impossible")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.ink)
                // Dire quoi faire, pas seulement que ça a raté.
                Text(
                    "Pulseon n'a pas pu lire ses enregistrements. Le collecteur continue de tourner ; rouvrir la fenêtre retentera la lecture."
                )
                .font(PulseonTheme.caption)
                .foregroundStyle(palette.inkSoft)
                Text(reason)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.inkFaint)
                    .textSelection(.enabled)
            }
        }
    }
}

// MARK: - La répartition

/// À quoi le temps a servi. Vaut pour une journée comme pour une semaine :
/// elle ne reçoit que des totaux par catégorie, sans savoir sur quelle durée
/// ils ont été cumulés.
struct BreakdownCard: View {
    let categories: [CategoryTotal]
    let palette: PulseonPalette


    var body: some View {
        // Les parts se calculent sur la somme des catégories, pas sur le total
        // de la période : deux catégories simultanées comptent chacune leur
        // temps, donc leur somme peut dépasser le temps passé devant un écran.
        // Rapporter au `coveredTotal` afficherait des pourcentages dépassant
        // 100 %.
        let sum = categories.reduce(0) { $0 + $1.total }

        Card(palette: palette) {
            VStack(alignment: .leading, spacing: PulseonEditorial.rowGap) {
                CardTitle("Répartition", palette: palette)
                    .padding(.bottom, 2)

                ForEach(categories) { category in
                    MeterRow(
                        symbol: PulseonTheme.symbol(for: category.category),
                        tint: PulseonTheme.color(for: category.category, in: palette),
                        fill: PulseonTheme.gradient(for: category.category, in: palette),
                        label: category.category.label,
                        apps: category.entities.prefix(3).map(\.entity),
                        total: category.total,
                        share: sum > 0 ? category.total / sum : 0,
                        palette: palette
                    )
                }
            }
        }
    }
}

// MARK: - Les appareils

/// Les appareils et leur temps. Les pistes d'une période portent les mêmes
/// champs que celles d'une journée, à ceci près que leurs `blocks` sont vides —
/// une position horaire n'a pas de sens sur sept jours. Cette carte n'en lit
/// aucun, elle vaut donc pour les deux écrans.
struct DevicesCard: View {
    let lanes: [Lane]
    /// Le dénominateur des parts : la somme des appareils, écrans simultanés
    /// comptés deux fois. C'est le seul total dont les parts font 100 %.
    let summedTotal: TimeInterval
    let palette: PulseonPalette


    var body: some View {
        Card(palette: palette) {
            VStack(alignment: .leading, spacing: PulseonEditorial.rowGap) {
                CardTitle("Appareils", palette: palette)
                    .padding(.bottom, 2)

                ForEach(lanes, id: \.device) { lane in
                    if lane.isConnected {
                        MeterRow(
                            symbol: PulseonTheme.symbol(for: lane.device),
                            tint: PulseonTheme.color(for: lane.device, in: palette),
                            fill: PulseonTheme.gradient(for: lane.device, in: palette),
                            label: lane.device.label,
                            // Sa part est honnête, sa place dans le temps est
                            // inconnue — et doit se dire.
                            detail: lane.kind == .counter ? "horaires inconnus" : "",
                            apps: lane.kind == .counter
                                ? []
                                : lane.topEntities.prefix(3).map(\.entity),
                            total: lane.total,
                            share: summedTotal > 0 ? lane.total / summedTotal : 0,
                            palette: palette
                        )
                    } else {
                        // « Pas encore branchée » n'est pas « à zéro ». Zéro est
                        // une affirmation ; ici on n'a rien mesuré.
                        UnpluggedRow(device: lane.device, palette: palette)
                    }
                }
            }
        }
    }
}

/// La correspondance entre une couleur et un appareil.
///
/// Les cartes du dessous portent déjà les mêmes pastilles, mais un anneau sans
/// légende à portée de regard oblige à descendre pour savoir ce que dit sa
/// couleur — et c'est précisément la couleur qu'on est censé lire d'un coup
/// d'œil. Ne montre que les appareils qui ont du temps : légender une source
/// absente ajouterait du bruit sans rien dire.
/// La légende des couleurs d'appareil, **en colonne**.
///
/// Sert la case principale en fenêtre large, où l'anneau laissait ~420 points
/// de vide de chaque côté. Les mêmes faits, rangés à sa droite : la durée y est
/// alignée à droite, donc les trois chiffres se comparent d'un coup d'œil, ce
/// qu'une légende horizontale ne permet pas.
struct DeviceLegendColumn: View {
    let lanes: [Lane]
    let palette: PulseonPalette

    var body: some View {
        VStack(alignment: .leading, spacing: PulseonSpace.tight) {
            ForEach(lanes, id: \.device) { lane in
                HStack(spacing: PulseonSpace.tight) {
                    Circle()
                        .fill(PulseonTheme.gradient(for: lane.device, in: palette))
                        .frame(width: 9, height: 9)
                    Text(lane.device.label)
                        .font(PulseonTheme.row)
                        .foregroundStyle(palette.inkSoft)
                    Spacer(minLength: PulseonSpace.base)
                    Text(DurationFormat.compact(lane.total))
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(palette.ink)
                }
            }
        }
    }
}

struct DeviceLegend: View {
    let lanes: [Lane]
    let palette: PulseonPalette

    var body: some View {
        HStack(spacing: 16) {
            ForEach(lanes, id: \.device) { lane in
                HStack(spacing: 6) {
                    Circle()
                        .fill(PulseonTheme.gradient(for: lane.device, in: palette))
                        .frame(width: 9, height: 9)
                    Text(lane.device.label)
                        .font(PulseonTheme.caption)
                        .foregroundStyle(palette.inkSoft)
                    Text(DurationFormat.compact(lane.total))
                        .font(PulseonTheme.caption.monospacedDigit())
                        .foregroundStyle(palette.inkFaint)
                }
            }
        }
    }
}
