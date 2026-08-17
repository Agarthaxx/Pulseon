import AppKit
import PulseonCore
import SwiftData

/// Ce qu'on sait d'une app au-delà de son nom : son identifiant de bundle, la
/// catégorie qu'elle déclare à macOS, et donc son icône.
///
/// Table à part, et pas des colonnes ajoutées à `StoredSession`, pour une raison
/// de volume : le nom d'app est déjà écrit sur chaque session, et y ajouter
/// l'identifiant de bundle et la catégorie recopierait la même information des
/// milliers de fois. Ici l'app est écrite **une fois**, et les sessions la
/// retrouvent par son nom.
///
/// Prix de ce choix, assumé : deux apps portant le même nom affiché seraient
/// confondues. En pratique ça n'arrive pas sur une machine donnée, et le
/// bénéfice — ne pas gonfler la base — est mesurable.
@Model
public final class StoredApp {
    /// La clé de rapprochement avec les sessions. Volontairement **sans**
    /// `@Attribute(.unique)` : les contraintes d'unicité ne sont pas supportées
    /// par CloudKit, qui est la cible de synchronisation du projet. L'unicité
    /// est donc tenue à la main dans `noteApp`.
    public var appName: String
    public var bundleID: String?
    /// La catégorie brute déclarée par l'app (`public.app-category.…`), stockée
    /// telle quelle. On garde la donnée d'origine plutôt que notre
    /// interprétation : si la table de correspondance change d'avis, tout
    /// l'historique se reclasse sans avoir rien perdu.
    public var declaredCategory: String?
    public var firstSeen: Date

    public init(
        appName: String,
        bundleID: String?,
        declaredCategory: String?,
        firstSeen: Date
    ) {
        self.appName = appName
        self.bundleID = bundleID
        self.declaredCategory = declaredCategory
        self.firstSeen = firstSeen
    }
}

/// Lit l'identité des apps et en tire une catégorie et une icône.
///
/// Les icônes sont ce qui remplace, chez Pulseon, les photos d'un design
/// d'application grand public : une rangée d'icônes se reconnaît en un coup
/// d'œil là où une liste de noms se déchiffre. macOS les fournit gratuitement,
/// sans réseau — donc sans rien révéler à personne.
@MainActor
public final class AppRegistry {
    private let context: ModelContext
    private let rules: AppCategoryRules

    /// Deux caches, pour deux coûts différents.
    ///
    /// Résoudre une icône veut dire trouver l'app sur le disque puis la
    /// rasteriser : hors de question de le refaire à chaque image d'une liste
    /// qui défile.
    private var identities: [String: StoredApp] = [:]
    private var icons: [String: NSImage] = [:]

    public init(context: ModelContext, rules: AppCategoryRules = AppCategoryRules()) {
        self.context = context
        self.rules = rules
    }

    /// Le classement de toutes les entités d'une journée, en une seule valeur.
    ///
    /// Résolu ici et figé, plutôt que consulté pendant l'agrégation : le calcul
    /// ne doit pas dépendre d'un objet vivant lié à la base, et surtout pas
    /// interroger SwiftData depuis une boucle chaude. Même leçon que les
    /// frontières de journées calculées une fois puis parcourues par dichotomie.
    public func assignment(for digest: DayDigest) -> CategoryAssignment {
        var byEntity: [String: AppCategory] = [:]
        for lane in digest.lanes {
            for entity in lane.topEntities where byEntity[entity.entity] == nil {
                byEntity[entity.entity] = category(ofApp: entity.entity, on: lane.device)
            }
        }
        return CategoryAssignment(byEntity: byEntity)
    }

    /// À quoi servait ce temps.
    ///
    /// - Parameter device: sert de repli quand l'app est inconnue de la base —
    ///   un jeu PlayStation n'a pas d'`Info.plist` à lire.
    public func category(ofApp name: String, on device: Device = .mac) -> AppCategory {
        guard device == .mac else { return device.defaultCategory }
        return category(ofApp: name)
    }

    private func category(ofApp name: String) -> AppCategory {
        let identity = identity(ofApp: name)
        return rules.category(
            forApp: name,
            bundleID: identity?.bundleID,
            declared: identity?.declaredCategory
        )
    }

    /// L'icône de l'app, ou nil si on ne peut pas l'avoir.
    ///
    /// Rendre nil est une vraie réponse, pas un échec à cacher : une app
    /// désinstallée n'a plus d'icône, et une source à compteur (un jeu
    /// PlayStation) n'en a jamais eu. À l'appelant d'afficher un repli qui n'ait
    /// pas l'air cassé, jamais un carré vide.
    public func icon(ofApp name: String) -> NSImage? {
        if let cached = icons[name] { return cached }
        guard
            let bundleID = identity(ofApp: name)?.bundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[name] = icon
        return icon
    }

    private func identity(ofApp name: String) -> StoredApp? {
        if let cached = identities[name] { return cached }
        var descriptor = FetchDescriptor<StoredApp>(
            predicate: #Predicate { $0.appName == name }
        )
        descriptor.fetchLimit = 1
        guard let found = try? context.fetch(descriptor).first else { return nil }
        identities[name] = found
        return found
    }
}

extension NSRunningApplication {
    /// La catégorie que l'app déclare à macOS, lue dans son `Info.plist`.
    ///
    /// C'est le point de départ du classement, et il est loin d'être fiable —
    /// voir `AppCategoryRules`, où le cas des navigateurs est documenté avec les
    /// valeurs relevées sur une vraie machine.
    var declaredCategory: String? {
        guard let url = bundleURL, let bundle = Bundle(url: url) else { return nil }
        return bundle.infoDictionary?["LSApplicationCategoryType"] as? String
    }
}
