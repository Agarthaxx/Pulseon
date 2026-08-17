import SwiftUI

/// Comment `PulseonUI` obtient l'icône d'une app sans jamais connaître AppKit.
///
/// **C'est le corollaire de la règle « rien d'AppKit ici ».** Une icône
/// d'application se lit avec `NSWorkspace` sur macOS et `UIImage` sur iOS ;
/// aucun des deux ne compile sur l'autre plateforme. Les vues ne peuvent donc
/// pas aller chercher l'icône elles-mêmes — elles reçoivent une fonction qui
/// sait le faire, et chaque plateforme fournit la sienne.
///
/// **Rendre nil est une vraie réponse, pas un échec à cacher** : une app
/// désinstallée n'a plus d'icône, et un jeu PlayStation n'en a jamais eu côté
/// Mac. La vue affiche alors le nom seul, jamais un carré vide.
public struct AppIconSource {
    private let resolve: (String) -> Image?

    public init(_ resolve: @escaping (String) -> Image?) {
        self.resolve = resolve
    }

    public func icon(for app: String) -> Image? { resolve(app) }

    /// Le défaut : aucune icône. C'est ce que voit une preview ou un test qui
    /// n'en fournit pas, et l'écran reste lisible.
    ///
    /// Calculé à chaque appel plutôt que rangé dans un `static let` : une
    /// constante globale d'un type non-`Sendable` est refusée en concurrence
    /// stricte, et rendre `AppIconSource` `Sendable` obligerait à promettre que
    /// la fonction de résolution l'est — or elle touche `NSWorkspace`, qui vit
    /// sur le fil principal.
    public static var unavailable: AppIconSource { AppIconSource { _ in nil } }
}

private struct AppIconSourceKey: EnvironmentKey {
    static var defaultValue: AppIconSource { .unavailable }
}

extension EnvironmentValues {
    /// Passe par l'environnement plutôt que de descendre en paramètre : les
    /// lignes qui affichent des icônes sont imbriquées loin sous le dashboard,
    /// et les traverser toutes avec un argument de plus rendrait chaque vue
    /// intermédiaire dépendante d'une chose qu'elle n'utilise pas.
    public var appIcons: AppIconSource {
        get { self[AppIconSourceKey.self] }
        set { self[AppIconSourceKey.self] = newValue }
    }
}

/// Une rangée d'icônes d'apps.
///
/// C'est ce qui remplace, chez Pulseon, les photos d'un design grand public :
/// **une rangée d'icônes se reconnaît d'un coup d'œil là où une liste de noms
/// se déchiffre.** Remarque d'Arthur en apportant sa maquette, et elle est
/// juste — sans images, ce style paraîtrait vide.
public struct AppIconStrip: View {
    private let apps: [String]
    private let size: CGFloat

    @Environment(\.appIcons) private var source

    public init(apps: [String], size: CGFloat = 15) {
        self.apps = apps
        self.size = size
    }

    public var body: some View {
        // Les noms sans icône ne laissent pas de trou : la rangée se resserre
        // sur ce qu'elle sait montrer.
        let icons = apps.compactMap { name in
            source.icon(for: name).map { (name, $0) }
        }

        HStack(spacing: 3) {
            ForEach(icons, id: \.0) { _, icon in
                icon
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
            }
        }
    }
}
