import Foundation
import Testing

@testable import PulseonMacKit

/// `flock` est attaché à la description de fichier ouverte, pas au processus :
/// deux `InstanceLock` sur le même chemin entrent donc en conflit **même dans
/// un seul processus**. C'est ce qui rend le garde-fou testable sans avoir à
/// lancer deux Pulseon.
private func scratchURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("pulseon-lock-\(UUID().uuidString)")
}

@Test("Le second collecteur n'obtient pas le verrou")
func secondCollectorIsRefused() {
    let url = scratchURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let first = InstanceLock(url: url)
    let second = InstanceLock(url: url)

    #expect(first.acquire())
    #expect(second.acquire() == false)
}

@Test("Le verrou rendu laisse la place au suivant")
func releasingHandsOver() {
    let url = scratchURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let first = InstanceLock(url: url)
    #expect(first.acquire())
    first.release()

    // C'est ce qui se passe quand le collecteur en place quitte : le suivant
    // doit pouvoir prendre le relais tout de suite, sans redémarrage.
    let second = InstanceLock(url: url)
    #expect(second.acquire())
}

@Test("Reprendre son propre verrou ne le perd pas")
func acquiringTwiceIsIdempotent() {
    let url = scratchURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let lock = InstanceLock(url: url)
    #expect(lock.acquire())
    #expect(lock.acquire())

    // Le deuxième appel ne doit pas avoir ouvert un second descripteur, sinon
    // `release` en laisserait un ouvert et le verrou survivrait à sa propre
    // libération.
    lock.release()
    #expect(InstanceLock(url: url).acquire())
}
