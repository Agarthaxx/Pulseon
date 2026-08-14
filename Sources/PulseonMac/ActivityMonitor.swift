import AppKit
import Foundation
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
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var isIdle = false

    public init(store: SessionStore) {
        self.store = store
    }

    public func start() {
        let workspace = NSWorkspace.shared
        let center = workspace.notificationCenter

        // Avant toute chose : réparer ce qu'un arrêt brutal a laissé ouvert.
        // Doit précéder la première activation, qui sinon fermerait la session
        // fantôme à l'instant présent.
        store.closeDanglingSessions()

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

    private func handleActivation(of app: NSRunningApplication?) {
        guard let name = app?.localizedName else { return }
        isIdle = false
        store.openSession(device: .mac, entity: name, at: Date())
    }

    private func checkIdle() {
        let idle = Self.systemIdleTime()

        if idle >= idleThreshold, !isIdle {
            isIdle = true
            // La session s'arrête au *début* de l'inactivité, pas maintenant :
            // sinon on compterait le temps passé loin du clavier.
            store.closeOpenSession(at: Date().addingTimeInterval(-idle))
        } else if idle < idleThreshold, isIdle {
            isIdle = false
            handleActivation(of: NSWorkspace.shared.frontmostApplication)
        } else if !isIdle {
            // Actif et déjà compté : on se contente de dater le dernier signe
            // de vie, pour borner la session si le processus meurt d'un coup.
            store.touchOpenSessions(at: Date())
        }
    }
}
