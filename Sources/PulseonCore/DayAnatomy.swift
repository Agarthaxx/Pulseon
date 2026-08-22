import Foundation

/// La forme d'une journée, et non sa quantité.
///
/// C'est le parti pris du projet poussé d'un cran : l'app native « Temps
/// d'écran » dit *combien*, l'anneau dit *de quoi c'est fait*, et ceci dit
/// **comment la journée s'est déroulée** — à quelle heure elle a commencé,
/// quand elle s'est arrêtée, si elle a tenu d'une traite ou en confettis. Deux
/// journées de 6 h peuvent n'avoir rien à voir : six heures d'affilée le matin,
/// ou vingt reprises étalées jusqu'à minuit.
///
/// **Les traites fusionnent tous les appareils.** Passer du Mac à la télé n'est
/// pas une coupure : l'écran n'a pas cessé, seul l'écran a changé. C'est la même
/// raison qui fait exister `coveredTotal` à côté de `summedTotal`.
public struct DayAnatomy: Sendable, Equatable {
    /// Une traite : du temps d'écran sans coupure notable.
    public struct Stretch: Sendable, Equatable {
        /// Secondes écoulées depuis minuit local.
        public let start: TimeInterval
        public let duration: TimeInterval

        public init(start: TimeInterval, duration: TimeInterval) {
            self.start = start
            self.duration = duration
        }

        public var end: TimeInterval { start + duration }
    }

    /// Le premier instant d'écran de la journée, en secondes depuis minuit.
    public let firstScreen: TimeInterval
    /// Le dernier instant d'écran **observé**. Sur une journée en cours, c'est
    /// « jusqu'ici » et non « fin de journée » : à l'appelant de le dire.
    public let lastScreen: TimeInterval
    /// La plus longue traite sans coupure.
    public let longestStretch: Stretch
    /// Les coupures retenues, dans l'ordre. Une coupure est un trou **entre
    /// deux traites**, donc jamais avant le premier écran ni après le dernier :
    /// une nuit de sommeil n'est pas une pause dans la journée.
    public let breaks: [Stretch]

    public init(
        firstScreen: TimeInterval,
        lastScreen: TimeInterval,
        longestStretch: Stretch,
        breaks: [Stretch]
    ) {
        self.firstScreen = firstScreen
        self.lastScreen = lastScreen
        self.longestStretch = longestStretch
        self.breaks = breaks
    }

    /// De la première à la dernière minute d'écran.
    ///
    /// **Ce n'est pas du temps d'écran**, et il ne faut jamais l'afficher comme
    /// tel : c'est l'étalement, coupures comprises. Une journée de 2 h d'écran
    /// peut avoir 14 h d'amplitude.
    public var span: TimeInterval { lastScreen - firstScreen }

    /// La plus longue coupure, s'il y en a une.
    public var longestBreak: Stretch? {
        breaks.max { $0.duration < $1.duration }
    }
}

/// Reconstitue l'anatomie d'une journée à partir de son agrégat.
public struct DayAnatomyBuilder: Sendable {
    /// En dessous de quoi un trou n'est pas une coupure.
    ///
    /// Sans seuil, la moindre respiration entre deux blocs compterait : le
    /// collecteur Mac tolère déjà deux minutes d'inactivité avant de fragmenter
    /// une session, donc annoncer « 47 coupures » sur une matinée de travail
    /// dirait quelque chose sur le pas d'échantillonnage, pas sur la journée.
    /// Cinq minutes est le premier seuil où un trou correspond à quelque chose
    /// qu'on a vraiment fait — se lever, changer de pièce.
    ///
    /// **Le seuil ne change rien aux totaux**, qui sont calculés ailleurs : il
    /// ne décide que de ce qui mérite d'être *appelé* une coupure.
    public static let minimumBreak: TimeInterval = 5 * 60

    private let minimumBreak: TimeInterval

    public init(minimumBreak: TimeInterval = DayAnatomyBuilder.minimumBreak) {
        self.minimumBreak = minimumBreak
    }

    /// - Returns: nil quand aucune source à intervalles n'a le moindre bloc.
    ///   **Nil et non une anatomie à zéro** : une journée sans horaire connu n'a
    ///   pas commencé à minuit, elle n'a pas d'anatomie du tout. C'est la même
    ///   règle que « pas encore branchée ≠ journée à zéro ».
    public func build(from digest: DayDigest) -> DayAnatomy? {
        // **Les sources à compteur sont écartées, et c'est la règle 1.** La
        // PlayStation ne donne qu'un total : la faire entrer ici lui inventerait
        // une heure de début. Conséquence assumée et à dire à l'écran quand elle
        // a du temps ce jour-là — l'anatomie ne parle alors que des autres
        // écrans.
        let blocks = digest.lanes
            .filter { $0.kind == .interval }
            .flatMap(\.blocks)
            // Un bloc de durée nulle n'est pas un instant d'écran : il vient
            // d'une session réparée (voir `clampedBlocks`), et le compter
            // avancerait le premier écran de la journée sur du vide.
            .filter { $0.duration > 0 }

        let runs = IntervalMath.mergedRuns(of: blocks)
        guard let first = runs.first, let last = runs.last else { return nil }

        var breaks: [DayAnatomy.Stretch] = []
        for (previous, next) in zip(runs, runs.dropFirst()) {
            let gap = next.start - previous.end
            guard gap >= minimumBreak else { continue }
            breaks.append(DayAnatomy.Stretch(start: previous.end, duration: gap))
        }

        // Les traites retenues pour « la plus longue » sont celles que séparent
        // de vraies coupures : deux blocs séparés d'une minute forment une seule
        // traite à l'écran, et en compter deux contredirait le nombre de
        // coupures affiché juste à côté.
        let stretches = Self.stretches(from: runs, minimumBreak: minimumBreak)
        guard let longest = stretches.max(by: { $0.duration < $1.duration }) else { return nil }

        return DayAnatomy(
            firstScreen: first.start,
            lastScreen: last.end,
            longestStretch: longest,
            breaks: breaks
        )
    }

    /// Refond les traites en ne coupant que sur les vraies coupures.
    private static func stretches(
        from runs: [IntervalMath.Run], minimumBreak: TimeInterval
    ) -> [DayAnatomy.Stretch] {
        var stretches: [DayAnatomy.Stretch] = []
        var open: IntervalMath.Run?

        for run in runs {
            guard var current = open else {
                open = run
                continue
            }
            if run.start - current.end < minimumBreak {
                current.end = max(current.end, run.end)
                open = current
            } else {
                stretches.append(
                    DayAnatomy.Stretch(start: current.start, duration: current.duration)
                )
                open = run
            }
        }
        if let current = open {
            stretches.append(
                DayAnatomy.Stretch(start: current.start, duration: current.duration)
            )
        }
        return stretches
    }
}
