import Foundation
import PulseonCore
import Testing

@testable import PulseonUI

/// Le découpage de la journée en segments d'un rail unique.
///
/// C'est la pièce qui règle le défaut de conception du multipiste : une piste par
/// appareil devient illisible dès le troisième écran. Ces tests vérifient la
/// règle, pas le dessin — le dessin se regarde en PNG.
@Suite struct RailLayoutTests {
    private func hour(_ value: Double) -> TimeInterval { value * 3600 }

    private func lane(
        _ device: Device,
        _ blocks: [(start: Double, hours: Double)]
    ) -> Lane {
        let traces = blocks.map {
            TraceBlock(entity: nil, startOffset: hour($0.start), duration: hour($0.hours))
        }
        return Lane(
            device: device,
            total: traces.reduce(0) { $0 + $1.duration },
            blocks: traces,
            topEntities: [],
            isConnected: true
        )
    }

    @Test("Un appareil seul occupe tout le rail")
    func singleDeviceFillsTheRail() throws {
        let segments = RailLayout.segments(from: [lane(.mac, [(9, 2)])])

        #expect(segments.count == 1)
        let segment = try #require(segments.first)
        #expect(segment.devices == [.mac])
        #expect(segment.startOffset == hour(9))
        #expect(segment.duration == hour(2))
    }

    /// Le cœur du sujet : deux appareils qui se chevauchent donnent trois
    /// segments — l'un seul, les deux ensemble, l'autre seul.
    @Test("Un chevauchement produit trois segments dont un partagé")
    func overlapSplitsIntoThree() {
        let segments = RailLayout.segments(from: [
            lane(.mac, [(9, 3)]),
            lane(.tv, [(11, 3)]),
        ])

        #expect(segments.map(\.devices) == [[.mac], [.mac, .tv], [.tv]])
        #expect(segments.map(\.startOffset) == [hour(9), hour(11), hour(12)])
        #expect(segments.map(\.duration) == [hour(2), hour(1), hour(2)])
    }

    @Test("Trois appareils simultanés tiennent dans le même segment")
    func threeDevicesShareOneSegment() throws {
        let segments = RailLayout.segments(from: [
            lane(.mac, [(20, 2)]),
            lane(.tv, [(20, 2)]),
            // Une source à compteur n'a jamais de bloc ; on prend donc la TV et
            // le Mac, plus un troisième appareil simulé par un second bloc TV
            // — ce qui teste aussi le comptage par appareil.
            lane(.tv, [(20, 2)]),
        ])

        let segment = try #require(segments.first)
        #expect(segments.count == 1)
        #expect(segment.devices == [.mac, .tv])
    }

    /// Sans fusion, une journée normale produirait des dizaines de segments
    /// collés que rien ne distingue, et chaque jointure dessinerait un liseré.
    @Test("Deux blocs contigus du même appareil ne font qu'un segment")
    func adjacentBlocksAreMerged() throws {
        let segments = RailLayout.segments(from: [lane(.mac, [(9, 1), (10, 1), (11, 1)])])

        #expect(segments.count == 1)
        #expect(try #require(segments.first).duration == hour(3))
    }

    @Test("Un trou entre deux blocs reste un trou")
    func gapsSurvive() {
        let segments = RailLayout.segments(from: [lane(.mac, [(9, 1), (14, 1)])])

        #expect(segments.count == 2)
        #expect(segments.map(\.startOffset) == [hour(9), hour(14)])
    }

    /// Deux blocs du même appareil qui se chevauchent ne doivent pas dédoubler la
    /// couche : c'est pourquoi le balayage compte les activations au lieu de
    /// tenir un simple ensemble.
    @Test("Deux blocs du même appareil qui se chevauchent ne le comptent qu'une fois")
    func selfOverlapCountsOnce() {
        let segments = RailLayout.segments(from: [lane(.mac, [(9, 3), (10, 3)])])

        #expect(segments.allSatisfy { $0.devices == [.mac] })
        #expect(segments.reduce(0) { $0 + $1.duration } == hour(4))
    }

    /// Règle non négociable : une source sans horaire n'a aucune place sur un axe
    /// de temps. La dessiner sur le rail serait inventer une heure.
    @Test("Une source à compteur n'apparaît pas sur le rail")
    func counterSourcesAreExcluded() {
        let playstation = Lane(
            device: .playstation,
            total: hour(2),
            blocks: [],
            topEntities: [EntityTotal(entity: "Elden Ring", total: hour(2))],
            isConnected: true
        )

        #expect(RailLayout.segments(from: [playstation]).isEmpty)
    }

    @Test("Une journée vide ne produit aucun segment")
    func emptyDayHasNoSegments() {
        #expect(RailLayout.segments(from: []).isEmpty)
        #expect(RailLayout.segments(from: [lane(.mac, [])]).isEmpty)
    }

    @Test("Un bloc de durée nulle est ignoré")
    func zeroLengthBlocksAreIgnored() {
        #expect(RailLayout.segments(from: [lane(.mac, [(9, 0)])]).isEmpty)
    }

    /// L'ordre des couches doit être le même d'un segment à l'autre, sinon un
    /// appareil sauterait de haut en bas au fil de la journée et la texture
    /// deviendrait illisible.
    @Test("L'ordre des couches est stable d'un segment à l'autre")
    func layerOrderIsStable() {
        let segments = RailLayout.segments(from: [
            lane(.tv, [(9, 2), (13, 2)]),
            lane(.mac, [(9, 2), (13, 2)]),
        ])

        #expect(segments.allSatisfy { $0.devices == [.mac, .tv] })
    }
}
