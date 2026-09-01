import Foundation

public struct CategoryTotal: Sendable, Equatable, Identifiable {
    public let category: AppCategory
    public let total: TimeInterval
    /// Ce qui a occupé cette catégorie, du plus long au plus court. Sert à
    /// afficher les icônes derrière un libellé — « Développement · Xcode,
    /// Ghostty » se lit mieux que « Développement » tout seul.
    public let entities: [EntityTotal]

    public var id: AppCategory { category }

    public init(category: AppCategory, total: TimeInterval, entities: [EntityTotal]) {
        self.category = category
        self.total = total
        self.entities = entities
    }
}

/// À quoi la journée a servi, plutôt que par quelle app elle est passée.
///
/// **Le classement n'est pas décidé ici.** Le cœur ne sait pas ce qu'est un
/// navigateur, et n'a pas à le savoir : il reçoit une fonction de classement et
/// s'en sert. C'est la même règle que pour la définition d'« actif », que chaque
/// collecteur décide pour son appareil — ici c'est le côté macOS qui sait lire
/// la catégorie déclarée d'une app, et lui seul.
///
/// **Ce que ces totaux veulent dire, exactement.** Chaque catégorie est fusionnée
/// sur elle-même : deux apps de développement ouvertes en même temps sur deux
/// écrans ne comptent qu'une fois. En revanche deux catégories simultanées
/// comptent chacune leur temps — coder en regardant un film donne du
/// développement *et* de la vidéo. La somme des catégories peut donc dépasser le
/// `coveredTotal` de la journée, exactement comme `summedTotal` le fait entre
/// appareils. C'est assumé : le seul autre choix serait d'attribuer arbitrairement
/// un instant partagé à l'une des deux, ce qui serait une invention.
public struct CategoryDigestBuilder: Sendable {
    /// Comment classer un bloc de temps.
    ///
    /// - Parameters:
    ///   - device: l'appareil, pour les sources qui n'ont pas d'entité — une TV
    ///     allumée ne dit pas ce qu'elle diffuse.
    ///   - entity: le nom de l'app ou du jeu, quand on l'a.
    public typealias Classifier = @Sendable (_ device: Device, _ entity: String?) -> AppCategory

    private let classify: Classifier

    public init(classify: @escaping Classifier) {
        self.classify = classify
    }

    public func build(from digest: DayDigest) -> [CategoryTotal] {
        var blocksByCategory: [AppCategory: [TraceBlock]] = [:]
        var entityTotals: [AppCategory: [String: TimeInterval]] = [:]

        for lane in digest.lanes {
            for block in lane.blocks {
                let category = classify(lane.device, block.entity)
                blocksByCategory[category, default: []].append(block)
                if let entity = block.entity {
                    entityTotals[category, default: [:]][entity, default: 0] += block.duration
                }
            }
        }

        return blocksByCategory.keys.map { category in
            CategoryTotal(
                category: category,
                // Fusionné et non additionné : deux apps de la même catégorie
                // ouvertes en parallèle ne comptent qu'une fois. Deux
                // *catégories* simultanées, elles, comptent chacune leur temps
                // — coder en regardant un film donne du développement et de la
                // vidéo, et l'instant partagé n'appartient à aucune des deux.
                total: IntervalMath.mergedDuration(of: blocksByCategory[category] ?? []),
                entities: rank(entityTotals[category] ?? [:])
            )
        }
        .filter { $0.total > 0 }
        .sorted { $0.total > $1.total }
    }

    private func rank(_ totals: [String: TimeInterval]) -> [EntityTotal] {
        totals
            .map { EntityTotal(entity: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }
}

extension CategoryTotal {
    /// Cumule les catégories de plusieurs journées en une seule liste.
    ///
    /// **Additionner est licite ici, et pour une raison précise** : deux
    /// journées ne se chevauchent jamais, là où deux appareils, eux, le
    /// peuvent. C'est le même argument qui autorise le `coveredTotal` d'une
    /// période à être la somme des totaux journaliers.
    ///
    /// Ce qui reste vrai en revanche, c'est que deux catégories simultanées
    /// comptent chacune leur temps : la somme des catégories d'une semaine peut
    /// dépasser le temps passé devant un écran, exactement comme au sein d'une
    /// journée.
    public static func merged(_ groups: [[CategoryTotal]]) -> [CategoryTotal] {
        var totals: [AppCategory: TimeInterval] = [:]
        var entities: [AppCategory: [String: TimeInterval]] = [:]

        for group in groups {
            for category in group {
                totals[category.category, default: 0] += category.total
                for entity in category.entities {
                    entities[category.category, default: [:]][entity.entity, default: 0] +=
                        entity.total
                }
            }
        }

        return totals
            .map { category, total in
                CategoryTotal(
                    category: category,
                    total: total,
                    entities: (entities[category] ?? [:])
                        .map { EntityTotal(entity: $0.key, total: $0.value) }
                        .sorted { $0.total > $1.total }
                )
            }
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
    }
}
