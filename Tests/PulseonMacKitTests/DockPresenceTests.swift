import AppKit
import Testing

@testable import PulseonMacKit

/// Ce qui compte comme « une fenêtre justifiant une icône Dock ».
///
/// Le test porte sur la fonction pure, jamais sur de vraies fenêtres : ouvrir
/// une `NSWindow` demanderait une session graphique, ce que la suite de tests
/// n'a pas.
@Suite struct DockPresenceTests {
    @Test("Une fenêtre à barre de titre visible compte")
    func titledVisibleWindowCounts() {
        #expect(DockPresence.counts(styleMask: [.titled, .closable, .resizable], isVisible: true))
    }

    @Test("Une fenêtre à barre de titre masquée ne compte pas")
    func hiddenWindowDoesNotCount() {
        #expect(!DockPresence.counts(styleMask: [.titled, .closable], isVisible: false))
    }

    /// Le cas qui motive le critère : l'élément de barre de menu porte une
    /// fenêtre sans barre de titre. La compter garderait l'icône Dock allumée en
    /// permanence, donc annulerait `LSUIElement`.
    @Test("La fenêtre de l'élément de barre de menu ne compte pas")
    func statusItemWindowDoesNotCount() {
        #expect(!DockPresence.counts(styleMask: [.borderless], isVisible: true))
    }
}
