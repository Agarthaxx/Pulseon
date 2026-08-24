---
name: pulseon-design
description: Les règles de dessin non négociables de Pulseon et l'état de sa direction visuelle — à charger avant de toucher à une vue SwiftUI du projet.
---

# Le dessin de Pulseon

À charger **avant** de toucher à une vue.

## La direction artistique : éditoriale, arrêtée le 2026-08-24

**Choisie par Arthur sur planche**, trois directions rendues côte à côte sur la
même journée : « j'adore la editorial sombre/light ». Elle **remplace le
traitement en cartes** de la maquette du 2026-08-17, dont tout le reste tient.

- **Pas de cartes.** Un filet fin en tête de bloc, le bord gauche aligné sur la
  marge de la page. L'écran est une page, pas une grille de boîtes.
- **Les titres portent l'or**, 21 pt, tracking −0,4. Sans cadre, c'est le titre
  seul qui dit « nouvelle rubrique » : l'or structure au lieu de décorer.
- **Libellés de ligne à 16 pt, durées à 18.** À 13 pt une liste se lit « tableau
  de bord » ; à 16 elle se lit « page ».
- **Jauges à 3 pt.** Sans cadre autour, une jauge épaisse vole la vedette au
  chiffre.
- **Le total au centre de l'anneau à 38 % du cœur**, contre 30 avant.

Les valeurs vivent dans `PulseonEditorial` et `PulseonTheme` — **ne jamais les
écrire en dur dans une vue.**

**Le fond n'est plus blanc** (2026-08-24, même soirée) : « je vois plus un truc
du style gris cassé avec un dégradé sympa plutôt que blanc blanc ». Le fond
porte un **dégradé vertical** (`groundTop` → `ground` → `groundDeep`), écrit en
clair et jamais dérivé par opacité, et **vertical et non diagonal** — une
diagonale a un sens de lecture, donc elle désigne un coin, or rien ici n'a à
être désigné. **Choisi sur planche** parmi trois gris cassés rendus côte à côte : le
**papier** (ivoire chaud) l'emporte, le greige neutre et l'ardoise froide ont été
supprimés le jour même — comme `PulseonSkin`. Seul le fond changeait de l'un à
l'autre : mélanger deux variables sur une planche empêche de savoir laquelle a
emporté le choix. L'ivoire est le seul des trois qui **s'accorde à l'or**, déjà
un ocre, et l'encre passe de bleutée à **neutre** — une encre froide sur un
papier chaud, ce sont deux températures qui se contredisent. **Ne pas
reproposer** de fond froid ni de blanc pur.

**Aucune animation perpétuelle**, jamais — c'est une règle de dessin autant que
de performance. Le halo du fond battait en `repeatForever` : **46 à 48 % d'un
cœur en continu** sur l'app installée, dès qu'une fenêtre était ouverte
(2026-08-24). Le coût ne vient pas de ce qui est animé — un point de 8 px seul
dans une fenêtre vide coûte le même cœur entier — mais du fait qu'une animation
sans fin tient le cycle d'affichage éveillé. Tout mouvement de Pulseon se joue
**une fois, à l'apparition, puis se tait**.

**L'écran de lancement** (`LaunchSplash`) se joue à **l'ouverture de la
fenêtre**, jamais au démarrage du processus — un agent de barre de menu vit des
jours sans fenêtre, donc un écran de lancement au démarrage serait dessiné pour
personne. Sa barre **ne mesure rien** : d'où aucun pourcentage affiché (ce serait
un chiffre inventé), une durée courte, et **les couleurs de la marque et jamais
l'or** — l'or désigne du temps mesuré, et une barre de chargement n'en mesure
pas.

