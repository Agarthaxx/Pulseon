import Testing

@testable import PulseonCore

/// La règle de classement, avec les cas relevés sur une vraie machine — pas des
/// exemples inventés. Chaque assertion ci-dessous correspond à une app installée
/// sur le Mac d'Arthur et à ce qu'elle déclare réellement.
@Suite struct AppCategoryTests {
    private let rules = AppCategoryRules()

    @Test("Un outil de développement est reconnu comme tel")
    func developerToolsAreDevelopment() {
        #expect(
            rules.category(
                forApp: "Ghostty",
                bundleID: "com.mitchellh.ghostty",
                declared: "public.app-category.developer-tools"
            ) == .development
        )
    }

    /// Firefox se déclare « productivity » sur la machine d'Arthur. C'est faux :
    /// ce qu'on fait dans un navigateur n'a rien à voir avec un outil de
    /// productivité, et la liste des navigateurs doit donc gagner.
    @Test("Un navigateur bat la catégorie qu'il déclare")
    func browserBeatsDeclaredCategory() {
        #expect(
            rules.category(
                forApp: "Firefox Developer Edition",
                bundleID: "org.mozilla.firefoxdeveloperedition",
                declared: "public.app-category.productivity"
            ) == .web
        )
        #expect(
            rules.category(
                forApp: "Safari",
                bundleID: "com.apple.Safari",
                declared: "public.app-category.productivity"
            ) == .web
        )
    }

    /// Brave ne déclare aucune catégorie. Reconnu par son identifiant de bundle.
    @Test("Un navigateur sans catégorie déclarée est reconnu quand même")
    func undeclaredBrowserIsStillWeb() {
        #expect(
            rules.category(forApp: "Brave Browser", bundleID: "com.brave.Browser", declared: nil) == .web
        )
    }

    /// Le repli par le nom existe parce que la base ne stocke le bundle que
    /// depuis peu : les sessions plus anciennes n'ont que le nom affiché.
    @Test("Un navigateur est reconnu par son nom si le bundle manque")
    func browserRecognisedByNameAlone() {
        #expect(rules.category(forApp: "Brave Browser", bundleID: nil, declared: nil) == .web)
    }

    @Test("Un réseau social devient de la communication")
    func socialNetworkingIsCommunication() {
        #expect(
            rules.category(
                forApp: "Discord",
                bundleID: "com.hnc.Discord",
                declared: "public.app-category.social-networking"
            ) == .communication
        )
    }

    /// Le cas gênant, assumé : l'Ankama Launcher se déclare « entertainment »,
    /// qui tombe dans « Vidéo et musique » parce que c'est ce que déclarent
    /// Netflix et les lecteurs vidéo. Un lanceur de jeux s'y retrouve à tort —
    /// c'est exactement le cas que la correction manuelle rattrape.
    @Test("Le divertissement tombe dans les médias, et la correction rattrape")
    func entertainmentFallsIntoMediaUnlessCorrected() {
        #expect(
            rules.category(forApp: "Ankama Launcher", declared: "public.app-category.entertainment")
                == .media
        )

        let corrected = AppCategoryRules(overrides: ["Ankama Launcher": .game])
        #expect(
            corrected.category(forApp: "Ankama Launcher", declared: "public.app-category.entertainment")
                == .game
        )
    }

    @Test("La correction manuelle gagne sur tout, navigateurs compris")
    func overrideBeatsEverything() {
        let rules = AppCategoryRules(overrides: ["Safari": .development])
        #expect(
            rules.category(
                forApp: "Safari",
                bundleID: "com.apple.Safari",
                declared: "public.app-category.productivity"
            ) == .development
        )
    }

    /// Le fourre-tout d'Apple ne doit pas gonfler la productivité.
    @Test("Les utilitaires restent en Autre")
    func utilitiesStayOther() {
        #expect(rules.category(forApp: "Rectangle", declared: "public.app-category.utilities") == .other)
    }

    @Test("Une app inconnue n'est jamais devinée")
    func unknownIsNeverGuessed() {
        #expect(rules.category(forApp: "Truc Bidule") == .other)
        // Surtout pas par ressemblance de nom : « Mail » n'est pas forcément un
        // client mail, et un faux rangement est pire qu'un « Autre » honnête.
        #expect(rules.category(forApp: "Mail Designer") == .other)
    }

    @Test("Un jeu, quelle que soit sa sous-catégorie, est un jeu")
    func everyGameSubcategoryIsGame() {
        for declared in [
            "public.app-category.games",
            "public.app-category.role-playing-games",
            "public.app-category.puzzle-games",
        ] {
            #expect(rules.category(forApp: "Un jeu", declared: declared) == .game)
        }
    }

    @Test("Chaque catégorie porte un libellé lisible")
    func everyCategoryHasALabel() {
        for category in AppCategory.allCases {
            #expect(!category.label.isEmpty)
        }
    }
}


