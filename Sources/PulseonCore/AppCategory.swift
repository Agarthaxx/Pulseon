import Foundation

/// À quoi servait le temps, et non quelle app l'a consommé.
///
/// Le collecteur enregistre des noms d'apps, ce qui est la bonne matière
/// première et une mauvaise réponse : au bout de trente apps dans la journée,
/// la liste devient du bruit, et surtout **elle ne se compare pas d'un jour à
/// l'autre**. « 6 h 12 de dev, 47 min de messages » se compare ; « Xcode,
/// Ghostty, Brave, Notion, Discord, Finder… » non.
///
/// Volontairement peu de catégories : l'intérêt est qu'une journée se lise en
/// quatre lignes. Une catégorie de plus, c'est une ligne de plus à interpréter.
public enum AppCategory: String, CaseIterable, Sendable, Codable {
    case development
    case web
    case communication
    case media
    case creation
    case productivity
    case game
    /// Ni devinée, ni devinable. Assumée comme telle : mieux vaut une ligne
    /// « Autre » honnête qu'un rangement inventé.
    case other

    public var label: String {
        switch self {
        case .development: "Développement"
        case .web: "Web"
        case .communication: "Communication"
        case .media: "Vidéo et musique"
        case .creation: "Création"
        case .productivity: "Productivité"
        case .game: "Jeu"
        case .other: "Autre"
        }
    }
}

/// Comment on décide de la catégorie d'une app.
///
/// La source de vérité de départ est macOS lui-même : chaque app déclare une
/// catégorie App Store dans son `Info.plist` (`LSApplicationCategoryType`).
/// C'est gratuit, hors-ligne, et ça marche pour des apps qu'on n'a jamais vues.
///
/// Mais ça ne suffit pas, et c'est **vérifié sur une vraie machine** plutôt que
/// supposé. Sur le Mac d'Arthur :
///
/// - Xcode, VS Code, Ghostty, Docker → `developer-tools`. Juste.
/// - Discord → `social-networking`. Juste.
/// - Firefox Developer Edition et Safari → `productivity`. **Faux** : ce sont
///   des navigateurs, et ce qu'on y fait n'a rien à voir avec un outil de
///   productivité.
/// - Brave Browser → **rien du tout**, aucune catégorie déclarée.
///
/// D'où l'ordre de décision : la correction manuelle d'abord, la liste des
/// navigateurs connus ensuite, la déclaration de macOS enfin, et `other` en
/// dernier recours.
///
/// **Ce qu'on ne fait pas** : deviner d'après le nom. « Mail » n'est pas
/// forcément un client mail, et un faux rangement est pire qu'un `other`.
public struct AppCategoryRules: Sendable {
    /// Les corrections de l'utilisateur, par nom d'app. Elles gagnent sur tout
    /// le reste — c'est ce qui fait que l'app est la sienne et pas celle
    /// d'Apple.
    public let overrides: [String: AppCategory]

    public init(overrides: [String: AppCategory] = [:]) {
        self.overrides = overrides
    }

    public func category(
        forApp name: String,
        bundleID: String? = nil,
        declared: String? = nil
    ) -> AppCategory {
        if let override = overrides[name] { return override }
        if Self.isBrowser(name: name, bundleID: bundleID) { return .web }
        if let declared, let mapped = Self.mapping[declared] { return mapped }
        return .other
    }

    /// Un navigateur n'est pas une activité, et aucune catégorie déclarée ne le
    /// dira jamais correctement.
    ///
    /// Trois heures de Firefox peuvent être de la documentation technique ou du
    /// YouTube, et c'est le même nom d'app. Le seul moyen de trancher serait de
    /// lire l'URL ou le titre de la fenêtre, ce qui demande la permission
    /// Accessibilité — nettement plus intrusif, et interdit en pratique dans le
    /// bac à sable de l'App Store. Donc les navigateurs ont leur propre
    /// catégorie et **on ne prétend rien de plus**.
    static func isBrowser(name: String, bundleID: String?) -> Bool {
        if let bundleID, browserBundleIDs.contains(bundleID) { return true }
        return browserNames.contains { name.localizedCaseInsensitiveContains($0) }
    }

    /// Reconnaître par l'identifiant de bundle est le chemin fiable ; le nom est
    /// le repli, parce que la base actuelle ne stocke que le nom affiché.
    static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",  // Arc
        "com.operasoftware.Opera",
        "org.chromium.Chromium",
        "com.vivaldi.Vivaldi",
        "app.zen-browser.zen",
    ]

    static let browserNames: [String] = [
        "Safari", "Chrome", "Firefox", "Brave", "Edge", "Arc",
        "Opera", "Chromium", "Vivaldi", "Zen Browser", "Tor Browser",
    ]

    /// Les catégories App Store d'Apple, ramenées à nos quelques cases.
    ///
    /// Deux choix discutables, assumés et signalés :
    ///
    /// - `entertainment` tombe dans `media`, parce que c'est ce que déclarent
    ///   Netflix et la plupart des lecteurs. Mais un lanceur de jeux peut le
    ///   déclarer aussi (l'Ankama Launcher le fait sur le Mac d'Arthur), et il
    ///   se retrouve alors en « Vidéo » — c'est exactement le cas que la
    ///   correction manuelle est là pour rattraper.
    /// - `utilities` tombe dans `other` et non `productivity` : c'est le
    ///   fourre-tout d'Apple, et le remonter en productivité gonflerait un
    ///   chiffre auquel on ne peut pas se fier.
    static let mapping: [String: AppCategory] = [
        "public.app-category.developer-tools": .development,

        "public.app-category.social-networking": .communication,

        "public.app-category.entertainment": .media,
        "public.app-category.video": .media,
        "public.app-category.music": .media,
        "public.app-category.news": .media,
        "public.app-category.photography": .creation,
        "public.app-category.graphics-design": .creation,

        "public.app-category.productivity": .productivity,
        "public.app-category.business": .productivity,
        "public.app-category.finance": .productivity,
        "public.app-category.education": .productivity,
        "public.app-category.reference": .productivity,
        "public.app-category.medical": .productivity,
        "public.app-category.travel": .productivity,
        "public.app-category.lifestyle": .productivity,
        "public.app-category.healthcare-fitness": .productivity,
        "public.app-category.weather": .productivity,
        "public.app-category.sports": .productivity,

        "public.app-category.utilities": .other,

        "public.app-category.games": .game,
        "public.app-category.action-games": .game,
        "public.app-category.adventure-games": .game,
        "public.app-category.arcade-games": .game,
        "public.app-category.board-games": .game,
        "public.app-category.card-games": .game,
        "public.app-category.casino-games": .game,
        "public.app-category.dice-games": .game,
        "public.app-category.educational-games": .game,
        "public.app-category.family-games": .game,
        "public.app-category.kids-games": .game,
        "public.app-category.music-games": .game,
        "public.app-category.puzzle-games": .game,
        "public.app-category.racing-games": .game,
        "public.app-category.role-playing-games": .game,
        "public.app-category.simulation-games": .game,
        "public.app-category.sports-games": .game,
        "public.app-category.strategy-games": .game,
        "public.app-category.trivia-games": .game,
        "public.app-category.word-games": .game,
    ]
}
