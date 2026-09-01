import Foundation
import Testing

@testable import PulseonMacKit

/// De quand date le binaire qui tourne.
///
/// Née d'un défaut qui s'est produit **deux fois** : une app périmée dans
/// `/Applications` faisant passer du travail réel pour des bugs. Ce qui se teste
/// ici est la seule partie pure — lire le vrai bundle demanderait d'en avoir un.
@Suite("L'estampille de compilation")
struct BuildStampTests {
    private let paris = TimeZone(identifier: "Europe/Paris")!
    private let french = Locale(identifier: "fr_FR")

    @Test("La date de compilation se lit dans le fuseau local")
    func stampIsShownInLocalTime() {
        // 17:25 UTC, soit 19:25 à Paris en heure d'été : c'est l'heure locale
        // qu'Arthur reconnaîtra, pas UTC.
        let label = BuildStamp.label(
            rawDate: "2026-09-01T17:25:00Z", commit: "ab26751",
            locale: french, timeZone: paris
        )

        #expect(label.contains("19:25"))
        #expect(label.contains("2026"))
        #expect(label.contains("ab26751"))
    }

    /// **Le cas qui justifie la fonction.** Lancée par `swift run`, l'app n'a pas
    /// de bundle, donc pas d'estampille. Afficher la date du lancement ou celle
    /// du fichier ferait exactement ce que cette ligne existe pour empêcher :
    /// laisser croire qu'on sait de quand date le code.
    @Test("Sans estampille, on le dit au lieu d'inventer une date")
    func missingStampSaysSo() {
        let label = BuildStamp.label(rawDate: nil, commit: nil)

        #expect(label.contains("inconnue"))
        // Surtout pas l'année en cours, qui se lirait comme une vraie date.
        #expect(!label.contains("Compilée"))
    }

    /// Une estampille illisible n'est pas une estampille : un `Info.plist`
    /// bricolé à la main ne doit pas produire une date de repli silencieuse.
    @Test("Une date incompréhensible vaut une absence de date")
    func unparsableDateIsTreatedAsMissing() {
        #expect(
            BuildStamp.label(rawDate: "hier après-midi", commit: "ab26751")
                .contains("inconnue")
        )
    }

    /// Le SHA répond à « laquelle ? », la date à « est-ce à jour ? ». Perdre le
    /// premier ne doit pas coûter la seconde.
    @Test("Sans SHA, la date reste affichée")
    func dateSurvivesAMissingCommit() {
        let label = BuildStamp.label(
            rawDate: "2026-09-01T17:25:00Z", commit: "",
            locale: french, timeZone: paris
        )

        #expect(label.contains("19:25"))
        #expect(!label.contains("·"))
    }

    /// **Un SHA seul mentirait** quand l'arbre est modifié : il désignerait du
    /// code qui n'est pas celui qu'on a compilé. Le `+` posé par `build-app.sh`
    /// traverse jusqu'à l'écran.
    @Test("Un arbre modifié se voit jusque dans le menu")
    func dirtyTreeIsVisible() {
        #expect(
            BuildStamp.label(
                rawDate: "2026-09-01T17:25:00Z", commit: "ab26751+",
                locale: french, timeZone: paris
            ).contains("ab26751+")
        )
    }
}
