import Foundation
import Testing

@testable import PulseonCore

/// Le classement d'une journée par catégorie.
///
/// Tout est piloté par une fonction de classement injectée : ces tests ne savent
/// pas ce qu'est un navigateur, et c'est voulu — c'est `AppCategoryRules` qui le
/// sait, et il a ses propres tests.
///
/// **Piège rencontré en écrivant ces tests** : dans `#expect`, un optionnel
/// comparé à une *expression arithmétique* échoue alors que la comparaison est
/// vraie — `#expect(totals.first?.total == 2 * 3600)` rapporte
/// « 7200.0 == 7200 » comme un échec. Un littéral seul (`== 1800`) passe, et la
/// même expression sans optionnel passe aussi. D'où `try #require` partout où il
/// faut lire une valeur : c'est la forme idiomatique, et elle contourne le piège.
@Suite struct CategoryDigestTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    private func day(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 16, hour: hour, minute: minute))!
    }

    private func digest(
        sessions: [ActivitySession],
        now: Date? = nil
    ) -> DayDigest {
        DayDigestBuilder(calendar: calendar).build(
            day: day(12),
            sessions: sessions,
            now: now ?? day(23, 59)
        )
    }

    private func build(
        _ digest: DayDigest,
        classify: @escaping CategoryDigestBuilder.Classifier
    ) -> [CategoryTotal] {
        CategoryDigestBuilder(classify: classify).build(from: digest)
    }

    private func fixed(_ map: [String: AppCategory]) -> CategoryDigestBuilder.Classifier {
        { device, entity in
            guard let entity, let known = map[entity] else { return device.defaultCategory }
            return known
        }
    }

    @Test("Deux apps de la même catégorie sont additionnées")
    func sameCategoryAccumulates() throws {
        let digest = digest(sessions: [
            ActivitySession(device: .mac, entity: "Xcode", start: day(9), end: day(11)),
            ActivitySession(device: .mac, entity: "Ghostty", start: day(11), end: day(12)),
        ])
        let totals = build(digest, classify: fixed(["Xcode": .development, "Ghostty": .development]))

        #expect(totals.count == 1)
        let development = try #require(totals.first)
        #expect(development.category == .development)
        #expect(development.total == 3 * 3600)
    }

    /// Le point délicat : deux apps de la même catégorie qui se chevauchent ne
    /// doivent pas compter deux fois. C'est la raison pour laquelle la fusion
    /// d'intervalles est partagée avec `DayDigest` au lieu d'être recopiée.
    @Test("Deux apps de la même catégorie qui se chevauchent ne comptent qu'une fois")
    func overlapWithinCategoryIsMergedOnce() throws {
        let digest = digest(sessions: [
            ActivitySession(device: .mac, entity: "Xcode", start: day(9), end: day(11)),
            // Impossible sur le Mac, mais le sera avec plusieurs appareils : on
            // teste la règle, pas le collecteur actuel.
            ActivitySession(device: .mac, entity: "Ghostty", start: day(10), end: day(12)),
        ])
        let totals = build(digest, classify: fixed(["Xcode": .development, "Ghostty": .development]))

        #expect(try #require(totals.first).total == 3 * 3600)
    }

    /// Et l'inverse, qui est assumé et documenté : coder en regardant un film
    /// donne du développement *et* de la vidéo. Attribuer arbitrairement
    /// l'instant partagé à l'un des deux serait une invention.
    @Test("Deux catégories simultanées comptent chacune leur temps")
    func overlapAcrossCategoriesCountsTwice() {
        let digest = digest(sessions: [
            ActivitySession(device: .mac, entity: "Xcode", start: day(20), end: day(22)),
            ActivitySession(device: .tv, entity: nil, start: day(20), end: day(22)),
        ])
        let totals = build(digest, classify: fixed(["Xcode": .development]))

        #expect(totals.count == 2)
        #expect(totals.allSatisfy { $0.total == 2 * 3600 })
    }

    /// Un appareil sans entité **ne se range pas dans un contenu**.
    ///
    /// Il valait `media` avant le 2026-08-19, et le raccourci a été payé à
    /// l'usage : 2 h 52 de télé s'affichaient « Vidéo et musique » un soir où
    /// l'app Musique avait tourné 6 secondes. Pulseon ne sait qu'une chose de
    /// la télé — l'écran était allumé — donc c'est la seule chose que la
    /// catégorie a le droit de dire.
    @Test("Un appareil muet est sa propre catégorie, pas un contenu supposé")
    func silentDeviceIsItsOwnCategory() throws {
        let digest = digest(sessions: [
            ActivitySession(device: .tv, entity: nil, start: day(21), end: day(23))
        ])
        let totals = build(digest, classify: fixed([:]))

        let tv = try #require(totals.first)
        #expect(tv.category == .tv)
        #expect(tv.total == 2 * 3600)
    }

    /// **Le cas qui a fait poser la question, le 2026-08-19.** Une soirée de
    /// télé et un film sur le Mac tombaient dans le même rond : « Vidéo et
    /// musique, 2 h 52 » un soir où l'app Musique avait tourné 6 secondes.
    ///
    /// Ce que le test verrouille, ce n'est pas le libellé mais la frontière :
    /// un contenu lu sur le Mac et un écran allumé ailleurs ne se cumulent
    /// jamais, même quand l'un des deux *pourrait* être du même genre.
    @Test("La télé ne se cumule pas avec les apps vidéo du Mac")
    func tvNeverMergesIntoMacMedia() throws {
        let digest = digest(sessions: [
            ActivitySession(device: .tv, entity: nil, start: day(19), end: day(22)),
            ActivitySession(device: .mac, entity: "IINA", start: day(21), end: day(23)),
        ])
        let totals = build(digest, classify: fixed(["IINA": .media]))

        #expect(totals.count == 2)
        let tv = try #require(totals.first { $0.category == .tv })
        let media = try #require(totals.first { $0.category == .media })
        #expect(tv.total == 3 * 3600)
        #expect(media.total == 2 * 3600)
        // La télé n'a pas d'entité : son rond ne peut donc pas emprunter le
        // logo d'une app, et c'est précisément ce qu'on veut.
        #expect(tv.entities.isEmpty)
        #expect(media.entities.map(\.entity) == ["IINA"])
    }

    @Test("Les catégories sortent de la plus longue à la plus courte")
    func sortedByTotal() {
        let digest = digest(sessions: [
            ActivitySession(device: .mac, entity: "Ghostty", start: day(9), end: day(10)),
            ActivitySession(device: .mac, entity: "Discord", start: day(10), end: day(13)),
        ])
        let totals = build(digest, classify: fixed(["Ghostty": .development, "Discord": .communication]))

        #expect(totals.map(\.category) == [.communication, .development])
    }

    @Test("Chaque catégorie retient ce qui l'a occupée, du plus long au plus court")
    func entitiesAreRankedInsideCategory() throws {
        let digest = digest(sessions: [
            ActivitySession(device: .mac, entity: "Ghostty", start: day(9), end: day(10)),
            ActivitySession(device: .mac, entity: "Xcode", start: day(10), end: day(13)),
        ])
        let totals = build(digest, classify: fixed(["Ghostty": .development, "Xcode": .development]))

        #expect(try #require(totals.first).entities.map(\.entity) == ["Xcode", "Ghostty"])
    }

    @Test("Une journée vide ne rend aucune catégorie")
    func emptyDayHasNoCategories() {
        #expect(build(digest(sessions: []), classify: fixed([:])).isEmpty)
    }

    /// Le classement figé traverse l'agrégation sans objet vivant.
    @Test("Le classement figé donne le même résultat")
    func assignmentBehavesLikeAClosure() {
        let assignment = CategoryAssignment(byEntity: ["Xcode": .development])
        #expect(assignment.category(for: .mac, entity: "Xcode") == .development)
        // Inconnue sur le Mac : aucune supposition, `other`.
        #expect(assignment.category(for: .mac, entity: "Inconnue") == .other)
        // Inconnue sur la télé : l'appareil lui-même est la réponse, et il ne
        // prétend pas connaître le contenu.
        #expect(assignment.category(for: .tv, entity: "Inconnue") == .tv)
        #expect(assignment.category(for: .tv, entity: nil) == .tv)
    }
}
