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
    /// Isolée au fil principal, parce que sa seule implémentation réelle
    /// interroge `NSWorkspace`, qui y vit. C'est gratuit ici : le corps d'une
    /// `View` est déjà isolé au fil principal, donc les vues l'appellent sans
    /// rien signer de plus.
    private let resolve: @MainActor (String) -> Image?

    public init(_ resolve: @escaping @MainActor (String) -> Image?) {
        self.resolve = resolve
    }

    @MainActor public func icon(for app: String) -> Image? { resolve(app) }

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

/// À quoi une ligne a servi : les apps, chacune derrière son icône.
///
/// C'est ce qui remplace, chez Pulseon, les photos d'un design grand public :
/// **une rangée d'icônes se reconnaît d'un coup d'œil là où une liste de noms
/// se déchiffre.** Remarque d'Arthur en apportant sa maquette, et elle est
/// juste — sans images, ce style paraîtrait vide.
///
/// **L'icône ne remplace pas le nom, elle le précède.** Une rangée d'icônes
/// seules obligerait à reconnaître un logo de 15 points pour savoir de quoi on
/// parle, et surtout elle mentirait dès qu'une app n'a pas d'icône : la rangée
/// se resserrerait sur ce qu'elle sait montrer, et on lirait trois noms sous
/// deux icônes sans jamais savoir laquelle manque. Appariées, les deux formes
/// disent toujours la même chose — l'icône seule est un raccourci, le nom seul
/// reste vrai.
public struct AppTrail: View {
    private let apps: [String]
    private let size: CGFloat

    @Environment(\.appIcons) private var source

    public init(apps: [String], size: CGFloat = 14) {
        self.apps = apps
        self.size = size
    }

    public var body: some View {
        // L'espacement entre deux apps est plus large que celui d'une app avec
        // sa propre icône : c'est ce qui fait lire des paires plutôt qu'une
        // file d'éléments, et ça évite d'avoir à poser un séparateur.
        HStack(spacing: 11) {
            // Indexé plutôt qu'identifié par le nom : deux entités homonymes
            // dans la même ligne feraient une collision d'identité, et un
            // `ForEach` qui perd son identité perd des lignes en silence.
            ForEach(Array(apps.enumerated()), id: \.offset) { _, app in
                HStack(spacing: 4) {
                    if let icon = source.icon(for: app) {
                        icon
                            .resizable()
                            .interpolation(.high)
                            .frame(width: size, height: size)
                    }
                    Text(app)
                        .lineLimit(1)
                }
                // Une app ne se coupe pas en deux : si la place manque, c'est
                // la dernière de la rangée qui se tronque, pas le nom de
                // chacune.
                .layoutPriority(1)
            }
        }
    }
}
