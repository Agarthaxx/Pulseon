---
name: pulseon-design
description: La direction visuelle de Pulseon — à charger avant de dessiner ou modifier la moindre vue SwiftUI du projet. Contient les couleurs, la typographie, les règles non négociables et ce qui est interdit.
---

# Le design de Pulseon

À charger **avant** de toucher à une vue. Sans ça, chaque session redécouvre la
direction et l'app dérive.

## Pourquoi l'app existe

Arthur consultait souvent « Temps d'écran » de macOS et la trouve **laide**.
Pulseon est d'abord le remplacement qu'il a *envie d'ouvrir*, avec une ambition
secondaire de mise en ligne.

Conséquence directe, et c'est le critère de tri de toute décision visuelle :
**si ce n'est pas beau, l'app n'a aucune raison d'exister.** La justesse des
chiffres est nécessaire mais ne suffit pas — le produit concurrent est gratuit,
préinstallé, et déjà juste.

Le parti pris produit, lui, ne bouge pas : **« Temps d'écran » dit *combien*,
Pulseon montre *quand*.**

## La direction : noir, une couleur, des cartes

**Choisie par Arthur le 2026-08-16 sur une référence qu'il a apportée** (une app
de fitness). Ce qui en est retenu, dans l'ordre d'importance :

1. **Un fond presque noir**, et des cartes légèrement plus claires qui flottent
   dessus. Ni bordure ni ombre : c'est l'écart de gris qui crée le relief.
2. **Un seul accent**, un vert acide, et il ne désigne qu'une chose : **du temps
   d'écran mesuré**. Il ne décore pas un titre, ne remplit pas une icône pour
   faire joli.
3. **Le grand nombre avec son unité en petit et en gris** — « 13 » énorme, « h »
   discret, « 15 » énorme.
4. **La donnée dessinée en signal** : des barres, un rail, pas des aplats.
5. **Le pointillé pour l'inconnu**, le plein pour le mesuré. C'est la règle
   « ne jamais inventer » devenue langage visuel.
6. **Les icônes d'apps remplacent les photos.** C'est la remarque d'Arthur, et
   elle est juste : une rangée d'icônes se reconnaît en un coup d'œil là où une
   liste de noms se déchiffre. Sans images, ce style paraîtrait vide.

**Pulseon est sombre tout le temps, y compris en apparence claire.** C'est un
choix : les blocs d'activité ne se lisent qu'en couleur saturée sur fond sombre,
et l'app se regarde surtout le soir.

### Ce qui a été abandonné, et pourquoi

La direction précédente — **« l'instrument de mesure »** : rack sombre,
sérigraphie en capitales espacées, monospace partout, hachures, cartouche rouge
vif, une piste par appareil — a été rejetée par Arthur en ces termes : « c'est
pas beau du tout, c'est pas épuré, visuellement c'est hard, le consommateur pète
un plomb en voyant ça ».

**Ne pas la ressusciter par morceaux.** Les tentations, une par une : remettre du
monospace pour « faire technique », remettre des étiquettes en capitales
espacées, hachurer une zone plutôt que la pointiller, redonner une couleur par
appareil.

Une critique de fond est venue avec, indépendante du style : **une piste par
appareil s'écroule au troisième écran.** Voir `RailLayout`.

### Le piège de cette direction

« Noir presque pur + un seul accent acide » est un des clichés du design généré
par IA, et l'ancienne version de ce fichier l'interdisait explicitement. Ce n'est
plus un défaut à éviter mais **une direction choisie par le client** : la
consigne est donc de l'exécuter sans que ça ressemble à un template.

Ce qui fait la différence, concrètement :

- **L'accent ne touche que la donnée.** Un template met de l'acide partout — les
  titres, les boutons, les bordures. Ici, une seule chose est verte : du temps
  mesuré.
- **De la densité d'information, pas de la densité d'ornement.** Chaque ligne
  porte un fait qu'on ne connaissait pas. Un écran aéré avec trois chiffres et
  rien à dire est aussi raté qu'un écran surchargé.
- **Les icônes d'apps** donnent une texture que le style seul n'a pas.
- **Aucun élément décoratif** : pas de dégradé, pas de forme de fond, pas de
  pastille vide.

## Couleurs

Définies dans `PulseonTheme` (`Sources/PulseonUI/PulseonTheme.swift`) — **s'y
référer, ne jamais écrire une couleur en dur dans une vue.**

| Rôle | Usage |
|---|---|
| `ground` | Le fond de la fenêtre |
| `surface` | Une carte |
| `surfaceSunken` | Un creux : rail vide, pastille, fond de barre |
| `hairline` | Un filet de séparation |
| `ink` / `inkSoft` / `inkFaint` | Le texte, par ordre d'importance décroissante |
| `accent` | **Le seul accent.** Du temps d'écran mesuré, rien d'autre |
| `accentSecondary` | Un vert d'eau, pour un **second** appareil simultané |
| `now` | L'instant courant. Le seul rouge de l'app, réservé à ça |

