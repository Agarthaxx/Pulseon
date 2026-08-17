import PulseonCore
import SwiftUI

/// L'écran d'une journée : ce qu'on voit en ouvrant Pulseon.
///
/// **Suit la maquette d'Arthur du 2026-08-17** — fond profond, cartes,
/// l'anneau en tête, puis la répartition, puis les appareils. Deux écarts
/// délibérés, tous deux demandés ou imposés par les règles du projet :
///
/// - **aucun objectif quotidien, aucun badge « On Track »**. La maquette en
///   portait ; Arthur a confirmé « on reste sur une application sans
///   jugement » en même temps qu'il validait le dessin. L'anneau garde donc sa
///   forme mais dit une composition, pas une progression (voir `RingLayout`) ;
/// - **la PlayStation n'apparaît sur aucune ligne de temps**. Elle ne connaît
///   pas ses horaires : elle a sa part dans l'anneau, qui n'est pas une
///   chronologie, et son total dans les listes.
public struct DayDashboard: View {
    public enum Load: Sendable {
        case loaded(DayPresentation)
        /// La lecture a échoué. Distinct d'une journée vide, et dit comme tel :
        /// afficher zéro serait affirmer une chose qu'on ne sait pas.
        case failed(String)
    }

    private let load: Load
    private let canGoForward: Bool
    private let onPrevious: () -> Void
    private let onNext: () -> Void
    private let onToday: () -> Void

    @Environment(\.colorScheme) private var scheme

    public init(
        load: Load,
        canGoForward: Bool,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onToday: @escaping () -> Void
    ) {
        self.load = load
        self.canGoForward = canGoForward
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onToday = onToday
    }

    public var body: some View {
        // Le contenu vit séparé du conteneur défilant : `ImageRenderer` ne rend
        // rien de l'intérieur d'un `ScrollView`, donc une vue défilante d'un
        // seul tenant serait invisible à la preview.
        ScrollView {
            DayDashboardContent(
                load: load,
                canGoForward: canGoForward,
                palette: PulseonTheme.palette(for: scheme),
                onPrevious: onPrevious,
                onNext: onNext,
                onToday: onToday
            )
        }
        .background(PulseonTheme.palette(for: scheme).ground)
        .frame(minWidth: 640, minHeight: 560)
    }
}

/// Le contenu du dashboard, rendable seul — c'est ce que regarde la preview.
public struct DayDashboardContent: View {
    let load: DayDashboard.Load
    let canGoForward: Bool
    let palette: PulseonPalette
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onToday: () -> Void

    public init(
        load: DayDashboard.Load,
        canGoForward: Bool,
        palette: PulseonPalette,
        onPrevious: @escaping () -> Void = {},
        onNext: @escaping () -> Void = {},
        onToday: @escaping () -> Void = {}
    ) {
        self.load = load
        self.canGoForward = canGoForward
        self.palette = palette
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onToday = onToday
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch load {
            case .loaded(let day):
                header(title: day.title, isLive: day.now != nil)
                RingCard(day: day, palette: palette)
                if !day.categories.isEmpty {
                    BreakdownCard(day: day, palette: palette)
                }
                DevicesCard(day: day, palette: palette)
            case .failed(let reason):
                header(title: "Journée", isLive: false)
                FailureCard(reason: reason, palette: palette)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.ground)
    }

    @ViewBuilder
    private func header(title: String, isLive: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isLive ? "Aujourd'hui" : "Journée")
                    // Grand et resserré : la hiérarchie de la maquette est
                    // franche, sans taille intermédiaire qui aplatirait tout.
                    .font(.system(size: 27, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(palette.ink)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.inkSoft)
            }

            Spacer()

            if canGoForward {
                Button("Aujourd'hui", action: onToday)
                    .buttonStyle(.plain)
                    .font(PulseonTheme.caption)
                    .foregroundStyle(palette.gold)
            }

            // `.buttonStyle(.plain)` n'est pas cosmétique : avec le style par
            // défaut, `ImageRenderer` sort des carrés jaunes à la place des
            // chevrons et la preview devient illisible.
            HStack(spacing: 2) {
                NavButton(symbol: "chevron.left", palette: palette, action: onPrevious)
                NavButton(
                    symbol: "chevron.right",
                    palette: palette,
                    isEnabled: canGoForward,
                    action: onNext
                )
            }
        }
    }
}

