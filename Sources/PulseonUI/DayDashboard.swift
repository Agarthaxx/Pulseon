import PulseonCore
import SwiftUI

/// L'écran d'une journée : ce qu'on voit en ouvrant Pulseon.
///
/// L'ordre de lecture est voulu, et il n'a pas changé de direction visuelle :
/// d'abord le temps réellement passé devant un écran, ensuite *quand* il l'a
/// été, enfin par quel appareil. Le chiffre répond à la question qu'on se pose en
/// ouvrant l'app ; le rail répond à celle qu'on ne savait pas se poser.
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
        ScrollView {
            DayDashboardContent(
                load: load, canGoForward: canGoForward,
                onPrevious: onPrevious, onNext: onNext, onToday: onToday
            )
        }
        .background(PulseonTheme.ground)
        .frame(minWidth: 560, minHeight: 480)
    }
}

/// Le contenu de l'écran, sans le défilement.
///
/// Séparé de `DayDashboard` pour une raison très concrète : **`ImageRenderer` ne
/// rend pas le contenu d'un `ScrollView`.** La première version de cette refonte
/// est sortie en PNG entièrement noir — fond seul, aucun contenu — et rien ne le
/// signalait, ni le compilateur ni les tests. Le défilement reste nécessaire
/// (l'écran va s'allonger), donc c'est le contenu qui devient rendable seul.
///
/// Public pour que l'outil de preview y accède ; à n'utiliser directement que
/// pour ça, ou pour l'intégrer dans un autre conteneur défilant.
public struct DayDashboardContent: View {
    private let load: DayDashboard.Load
    private let canGoForward: Bool
    private let onPrevious: () -> Void
    private let onNext: () -> Void
    private let onToday: () -> Void

