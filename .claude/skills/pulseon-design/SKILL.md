---
name: pulseon-design
description: Les règles de dessin non négociables de Pulseon et l'état de sa direction visuelle — à charger avant de toucher à une vue SwiftUI du projet.
---

# Le dessin de Pulseon

À charger **avant** de toucher à une vue.

## La direction visuelle est en attente, et ce n'est pas à nous de la choisir

**Arthur fournira ses maquettes.** Le 2026-08-16 il a écarté trois propositions
successives, dont une tirée d'une référence qu'il avait lui-même apportée, et a
tranché ainsi :

> « On fait le cœur du métier, et je verrai après pour une maquette magnifique.
> Le front-end se bosse aussi, c'est un vrai métier. »

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

### Ce qui a été essayé et écarté

Pour ne pas le reproposer par morceaux :

1. **« L'instrument de mesure »** — rack sombre, sérigraphie en capitales
   espacées, monospace partout, hachures, cartouche rouge vif, une piste par
   appareil. Rejeté : « c'est pas beau du tout, c'est pas épuré, visuellement
   c'est hard, le consommateur pète un plomb en voyant ça ». **Les versions
   anciennes de ce fichier décrivaient cette direction comme la bonne** — elle ne
   l'est plus.
2. **Une version épurée** en cartes claires sur iPhone. Écartée sans détail.
3. **Fond noir à accent vert acide**, d'après une référence qu'Arthur avait
   apportée. Implémentée entièrement (PR #22), puis : « j'aime pas du tout ».

Les tentations à ne pas suivre : remettre du monospace pour « faire technique »,
des étiquettes en capitales espacées, des hachures plutôt qu'un pointillé, une
couleur par appareil.

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
6. **Un seul rail pour la journée, jamais une piste par appareil.** Décision
   prise après la critique d'Arthur — « à plusieurs devices c'est illisible » — et
   elle est structurelle, pas esthétique : une piste par appareil allonge l'écran
   et transforme les simultanéités en mur dès le troisième écran. Le rail garde
   une hauteur fixe et se divise en hauteur. L'implémentation vit dans
   `RailLayout` (PR #22, non mergée à ce jour).
7. **Aucune comparaison ne juge.** Pulseon mesure l'usage, il ne dit pas si c'est
   bien : pas de rouge sur un dépassement de moyenne, ce serait transformer un
   miroir en juge.
8. **Rien d'AppKit dans `PulseonUI`.** Ces vues serviront à l'app iOS telles
   quelles — `.buttonStyle(.link)` s'y est déjà fait refuser. Corollaire pour les
   icônes d'apps : elles n'entrent pas ici en `NSImage`, mais par une fonction
   injectée que chaque plateforme fournit.

### Couleurs et typographie

Tout vit dans `PulseonTheme` (`Sources/PulseonUI/PulseonTheme.swift`) — **s'y
référer, ne jamais écrire une couleur en dur dans une vue.** Son contenu changera
avec les maquettes d'Arthur ; l'endroit, non.

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
