import PulseonCore
import SwiftUI

/// Un appareil trouvé sur le réseau **et vérifié**.
///
/// Il n'existe qu'une fois la vérification passée : ce type ne peut pas
/// représenter un candidat douteux, ce qui est délibéré. La vue ne peut donc
/// pas afficher « peut-être une télé » — elle n'a pas les mots pour.
///
/// **Le nom et le modèle viennent de la télé**, jamais d'un catalogue écrit à
/// la main ni du nom d'instance mDNS. Même règle que pour les apps de la télé.
public struct DiscoveredDisplay: Sendable, Equatable, Identifiable {
    /// Le nom d'hôte à écrire dans les réglages — `Samsung.local`.
    public let host: String
    /// Le nom que l'appareil se donne — « [TV] Samsung S90C ».
    public let name: String
    /// Son modèle, quand il le donne.
    public let model: String?

    public var id: String { host }

    public init(host: String, name: String, model: String? = nil) {
        self.host = host
        self.name = name
        self.model = model
    }
}

/// L'écran « Relier un appareil ».
///
/// Il remplace le `defaults write com.arthurlanllier.pulseon TVHost …` qu'il
/// fallait taper dans un terminal en connaissant d'avance le nom mDNS de sa
/// télé. Le back vit dans `DeviceDiscovery`, côté macOS ; ici il n'y a que du
/// dessin, pour que l'app iOS puisse s'en servir le jour venu.
public enum DeviceSetup {
    /// Où en est la recherche.
    ///
    /// **Cinq états, et le quatrième est celui qui compte.** Une liste vide ne
    /// veut pas dire « tu n'as pas de télé » : une télé en veille profonde
    /// refuse le port 8001, donc elle est **introuvable par construction**, et
    /// le Mac doit de toute façon être sur son réseau. Confondre « rien trouvé »
    /// avec « rien à trouver » serait la même faute que confondre « pas encore
    /// branchée » avec « journée à zéro ».
    public enum State: Sendable, Equatable {
        /// On n'a pas encore cherché.
        case idle
        case scanning
        /// Au moins un appareil vérifié. Publié au fil de l'eau : trouver sa
        /// télé en deux secondes puis attendre la fin du balayage donnerait
        /// l'impression que rien ne marche.
        case found([DiscoveredDisplay])
        /// La recherche est allée à son terme sans rien confirmer.
        case nothingFound
        /// Le balayage lui-même a échoué — sur macOS récent, presque toujours
        /// l'autorisation « réseau local » refusée.
        case failed(String)
        /// Un appareil vient d'être relié.
        case bound(DiscoveredDisplay)
    }
}

public struct DeviceSetupView: View {
    private let state: DeviceSetup.State
    /// Le nom d'hôte déjà relié, s'il y en a un.
    private let boundHost: String?
    private let onScan: () -> Void
    private let onBind: (DiscoveredDisplay) -> Void
    private let onUnbind: () -> Void
    private let palette: PulseonPalette

    /// Ce qu'on a tapé à la main. Un filet, pas la voie normale : il sert le
    /// jour où la télé est éteinte au moment où l'on installe l'app, et il
    /// évite d'avoir à ressortir le terminal.
    @State private var typedHost: String = ""

