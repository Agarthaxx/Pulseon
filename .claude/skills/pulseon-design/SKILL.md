---
name: pulseon-design
description: La direction visuelle de Pulseon — à charger avant de dessiner ou modifier la moindre vue SwiftUI du projet. Contient les couleurs, la typographie, les règles non négociables et ce qui est interdit.
---

# Le design de Pulseon

À charger **avant** de toucher à une vue. Sans ça, chaque session redécouvre la
direction et l'app dérive vers le dashboard générique que ce fichier existe pour
éviter.

## Le parti pris, en une phrase

L'app « Temps d'écran » d'Apple dit **combien**. Pulseon montre **quand**.

Tout découle de là. Un total en gros chiffres, c'est ce que fait déjà le
système ; ce que Pulseon apporte, c'est la journée déployée sur un axe de temps,
avec ses chevauchements et ses trous.

## La direction : l'instrument de mesure

Le vocabulaire du projet était déjà celui d'un séquenceur — « multipiste »,
« piste », « signal », « marqueur d'heure courante », une icône `waveform`. La
direction va au bout de cette métaphore : **la journée est un rack d'appareil de
mesure**, posé dans une fenêtre native.

Ce n'est pas une décoration plaquée. Un séquenceur affiche du temps sur un axe
horizontal, ce qui est exactement le besoin — et c'est ce qui rend la direction
non transposable à un autre projet.

**Le rack reste sombre même en apparence claire.** Un instrument ne change pas
de couleur avec le papier peint, et les blocs d'activité ne se lisent qu'en
couleur saturée sur fond sombre. Le reste de la fenêtre suit le système, comme
n'importe quelle app native.

## Les références, et ce qu'on en retient

**Flighty** (suivi de vols) — la couleur y est **sémantique**, jamais
décorative : rouge = retard, vert = à l'heure, orange = attention. La hiérarchie
typographique est brutale et sans milieu : une heure énorme à côté d'un « 10m
Late » minuscule, un `45` géant surmontant un `MINUTES` en petites capitales.
Chaque ligne est **dense en faits utiles** — terminal, retard, prédiction — sans
jamais être décorative.

**Notion Calendar** — la même philosophie à température opposée : gris neutres,
cartes discrètes, typographie petite et dense, couleur réduite à des pastilles
de catégorie.

Ce que les deux partagent, et qui est la règle : **la donnée est le design.**
Aucun ornement. Ce qui occupe de la place à l'écran est une information.

Conséquence directe pour Pulseon : **viser la densité de Flighty.** Un écran
aéré avec trois chiffres est un écran qui n'a pas assez à dire. Chaque piste et
chaque ligne doit porter un fait que l'utilisateur ne connaissait pas.

## Couleurs

Définies dans `PulseonTheme` (`Sources/PulseonUI/PulseonTheme.swift`) — **s'y
référer, ne jamais écrire une couleur en dur dans une vue.**

| Rôle | Usage |
|---|---|
| `rack` | Le panneau qui porte les pistes |
| `lane` | Le fond d'une piste : la journée qu'on n'a pas passée là |
| `grid` | Les graduations horaires |
| `color(for: device)` | **Une couleur par appareil.** Elle dit de quel écran on parle : elle porte de l'information et ne se choisit pas à l'humeur |
| `playhead` | Le rouge de la tête de lecture, emprunté à l'enregistrement en cours sur une station audio. **Réservé à ça** — aucun autre élément ne le porte |

Règle générale, tirée des références : **une couleur doit signifier quelque
chose.** Si elle n'encode ni un appareil, ni un état, ni l'instant courant, elle
n'a rien à faire là.

## Typographie

- **Les grands nombres** : `PulseonTheme.readout(_:)` — caractères comprimés
  (`.width(.compressed)`) et à chasse fixe. Comprimés parce que c'est le dessin
  des afficheurs d'instruments ; chasse fixe pour que les chiffres ne tremblent
  pas quand ils défilent.
- **Étiquettes et règle horaire** : `PulseonTheme.stencil` — petites capitales
  espacées, le vocabulaire de la sérigraphie sur un boîtier.
- **Hiérarchie sans milieu**, comme Flighty : ce qui compte est énorme, le reste
  est minuscule et gris. Éviter la gamme de tailles intermédiaires qui aplatit
  tout.

## Règles non négociables

1. **Ne jamais inventer de placement horaire.** Une source à compteur (la
   PlayStation) ne connaît pas ses horaires : son bloc est **centré**, sa piste
   n'a **pas de graduations**, et le libellé dit « heure inconnue ». Calé à
   gauche, il se lisait « joué de minuit à 1 h 48 » — la première version de la
   vue commettait exactement cette faute. Les hachures ne suffisent pas si la
   *position* ment.
2. **« Pas encore branchée » ≠ « journée à zéro ».** Deux états visuellement
   distincts, toujours.
3. **Les durées sont tronquées, jamais arrondies.** Afficher 1 h à 59 min 40
   annoncerait du temps qui n'a pas eu lieu.
4. **Une lecture qui échoue se dit.** Un tiret, jamais un zéro : zéro est une
   affirmation, et on ne sait pas.
5. **La tête de lecture n'existe que sur aujourd'hui.** Une journée passée est
   entièrement jouée.
6. **Rien d'AppKit dans `PulseonUI`.** Ces vues serviront à l'app iOS telles
   quelles — `.buttonStyle(.link)` s'y est déjà fait refuser.

## Interdits

Ce qui trahit un design généré, et n'entre pas ici :

- Les trois clichés : fond crème + serif à fort contraste + accent terracotta ;
  noir presque pur + un seul accent acide ; mise en page journal à filets d'un
  pixel.
- Dégradés violets, Inter/Roboto, emojis en guise d'icônes, ombres portées
  décoratives, cartes toutes identiques.
- Le gros chiffre isolé au-dessus de trois stats secondaires, sans rien à dire
  de plus.
- Toute couleur qui n'encode rien.

## Sur iOS, le piège s'inverse

Le réflexe « faire du beau design » pousse à importer des habitudes web dans une
app native, et ça se voit immédiatement. Une app iOS crédible respecte SF Pro et
ses variantes de graisse et de largeur, les matériaux système, Dynamic Type et
les safe areas. La distinction se joue ensuite sur **un** élément signature — ici
la tête de lecture — pas sur une réinvention des conventions.

Flighty, encore, montre la cible produit : l'information arrive sur l'écran
verrouillé sans ouvrir l'app. L'équivalent iOS de la barre de menu macOS est une
Live Activity ou un widget.

## Regarder avant de livrer

Un design qu'on ne regarde pas est un design qu'on ne corrige pas. Utiliser la
skill **`pulseon-preview`** pour rendre les vues en PNG et les examiner : elle a
trouvé, en une session, une étiquette coupée, un bloc qui mentait sur l'heure et
une grille horaire qui partait de midi — trois défauts qu'aucun test n'attrapait
et que le compilateur ne signalait pas.
