import AppKit
import Foundation
import IOKit.pwr_mgt
import PulseonCore

/// Observe l'usage du Mac et le transforme en sessions.
///
/// Deux signaux se combinent : l'app au premier plan (`NSWorkspace`) et le
/// temps depuis la dernière interaction clavier/souris (`CGEventSource`).
/// Une session reste ouverte tant que la même app est active *et* que tu
/// interagis ; elle se ferme au changement d'app, à l'inactivité, à la mise
/// en veille ou à la fermeture de session.
///
/// Contrairement à la version précédente qui pollait via launchd, on écoute
/// les notifications système : le changement d'app est capté à la seconde
/// près au lieu d'être arrondi à l'intervalle de poll.
@MainActor
public final class ActivityMonitor {
    /// Au-delà, on considère que tu n'es plus devant. Volontairement généreux :
    /// lire un article sans toucher au clavier ne doit pas couper la session.
    public var idleThreshold: TimeInterval = 120

    /// Fréquence de vérification de l'inactivité. Ne conditionne pas la
    /// précision des changements d'app, qui arrivent par notification.
    private let idleCheckInterval: TimeInterval = 15

    private let store: SessionStore
    private let heartbeat: Heartbeat
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var isIdle = false
    /// Dernier tick où une vidéo tournait. Voir `endOfActivity`.
    private var lastWatchedAt: Date = .distantPast

    public init(store: SessionStore, heartbeat: Heartbeat? = nil) {
        self.store = store
        self.heartbeat = heartbeat ?? Heartbeat(url: StoreLocation.heartbeatURL)
    }

    public func start() {
        let workspace = NSWorkspace.shared
        let center = workspace.notificationCenter

        // Avant toute chose : réparer ce qu'un arrêt brutal a laissé ouvert.
        // Doit précéder la première activation, qui sinon fermerait la session
        // fantôme à l'instant présent.
        store.closeDanglingSessions(at: heartbeat.lastMark())
        heartbeat.mark(Date(), force: true)

        observers.append(
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil, queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
                MainActor.assumeIsolated { self?.handleActivation(of: app) }
            }
        )

        // Veille et déconnexion ferment la session : sans ça, une nuit de
        // sommeil compterait comme du temps d'écran.
        for name: NSNotification.Name in [
            NSWorkspace.willSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.store.closeOpenSession(at: Date()) }
                }
            )
        }

        for name: NSNotification.Name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.handleActivation(of: NSWorkspace.shared.frontmostApplication)
                    }
                }
            )
        }

        let timer = Timer.scheduledTimer(withTimeInterval: idleCheckInterval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.checkIdle() }
        }
        // Laisse macOS regrouper ce réveil avec ceux des autres processus au
        // lieu d'en provoquer un rien que pour nous. Rien ici n'exige la
        // seconde près, et grouper les réveils est ce qui économise la
        // batterie.
        timer.tolerance = idleCheckInterval / 2
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)

        handleActivation(of: workspace.frontmostApplication)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
        store.closeOpenSession(at: Date())
    }

    /// Secondes depuis la dernière interaction clavier ou souris.
    static func systemIdleTime() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .hidSystemState, eventType: .init(rawValue: ~0)!
        )
    }

    /// Vrai quand quelque chose empêche l'écran de s'éteindre — typiquement un
    /// lecteur vidéo pendant la lecture.
    ///
    /// C'est le signal qui rattrape le cas du film : personne ne tape, mais
    /// quelqu'un regarde. Sans lui, deux heures de film comptaient pour zéro.
    ///
    /// On lit bien `PreventUserIdleDisplaySleep` et surtout pas son voisin
    /// `PreventUserIdleSystemSleep`, qui est levé par des tâches de fond
    /// (Handoff, sauvegardes, `caffeinate`) et compterait un téléchargement
    /// nocturne écran éteint comme du temps d'écran.
    static func isDisplayKeptAwake() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
            let levels = status?.takeRetainedValue() as? [String: Int]
        else { return false }
        // Constante déclarée via CFSTR côté C, donc absente en Swift : la
        // chaîne est celle qu'affiche `pmset -g assertions`.
        return (levels["PreventUserIdleDisplaySleep"] ?? 0) > 0
    }

    /// Jusqu'à quel instant l'activité est **observée**, à l'instant `now`.
    ///
    /// C'est l'horizon que l'affichage doit utiliser pour faire défiler le
    /// total du jour, et il répond à un problème précis : la session en cours
    /// reste ouverte pendant les `idleThreshold` secondes de tolérance, puis
    /// est fermée *rétroactivement* à ton dernier signe de vie. Un compteur qui
    /// avancerait jusqu'à `now` devrait donc reculer de deux minutes à chaque
    /// pause. Reculer est pire qu'attendre : on n'avance que sur du constaté.
    ///
    /// Conséquence assumée : lire un article sans toucher la souris fige
    /// l'affichage. Le temps est bien compté — il apparaît d'un bloc au premier
    /// mouvement.
    ///
    /// Effet de bord voulu : chaque appel rafraîchit `lastWatchedAt`, donc plus
    /// l'affichage interroge, plus la fin de session écrite en base est précise.
    public func observedActivityEnd(now: Date = Date()) -> Date {
        let idle = Self.systemIdleTime()
        if Self.isDisplayKeptAwake() { lastWatchedAt = now }
        return endOfActivity(now: now, idle: idle)
    }

    private func handleActivation(of app: NSRunningApplication?) {
        guard let name = app?.localizedName else { return }
        isIdle = false
        store.openSession(device: .mac, entity: name, at: Date())
    }

    private func checkIdle() {
        let now = Date()
        let idle = Self.systemIdleTime()
        let watching = Self.isDisplayKeptAwake()
        if watching { lastWatchedAt = now }

        // Deux façons d'être là : interagir, ou regarder.
        let isActive = idle < idleThreshold || watching

        if !isActive, !isIdle {
            isIdle = true
            store.closeOpenSession(at: endOfActivity(now: now, idle: idle))
        } else if isActive, isIdle {
            isIdle = false
            handleActivation(of: NSWorkspace.shared.frontmostApplication)
        } else if isActive {
            // Rien à écrire en base : l'activité n'a pas changé d'état. On se
            // contente de dater la trace de vie, hors base et à sa cadence.
            heartbeat.mark(now)
        }
    }

    /// Quand l'activité s'est réellement arrêtée.
    ///
    /// Le dernier événement clavier date de `now - idle`, mais une vidéo a pu
    /// tourner bien après : la fin est le plus tardif des deux signaux
    /// *observés*. Sans ce `max`, arrêter un film de deux heures fermait la
    /// session deux heures en arrière et effaçait le film qu'on venait tout
    /// juste de compter.
    private func endOfActivity(now: Date, idle: TimeInterval) -> Date {
        min(max(now.addingTimeInterval(-idle), lastWatchedAt), now)
    }
}
