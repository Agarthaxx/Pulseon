import AppKit
import PulseonCore
import PulseonUI
import SwiftData
import SwiftUI

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
    /// **L'identité est propre à un appareil.** « Apple TV », « Spotify » et
    /// « Netflix » existent à la fois sur le Mac et sur la télé, et sans cette
    /// colonne les deux se disputeraient la même ligne : chaque relevé de la
    /// télé réécrirait l'identifiant de bundle de l'app du Mac, puis
    /// l'activation suivante le réécrirait en sens inverse. C'est exactement
    /// l'écriture-à-chaque-tick que `noteApp` existe pour empêcher, doublée
    /// d'une catégorie qui changerait de camp à chaque passage.
    ///
    /// Optionnelle, et nil vaut `.mac` : toutes les lignes écrites avant la
    /// télé sont des apps du Mac, par construction. Un attribut optionnel
    /// ajouté à un `@Model` est la seule forme de migration que SwiftData
    /// sache faire sans plan de migration explicite.
    public var deviceRaw: String?
    public var bundleID: String?
    /// La catégorie brute déclarée par l'app (`public.app-category.…`), stockée
    /// telle quelle. On garde la donnée d'origine plutôt que notre
    /// interprétation : si la table de correspondance change d'avis, tout
    /// l'historique se reclasse sans avoir rien perdu.
    public var declaredCategory: String?
    public var firstSeen: Date

    public init(
        appName: String,
        device: Device = .mac,
        bundleID: String?,
        declaredCategory: String?,
        firstSeen: Date
    ) {
        self.appName = appName
        self.deviceRaw = device.rawValue
        self.bundleID = bundleID
        self.declaredCategory = declaredCategory
        self.firstSeen = firstSeen
    }

    public var device: Device {
        deviceRaw.flatMap(Device.init(rawValue:)) ?? .mac
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
        switch device {
        case .mac:
            return category(ofApp: name, on: .mac, fallingBackTo: rules.category(forApp: name))

        case .tv:
            // **La télé ne classe que ce qu'elle a nommé.** Sans identité en
            // base, on ne sait toujours qu'une chose de cet écran —
            // `PowerState: on` — et c'est `.tv` qui le dit. Ne surtout pas
            // retomber sur les règles du Mac ici : elles devineraient un
            // navigateur d'après le nom, or une app de télé qui contiendrait
            // « Arc » ou « Edge » n'en est pas un.
            guard let identity = identity(ofApp: name, on: .tv) else {
                return device.defaultCategory
            }
            return rules.category(
                forApp: name,
                bundleID: identity.bundleID,
                declared: identity.declaredCategory
            )

        }
    }

    private func category(
        ofApp name: String, on device: Device, fallingBackTo fallback: AppCategory
    ) -> AppCategory {
        guard let identity = identity(ofApp: name, on: device) else { return fallback }
        return rules.category(
            forApp: name,
            bundleID: identity.bundleID,
            declared: identity.declaredCategory
        )
    }

    /// L'icône de l'app, ou nil si on ne peut pas l'avoir.
    ///
    /// Rendre nil est une vraie réponse, pas un échec à cacher : une app
    /// désinstallée n'a plus d'icône, et une source à compteur (un jeu
    /// PlayStation) n'en a jamais eu. À l'appelant d'afficher un repli qui n'ait
    /// pas l'air cassé, jamais un carré vide.
    /// Cherchée du côté du **Mac**, quel que soit l'appareil qui a consommé le
    /// temps — et c'est voulu. « Netflix » sur la télé et « Netflix » sur le Mac
    /// sont le même produit et le même logo : emprunter l'icône du Mac quand
    /// elle existe est juste. Quand elle n'existe pas — le cas courant, aucune
    /// app de télé n'étant installée sur le Mac — on rend nil, et l'appelant
    /// affiche son repli.
    public func icon(ofApp name: String) -> NSImage? {
        if let cached = icons[name] { return cached }
        guard
            let bundleID = identity(ofApp: name, on: .mac)?.bundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[name] = icon
        return icon
    }

    /// L'accès des vues aux icônes, sous la seule forme que `PulseonUI` sait
    /// recevoir.
    ///
    /// **C'est ici que `NSImage` s'arrête.** Les vues serviront telles quelles à
    /// l'app iOS, où `NSImage` n'existe pas ; la traduction se fait donc du côté
    /// qui connaît la plateforme, et le paquet de dessin ne voit passer qu'une
    /// `Image` de SwiftUI.
    ///
    /// Capture faible : la fonction vit dans l'environnement SwiftUI, donc aussi
    /// longtemps que la fenêtre — la garder forte ferait vivre le registre, et
    /// son contexte SwiftData, après la fermeture de celle-ci.
    public var iconSource: AppIconSource {
        AppIconSource { [weak self] name in
            self?.icon(ofApp: name).map(Image.init(nsImage:))
        }
    }

    private func identity(ofApp name: String, on device: Device) -> StoredApp? {
        let key = "\(device.rawValue)\u{1}\(name)"
        if let cached = identities[key] { return cached }
        let raw = device.rawValue
        let macRaw = Device.mac.rawValue
        var descriptor = FetchDescriptor<StoredApp>(
            // `??` et surtout pas `!` : SwiftData refuse le déballage forcé
            // dans un prédicat. Les lignes écrites avant la télé n'ont pas de
            // colonne d'appareil, et ce sont toutes des apps du Mac.
            predicate: #Predicate { ($0.deviceRaw ?? macRaw) == raw && $0.appName == name }
        )
        descriptor.fetchLimit = 1
        guard let found = try? context.fetch(descriptor).first else { return nil }
        identities[key] = found
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
