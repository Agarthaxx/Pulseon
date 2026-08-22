import Foundation
import PulseonCore
import SwiftData
import Testing

@testable import PulseonMacKit

/// Ce que la télé sait dire de l'app à l'écran, et ce qu'elle ne sait pas.
///
/// Les réponses simulées ici sont **copiées de la vraie télé** (Samsung
/// `TQ55S90CATXXC`, 2026-08-22, pendant qu'Arthur regardait YouTube) : c'est
/// d'elles que vient la seule chose qui compte, à savoir que `running` est vrai
/// pour trois apps à la fois et que seul `visible` désigne l'écran.
@Suite struct TVAppTests {
    private let now = Date(timeIntervalSince1970: 1_770_213_600)

    // MARK: La lecture de la réponse

    /// Réponse réelle de la télé pour YouTube, à l'écran.
    private static let youTube = Data(
        #"{"id":"111299001912","name":"YouTube","running":true,"version":"2.1.527","visible":true}"#
            .utf8
    )
    /// Réponse réelle pour Prime Video, **chargée mais pas affichée**.
    private static let primeVideo = Data(
        #"{"id":"3201910019365","name":"Prime Video","running":true,"version":"5.2.19","visible":false}"#
            .utf8
    )

    @Test("L'app à l'écran est lue avec le nom que la télé lui donne")
    func visibleAppIsRead() {
        #expect(
            SamsungTVAppProbe.state(from: Self.youTube)
                == .installed(name: "YouTube", visible: true)
        )
    }

    /// **Le piège que la mesure a évité.** Trois apps répondaient `running: true`
    /// pour un seul écran : compter `running` aurait attribué la même soirée à
    /// YouTube, Prime Video et Apple TV en même temps.
    @Test("Une app qui tourne sans être affichée n'est pas à l'écran")
    func runningIsNotVisible() {
        #expect(
            SamsungTVAppProbe.state(from: Self.primeVideo)
                == .installed(name: "Prime Video", visible: false)
        )
    }

    /// Le nom vient de la télé, jamais d'un libellé écrit à la main : personne
    /// n'aurait deviné celui-là.
    @Test("Le nom localisé de la télé est repris tel quel")
    func localizedNameIsKept() {
        let body = Data(
            #"{"id":"3201606009684","name":"Spotify - Musique et podcasts","running":false,"visible":false}"#
                .utf8
        )
        #expect(
            SamsungTVAppProbe.state(from: body)
                == .installed(name: "Spotify - Musique et podcasts", visible: false)
        )
    }

    /// Un changement de firmware ne doit pas effacer le nom d'une app en cours.
    @Test("Une réponse incompréhensible ne vaut pas « pas à l'écran »")
    func malformedIsUnreachable() {
        #expect(SamsungTVAppProbe.state(from: Data("pas du json".utf8)) == .unreachable)
        #expect(SamsungTVAppProbe.state(from: Data()) == .unreachable)
    }

    // MARK: Le catalogue

    @Test("Une app hors catalogue ne reçoit aucune catégorie")
    func unknownAppIsNotClassified() {
        #expect(TVAppCatalog.declaredCategory(for: "0000000000") == nil)
    }

    /// La catégorie est rangée **brute**, au format d'Apple, exactement comme
    /// celle d'une app du Mac : si la table de correspondance change d'avis,
    /// tout l'historique se reclasse sans avoir rien perdu.
    @Test("Les catégories du catalogue sont celles que sait lire AppCategoryRules")
    func catalogueSpeaksTheSameLanguage() {
        let rules = AppCategoryRules()
        for (id, declared) in TVAppCatalog.categories {
            #expect(
                rules.category(forApp: "peu importe", bundleID: nil, declared: declared) == .media,
                "l'identifiant \(id) déclare \(declared), que les règles ne savent pas lire"
            )
        }
    }

    // MARK: Ce qui finit vraiment en base

    @MainActor
    private final class TVBase {
        let container: ModelContainer
        let store: SessionStore
        let monitor: TVMonitor
        let registry: AppRegistry

        init() throws {
            container = try ModelContainer(
                for: StoredSession.self, StoredCounterSample.self, StoredApp.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            store = SessionStore(context: container.mainContext)
            monitor = TVMonitor(probe: SilentProbe(), store: store)
            registry = AppRegistry(context: container.mainContext)
        }

        func sessions(around date: Date) throws -> [ActivitySession] {
            try store.sessions(
                from: date.addingTimeInterval(-86_400), to: date.addingTimeInterval(86_400)
            )
            .filter { $0.device == .tv }
        }
    }

    private struct SilentProbe: TVProbe {
        func read() async -> TVReading { .unknown }
    }

    private static let youTubeApp = TVApp(id: "111299001912", name: "YouTube")
    private static let netflixApp = TVApp(id: "3201907018807", name: "Netflix")

    @Test("La session porte le nom de l'app que la télé a nommée")
    @MainActor
    func sessionCarriesTheAppName() throws {
        let base = try TVBase()
        base.monitor.apply(.on, app: .app(Self.youTubeApp), at: now)
        base.monitor.apply(.off, app: .unknown, at: now.addingTimeInterval(30))

        let session = try #require(try base.sessions(around: now).first)
        #expect(session.entity == "YouTube")
    }

    /// Le cas normal d'une entrée HDMI — la PS5 d'Arthur est branchée sur cette
    /// télé — et celui d'une app absente du catalogue. On sait que l'écran était
    /// allumé, rien de plus, et c'est exactement ce qu'on écrit.
    @Test("Aucune app reconnue laisse la session sans nom, et surtout pas un nom deviné")
    @MainActor
    func noVisibleAppLeavesTheSessionUnnamed() throws {
        let base = try TVBase()
        base.monitor.apply(.on, app: .noneVisible, at: now)
        base.monitor.apply(.off, app: .unknown, at: now.addingTimeInterval(30))

        let session = try #require(try base.sessions(around: now).first)
        #expect(session.entity == nil)
    }

    /// **Ne pas avoir pu demander n'est pas « plus aucune app ».** Sans cette
    /// distinction, une seule requête perdue ferait basculer une soirée de
    /// Netflix dans « Télé ».
    @Test("Une réponse manquante garde le nom précédent")
    @MainActor
    func unknownKeepsTheName() throws {
        let base = try TVBase()
        base.monitor.apply(.on, app: .app(Self.netflixApp), at: now)
        base.monitor.apply(.on, app: .unknown, at: now.addingTimeInterval(60))
        base.monitor.apply(.off, app: .unknown, at: now.addingTimeInterval(90))

        let sessions = try base.sessions(around: now)
        #expect(sessions.count == 1)
        #expect(sessions.first?.entity == "Netflix")
    }

    /// Changer d'app coupe la session, comme une activation côté Mac. La coupure
    /// est datée de l'instant du relevé : l'écran a été observé allumé des deux
    /// côtés de la bascule, donc reculer la coupure creuserait un trou dans du
    /// temps mesuré.
    @Test("Changer d'app coupe la session sans trouer le temps mesuré")
    @MainActor
    func switchingAppSplitsTheSession() throws {
        let base = try TVBase()
        let switchAt = now.addingTimeInterval(60)
        base.monitor.apply(.on, app: .app(Self.netflixApp), at: now)
        base.monitor.apply(.on, app: .app(Self.youTubeApp), at: switchAt)
        base.monitor.apply(.off, app: .unknown, at: switchAt.addingTimeInterval(60))

        let sessions = try base.sessions(around: now).sorted { $0.start < $1.start }
        #expect(sessions.count == 2)
        #expect(sessions.first?.entity == "Netflix")
        #expect(sessions.first?.end == switchAt)
        #expect(sessions.last?.entity == "YouTube")
        #expect(sessions.last?.start == switchAt)
    }

    /// La même app à l'écran ne doit rien écrire de plus, sinon une soirée de
    /// film se fragmenterait en une session par minute.
    @Test("La même app à l'écran n'ouvre pas de nouvelle session")
    @MainActor
    func sameAppDoesNotFragment() throws {
        let base = try TVBase()
        for tick in 0..<10 {
            base.monitor.apply(
                .on, app: .app(Self.youTubeApp), at: now.addingTimeInterval(Double(tick) * 60)
            )
        }
        #expect(try base.sessions(around: now).count == 1)
    }

    // MARK: Le classement

    @Test("Le temps d'une app nommée par la télé rejoint une catégorie de contenu")
    @MainActor
    func namedTVAppIsClassifiedByItsContent() throws {
        let base = try TVBase()
        base.monitor.apply(.on, app: .app(Self.netflixApp), at: now)
        #expect(base.registry.category(ofApp: "Netflix", on: .tv) == .media)
    }

    /// La règle qui a coûté la PR #42 tient toujours : sans nom d'app, la télé
    /// reste un écran et non un contenu.
    @Test("Sans app nommée, la télé reste sa propre catégorie")
    @MainActor
    func unnamedTVTimeStaysTV() throws {
        let base = try TVBase()
        #expect(base.registry.category(ofApp: "Une app inconnue", on: .tv) == .tv)
    }

    /// **Le cas qui a motivé la colonne d'appareil.** « Apple TV » existe des
    /// deux côtés ; sans borne par appareil, les deux lignes n'en feraient
    /// qu'une et se réécriraient l'une l'autre à chaque relevé.
    @Test("Une app de même nom sur le Mac et sur la télé garde deux identités")
    @MainActor
    func sameNameOnTwoDevicesKeepsTwoIdentities() throws {
        let base = try TVBase()
        base.store.noteApp(
            name: "Apple TV",
            device: .mac,
            bundleID: "com.apple.TV",
            declaredCategory: "public.app-category.entertainment",
            at: now
        )
        base.store.noteApp(
            name: "Apple TV",
            device: .tv,
            bundleID: TVAppCatalog.bundleID(for: "3201807016597"),
            declaredCategory: "public.app-category.video",
            at: now
        )

        let apps = try base.container.mainContext.fetch(FetchDescriptor<StoredApp>())
        #expect(apps.count == 2)
        #expect(Set(apps.map(\.device)) == [.mac, .tv])
    }

    /// Les lignes écrites avant que la télé n'existe n'ont pas de colonne
    /// d'appareil. Elles sont toutes des apps du Mac, par construction — et
    /// elles doivent continuer de se retrouver.
    @Test("Une identité écrite avant la télé reste celle du Mac")
    @MainActor
    func legacyIdentityIsAMacApp() throws {
        let base = try TVBase()
        let legacy = StoredApp(
            appName: "Xcode",
            bundleID: "com.apple.dt.Xcode",
            declaredCategory: "public.app-category.developer-tools",
            firstSeen: now
        )
        legacy.deviceRaw = nil
        base.container.mainContext.insert(legacy)

        #expect(legacy.device == .mac)
        #expect(base.registry.category(ofApp: "Xcode", on: .mac) == .development)
    }
}
