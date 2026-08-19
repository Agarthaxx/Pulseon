---
name: pulseon-design
description: Les règles de dessin non négociables de Pulseon et l'état de sa direction visuelle — à charger avant de toucher à une vue SwiftUI du projet.
---

# Le dessin de Pulseon

À charger **avant** de toucher à une vue.

## La direction est arrêtée : la maquette d'Arthur, 2026-08-17

**Elle fait foi.** Fournie après trois propositions écartées, en version desktop
d'abord, iPhone ensuite. Ce qu'elle porte, dans l'ordre d'importance :

1. **Un fond profond bleu nuit**, presque noir, jamais un gris neutre — et des
   **cartes** à grand rayon posées dessus, sans bordure ni ombre : c'est l'écart
   de gris qui crée le relief.
2. **Deux accents, l'or et le bleu nuit**, ceux de l'icône de l'app.
3. **L'anneau en tête d'écran**, grand nombre au centre, unité en petit et en
   gris. **Double depuis le 2026-08-19** : couronne extérieure = les appareils,
   couronne intérieure = les catégories. Demandé par Arthur (« embellis plutôt le
   rond ») en écartant un graphique de plus. L'intérieure est plus fine, et un
   écart les sépare — collées, elles se lisent comme un seul anneau à deux tons.
4. **Des lignes denses** : pastille colorée à glyphe, libellé, durée, part,
   jauge fine, et le détail (les apps) en dessous.
5. **Le clair *et* le sombre**, tous deux dessinés (écran 5 de la maquette).
   D'où `PulseonPalette`, une **valeur** résolue depuis `colorScheme` — des
   `static let` de couleurs ne peuvent pas suivre l'apparence, et `PulseonUI`
   n'a pas le droit d'appeler AppKit pour les résoudre.

**Donc : ne pas proposer de direction visuelle, ne pas restyler spontanément, ne
pas « améliorer » une vue au passage.** Quand ses maquettes arrivent, les
implémenter fidèlement et ne vérifier qu'une chose : qu'elles ne cassent pas les
règles ci-dessous.