// MARK: Un titre PlayStation, classé par ce que Sony en déclare

/// La bascule du 2026-08-30 : la console nomme, donc son temps peut enfin
/// rejoindre une vraie catégorie de contenu. 162 h de YouTube sur PS5 ne sont
/// pas du jeu.
@Test("Une app média de la PS5 rejoint la vidéo, pas la console")
func playstationMediaAppIsContent() {
    let rules = AppCategoryRules()
    #expect(
        rules.category(forPlayStationTitle: "YouTube", declared: "ps5_native_media_app")
            == .media
    )
    #expect(
        rules.category(forPlayStationTitle: "Spotify", declared: "ps5_web_based_media_app")
            == .media
    )
}

/// « Jeu » reste le classement d'un jeu **sur le Mac** : la console garde sa
/// propre catégorie, c'est ce qui distingue les deux écrans.
@Test("Un jeu PS5 reste rangé sous la console")
func playstationGameStaysOnTheConsole() {
    let rules = AppCategoryRules()
    #expect(
        rules.category(forPlayStationTitle: "ELDEN RING", declared: "ps5_native_game")
            == .playstation
    )
    #expect(rules.category(forPlayStationTitle: "ELDEN RING", declared: "ps4_game") == .playstation)
}

/// Sans déclaration — un titre relevé avant que les identités ne soient notées,
/// ou une valeur que Sony n'a jamais produite — on ne devine pas.
@Test("Un titre sans catégorie déclarée retombe sur la console")
func undeclaredTitleFallsBackToTheConsole() {
    let rules = AppCategoryRules()
    #expect(rules.category(forPlayStationTitle: "Un jeu inconnu") == .playstation)
    #expect(
        rules.category(forPlayStationTitle: "Un jeu inconnu", declared: "ps9_something")
            == .playstation
    )
}

/// **Le piège que la séparation des règles évite.** Côté Mac, un navigateur se
/// reconnaît au nom : « Arc », « Edge », « Opera ». Un titre PlayStation qui
/// contient un de ces mots n'est pas un navigateur, et le faire passer par les
/// règles du Mac le rangerait en Web. Même précaution que pour la télé.
@Test("Un jeu dont le nom contient celui d'un navigateur n'est pas du Web")
func playstationTitleIsNeverMistakenForABrowser() {
    let rules = AppCategoryRules()
    #expect(
        rules.category(forPlayStationTitle: "ARC Raiders", declared: "ps5_native_game")
            == .playstation
    )
    // Et le Mac, lui, continue de le faire — c'est bien deux règles distinctes.
    #expect(rules.category(forApp: "Arc", bundleID: "company.thebrowser.Browser") == .web)
}

/// La correction manuelle gagne sur Sony comme elle gagne sur Apple : c'est ce
/// qui fait que l'app est celle d'Arthur.
@Test("Une correction manuelle gagne sur la déclaration de Sony")
func overrideBeatsSony() {
    let rules = AppCategoryRules(overrides: ["Twitch": .communication])
    #expect(
        rules.category(forPlayStationTitle: "Twitch", declared: "ps5_web_based_media_app")
            == .communication
    )
}
