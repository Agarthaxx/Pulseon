import Foundation
import Testing

@testable import PulseonMacKit

/// Jusqu'où compter, quand plus rien ne bouge.
///
/// Cette règle sert deux fois : pour fermer une session en base, et pour faire
/// défiler le compteur de la barre de menu. Les tests ci-dessous valent donc
/// pour les deux — c'est tout l'intérêt de n'avoir qu'un seul calcul.
private let grace: TimeInterval = 60
private let now = Date(timeIntervalSince1970: 1_000_000)
private let jamais = Date.distantPast

private func end(idle: TimeInterval, lastWatched: Date = jamais) -> Date {
    ActivityMonitor.activityEnd(
        now: now, idle: idle, lastWatched: lastWatched, grace: grace
    )
}

@Test("Une pause courte continue de compter")
func shortPauseStillCounts() {
    // Trente secondes sans rien toucher, c'est du temps devant l'écran : on
    // lit, on réfléchit. Le compteur doit continuer d'avancer.
    #expect(end(idle: 0) == now)
    #expect(end(idle: 2) == now)
    #expect(end(idle: 30) == now)
    #expect(end(idle: 59) == now)
}

@Test("Au-delà de la grâce, le temps s'arrête au dernier geste plus la grâce")
func longPauseStopsAtGrace() {
    // À 61 s d'inactivité, on ne compte plus que jusqu'à la 60ᵉ.
    #expect(end(idle: 61) == now.addingTimeInterval(-1))
    #expect(end(idle: 120) == now.addingTimeInterval(-60))
    // Trois heures d'absence ne comptent pas trois heures : la valeur reste
    // accrochée au dernier geste, plus la minute de grâce.
    #expect(end(idle: 3 * 3600) == now.addingTimeInterval(grace - 3 * 3600))
}

@Test("La valeur est déjà figée quand la session se ferme")
func displayIsFrozenBeforeTheSessionCloses() {
    // C'est ce qui interdit au compteur de reculer : entre la fin de la grâce
    // (60 s) et la fermeture par le moniteur (idleThreshold, 120 s), la valeur
    // ne bouge plus d'un pouce — celle affichée est déjà la définitive.
    let atGrace = end(idle: grace)
    let atThreshold = ActivityMonitor.activityEnd(
        now: now.addingTimeInterval(60), idle: 120, lastWatched: jamais, grace: grace
    )
    #expect(atGrace == atThreshold)
}

@Test("Une vidéo en cours l'emporte sur l'inactivité du clavier")
func watchingBeatsIdleKeyboard() {
    // Deux heures de film sans toucher au clavier : la fin est l'instant vidéo
    // observé, pas le dernier geste. Sans ça, arrêter le film effacerait le
    // film qu'on venait de compter.
    #expect(end(idle: 7200, lastWatched: now) == now)
    let stoppedAt = now.addingTimeInterval(-10)
    #expect(end(idle: 7200, lastWatched: stoppedAt) == stoppedAt)
}

@Test("La grâce ne s'ajoute pas à la vidéo")
func graceAppliesToGesturesOnly() {
    // Une lecture qui s'arrête est un signal net : rien à couvrir. La grâce
    // existe pour l'ambiguïté d'un clavier silencieux, pas ici.
    let stoppedAt = now.addingTimeInterval(-30)
    #expect(end(idle: 7200, lastWatched: stoppedAt) == stoppedAt)
}

@Test("On ne compte jamais du temps pas encore écoulé")
func neverCountsBeyondNow() {
    // La grâce ne doit pas projeter la fin dans le futur, et une vidéo datée
    // en avance — horloge remise à l'heure — ne doit pas non plus.
    #expect(end(idle: 0) == now)
    #expect(end(idle: 0, lastWatched: now.addingTimeInterval(3600)) == now)
}
