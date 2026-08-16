import PulseonCore
import SwiftUI

/// L'écran d'une journée : ce qu'on voit en ouvrant Pulseon.
///
/// L'ordre de lecture est voulu : d'abord le temps réellement passé devant un
/// écran, ensuite *quand* il l'a été, enfin le détail par appareil. Le chiffre
/// répond à la question qu'on se pose en ouvrant l'app ; la timeline répond à
/// celle qu'on ne savait pas se poser.
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
        VStack(alignment: .leading, spacing: 18) {
            switch load {
            case .loaded(let day):
                header(day)
                readout(day)
                DayTimeline(day: day)
                breakdown(day)
            case .failed(let reason):
                header(nil)
                Failure(reason: reason)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(minWidth: 620, minHeight: 460)
    }

    // MARK: En-tête

    @ViewBuilder
    private func header(_ day: DayPresentation?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(day?.title ?? "Journée")
                .font(.system(size: 20, weight: .semibold))
                .textCase(.lowercase)

            if let day, day.now != nil {
                Text("en cours")
                    .font(PulseonTheme.stencil)
                    .foregroundStyle(PulseonTheme.playhead)
            }

            Spacer()

            // `.link` n'existe que sur macOS, et ces vues doivent compiler
            // telles quelles pour l'app iOS.
            Button("Aujourd'hui", action: onToday)
                .buttonStyle(.borderless)
                .opacity(canGoForward ? 1 : 0)

            HStack(spacing: 4) {
                Button(action: onPrevious) { Image(systemName: "chevron.left") }
                    .help("Journée précédente")
                Button(action: onNext) { Image(systemName: "chevron.right") }
                    .help("Journée suivante")
                    .disabled(!canGoForward)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: Les deux totaux

    @ViewBuilder
    private func readout(_ day: DayPresentation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if day.isEmpty {
                // Une journée sans aucune source branchée n'est pas une journée
                // à zéro : on n'a simplement rien mesuré.
                Text("Rien de branché ce jour-là")
                    .font(PulseonTheme.readout(34))
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(DurationFormat.compact(day.digest.coveredTotal))
                        .font(PulseonTheme.readout(56))
                    Text("devant un écran")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                // Le second total ne s'affiche que s'il dit autre chose : sans
                // chevauchement, répéter le même chiffre sous un autre nom ne
                // fait qu'embrouiller.
                if day.digest.summedTotal - day.digest.coveredTotal > 60 {
                    Text(
                        "\(DurationFormat.compact(day.digest.summedTotal)) en cumulant les appareils, écrans simultanés comptés deux fois"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: Le détail

    @ViewBuilder
    private func breakdown(_ day: DayPresentation) -> some View {
        let lanes = day.digest.lanes.filter { $0.isConnected && !$0.topEntities.isEmpty }
        if !lanes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(lanes, id: \.device) { lane in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(PulseonTheme.color(for: lane.device))
                            .frame(width: 7, height: 7)
                        Text(lane.device.label)
                            .font(.system(size: 12, weight: .medium))
                        Text(DurationFormat.long(lane.total))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(lane.topEntities.prefix(3).map(\.entity).joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct Failure: View {
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Lecture impossible")
                .font(.system(size: 15, weight: .semibold))
            // Dire quoi faire, pas seulement que ça a raté.
            Text(
                "Pulseon n'a pas pu lire ses enregistrements. Le collecteur continue de tourner ; rouvrir la fenêtre retentera la lecture."
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            Text(reason)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