    public init(
        load: DayDashboard.Load,
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
        VStack(alignment: .leading, spacing: 22) {
            switch load {
            case .loaded(let day):
                header(title: day.title, isLive: day.now != nil)
                Hero(day: day)
                if !day.isEmpty {
                    Card { DayRail(day: day) }
                }
                DeviceList(lanes: day.digest.lanes)
            case .failed(let reason):
                header(title: "Journée", isLive: false)
                Failure(reason: reason)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: En-tête

    @ViewBuilder
    private func header(title: String, isLive: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(PulseonTheme.ink)

            if isLive { LivePill() }

            Spacer(minLength: 8)

            if canGoForward {
                Button(action: onToday) {
                    Text("Aujourd'hui")
                        .font(PulseonTheme.caption)
                        .foregroundStyle(PulseonTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(PulseonTheme.surfaceSunken, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            RoundIconButton(symbol: "chevron.left", help: "Journée précédente", action: onPrevious)
            RoundIconButton(
                symbol: "chevron.right", help: "Journée suivante",
                isEnabled: canGoForward, action: onNext
            )
        }
    }
}

// MARK: - L'état « en cours »

/// Dit que la journée n'est pas finie, donc que le chiffre va encore monter.
/// Porte le rouge de l'instant courant, comme le marqueur du rail : c'est la même
/// information, elle doit avoir la même couleur.
private struct LivePill: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(PulseonTheme.now)
                .frame(width: 5, height: 5)
            Text("en cours")
                .font(PulseonTheme.footnote)
                .foregroundStyle(PulseonTheme.inkSoft)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(PulseonTheme.surfaceSunken, in: Capsule())
    }
}

private struct RoundIconButton: View {
    let symbol: String
    let help: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? PulseonTheme.ink : PulseonTheme.inkFaint)
                .frame(width: 28, height: 28)
                .background(PulseonTheme.surfaceSunken, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Le chiffre du jour

private struct Hero: View {
    let day: DayPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if day.isEmpty {
                // Une journée sans aucune source branchée n'est pas une journée à
                // zéro : on n'a simplement rien mesuré. Zéro serait une
                // affirmation.
                Text("Rien de branché ce jour-là")
                    .font(PulseonTheme.readout(30))
                    .foregroundStyle(PulseonTheme.inkSoft)
                Text("Aucun collecteur n'a écrit quoi que ce soit — ce n'est pas une journée sans écran.")
                    .font(PulseonTheme.caption)
                    .foregroundStyle(PulseonTheme.inkFaint)
            } else {
                Readout(DurationFormat.compact(day.digest.coveredTotal), size: 54)
                Text("devant un écran")
                    .font(PulseonTheme.caption)
                    .foregroundStyle(PulseonTheme.inkSoft)

                // Le second total ne s'affiche que s'il dit autre chose : sans
                // chevauchement, répéter le même chiffre sous un autre nom
                // n'embrouille que le lecteur.
                if day.digest.summedTotal - day.digest.coveredTotal > 60 {
                    Text(
                        "\(DurationFormat.compact(day.digest.summedTotal)) en cumulant les appareils — les écrans simultanés y comptent deux fois"
                    )
                    .font(PulseonTheme.footnote)
                    .foregroundStyle(PulseonTheme.inkFaint)
                    .padding(.top, 2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Un grand nombre dont les unités sont plus petites et plus grises.
///
/// « 10h52 » se lit mieux si le `h` ne pèse pas autant que les chiffres : c'est
/// le dessin du grand chiffre avec son unité en dessous, appliqué à une durée.
/// L'unité n'est pas décorative pour autant — c'est elle qui empêche de lire le
/// total comme l'horloge du système.
struct Readout: View {
    private let text: String
    private let size: CGFloat

    init(_ text: String, size: CGFloat) {
        self.text = text
        self.size = size
    }

    var body: some View {
        runs.reduce(Text("")) { accumulated, run in
            accumulated
                + Text(run.text)
                .font(run.isDigits ? PulseonTheme.readout(size) : PulseonTheme.unit(size * 0.46))
                .foregroundColor(run.isDigits ? PulseonTheme.ink : PulseonTheme.inkSoft)
                // Sans ça l'unité, partageant la ligne de base des grands
                // chiffres, tombe tout en bas et se lit comme un indice de
                // formule chimique. Constaté en PNG.
                .baselineOffset(run.isDigits ? 0 : size * 0.13)
        }
        .accessibilityLabel(text)
    }

    /// Découpe « 10h52 » en « 10 », « h », « 52 ». Les chiffres d'un côté, tout
    /// le reste de l'autre : ça marche pour `3h07`, `7m12` et `42s` sans
    /// connaître le format.
    private var runs: [(text: String, isDigits: Bool)] {
        var runs: [(text: String, isDigits: Bool)] = []
        for character in text {
            let isDigit = character.isNumber
            if let last = runs.last, last.isDigits == isDigit {
                runs[runs.count - 1].text.append(character)
            } else {
                runs.append((String(character), isDigit))
            }
        }
        return runs
    }
}

// MARK: - Les appareils

/// La liste des appareils, qui sert aussi de légende du rail.
///
/// Chaque ligne porte la **pastille du traitement** de son appareil — plein,
/// translucide, pointillé. C'est ce qui apprend à lire le rail sans qu'aucun
/// texte n'ait à l'expliquer.
private struct DeviceList: View {
    let lanes: [Lane]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Text("Appareils")
                    .font(PulseonTheme.sectionTitle)
                    .foregroundStyle(PulseonTheme.ink)
                    .padding(.bottom, 12)

                ForEach(Array(lanes.enumerated()), id: \.element.device) { index, lane in
                    if index > 0 {
                        Rectangle()
                            .fill(PulseonTheme.hairline)
                            .frame(height: 1)
                    }
                    DeviceRow(lane: lane)
                }
            }
        }
    }
}

private struct DeviceRow: View {
    let lane: Lane

    var body: some View {
        HStack(spacing: 11) {
            Swatch(lane: lane)

            Text(lane.device.label)
                .font(PulseonTheme.row)
                .foregroundStyle(lane.isConnected ? PulseonTheme.ink : PulseonTheme.inkFaint)

            Spacer(minLength: 8)

            if lane.isConnected {
                if let top = lane.topEntities.first {
                    Text(top.entity)
                        .font(PulseonTheme.caption)
                        .foregroundStyle(PulseonTheme.inkFaint)
                        .lineLimit(1)
                }
                Text(DurationFormat.long(lane.total))
                    .font(PulseonTheme.row.monospacedDigit())
                    .foregroundStyle(PulseonTheme.inkSoft)
            } else {
                // « Pas encore branchée » n'est pas « journée à zéro », et l'UI
                // ne doit jamais laisser confondre les deux.
                Text("pas encore branchée")
                    .font(PulseonTheme.caption)
                    .foregroundStyle(PulseonTheme.inkFaint)
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard lane.isConnected else { return "\(lane.device.label), pas encore branchée" }
        return "\(lane.device.label), \(DurationFormat.long(lane.total))"
    }
}

/// La pastille qui dit comment cet appareil se dessine sur le rail.
private struct Swatch: View {
    let lane: Lane

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        Group {
            if !lane.isConnected {
                shape.fill(PulseonTheme.surfaceSunken)
            } else if lane.kind == .counter {
                shape
                    .strokeBorder(
                        PulseonTheme.color(for: lane.device),
                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])
                    )
            } else {
                shape.fill(PulseonTheme.color(for: lane.device))
            }
        }
        .frame(width: 14, height: 10)
    }
}

// MARK: - L'échec

private struct Failure: View {
    let reason: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Lecture impossible")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PulseonTheme.ink)
                // Dire quoi faire, pas seulement que ça a raté.
                Text(
                    "Pulseon n'a pas pu lire ses enregistrements. Le collecteur continue de tourner ; rouvrir la fenêtre retentera la lecture."
                )
                .font(PulseonTheme.caption)
                .foregroundStyle(PulseonTheme.inkSoft)
                Text(reason)
                    .font(PulseonTheme.footnote.monospaced())
                    .foregroundStyle(PulseonTheme.inkFaint)
                    .textSelection(.enabled)
            }
        }
    }
}