**Deux directions écartées le même jour, à ne pas reproposer** : la **pleine**
(cartes, filet, ombre — jugée « trop simple »), et le **verre** (translucide,
champs de couleur, reflet — séduisant mais daté, « une mode datée se voit plus
vite qu'une composition sobre »). Le type `PulseonSkin` qui permettait de les
comparer a été supprimé : une option qui survit à la décision qu'elle servait
devient une dette.

**Leçon de méthode de cette séance** : régler des marges, des titres et une
disposition **n'est pas une direction artistique**. Arthur l'a dit sans détour —
« qu'en est-il du design de l'app ? le front n'a pas bougé ? ». Une DA change ce
qu'on voit *avant* de lire. Et elle se choisit **sur planche**, pas sur des
adjectifs.

## Ce qui tient de la maquette d'Arthur, 2026-08-17

**Elle fait foi.** Fournie après trois propositions écartées, en version desktop
d'abord, iPhone ensuite. Ce qu'elle porte, dans l'ordre d'importance :

1. **Un fond profond bleu nuit**, presque noir, jamais un gris neutre — et des
   **cartes** à grand rayon posées dessus, sans bordure ni ombre : c'est l'écart
   de gris qui crée le relief.
2. **Deux accents, l'or et le bleu nuit**, ceux de l'icône de l'app.
3. **L'anneau en tête d'écran**, grand nombre au centre, unité en petit et en
   gris, légende de couleurs dessous. **Les catégories sont une rangée de petits
   ronds sous l'anneau** (2026-08-19), un par catégorie, **tous de la même
   taille**, portant le logo de l'app dominante (glyphe de la catégorie à
   défaut). **La taille n'encode rien, ni ici ni sur la rangée de la semaine** :
   la durée est écrite au-dessus de chaque rond.
   **Deux formes écartées le même jour, à ne pas reproposer :** une couronne
   intérieure concentrique (« à quoi correspond le deuxième anneau ? » — une
   forme qui demande une légende n'est pas plus dense, elle est plus opaque), et
   deux anneaux pleins côte à côte (« je ne suis pas trop fan » — et il fallait
   écrire au centre du second une somme de catégories qui n'est pas comparable au
   total de la journée).
   **La télé et la PlayStation ont chacune leur rond** (2026-08-19), et il
   n'apparaît que les jours où l'appareil a servi. Chacun porte **la couleur de
   son arc** dans l'anneau du haut. Voir la règle 9 ci-dessous.
   **Une seule rangée, toujours** — « je préfère la photo avec une seule
   rangée ». Quand la fenêtre se resserre, les ronds rétrécissent
   (`ViewThatFits`, 48 → 40 → 32 points) au lieu de passer à la ligne.
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

### L'icône, arrêtée le 2026-08-19

**Le cadran de la référence d'Arthur** (`Design/icon-reference-2026-08-19.jpg`) :
carré bleu nuit, anneau bleu → violet coupé à gauche et à droite, battement qui
le traverse, repères à 12 h, 3 h et 6 h. Dessinée en SwiftUI (`PulseonMark`),
trait à 4,8 % du côté.

**Trois formes écartées le même jour, à ne pas reproposer** : « épuré » (le même
sans repères), « contenu » (anneau fermé, battement à l'intérieur) et « parts »
(l'anneau du dashboard découpé — il demande de connaître l'app pour être lu, or
une icône se lit avant d'ouvrir).

**Le bleu et le violet ne remplacent pas l'or.** L'or *désigne du temps mesuré*
à l'intérieur de l'app ; une icône n'a rien à désigner, elle doit se reconnaître
dans une rangée d'autres icônes. Ne pas « harmoniser » l'un sur l'autre.

**Les repères ne sont pas une graduation** et ne doivent jamais le devenir :
c'est la règle 1 jusque dans l'icône.

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
9. **Un écran n'est pas un contenu.** Un appareil qui ne dit pas ce qu'il affiche
   ne se range jamais dans une catégorie de contenu. `Device.tv` valait `.media`
   jusqu'au 2026-08-19 : une soirée de télé s'affichait « Vidéo et musique »
   alors que l'app Musique avait tourné 6 secondes, et une soirée de PS5 branchée
   sur cette télé s'y serait rangée en musique. La télé et la PlayStation ont
   donc **chacune leur catégorie**. Corollaire : « Jeu » reste le classement d'un
   jeu *sur le Mac*, lu dans son `Info.plist`. C'est la règle 1 appliquée au
   classement plutôt qu'à l'horaire — **ne pas affirmer ce qu'on n'a pas
   mesuré**, ici un genre de contenu plutôt qu'une heure.

### La disposition : grille quand il y a la place, colonne sinon

**Arrêté le 2026-08-22, sur demande d'Arthur** : « quand l'appli desktop est
ouverte, on ne doit pas scroller, genre en grille de 4 cases ». Sa fenêtre fait
1512 × 949.

- **Au-dessus de 980 points de large** : une grille à deux colonnes pondérées
  **57 / 43** (`WeightedColumns`). Jour = 4 cases (anneau · répartition /
  déroulé · appareils), semaine = 3. L'anneau prend la colonne large **et**
  grossit (248 au lieu de 208) : c'est la case principale, et une case
  principale qui porterait le même anneau qu'ailleurs ne dirait pas qu'elle
  l'est.
- **En dessous** : la colonne bornée à 720, qui défile. Deux colonnes illisibles
  sont pires qu'une colonne lisible qui défile.
- **La chronologie ne se borne pas** : c'est le seul écran où la largeur porte de
  l'information — deux fois plus large, deux fois plus de résolution par heure.
  Les listes, elles, gardent leur colonne : leurs jauges deviendraient illisibles
  étirées sur 1500 points.

**Le piège, payé deux fois le même jour** : `frame(maxWidth: .infinity)` rend une
vue infiniment compressible, donc `ViewThatFits` retient **toujours** sa première
proposition et la fait écraser au lieu de la laisser céder. Une proposition doit
annoncer sa largeur réelle (`minWidth` explicite, colonnes à taille intrinsèque,
texte en `fixedSize`) pour que la bascule fonctionne.

**Limite assumée** : à dix catégories — le maximum possible — la fenêtre déborde
d'environ 90 points et défile. On laisse défiler : resserrer coûterait les icônes
d'apps, tronquer cacherait des données mesurées.

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

**Une quantité ne passe jamais par le remplissage d'un anneau.** Un anneau qui
ne fait pas le tour se lit « objectif atteint à 66 % », ce qu'Arthur a
explicitement retiré de sa maquette. Les arcs font toujours le tour, à toutes les
échelles.

**Et les petits ronds font tous la même taille** (2026-08-19, sur l'écran du jour
comme sur celui de la semaine) : « je me fiche de la logique le rond grossit plus
le temps est grand ». La durée est écrite au-dessus de chaque rond, donc le
diamètre ne disait rien de plus. Si une quantité devait un jour passer par la
forme, ce serait par la taille — calculée sur la **racine carrée** du temps,
l'œil comparant des surfaces — mais ne pas la réintroduire sans qu'il le demande.

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