    public init(
        state: DeviceSetup.State,
        boundHost: String?,
        palette: PulseonPalette,
        onScan: @escaping () -> Void,
        onBind: @escaping (DiscoveredDisplay) -> Void,
        onUnbind: @escaping () -> Void
    ) {
        self.state = state
        self.boundHost = boundHost
        self.palette = palette
        self.onScan = onScan
        self.onBind = onBind
        self.onUnbind = onUnbind
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let boundHost {
                boundCard(boundHost)
            }

            resultCard

            // **La saisie à la main n'apparaît que quand elle sert.** L'offrir
            // sous une télé qu'on vient de trouver invite à taper un nom d'hôte
            // qu'on a déjà. Effet de bord utile : les écrans les plus regardés
            // (trouvée, reliée, recherche) sont alors **entièrement rendables
            // par la preview** — voir la note sur `TextField` plus bas.
            if showsManualEntry {
                manualEntry
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.ground)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Relier un appareil")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(palette.ink)
                // Ce que la recherche fait, en une ligne, parce qu'un scan
                // réseau mérite d'être annoncé plutôt que subi.
                Text("Pulseon cherche sur ton réseau local. Rien ne sort de ta machine.")
                    .font(PulseonTheme.caption)
                    .foregroundStyle(palette.inkFaint)
            }
            Spacer(minLength: 12)
            ActionButton(
                title: isScanning ? "Recherche…" : "Chercher",
                palette: palette,
                isEnabled: !isScanning,
                action: onScan
            )
        }
    }

    private var isScanning: Bool {
        if case .scanning = state { return true }
        return false
    }

    /// Vrai seulement quand la découverte n'a rien donné — ou n'a pas encore
    /// été lancée.
    private var showsManualEntry: Bool {
        switch state {
        case .idle, .nothingFound, .failed: true
        case .scanning, .found, .bound: false
        }
    }

    private func boundCard(_ host: String) -> some View {
        Card(palette: palette) {
            HStack(spacing: 11) {
                Chip(
                    symbol: PulseonTheme.symbol(for: Device.tv),
                    tint: PulseonTheme.color(for: Device.tv, in: palette),
                    palette: palette
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reliée")
                        .font(PulseonTheme.row)
                        .foregroundStyle(palette.ink)
                    Text(host)
                        .font(PulseonTheme.caption.monospaced())
                        .foregroundStyle(palette.inkFaint)
                }
                Spacer(minLength: 8)
                ActionButton(
                    title: "Délier", palette: palette, isProminent: false, action: onUnbind)
            }
        }
    }

    @ViewBuilder
    private var resultCard: some View {
        switch state {
        case .idle:
            Card(palette: palette) {
                Note(
                    title: "Aucune recherche lancée",
                    detail: "« Chercher » interroge les appareils qui s'annoncent sur ton réseau.",
                    palette: palette
                )
            }

        case .scanning:
            Card(palette: palette) {
                Note(
                    title: "Recherche sur le réseau local…",
                    detail:
                        "Seuls les appareils que Pulseon sait vraiment mesurer apparaîtront ici.",
                    palette: palette
                )
            }

        case .found(let displays):
            Card(palette: palette) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Trouvés sur ton réseau", palette: palette)
                    ForEach(displays) { display in
                        DiscoveredRow(
                            display: display,
                            isBound: display.host == boundHost,
                            palette: palette,
                            onBind: { onBind(display) }
                        )
                    }
                }
            }

        case .nothingFound:
            Card(palette: palette) {
                Note(
                    title: "Aucun appareil trouvé",
                    // **Dire pourquoi.** Un écran vide se lirait « ça ne marche
                    // pas », alors que les deux causes les plus probables sont
                    // parfaitement normales et réparables par Arthur.
                    detail: """
                        Une télé éteinte ne répond pas — allume-la, puis relance \
                        la recherche. Et le Mac doit être sur le même réseau qu'elle.
                        """,
                    palette: palette
                )
            }

        case .failed(let reason):
            Card(palette: palette) {
                Note(
                    title: "La recherche n'a pas pu démarrer",
                    detail: """
                        \(reason)

                        macOS demande une autorisation « réseau local » au premier \
                        scan. Elle se donne dans Réglages Système › Confidentialité.
                        """,
                    palette: palette
                )
            }

        case .bound(let display):
            Card(palette: palette) {
                Note(
                    title: "\(display.name) est reliée",
                    detail:
                        "Le collecteur l'interroge toutes les trente secondes, tant que le Mac est sur son réseau.",
                    palette: palette
                )
            }
        }
    }

    /// **`TextField` n'est pas rendu par `ImageRenderer`** : il sort en
    /// rectangle jaune barré d'un panneau d'interdiction rouge. C'est un défaut
    /// de la preview, pas du dessin — mais il faut le savoir, parce que du
    /// jaune et du rouge dans une app qui s'interdit le rouge ressemble à une
    /// faute grave. Trouvé au premier rendu, le 2026-08-24.
    ///
    /// Contrairement à `Picker(.segmented)`, on ne peut pas le remplacer par un
    /// dessin maison : il n'y a pas de champ de saisie à écrire soi-même en
    /// SwiftUI pur. Le coût est borné — l'angle mort est une boîte de texte
    /// sans logique de mise en page — et il est repoussé aux seuls états où la
    /// découverte a échoué.
    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionTitle("Ou saisir le nom à la main", palette: palette)
            HStack(spacing: 8) {
                TextField("Samsung.local", text: $typedHost)
                    .textFieldStyle(.plain)
                    .font(PulseonTheme.caption.monospaced())
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(palette.sunken)
                    )
                ActionButton(
                    title: "Relier",
                    palette: palette,
                    isProminent: false,
                    isEnabled: !typedHost.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    let host = typedHost.trimmingCharacters(in: .whitespaces)
                    // Saisi à la main, donc **non vérifié** : on ne connaît ni
                    // son nom ni son modèle, et on ne les invente pas. Le nom
                    // affiché est l'hôte lui-même, faute de mieux.
                    onBind(DiscoveredDisplay(host: host, name: host, model: nil))
                }
            }
        }
    }
}

