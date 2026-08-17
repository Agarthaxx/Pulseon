import Foundation

/// Ce qu'une journée vaut par rapport aux précédentes.
///
/// Sans ça, le chiffre du jour ne veut rien dire — c'est le manque que ressent
/// n'importe qui ouvrant l'app : « 9 h 39, c'est beaucoup ou c'est ma normale ? ».
///
/// **La comparaison ne juge pas.** Pulseon mesure l'usage d'un appareil, il ne
/// décide pas si c'est bien. Rien ici ne dit qu'un écart est bon ou mauvais, et
/// l'UI ne doit pas colorer un dépassement en rouge : ce serait transformer un
/// miroir en juge.
public struct DayComparison: Sendable, Equatable {
    /// Le total de la journée affichée.
    public let subject: TimeInterval
    /// La moyenne des journées de référence.
    public let average: TimeInterval
    /// Combien de journées ont servi à la calculer. Affiché, parce qu'une
    /// moyenne sur trois jours et une moyenne sur trente ne se valent pas.
    public let referenceDays: Int
    /// Vrai quand la comparaison s'arrête **à la même heure du jour** dans
    /// chaque journée de référence, la journée affichée étant encore en cours.
    public let isPartial: Bool

    public init(
        subject: TimeInterval,
        average: TimeInterval,
        referenceDays: Int,
        isPartial: Bool
    ) {
        self.subject = subject
        self.average = average
        self.referenceDays = referenceDays
        self.isPartial = isPartial
    }

    public var delta: TimeInterval { subject - average }

    /// En dessous de cet écart, annoncer une différence serait du bruit : cinq
    /// minutes sur une journée ne distinguent rien.
    public static let tolerance: TimeInterval = 5 * 60

    public var isTypical: Bool { abs(delta) <= Self.tolerance }
}

public enum DayComparisonBuilder {
    /// En dessous de trois journées mesurées, on ne dit rien.
    ///
    /// Une « moyenne » sur une seule journée n'est pas une moyenne, c'est cette
    /// journée-là présentée sous un nom trompeur. Se taire est plus honnête que
    /// d'annoncer une tendance qui n'existe pas.
    public static let minimumReferenceDays = 3

    /// - Parameters:
    ///   - references: les journées précédentes. Celles où **aucune source
    ///     n'a écrit** sont écartées : le collecteur était éteint, ce qui ne dit
    ///     rien de l'usage, et les compter tirerait la moyenne vers zéro pour une
    ///     raison qui n'a aucun rapport avec le temps d'écran. Une journée où une
    ///     source était branchée et n'a rien enregistré, elle, est un vrai zéro
    ///     et compte.
    ///   - isPartial: vrai si les totaux sont arrêtés à la même heure du jour.
    /// - Returns: nil quand il n'y a pas de quoi comparer honnêtement.
    public static func compare(
        subject: DayDigest,
        against references: [DayDigest],
        isPartial: Bool
    ) -> DayComparison? {
        let measured = references.filter(\.hasMeasuredSource)
        guard measured.count >= minimumReferenceDays else { return nil }

        let total = measured.reduce(0) { $0 + $1.coveredTotal }
        return DayComparison(
            subject: subject.coveredTotal,
            average: total / Double(measured.count),
            referenceDays: measured.count,
            isPartial: isPartial
        )
    }
}
