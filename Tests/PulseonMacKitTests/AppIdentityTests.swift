import Foundation
import PulseonCore
import SwiftData
import Testing

@testable import PulseonMacKit

/// L'identité des apps : retenue une fois, jamais réécrite pour rien.
@MainActor
@Suite struct AppIdentityTests {
    /// `ModelContext` ne retient pas son `ModelContainer` : si le conteneur est
    /// créé en local et libéré, tout accès ultérieur plante sur un signal, sans
    /// message. Il doit donc vivre aussi longtemps que le contexte — d'où cette
    /// classe, qu'il faut garder dans une variable (`let base = TestBase()`) et
    /// non déréférencer à la volée.
    @MainActor
    final class TestBase {
        let container: ModelContainer
        let store: SessionStore
        let registry: AppRegistry

        init(rules: AppCategoryRules = AppCategoryRules()) {
            container = try! ModelContainer(
                for: StoredSession.self, StoredCounterSample.self, StoredApp.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let context = ModelContext(container)
            store = SessionStore(context: context)
            registry = AppRegistry(context: context, rules: rules)
        }

        func storedApps() -> [StoredApp] {
            (try? container.mainContext.fetch(FetchDescriptor<StoredApp>())) ?? []
        }
    }

    @Test("Une app vue pour la première fois est retenue")
    func firstSightIsRecorded() {
        let base = TestBase()
        base.store.noteApp(
            name: "Ghostty",
            bundleID: "com.mitchellh.ghostty",
            declaredCategory: "public.app-category.developer-tools",
            at: Date()
        )
        let apps = base.storedApps()
        #expect(apps.count == 1)
        #expect(apps.first?.bundleID == "com.mitchellh.ghostty")
    }

    /// Le point qui compte : une app est activée des centaines de fois par jour.
    /// Réécrire son identité à chaque fois refait l'erreur du `lastSeen` en base
    /// — 78 Ko d'écriture pour une information qui n'a pas bougé.
    @Test("Revoir la même app n'écrit rien de plus")
    func identicalSightingIsNotRewritten() {
        let base = TestBase()
        for _ in 0..<50 {
            base.store.noteApp(
                name: "Xcode",
                bundleID: "com.apple.dt.Xcode",
                declaredCategory: "public.app-category.developer-tools",
                at: Date()
            )
        }
        #expect(base.storedApps().count == 1)
    }

    @Test("Une app mise à jour voit son identité corrigée")
    func changedIdentityIsUpdated() {
        let base = TestBase()
        base.store.noteApp(name: "Brave Browser", bundleID: nil, declaredCategory: nil, at: Date())
        base.store.noteApp(
            name: "Brave Browser",
            bundleID: "com.brave.Browser",
            declaredCategory: nil,
            at: Date()
        )
        let apps = base.storedApps()
        #expect(apps.count == 1)
        #expect(apps.first?.bundleID == "com.brave.Browser")
    }

    @Test("La catégorie se déduit de ce que l'app déclare")
    func categoryComesFromDeclaration() {
        let base = TestBase()
        base.store.noteApp(
            name: "Ghostty",
            bundleID: "com.mitchellh.ghostty",
            declaredCategory: "public.app-category.developer-tools",
            at: Date()
        )
        #expect(base.registry.category(ofApp: "Ghostty") == .development)
    }

    /// Le cas relevé sur la machine d'Arthur : Firefox se déclare
    /// « productivity », ce qui est faux. La liste des navigateurs passe avant.
    @Test("Un navigateur reste un navigateur, quoi qu'il déclare")
    func browserBeatsDeclaration() {
        let base = TestBase()
        base.store.noteApp(
            name: "Firefox Developer Edition",
            bundleID: "org.mozilla.firefoxdeveloperedition",
            declaredCategory: "public.app-category.productivity",
            at: Date()
        )
        #expect(base.registry.category(ofApp: "Firefox Developer Edition") == .web)
    }

    /// Brave ne déclare aucune catégorie. Sans la liste des navigateurs elle
    /// tomberait en « Autre » ; avec, elle est correctement classée.
    @Test("Une app sans catégorie déclarée n'invente rien")
    func undeclaredFallsBackHonestly() {
        let base = TestBase()
        base.store.noteApp(name: "Ankama Launcher", bundleID: nil, declaredCategory: nil, at: Date())
        #expect(base.registry.category(ofApp: "Ankama Launcher") == .other)
    }

    @Test("Une app jamais vue ne fait pas planter la lecture")
    func unknownAppIsOther() {
        let base = TestBase()
        #expect(base.registry.category(ofApp: "Jamais vue") == .other)
        #expect(base.registry.icon(ofApp: "Jamais vue") == nil)
    }

    /// La correction manuelle gagne sur tout : c'est ce qui fait que le
    /// classement est celui d'Arthur et pas celui d'Apple.
    @Test("La correction manuelle passe avant tout le reste")
    func overrideWins() {
        let base = TestBase(rules: AppCategoryRules(overrides: ["Safari": .development]))
        base.store.noteApp(
            name: "Safari",
            bundleID: "com.apple.Safari",
            declaredCategory: "public.app-category.productivity",
            at: Date()
        )
        #expect(base.registry.category(ofApp: "Safari") == .development)
    }
}
