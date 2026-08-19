import Foundation
import Testing

@testable import PulseonCore

@Suite("Cumuler les catégories de plusieurs journées")
struct CategoryMergeTests {
    private func total(
        _ category: AppCategory, _ hours: Double, _ entities: [(String, Double)] = []
    ) -> CategoryTotal {
        CategoryTotal(
            category: category,
            total: hours * 3600,
            entities: entities.map { EntityTotal(entity: $0.0, total: $0.1 * 3600) }
        )
    }

    @Test("additionne une même catégorie d'un jour à l'autre")
    func sumsAcrossDays() throws {
        let merged = CategoryTotal.merged([
            [total(.development, 6)],
            [total(.development, 2)],
        ])

        #expect(merged.count == 1)
        let development = try #require(merged.first)
        #expect(development.total == 8 * 3600)
    }

    @Test("fusionne les apps et les classe par temps")
    func mergesEntities() throws {
        let merged = CategoryTotal.merged([
            [total(.development, 3, [("Xcode", 2), ("Ghostty", 1)])],
            [total(.development, 3, [("Ghostty", 3)])],
        ])

        let entities = try #require(merged.first).entities
        #expect(entities.map(\.entity) == ["Ghostty", "Xcode"])
        // Ghostty repasse devant Xcode sur la semaine, alors qu'il était
        // derrière le premier jour : c'est tout l'intérêt de cumuler.
        //
        // Déballé avant comparaison : un optionnel confronté à une expression
        // arithmétique fait échouer `#expect` alors que l'égalité est vraie
        // (« 14400.0 == 14400 » rapporté comme un échec). Piège connu du
        // projet, revu ici en direct.
        let longest = try #require(entities.first).total
        #expect(longest == 4 * 3600)
    }

    @Test("classe les catégories de la plus longue à la plus courte")
    func sortsByTotal() {
        let merged = CategoryTotal.merged([
            [total(.web, 1), total(.development, 2)],
            [total(.web, 5)],
        ])

        #expect(merged.map(\.category) == [.web, .development])
    }

    @Test("écarte une catégorie sans temps")
    func dropsEmpty() {
        let merged = CategoryTotal.merged([[total(.game, 0)], [total(.media, 1)]])

        #expect(merged.map(\.category) == [.media])
    }

    @Test("ne rend rien quand il n'y a rien à cumuler")
    func empty() {
        #expect(CategoryTotal.merged([]).isEmpty)
        #expect(CategoryTotal.merged([[], []]).isEmpty)
    }
}
