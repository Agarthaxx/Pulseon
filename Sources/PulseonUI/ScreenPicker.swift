import SwiftUI

/// Les écrans du dashboard.
///
/// Vit ici et non côté macOS parce que c'est la même barre que l'app iOS
/// portera — sous une autre forme (un `TabView` y est la convention), mais sur
/// la même liste d'écrans.
public enum PulseonScreen: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case timeline

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .day: "Jour"
        case .week: "Semaine"
        case .timeline: "Chronologie"
        }
    }

    public var symbol: String {
        switch self {
        case .day: "circle.dashed"
        case .week: "chart.bar.fill"
        case .timeline: "chart.bar.doc.horizontal"
        }
    }
}

/// La bascule entre les écrans.
///
/// Écrite à la main plutôt qu'avec `Picker(.segmented)` : le style système
/// impose ses propres couleurs, qui jurent avec le fond profond de la maquette,
/// et `ImageRenderer` ne le rend pas — l'écran deviendrait invisible à la
/// preview, ce qui est précisément la panne qu'on cherche à ne plus avoir.
public struct ScreenPicker: View {
    @Binding private var selection: PulseonScreen
    private let palette: PulseonPalette

    public init(selection: Binding<PulseonScreen>, palette: PulseonPalette) {
        self._selection = selection
        self.palette = palette
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(PulseonScreen.allCases) { screen in
                Segment(
                    screen: screen,
                    isSelected: screen == selection,
                    palette: palette,
                    action: { selection = screen }
                )
            }
        }
        .padding(3)
        .background(
            Capsule().fill(palette.sunken)
        )
    }

    private struct Segment: View {
        let screen: PulseonScreen
        let isSelected: Bool
        let palette: PulseonPalette
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 5) {
                    Image(systemName: screen.symbol)
                        .font(.system(size: 10, weight: .semibold))
                    Text(screen.label)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(isSelected ? palette.ink : palette.inkSoft)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isSelected ? palette.surface : .clear)
                        // L'ombre décolle le segment choisi de son creux : sans
                        // elle, les deux gris se lisent comme un seul aplat sur
                        // un fond aussi sombre.
                        .shadow(
                            color: isSelected ? palette.shadow : .clear, radius: 4, y: 1)
                )
            }
            // Sans `.plain`, `ImageRenderer` sort des carrés jaunes à la place
            // des boutons.
            .buttonStyle(.plain)
        }
    }
}
