import Foundation

/// Garantit qu'un seul Pulseon écrit dans la base.
///
/// ## Pourquoi ce fichier existe
///
/// Le 2026-08-18, deux Pulseon ont démarré à une seconde d'intervalle : l'un
/// par le `LaunchAgent`, l'autre par l'élément d'ouverture de Réglages Système,
/// ajouté à la main. Les deux ont ouvert **la même base** avec chacun leur
/// `ModelContainer`, et rien ne l'a signalé.
///
/// Le dégât n'est pas le doublement qu'on imagine. À chaque activation d'app,
/// les deux insèrent une session ; mais `openSession(for:)` ne rend que la plus
/// récemment ouverte, donc l'une des deux est fermée et l'autre reste ouverte
/// pour toujours. Vingt épaves en une matinée — et chaque retour d'inactivité
/// venait en fermer une à l'heure courante, attribuant à une app des heures de
/// machine éteinte. Résultat à l'écran : **51 h sur une journée de 2 h**.
///
/// ## Pourquoi un verrou de fichier et pas `NSRunningApplication`
///
/// Compter les instances par `NSRunningApplication.runningApplications(
/// withBundleIdentifier:)` est plus lisible, mais c'est une course : les deux
/// processus ci-dessus ont démarré à 300 ms d'écart, avant que le second soit
/// forcément visible du premier via LaunchServices. Ça suppose aussi un bundle
/// identifier, que l'exécutable SwiftPM n'a pas hors de son `.app`.
///
/// `flock` ne se trompe pas : l'exclusivité est tenue par le noyau, le verrou
/// est attaché à la description de fichier ouverte, et il tombe **tout seul**
/// quand le processus meurt — y compris sur un `kill -9`, où aucun code de
/// nettoyage ne tournerait. Même esprit que `Heartbeat`, où c'est une
/// métadonnée de fichier qui porte l'information plutôt qu'une écriture.
public final class InstanceLock {
    private let url: URL
    private var descriptor: Int32 = -1

    public init(url: URL = StoreLocation.instanceLockURL) {
        self.url = url
    }

    /// Prend le verrou, sans jamais attendre.
    ///
    /// - Returns: vrai si ce processus a l'exclusivité et peut collecter.
    ///   Faux uniquement quand **un autre processus vivant** le détient.
    ///
    /// Si le fichier lui-même ne peut pas être ouvert — disque plein, dossier
    /// en lecture seule — on répond vrai. Ne pas savoir verrouiller n'est pas
    /// une raison d'arrêter de mesurer : le collecteur doit tourner, et le pire
    /// qu'on risque alors est de retomber dans la situation d'avant, pas pire.
    @discardableResult
    public func acquire() -> Bool {
        if descriptor >= 0 { return true }

        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        let fd = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return true }

        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }
        descriptor = fd
        return true
    }

    /// Rend le verrou. Appelé par `deinit`, mais le noyau le ferait de toute
    /// façon à la mort du processus — c'est bien pour ça qu'on utilise `flock`.
    public func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit { release() }
}