**Correction du 2026-08-17, à ne pas confondre avec ce qui précède : « pas de
direction visuelle » ne veut plus dire « pas de front ».** Les PR purement back
(#21, #23, #26) ont produit du travail réel resté invisible plusieurs sessions —
Arthur a perdu le fil de l'avancement. Depuis, **chaque feature porte son écran**,
mais en composants système neutres : `List`, `Text`, couleurs et typographie par
défaut, aucune trace de `PulseonTheme`. Ce n'est toujours pas « proposer une
direction » — c'est juste rendre une donnée lisible. Quand la maquette d'Arthur
arrive, on repeint des écrans qui existent déjà.

### Ce qui a été retiré de la maquette, et pourquoi

Elle portait un **objectif quotidien** (« / 5h Daily Goal »), un badge **« On
Track »** et un « 87 % — objectif tenu 6 jours sur 7 ». Arthur a tranché en même
temps qu'il validait le dessin : « **on reste sur une application sans
jugement** ».

D'où l'anneau de **composition** et non de progression (`RingLayout`) : même
dessin, mais ses arcs sont des parts et il fait **toujours** le tour complet. Un
anneau qui se remplit vers une cible annoncerait une réussite ou un échec.
**Ne pas réintroduire d'objectif, de seuil, ni de couleur d'alerte** même si une
future maquette en montre : c'est la règle 7, et elle a survécu à trois
directions visuelles.

### Ce qui a été essayé et écarté avant

Pour ne pas le reproposer par morceaux :

1. **« L'instrument de mesure »** — rack sombre, sérigraphie en capitales
   espacées, monospace partout, hachures, cartouche rouge vif, une piste par
   appareil. Rejeté : « c'est pas beau du tout, c'est pas épuré, visuellement
   c'est hard, le consommateur pète un plomb en voyant ça ».
2. **Une version épurée** en cartes claires sur iPhone. Écartée sans détail.
3. **Fond noir à accent vert acide**, d'après une référence qu'Arthur avait
   apportée. Implémentée entièrement (PR #22), puis : « j'aime pas du tout ».
4. **Un graphique en colonnes** pour la semaine (PR #32, 2026-08-19) : « je
   n'aime pas les graphs en colonne, je me dis que si c'est en colonne, autant
   garder l'ancienne app temps d'écran macOS ». **Le rond est l'élément
   signature**, et il tient toutes les échelles — un grand anneau pour une
   période, des petits pour ses journées. Ne pas reproposer de barres, ni
   empilées ni groupées.

Les tentations à ne pas suivre : remettre du monospace pour « faire technique »,
des étiquettes en capitales espacées, des hachures plutôt qu'un pointillé.

### La timeline chronologique a été retirée de l'écran du jour

Arthur, en validant la maquette : « **j'aime bien le rond plutôt que la timeline
chrono qu'on a** ». `DayTimeline` — la journée en multipiste, l'ancien élément
signature — est donc supprimée, et l'anneau prend sa place en tête d'écran.
`TimelineGeometry` est conservée : elle est pure, testée, et servira à l'onglet
Timeline de la maquette (écran 4).

**L'onglet Chronologie existe depuis le 2026-08-19** (`DayTimeline`), bâti sur
`TimelineGeometry` et sur le `RailLayout` repris de la PR #22. La maquette y
plaçait la PlayStation à 12:20 : elle n'y est pas, elle vit sous un filet dans
une section « Sans horaire connu ». C'est la règle 1, et cet écran-là ne peut pas
la lister comme les autres.

## Ce qui survit à n'importe quelle maquette

Le parti pris produit ne bouge pas : **« Temps d'écran » dit *combien*, Pulseon
montre *quand*.**

### Règles non négociables

1. **Ne jamais inventer de placement horaire.** Une source à compteur (la
   PlayStation) ne connaît pas ses horaires. Et **centrer son bloc ne suffit
   pas** : centré sous un axe des heures, il tombait pile sous « 12 h » et se
   lisait « joué vers midi ». Il faut cumuler un filet, un titre de section
   explicite, le bloc centré, son libellé centré dessous, et un contour
   pointillé.
2. **« Pas encore branchée » ≠ « journée à zéro ».** Deux états visuellement
   distincts, toujours. Zéro est une affirmation ; « rien de mesuré » n'en est
   pas une.
3. **Les durées sont tronquées, jamais arrondies.** Afficher 1 h à 59 min 40
   annoncerait du temps qui n'a pas eu lieu.
4. **Une lecture qui échoue se dit.** Un tiret ou un message, jamais un zéro.
5. **Le marqueur d'instant courant n'existe que sur aujourd'hui.** Une journée
   passée est entièrement jouée.
6. **Jamais une piste par appareil.** *(Tenu par `RailLayout` depuis le
   2026-08-19.)* Critique d'Arthur — « à plusieurs devices
   c'est illisible » — et elle est structurelle, pas esthétique : ça allonge
   l'écran et transforme les simultanéités en mur dès le troisième appareil. Sur
   l'écran du jour, l'anneau règle la question : un appareil de plus est un arc
   de plus, la hauteur ne bouge pas. Une future timeline devra tenir la même
   contrainte (un rail unique divisé en hauteur, cf. `RailLayout` dans la PR #22
   non mergée).
7. **Aucune comparaison ne juge.** Pulseon mesure l'usage, il ne dit pas si c'est
   bien : pas de rouge sur un dépassement de moyenne, ce serait transformer un
   miroir en juge.
8. **Rien d'AppKit dans `PulseonUI`.** Ces vues serviront à l'app iOS telles
   quelles — `.buttonStyle(.link)` s'y est déjà fait refuser. Corollaire pour les
   icônes d'apps : elles n'entrent pas ici en `NSImage`, mais par une fonction
   injectée que chaque plateforme fournit.

### Couleurs et typographie

Tout vit dans `PulseonTheme` (`Sources/PulseonUI/PulseonTheme.swift`) — **s'y
référer, ne jamais écrire une couleur en dur dans une vue.**

`PulseonTheme.palette(for:)` rend la palette de l'apparence courante ; une vue la
reçoit en paramètre plutôt que de la chercher elle-même, ce qui la rend rendable
hors écran par la preview.

**Aucune couleur de catégorie n'est rouge.** Le rouge dirait « trop », et Pulseon
ne juge pas. Les teintes des catégories sont dérivées du même axe bleu nuit → or
que la maquette.

**Les formes portent autant d'information que les teintes** : plein pour du
mesuré, pointillé pour de l'inconnu, gris neutre pour un appareil non branché.
Une différence de forme survit au daltonisme, une différence de teinte non.

**La quantité d'un anneau passe par sa taille, jamais par son remplissage.** Un
anneau qui ne fait pas le tour se lit « objectif atteint à 66 % », ce qui est
exactement ce qu'Arthur a retiré de sa maquette. Pour comparer des journées entre
elles, faire varier le diamètre — et le calculer sur la **racine carrée** du
temps, l'œil comparant des surfaces.

**Un pourcentage non nul ne s'affiche jamais « 0 % ».** Trois minutes dans une
journée font 0,4 %, tronqué à zéro juste à côté d'une durée non nulle — zéro est
une affirmation, et celle-ci est fausse. En dessous de 1 %, écrire « < 1 % ».

## Regarder avant de livrer

Un design qu'on ne regarde pas est un design qu'on ne corrige pas. Utiliser la
skill **`pulseon-preview`**.

Ce qu'elle a déjà trouvé, et qu'aucun test ni compilateur ne signalait :

- **`ImageRenderer` ne rend pas le contenu d'un `ScrollView`.** Une refonte est
  sortie en PNG entièrement noir — le fond seul. **Toute vue défilante doit garder
  son contenu extractible** (`DayDashboardContent`), sinon elle est invisible à la
  preview.
- Les boutons ne se rendent qu'avec **`.buttonStyle(.plain)`** ; avec le style par
  défaut, `ImageRenderer` sort des carrés jaunes à leur place.
- Un accent unique **décliné en opacités** donne un olive sale sur fond sombre :
  ça se lit « sali », pas « différent ».
- L'unité d'un grand nombre (« h » dans « 13h15 ») tombe en indice de formule
  chimique si elle partage la ligne de base des chiffres.
- Un bloc « heure inconnue » **centré** qui se lit quand même « vers midi ».
- Une étiquette « PLAYSTATIO/N » coupée, et une grille horaire qui partait de
  midi — **un `ZStack` de rectangles d'un point ne mesure qu'un point de large**.

## Sur iOS, le piège s'inverse

Le réflexe « faire du beau design » pousse à importer des habitudes web dans une
app native, et ça se voit immédiatement. Une app iOS crédible respecte SF Pro, les
matériaux système, Dynamic Type et les safe areas. La distinction se joue ensuite
sur **un** élément signature — ici le rail de la journée — pas sur une
réinvention des conventions.