**Deux teintes, et deux seulement.** La première version de la refonte tenait un
seul accent décliné en opacités : bonne théorie, **rendu raté et constaté en
PNG** — de la couleur translucide sur un rail gris foncé donne un olive sale, qui
se lit « sali » plutôt que « différent ». Trois teintes, en revanche,
recommenceraient le tableau de bord d'ingénieur qu'on vient d'abandonner.

Ce sont les **formes** qui portent le reste de l'information : plein pour un
horaire connu, pointillé pour une durée sans horaire, gris neutre pour un
appareil non branché. Une différence de forme survit au daltonisme, une
différence de teinte non.

## Typographie

- `PulseonTheme.readout(_:)` — les grands nombres. **Plus de caractères
  comprimés** : c'était le dessin d'un afficheur d'instrument. La chasse fixe des
  chiffres reste, pour qu'un total qui défile ne tremble pas.
- `PulseonTheme.unit(_:)` — l'unité collée au grand nombre, plus petite et plus
  grise. **Elle a besoin d'un `baselineOffset`** : partageant la ligne de base
  des grands chiffres, elle tombe sinon tout en bas et se lit comme un indice de
  formule chimique (constaté en PNG).
- `sectionTitle`, `row`, `caption`, `footnote` — le reste. **Plus de `stencil`** :
  les petites capitales espacées en monospace étaient la moitié de la dureté de
  l'ancienne version.
- Hiérarchie franche : ce qui compte est grand et blanc, le reste est petit et
  gris. Éviter la gamme de tailles intermédiaires qui aplatit tout.

## Règles non négociables

1. **Ne jamais inventer de placement horaire.** Une source à compteur ne connaît
   pas ses horaires. Et **centrer son bloc ne suffit pas** : centré juste sous un
   axe des heures, il tombait pile sous « 12 h » et se lisait « joué vers midi ».
   Il faut cumuler : un filet et un titre (« Sans horaire connu ») qui coupent le
   lien avec l'axe, le bloc centré, son libellé centré dessous, et un contour
   pointillé.
2. **« Pas encore branchée » ≠ « journée à zéro ».** Deux états visuellement
   distincts, toujours. Zéro est une affirmation.
3. **Les durées sont tronquées, jamais arrondies.** Afficher 1 h à 59 min 40
   annoncerait du temps qui n'a pas eu lieu.
4. **Une lecture qui échoue se dit.** Un tiret ou un message, jamais un zéro.
5. **Le marqueur d'instant courant n'existe que sur aujourd'hui.** Une journée
   passée est entièrement jouée.
6. **Un seul rail pour la journée, jamais une piste par appareil.** La hauteur du
   rail ne change pas : deux appareils simultanés se partagent la hauteur, trois
   la divisent en trois. L'ordre des couches est stable (`Device.allCases`), sinon
   un appareil sauterait de haut en bas au fil de la journée.
7. **Rien d'AppKit dans `PulseonUI`.** Ces vues serviront à l'app iOS telles
   quelles — `.buttonStyle(.link)` s'y est déjà fait refuser. Corollaire pour les
   icônes d'apps : elles n'entrent pas ici en `NSImage`, mais par une fonction
   injectée que chaque plateforme fournit.

## Regarder avant de livrer

Un design qu'on ne regarde pas est un design qu'on ne corrige pas. Utiliser la
skill **`pulseon-preview`**.

Ce qu'elle a trouvé, et qu'aucun test ni compilateur ne signalait :

- **`ImageRenderer` ne rend pas le contenu d'un `ScrollView`.** La refonte est
  sortie en PNG entièrement noir — fond seul. D'où `DayDashboardContent`,
  rendable seul, séparé du conteneur défilant. **Toute nouvelle vue défilante doit
  garder son contenu extractible**, sinon elle devient invisible à la preview.
- L'échelle d'opacité entre appareils qui donne de l'olive sale.
- L'unité d'un grand nombre qui tombe en indice.
- Un bloc « heure inconnue » centré qui se lit quand même « vers midi ».
- Une étiquette « PLAYSTATIO/N » coupée, et une grille horaire qui partait de
  midi (`ZStack` de rectangles d'un point : il ne mesure qu'un point de large).

Les boutons, eux, **se rendent** en PNG à condition d'utiliser
`.buttonStyle(.plain)` : avec le style par défaut, `ImageRenderer` sortait des
carrés jaunes à leur place.

## Sur iOS, le piège s'inverse

Le réflexe « faire du beau design » pousse à importer des habitudes web dans une
app native, et ça se voit immédiatement. Une app iOS crédible respecte SF Pro,
les matériaux système, Dynamic Type et les safe areas. La distinction se joue
ensuite sur **un** élément signature — ici le rail de la journée — pas sur une
réinvention des conventions.
