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
                        .font(PulseonTheme.row)
                        .foregroundStyle(palette.ink)
                    Spacer(minLength: 6)
                    Text(DurationFormat.compact(total))
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
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

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.sunken)
                Capsule()
                    .fill(fill)
                    // Une part minuscule doit rester visible : à 0,5 % la jauge
                    // ferait 0,3 point de large et se lirait « rien ».
                    .frame(width: max(3, geometry.size.width * min(1, max(0, share))))
            }
        }
        .frame(height: 6)
    }
}

struct Chip: View {
    let symbol: String
    let tint: Color
    let palette: PulseonPalette

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(tint.opacity(0.18))
            .frame(width: 34, height: 34)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tint.opacity(0.28), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
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

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(palette.surfaceGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(palette.hairline.opacity(0.6), lineWidth: 0.5)
            )
            .shadow(color: palette.shadow, radius: 16, y: 8)
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