// MARK: - Briques locales

private struct DiscoveredRow: View {
    let display: DiscoveredDisplay
    let isBound: Bool
    let palette: PulseonPalette
    let onBind: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Chip(
                symbol: PulseonTheme.symbol(for: Device.tv),
                tint: PulseonTheme.color(for: Device.tv, in: palette),
                palette: palette
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(display.name)
                    .font(PulseonTheme.row)
                    .foregroundStyle(palette.ink)
                // L'hôte est ce qui sera vraiment écrit dans les réglages : le
                // montrer évite d'avoir à faire confiance sur parole.
                Text(display.model.map { "\($0) · \(display.host)" } ?? display.host)
                    .font(PulseonTheme.caption.monospaced())
                    .foregroundStyle(palette.inkFaint)
            }
            Spacer(minLength: 8)
            if isBound {
                Text("reliée")
                    .font(PulseonTheme.caption)
                    .foregroundStyle(palette.inkFaint)
            } else {
                ActionButton(title: "Relier", palette: palette, action: onBind)
            }
        }
    }
}

private struct SectionTitle: View {
    let text: String
    let palette: PulseonPalette

    init(_ text: String, palette: PulseonPalette) {
        self.text = text
        self.palette = palette
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(palette.inkFaint)
    }
}

private struct Note: View {
    let title: String
    let detail: String
    let palette: PulseonPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.ink)
            Text(detail)
                .font(PulseonTheme.caption)
                .foregroundStyle(palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Un bouton.
///
/// Écrit à la main plutôt qu'avec `.borderedProminent` : le style système
/// impose ses couleurs, qui jurent avec le fond profond de la maquette, et
/// `ImageRenderer` ne le rend pas — l'écran deviendrait invisible à la preview,
/// ce qui est précisément la panne qu'on cherche à ne plus avoir. Même raison
/// que `ScreenPicker`.
private struct ActionButton: View {
    let title: String
    let palette: PulseonPalette
    var isProminent: Bool = true
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(background)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var foreground: Color {
        guard isEnabled else { return palette.inkFaint.opacity(0.5) }
        return isProminent ? palette.navyDeep : palette.inkSoft
    }

    private var background: some ShapeStyle {
        guard isEnabled, isProminent else { return AnyShapeStyle(palette.sunken) }
        return AnyShapeStyle(palette.goldGradient)
    }
}