// MARK: - L'anneau

private struct RingCard: View {
    let day: DayPresentation
    let palette: PulseonPalette

    var body: some View {
        let lanes = day.digest.lanes.filter { $0.total > 0 }

        Card(palette: palette) {
            VStack(spacing: 14) {
                ActivityRing(
                    segments: lanes.map {
                        .init(
                            id: $0.device.rawValue,
                            value: $0.total,
                            fill: PulseonTheme.gradient(for: $0.device, in: palette)
                        )
                    },
                    total: day.isEmpty ? nil : day.digest.coveredTotal,
                    caption: day.isEmpty ? "rien de branché" : "devant un écran",
                    palette: palette
                )

                // Le second total ne s'affiche que s'il dit autre chose : sans
                // chevauchement, répéter le même chiffre sous un autre nom ne
                // fait qu'embrouiller.
                if day.digest.summedTotal - day.digest.coveredTotal > 60 {
                    Text(
                        "\(DurationFormat.compact(day.digest.summedTotal)) en cumulant les appareils, écrans simultanés comptés deux fois"
                    )
                    .font(PulseonTheme.caption)
                    .foregroundStyle(palette.inkFaint)
                    .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - La répartition

private struct BreakdownCard: View {
    let day: DayPresentation
    let palette: PulseonPalette

    var body: some View {
        // Les parts se calculent sur la somme des catégories, pas sur le total
        // de la journée : deux catégories simultanées comptent chacune leur
        // temps, donc leur somme peut dépasser le temps passé devant un écran.
        // Rapporter au `coveredTotal` afficherait des pourcentages dépassant
        // 100 %.
        let sum = day.categories.reduce(0) { $0 + $1.total }

        Card(palette: palette) {
            VStack(alignment: .leading, spacing: 15) {
                Text("Répartition")
                    .font(PulseonTheme.sectionTitle)
                    .foregroundStyle(palette.inkSoft)
                    .padding(.bottom, 2)

                ForEach(day.categories) { category in
                    MeterRow(
                        symbol: PulseonTheme.symbol(for: category.category),
                        tint: PulseonTheme.color(for: category.category, in: palette),
                        fill: PulseonTheme.gradient(for: category.category, in: palette),
                        label: category.category.label,
                        detail: category.entities.prefix(3).map(\.entity).joined(separator: " · "),
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

private struct DevicesCard: View {
    let day: DayPresentation
    let palette: PulseonPalette

    var body: some View {
        let sum = day.digest.summedTotal

        Card(palette: palette) {
            VStack(alignment: .leading, spacing: 15) {
                Text("Appareils")
                    .font(PulseonTheme.sectionTitle)
                    .foregroundStyle(palette.inkSoft)
                    .padding(.bottom, 2)

                ForEach(day.digest.lanes, id: \.device) { lane in
                    if lane.isConnected {
                        MeterRow(
                            symbol: PulseonTheme.symbol(for: lane.device),
                            tint: PulseonTheme.color(for: lane.device, in: palette),
                            fill: PulseonTheme.gradient(for: lane.device, in: palette),
                            label: lane.device.label,
                            detail: lane.kind == .counter
                                // Sa part de l'anneau est honnête, sa place dans
                                // la journée est inconnue — et doit se dire.
                                ? "horaires inconnus"
                                : lane.topEntities.prefix(3).map(\.entity).joined(separator: " · "),
                            total: lane.total,
                            share: sum > 0 ? lane.total / sum : 0,
                            palette: palette
                        )
                    } else {
                        // « Pas encore branchée » n'est pas « journée à zéro ».
                        // Zéro est une affirmation ; ici on n'a rien mesuré.
                        UnpluggedRow(device: lane.device, palette: palette)
                    }
                }
            }
        }
    }
}

// MARK: - Briques

private struct MeterRow: View {
    let symbol: String
    let tint: Color
    let fill: LinearGradient
    let label: String
    let detail: String
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

                if !detail.isEmpty {
                    Text(detail)
                        .font(PulseonTheme.caption)
                        .foregroundStyle(palette.inkFaint)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct Meter: View {
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

private struct Chip: View {
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

private struct UnpluggedRow: View {
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
private struct Card<Content: View>: View {
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

private struct NavButton: View {
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

private struct FailureCard: View {
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
