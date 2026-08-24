# Pulseon

App native Apple pour suivre le temps passé sur Mac, PlayStation, TV, et
(potentiellement, plus tard) iPhone. **iOS d'abord**, macOS ensuite.

## Sources de données et statut

| Source      | Statut  | Méthode                                                                 |
|-------------|---------|-------------------------------------------------------------------------|
| Mac         | **Tourne** | `NSWorkspace` (app active) + `Quartz` (inactivité) + assertion vidéo, depuis l'app macOS |
| PlayStation | À faire | API non-officielle PSN — poll de `playDuration` par jeu, temps journalier = delta entre deux relevés |
| TV          | **Codée** | API HTTP locale de la télé (Samsung Tizen, port 8001) — `PowerState` dit si l'écran est allumé. Source à intervalles, comme le Mac |
| iPhone      | Différé | Voir contrainte ci-dessous                                              |

## Décisions et contraintes connues

- **iPhone : pas d'automatisation 100% fiable possible.** Le framework
  DeviceActivity d'Apple ne laisse pas une app tierce (même perso) accéder
  aux chiffres bruts : `DeviceActivityReport` n'affiche qu'une vue système
  fermée, et `DeviceActivityMonitor` ne donne que des callbacks sur des
  seuils définis à l'avance, pas un flux de données exploitable.
  **Attention à ne pas confondre** : *afficher* le dashboard sur iPhone ne
  pose aucun problème et c'est même la cible principale. C'est *collecter*
  le temps d'écran de l'iPhone qui est bloqué. Le pivot iOS ne rouvre pas ce
  dossier.
- **PlayStation** : pas de temps de jeu en temps réel exposé par l'API,
  seulement un total cumulé par jeu (`playDuration`), mis à jour avec un
  délai. On reconstitue le temps journalier par différence entre deux
  relevés.
- **TV : la mesure exige que le Mac collecteur soit sur le même réseau que
  la télé, au moment où elle est allumée.** `SamsungTVProbe` interroge
  l'API HTTP locale de la télé (`:8001`) — constaté le 2026-08-17 en
  cherchant à la joindre depuis le bureau : ni DNS ni mDNS ne résolvent son
  nom `.local` hors du réseau domestique, et le port ne répond pas. **Ce
  n'est pas un bug à corriger, c'est une conséquence de l'architecture** :
  le Mac est le seul collecteur du projet, et Arthur l'emporte avec lui —
  donc le suivi Mac lui-même s'arrête déjà quand il part. La télé hérite de
  la même limite plutôt que d'en ajouter une nouvelle.
  Alternative écartée pour l'instant : l'API cloud SmartThings de Samsung
  rendrait l'état de la télé lisible depuis n'importe où, au prix d'une
  dépendance externe de plus (compte Samsung, jeton OAuth) — pour un gain
  faible, puisque la télé a peu de chances d'être allumée précisément les
  jours où Arthur est absent.

## Stack technique

Décidée le 2026-08-14, **après un premier essai abandonné** en Tauri +
Svelte + Python (voir « Historique » plus bas). Objectif : un produit
perçu comme pro, avec une identité visuelle forte, et une stack légère.

- **Swift / SwiftUI**, un seul codebase pour les deux cibles. Pas de techno
  web.
- **`PulseonCore`** (`Sources/PulseonCore/`) : package Swift pur, sans
  dépendance à SwiftUI ni SwiftData, qui porte les modèles et toute la
  logique d'agrégation. C'est volontaire : ça se teste en ligne de commande,
  sans simulateur.
- **SwiftData** pour la persistance, choisi surtout parce qu'il se
  synchronise avec CloudKit quasi gratuitement.
- **CloudKit** pour la synchro Mac → iPhone. L'iPhone ne peut pas lire le
  disque du Mac, et tous les collecteurs tournent côté Mac : sans synchro,
  une app iOS n'a rien à afficher. **Exige l'Apple Developer Program payant
  (~99 €/an)** — point bloquant à ne pas découvrir trop tard.

### Prérequis machine

- **Xcode complet requis.** Les Command Line Tools seuls ne suffisent pas :
  pas de SDK iOS, pas de simulateur, et le `Testing.framework` livré est
  incomplet (`lib_TestingInterop.dylib` manquant) donc `swift test` compile
  mais ne s'exécute pas.
- **Xcode est installé et sa licence est acceptée** (vérifié le 2026-08-15).
  Il reste seulement à ce que `swift` vise Xcode et non les CLT — voir
  « Lancer les tests ».

## Architecture d'exécution

- **L'app macOS est elle-même le collecteur**, sous forme d'agent en barre de
  menu. Elle tourne en continu sans fenêtre ouverte. Ça remplace le trio
  script Python + venv + launchd de la première version.
- **L'app iOS ne collecte rien**, elle lit et affiche.
- La règle d'origine tient toujours : la collecte ne doit pas dépendre d'une
  fenêtre ouverte, et l'affichage ne fait que lire des données déjà
  accumulées.
- La prise connectée (TV) a sa propre logique côté cloud/webhook,
  indépendante du Mac.

### Collecteur macOS : ce qui tourne, et les pièges payés

Depuis le 2026-08-15, le collecteur **tourne et écrit vraiment** : sessions
horodatées avec le nom de l'app active, vérifiées dans la base. Trois pièges
ont été payés au passage, tous invisibles à la compilation.

**Le store doit être nommé explicitement.** Un exécutable SwiftPM n'a pas de
bundle identifier ; SwiftData retombe alors sur
`~/Library/Application Support/default.store`, un chemin non-namespacé.
Pulseon y a ouvert la base d'une autre app et a planté au démarrage. La base
vit maintenant dans `~/Library/Application Support/Pulseon/Pulseon.store`
(voir `StoreLocation`).

**`entity` et `entityName` sont inutilisables comme noms de propriété dans un
`@Model`.** SwiftData s'appuie sur CoreData, où ces noms sont pris. `entity`
plante au démarrage (« Could not cast NSEntityDescription to NSString ») ;
`entityName` **échoue en silence** — l'objet en mémoire porte la valeur, la
colonne reste NULL, aucune erreur nulle part. D'où `appName` côté persistance,
traduit en `entity` à la frontière de `PulseonCore`, qui garde son vocabulaire.
Le silence est le vrai danger : une base de temps d'écran sans nom d'app se
remplit sans rien signaler.

**Une session ouverte doit pouvoir survivre à un crash.** Au démarrage,
`closeDanglingSessions(at:)` ferme ce qu'un arrêt brutal a laissé ouvert, à
la date du dernier signe de vie. Sans ça la première activation venue fermait
la session fantôme à l'instant présent, et une nuit machine éteinte comptait
comme du temps d'écran. Sans trace de vie du tout, la session est fermée sur
son propre début : durée nulle plutôt qu'une fin inventée.

**Ce signe de vie ne va pas dans la base**, et la raison est mesurée, pas
théorique. Il y vivait au départ (un champ `lastSeen` réécrit à chaque tick) :
chaque écriture coûtait **78 Ko** — journal SQLite plus historique CoreData —
pour une information de 8 octets, soit **~450 Mo par jour** une fois l'agent
lancé en continu. Aucun risque pour le disque (il faudrait des siècles pour
l'entamer), mais indéfendable.

`Heartbeat` le remplace par un fichier vide dont **la date de modification
est l'information** : marquer ne touche qu'une métadonnée, sans écrire un
octet de contenu, et aucun arrêt brutal ne peut le laisser à moitié écrit. Il
est daté au plus une fois par minute — la seule chose en jeu est la précision
de la réparation après un crash, événement rare. La base, elle, n'est plus
écrite que sur de vrais événements : ouverture et fermeture de session.

Le timer porte aussi une `tolerance`, qui laisse macOS regrouper son réveil
avec ceux des autres processus au lieu d'en provoquer un pour nous seuls.

**Regarder est une activité.** Le clavier et la souris ne suffisent pas :
sans autre signal, deux heures de film comptaient pour zéro, et Pulseon
effaçait précisément le moment où on est le plus devant l'écran. On lit donc
aussi l'assertion système `PreventUserIdleDisplaySleep`, que tout lecteur
vidéo lève pendant la lecture (`ActivityMonitor.isDisplayKeptAwake`).

Deux pièges, tous deux vérifiés à l'exécution :

- **Lire la bonne assertion.** `PreventUserIdleSystemSleep`, sa voisine, est
  levée par Handoff, les sauvegardes et `caffeinate` — elle compterait un
  téléchargement nocturne écran éteint comme du temps d'écran.
- **La fin du film.** Le dernier événement clavier peut dater d'une heure ;
  fermer la session à `maintenant - inactivité` effacerait le film qu'on
  vient de compter. La fin retenue est le plus tardif des signaux *observés*
  (`endOfActivity`). Conséquence assumée : on sous-compte d'au plus un tick
  (15 s) à la fin d'une vidéo, parce qu'on ignore à quel instant exact elle
  s'est arrêtée entre deux vérifications. Sous-compter est permis, inventer
  ne l'est pas.

### Ce que « actif » veut dire, appareil par appareil

Règle générale, valable pour toute source à venir : **chaque collecteur
décide seul de ce qu'« actif » signifie pour son appareil.** Le cœur ne
reçoit jamais que deux formes, et un nouvel appareil doit répondre à l'une
ou l'autre — jamais à autre chose :

| Appareil    | Signal d'activité                                  | Forme envoyée |
|-------------|----------------------------------------------------|---------------|
| Mac         | Clavier/souris **+ vidéo en cours**                | Intervalles   |
| TV          | Consommation électrique de la prise au-dessus d'un seuil | Intervalles |
| PlayStation | Aucun signal temporel, juste un total qui monte    | Compteur      |

Corriger le cas du film rapproche d'ailleurs le Mac de la TV : les deux
disent désormais « l'écran était allumé et montrait quelque chose », au lieu
de « quelqu'un tapait ». Ni l'un ni l'autre ne sait si tu t'es endormi
devant — on mesure l'usage de l'appareil, pas l'attention, et on ne prétend
pas le contraire.

### À quoi le temps a servi : identité des apps et catégories

Le collecteur n'écrivait que le **nom affiché** de l'app. C'est la bonne matière
première et une mauvaise réponse : au bout de trente apps dans la journée, la
liste devient du bruit, et surtout **elle ne se compare pas d'un jour à
l'autre**. « 6 h 12 de dev, 47 min de messages » se compare ; une liste de noms
non.

**`StoredApp` est une table à part**, et non des colonnes ajoutées à
`StoredSession`. Le nom est déjà répété sur chaque session : y coller
l'identifiant de bundle et la catégorie recopierait la même information des
milliers de fois. Prix assumé, documenté dans le code : deux apps de même nom
affiché seraient confondues, ce qui n'arrive pas sur une machine donnée.

Trois décisions qui ne se devinent pas à la lecture :

- **`noteApp` n'écrit rien quand rien n'a changé.** Une app est activée des
  centaines de fois par jour et son identité ne bouge jamais. Réécrire à chaque
  activation refait exactement l'erreur du `lastSeen` en base.
- **Pas d'`@Attribute(.unique)`** sur le nom : les contraintes d'unicité ne sont
  pas supportées par CloudKit, qui est la cible de synchronisation. L'unicité est
  tenue à la main.
- **La catégorie brute d'Apple est stockée telle quelle**, pas notre
  interprétation. Si la table de correspondance change d'avis, tout l'historique
  se reclasse sans avoir rien perdu.

**La catégorie déclarée par macOS est un point de départ, pas la vérité**, et
c'est vérifié sur la machine d'Arthur plutôt que supposé : Xcode, VS Code,
Ghostty et Docker déclarent `developer-tools` (juste) ; Discord
`social-networking` (juste) ; **Firefox et Safari déclarent `productivity`**,
ce qui est faux ; **Brave ne déclare rien du tout**. D'où l'ordre de décision de
`AppCategoryRules` : correction manuelle, puis liste des navigateurs connus,
puis déclaration de macOS, puis `other`.

**Un navigateur n'est pas une activité**, et aucune catégorie déclarée ne le
dira. Trois heures de Firefox peuvent être de la documentation ou du YouTube.
Trancher demanderait de lire l'URL ou le titre de fenêtre — permission
Accessibilité, nettement plus intrusive, et interdite en pratique dans le bac à
sable de l'App Store. Les navigateurs ont donc leur propre catégorie et **on ne
prétend rien de plus**. On ne classe jamais d'après la ressemblance du nom :
« Mail Designer » n'est pas un client mail, et un faux rangement est pire qu'un
`other` honnête.

**Un écran n'est pas un contenu.** La télé et la PlayStation ont **chacune leur
propre catégorie** (`Télé`, `PlayStation`), et ce n'est pas un détail de
libellé — c'est une correction payée à l'usage le 2026-08-19. `Device.tv`
valait `.media` : tout le temps de télé tombait donc dans « Vidéo et musique »,
**avant même de savoir ce qui passait à l'écran**. Le soir où la télé a
réellement été mesurée pour la première fois, la catégorie affichait 2 h 52
alors que l'app Musique avait tourné **6 secondes** — et c'est Arthur qui l'a vu :
« pourquoi ma musique a autant grimpé ? ».

Le raccourci qui la défendait (« une console sert à jouer, une télé à regarder »)
tient tant qu'on parle de l'appareil, et casse à l'instant où le total atterrit
dans une catégorie de contenu, à côté d'IINA : l'app affirme alors ce qu'elle n'a
pas mesuré. Pulseon ne sait qu'une chose de la télé — `PowerState: on`. **Le cas
qui rend la faute indéfendable est déjà réel** : la PS5 d'Arthur est branchée sur
cette télé et le collecteur PSN est bloqué, donc une soirée de jeu n'existe que
sous forme de « télé allumée » — elle aurait été rangée en musique.

Trois conséquences à ne pas défaire :

- **« Jeu » reste le classement d'un jeu *sur le Mac***, lu dans son `Info.plist`.
  La console est un écran, pas un contenu. Les deux portent l'or, celui de
  l'appareil PlayStation — elles ne se distingueraient que par leur libellé le
  jour où un jeu Mac et la console tournent la même journée.
- **La couleur d'un rond d'appareil est celle de son arc** dans l'anneau du haut
  et de sa pastille dans la légende. Un rond qui parle d'un écran doit se
  rattacher à cet écran sans qu'on redescende lire un libellé.
- **Le rond n'existe que si l'appareil a servi** : une catégorie à zéro n'est pas
  dessinée. On ne peut pas afficher « Télé — 0 min » les jours d'extinction,
  parce que la base ne distingue pas « éteinte toute la journée » de « le Mac
  n'était pas sur son réseau » — ce serait affirmer un zéro non mesuré (règle 2).
  La carte « Appareils », elle, garde la distinction.

**C'est arrivé le 2026-08-22** : la télé nomme son app quand elle la reconnaît,
et ce temps-là repart vers une vraie catégorie de contenu — `Télé` devient le
repli, comme prévu, **sans rien perdre de l'historique**, la catégorie brute
étant stockée telle quelle. Le repli n'est pas résiduel pour autant : la PS5 est
branchée sur cette télé, et une entrée HDMI reste un écran allumé sans app
visible. Voir « Ce que la télé sait nommer ».

**Une seule rangée de ronds, toujours** (choix d'Arthur le 2026-08-19 :
« je préfère la photo avec une seule rangée »). Passer de cinq catégories à sept
a fait déborder la rangée en fenêtre étroite — 612 points réclamés dans 560 — et
le débordement **entraînait toute la colonne** : les cartes du dessous se
retrouvaient rognées des deux côtés. `ViewThatFits` prend la première des trois
tailles de rond qui tient (48, 40, 32 points) au lieu de replier la rangée.
Invisible à la compilation, invisible en fenêtre large, **trouvé en PNG**.

**Ce que les totaux par catégorie veulent dire, exactement.** Chaque catégorie
est fusionnée sur elle-même : deux apps de dev en parallèle ne comptent qu'une
fois. Mais deux catégories simultanées comptent chacune leur temps — coder en
regardant un film donne du développement *et* de la vidéo. La somme des
catégories peut donc dépasser le `coveredTotal`, exactement comme `summedTotal`
entre appareils. Le seul autre choix serait d'attribuer arbitrairement l'instant
partagé à l'une des deux, ce qui serait une invention.

**Le classement n'est pas décidé dans `PulseonCore`.** Le cœur ne sait pas ce
qu'est un navigateur et n'a pas à le savoir : il reçoit une fonction de
classement. Même règle que pour la définition d'« actif », que chaque collecteur
décide pour son appareil. Le côté macOS résout tout **une fois** dans un
`CategoryAssignment` — une valeur figée — plutôt que d'être interrogé depuis la
boucle d'agrégation : même leçon que les frontières de journées calculées une
fois puis parcourues par dichotomie.

**Les icônes d'apps sont l'équivalent, chez Pulseon, des photos d'une app grand
public.** Une rangée d'icônes se reconnaît en un coup d'œil là où une liste de
noms se déchiffre, et macOS les fournit sans réseau — donc sans rien révéler à
personne. `AppRegistry` les résout par identifiant de bundle et les met en cache
(trouver l'app sur le disque puis la rasteriser ne doit pas se refaire à chaque
image d'une liste qui défile). **Rendre `nil` est une vraie réponse** : une app
désinstallée n'a plus d'icône, un jeu PlayStation n'en a jamais eu. À l'appelant
d'afficher un repli, jamais un carré vide.

**Le trajet complet, parce qu'il traverse trois paquets et que c'est voulu :**
`AppRegistry.iconSource` traduit `NSImage` en `Image` — **c'est là que AppKit
s'arrête**, ces vues servant telles quelles à l'app iOS — `DayBrowser` l'expose,
la fenêtre l'injecte dans l'environnement SwiftUI, et `AppTrail` l'y lit. La
fonction est isolée au fil principal (`NSWorkspace` y vit) et capturée
faiblement : elle vit aussi longtemps que la fenêtre, et garder le registre fort
ferait survivre son contexte SwiftData à la fermeture.

**L'icône précède le nom, elle ne le remplace pas.** Une rangée d'icônes seules
se resserrait en silence sur celles qu'elle savait résoudre : on lisait trois
noms sous deux icônes sans jamais savoir laquelle manquait. Appariées, les deux
formes disent toujours la même chose.

**Ce que les icônes ne rattraperont pas, et il vaut mieux le savoir** : les
identifiants de bundle ne sont en base que depuis que `noteApp` tourne — sur la
machine d'Arthur, le **2026-08-17 à 13 h 16** (relevé dans `ZSTOREDAPP`). Une app
utilisée avant et jamais réactivée depuis n'a **aucune identité** : ni icône, ni
catégorie autre qu'`other`. C'est le cas de « Claude » (82 sessions) et de
« Plans ». Ça se répare tout seul à la prochaine activation, mais les journées
passées gardent le trou. **Ne pas le corriger en devinant l'app d'après son nom
affiché** : c'est la même pente que les catégories déduites d'une ressemblance de
nom, et un faux rangement est pire qu'un vide honnête.

**Les favicons de sites, en revanche, sont un autre sujet** — et le piège est
identifié : appeler une API publique de favicons revient à dire à un tiers quels
sites on visite, ce qui détruit la promesse « rien ne sort de ta machine ».
Solutions propres : embarquer un jeu de logos, ou piocher dans le cache de
favicons du navigateur lui-même (gratuit si on lit déjà son historique). Hors
sujet pour la v1, qui s'en tient aux icônes d'apps.

### Un seul collecteur, ou la journée de 51 heures

Le 2026-08-18, la fenêtre annonçait **51 h de Mac sur une journée de 2 h**. La
cause n'était pas un calcul : **deux Pulseon tournaient**, lancés à une seconde
d'intervalle à l'ouverture de session — l'un par le `LaunchAgent`, l'autre par
un élément d'ouverture ajouté à la main dans Réglages Système. Le journal
système le dit sans ambiguïté (`log show --predicate 'process == "Pulseon"'`,
deux PID vivants en parallèle) ; `sfltool dumpbtm` montrait les deux
inscriptions, `app` et `legacy agent`.

**Le dégât n'est pas le doublement qu'on imagine.** Chaque instance avait son
propre `ModelContainer` sur le même fichier. À chaque activation d'app, les deux
insèrent une session ; mais `openSession(for:)` ne rend que la plus récemment
ouverte, donc l'une des deux est fermée et l'autre reste ouverte **pour
toujours**. Vingt épaves en une matinée. Et comme une session ouverte est bornée
à l'horizon d'activité, chacune « courait » encore : vingt sessions parallèles
depuis 9 h.

Pire, et invisible : au retour d'inactivité, `handleActivation` tombait sur une
de ces épaves et la fermait à l'heure courante. Des heures de machine éteinte
sont devenues du temps d'écran **écrit en base**, indiscernable du reste. Une
session de 213 minutes attribuée à une app qui n'a jamais tourné aussi
longtemps. C'est ce qui a demandé une réparation de la base, pas seulement un
correctif de code.

Trois défenses, à des étages différents — aucune ne remplace les autres :

- **`InstanceLock`** ferme la cause. Un `flock` sur `collector.lock`, à côté de
  la base : le second processus n'obtient pas le verrou et sort. **Pas de
  comptage via `NSRunningApplication`** — les deux instances ont démarré à
  300 ms d'écart, avant que LaunchServices ne les connaisse toutes les deux, et
  l'exécutable SwiftPM n'a pas de bundle identifier hors de son `.app`. Le noyau,
  lui, ne se trompe pas, et il rend le verrou tout seul à la mort du processus,
  y compris sur un `kill -9`. Même esprit que `Heartbeat` : c'est le fichier qui
  porte l'information, pas son contenu.
- **`closeDanglingSessions` répare *toutes* les sessions ouvertes** de chaque
  appareil, plus seulement la dernière. Un collecteur seul ne peut en laisser
  qu'une ; c'est gratuit dans ce cas, et ça ferme le trou dans l'autre.
- **`Lane.total` fusionne ses propres intervalles** au lieu de les additionner :
  **un appareil ne peut pas être allumé deux fois en même temps.** Le
  chevauchement a un sens entre appareils — c'est tout l'objet de `summedTotal` —
  jamais à l'intérieur d'un seul. L'écran n'aurait jamais dû pouvoir afficher
  « Mac : 51 h », quelle que soit la cause en amont.

**Un `@State` avec valeur par défaut est évalué avant le corps d'`init`.** Écrire
`@State private var engine = CollectionEngine()` aurait ouvert la base et lancé
la collecte *avant* le contrôle d'instance unique. La valeur est donc assignée à
`_engine` à la fin d'`init`, une fois le verrou obtenu.

**Ce que la réparation de la base a fait, et pourquoi comme ça.** Deux invariants
suffisent à reconstituer la vérité : un même événement d'activation n'a produit
qu'une session réelle, et sur un même appareil deux sessions ne se chevauchent
jamais. Entre deux copies, **la vraie fin est la plus tôt** — l'autre a été
fermée après coup par un retour d'inactivité. Les copies sont ramenées à une
**durée nulle** plutôt que supprimées : `clampedBlocks` écarte déjà
`duration > 0`, donc elles disparaissent de tous les agrégats sans qu'on efface
une ligne qu'un processus a vraiment écrite. 35 sessions corrigées, 13,5 h de
durée inventée retirées, la journée retombant à 2 h 08. Signe que le modèle était
juste : une fois les copies appariées, la règle de non-chevauchement n'a plus
rien eu à corriger.

**Leçon transposable** : le premier symptôme visible (« 51 h ») était le moins
grave. Une donnée fausse mais *fermée* ne se distingue plus d'une donnée vraie —
c'est elle qu'il faut chercher, pas celle qui saute aux yeux.

### L'icône de l'app

Livrée le 2026-08-19, **d'après une référence fournie par Arthur**
(`Design/icon-reference-2026-08-19.jpg`, générée par Gemini) : carré arrondi
bleu nuit, anneau en dégradé bleu → violet coupé à gauche et à droite, un
battement qui le traverse, et des repères de cadran à 12 h, 3 h et 6 h — celui
de 9 h manque parce que le battement entre par là. Jusqu'ici l'app portait le
rectangle blanc générique de macOS.

**Elle est dessinée en SwiftUI, pas importée.** `PulseonMark` et
`PulseonAppIcon` vivent dans `PulseonUI`, en fractions du côté et jamais en
points : la même vue rend le 1024 du Finder et le 16 d'une liste. Un PNG
embarqué serait flou au premier écran Retina et illisible en petit ; et comme
c'est du SwiftUI sans AppKit, l'app iOS la réutilisera telle quelle.

**Chaque taille est redessinée, jamais réduite depuis le 1024.** Un trait de
6 % du côté fait 62 points en 1024 et 1 point en 16 : la version réduite
devient une bouillie grise là où la vue redessinée reste un anneau.
`Scripts/make-icon.sh` rend les dix entrées de l'iconset puis appelle
`iconutil` ; le `.icns` est **commité** (`Resources/AppIcon.icns`) pour que
`build-app.sh` n'ait besoin de rien d'autre que du dépôt.

**Le défaut trouvé en PNG et par rien d'autre** : au premier jet, le pic du
battement montait jusqu'à l'anneau. Croisé avec la ligne horizontale, le dessin
devenait un **réticule de visée** — reconnaissable, mais ce n'était pas un
pouls. L'amplitude est bornée à un quart de tour de part et d'autre de l'axe :
le battement reste contenu *dans* le cadran. Encore un défaut qu'aucun test ne
pouvait voir.

**L'épaisseur du trait est choisie sur planche, pas à l'estime.** Le premier jet
tenait 6,2 % du côté — « c'est peut-être un peu trop épais ?  », et c'était
juste. Quatre valeurs rendues côte à côte à cinq tailles : en dessous de 4 %,
l'anneau devient fragile dès 32 points et le pic se casse. **Retenu : 4,8 %.**
La même planche sert à toute retouche future — `Scripts/make-icon.sh` l'ouvre.

**Trois autres formes ont été dessinées puis écartées le même jour**, Arthur
ayant choisi le cadran (« j'aime beaucoup la version Cadran ! »). À ne pas
reproposer :

| Forme | Ce qu'elle donnait | Pourquoi elle n'est pas retenue |
|---|---|---|
| **épuré** | le cadran sans ses repères, battement traversant symétrique | plus net en petit, mais Arthur veut sa référence |
| **contenu** | anneau fermé, battement entièrement à l'intérieur | l'anneau redevient un cercle ordinaire |
| **parts** | l'anneau *du dashboard*, découpé en parts inégales | demande de connaître l'app pour être lu, or une icône se lit avant d'ouvrir |

**Les repères disparaissent en dessous de 48 points, et c'est assumé** : à cette
taille ils ne pèsent plus qu'un pixel, quand le cercle et le pic tiennent
encore. Une marque doit se dégrader en perdant son détail, pas sa silhouette.
Et ils **ne doivent jamais devenir une graduation** : Pulseon n'affiche pas un
horaire qu'il n'a pas mesuré, jusque dans son icône.

**Les couleurs de l'icône sont les seules `static let` du thème**, et c'est
assumé : une icône vit dans le Dock et le Finder, pas dans nos fenêtres — elle
est la même en clair et en sombre, donc elle n'a rien à résoudre depuis un
`colorScheme`. Le bleu et le violet ne remplacent pas l'or : **l'or désigne du
temps mesuré à l'intérieur de l'app**, où il s'oppose au fond ; une icône n'a
rien à désigner, elle doit se reconnaître dans une rangée d'autres icônes.

**Les proportions sont celles d'Apple, pas des valeurs choisies à l'œil** : sur
une toile de 1024, le carré occupe 824 points et son rayon vaut 185,4. Une icône
dessinée bord à bord paraît trop grosse à côté des autres du Dock.

**Où elle se voit, et où elle ne se voit pas** : `LSUIElement` retire l'app du
Dock, donc l'icône apparaît dans le Finder, `/Applications` et ⌘Tab — et dans le
Dock seulement pendant qu'une fenêtre est ouverte, quand `DockPresence` bascule
en `.regular`. La barre de menu, elle, garde le symbole système `waveform`, qui
dit la même chose en monochrome : une icône couleur y serait hors sujet.

### Empaquetage et démarrage automatique

`Scripts/build-app.sh` fabrique `Pulseon.app` à partir de l'exécutable
SwiftPM, sans projet Xcode : arborescence du bundle, `Info.plist`, signature
ad-hoc. `LSUIElement` y vaut vrai — l'agent vit dans la barre de menu, pas
dans le Dock.

```
./Scripts/build-app.sh
cp -R .build/release/Pulseon.app /Applications/
open /Applications/Pulseon.app
```

Le démarrage automatique s'active ensuite depuis le menu de l'app. **Et
seulement depuis là** : l'ajouter *en plus* dans Réglages Système > Général >
Ouverture lance deux Pulseon, ce qui est arrivé le 2026-08-18 (voir « Un seul
collecteur »). `InstanceLock` empêche désormais le second de collecter, mais le
doublon reste à retirer — pour vérifier, `sfltool dumpbtm | grep -A6 Pulseon` ne
doit montrer qu'une inscription, de type `legacy agent`.

**`SMAppService` est inutilisable ici, et ça a été vérifié à l'exécution.**
L'API moderne exige une **vraie signature** : une signature ad-hoc n'en est
pas une. Depuis `/Applications`, lancée par LaunchServices, avec le bon
bundle identifier, `status` renvoie quand même `notFound` — la machine n'a
aucune identité (`security find-identity` : zéro identité valide).

D'où le repli sur un **`LaunchAgent`** : un `.plist` déposé dans
`~/Library/LaunchAgents`, que launchd lit à chaque ouverture de session.
Aucune signature, aucun compte, aucun privilège administrateur, et pas de
sous-processus — écrire le fichier suffit, launchd le découvre seul.
`KeepAlive` reste à faux pour que « Quitter Pulseon » quitte vraiment.

À retenir pour la suite : **le compte Apple payant conditionne CloudKit
(étape 5), pas le démarrage automatique.** Le jour où une vraie identité
existe, revenir à `SMAppService` est la bonne cible — c'est l'API supportée,
et elle apparaît proprement dans Réglages > Général > Ouverture.

**Limite restante** : sans signature Developer ID, l'app ne s'installe pas
sur une autre machine sans avertissement Gatekeeper. Sans objet tant que
Pulseon ne tourne que sur le Mac d'Arthur.

### Une vraie app, mais seulement le temps d'une fenêtre

`LSUIElement` ne retire pas seulement l'icône du Dock : il retire **la barre de
menus**. Constaté à l'usage le 2026-08-16 — la fenêtre du dashboard s'ouvrait
sans menu « Pulseon », donc sans menu Fenêtre, donc sans ⌘W, sans plein écran,
et sans ⌘Tab pour la retrouver une fois passée derrière une autre app.

**Retirer `LSUIElement` coûterait plus cher que ça ne rapporte** : le réflexe
⌘Q arrêterait la collecte, et une app de mesure qui s'arrête avec sa fenêtre ne
mesure plus rien — c'est la règle fondatrice du projet. `DockPresence` bascule
donc en `.regular` tant qu'une fenêtre vit, et revient en `.accessory` ensuite.
Au démarrage, rien n'apparaît : ⌘Q n'est jamais à portée de doigt.

Deux pièges tenus dans le code, tous deux invisibles à la compilation :

- Au moment de `willCloseNotification`, la fenêtre qui se ferme est **encore
  visible et encore dans `NSApp.windows`**. Sans l'exclure explicitement, on
  reste en `.regular` pour toujours et l'icône Dock ne part plus jamais.
- **L'élément de barre de menu porte lui aussi une fenêtre.** La compter
  allumerait l'icône Dock en permanence, ce qui annule `LSUIElement`. D'où le
  critère `.titled`, seul point testable de la classe et donc `nonisolated`.

#### L'app ne se retire qu'une fois la fenêtre partie

Question d'Arthur le 2026-08-23 : « quand je fais ⌘W ou ⌘M, les animations ne
sont pas du tout fluides, pourquoi ? ». La réponse tenait en une hypothèse
plausible — `sync` retombe en `.accessory` depuis `willCloseNotification`, donc
**pendant** l'animation — et cette hypothèse était fausse sur les chiffres.

**Ce que la mesure a dit** (banc `Tools/Preview`, cible `Bench` : il ouvre puis
ferme la vraie `DayDashboard` dans une fenêtre de 1512 × 949, avec un tick de
2 ms sur le fil principal ; 8 cycles par mode) :

| | avant | après | témoin sans bascule |
|---|---|---|---|
| Trou du fil principal à la fermeture | 12,1 ms | **5,7 ms** | 4,4 ms |
| Images perdues (> 16,7 ms) | 0 | 0 | 0 |
| Coût de `setActivationPolicy` | 5,9 ms | 3,9 ms | — |

**Aucune image perdue, ni avant ni après : le fil principal n'a jamais été la
cause.** L'écran filmé le confirme — l'animation de fermeture rend 6 images en
83 ms (72 im/s), et la réduction 25 images en 442 ms (57 im/s), sans un seul
gel. Ce qui change avec le correctif n'est donc pas une vitesse mais **un
ordre** : la fenêtre s'efface d'abord, l'icône du Dock et la barre de menus
partent 250 ms plus tard, au lieu de disparaître dans la même image.

Trois choses à ne pas réapprendre :

- **Les 615 ms de fil principal bloqué à la réduction sont l'animation
  « genie » elle-même**, pas un défaut : `miniaturize(nil)` ne rend la main
  qu'à la fin, et le chiffre est identique quand on ne touche jamais à la
  politique d'activation (mode témoin). Un blocage du fil principal n'est pas
  une image perdue — la fenêtre réduite est une capture, dessinée par le
  WindowServer.
- **Le délai est mesuré, pas estimé** : 83 ms d'animation, 250 ms de grâce.
  Il est annulé dès qu'une fenêtre rouvre, et **revérifié à l'échéance** —
  l'annulation seule ne couvre pas une fenêtre ouverte sans devenir clé.
- **Ce correctif ne se teste pas hors session graphique**, comme le reste de
  la classe : `counts` reste le seul point pur. C'est le banc qui vérifie, et
  c'est pour ça qu'il est commité plutôt que jeté après usage.

**Et une leçon sur la vérification** : `lsappinfo info -only ApplicationType`
répond `Foreground` dès que l'app est active, *quelle que soit* sa politique
d'activation. Ça ne distingue pas `.regular` de `.accessory` — le relevé
automatique n'a rien prouvé, c'est l'œil d'Arthur qui a validé. À retenir avant
de bâtir une sonde : vérifier qu'elle mesure bien ce qu'on croit.

### Le mouvement, et le sens dans lequel il a le droit d'échouer

Arthur, le 2026-08-24, sur l'app installée : elle « fait figé, pas fini ». Le
diagnostic n'était pas une impression — **zéro animation dans tout `PulseonUI`**,
et deux raccourcis clavier en tout (⌘J, ⌘Q). Un anneau apparaissait d'un bloc,
une journée en remplaçait une autre par saut.

Ce qui bouge désormais : l'anneau **se trace en s'enroulant** à l'ouverture, le
total monte avec lui, et les journées **glissent dans le sens de la navigation**
— sans direction, reculer et avancer produisent la même transition et
l'animation ne dit plus rien. Au clavier : ←/→ pour la journée, ⌘1/⌘2/⌘3 pour
les onglets, ⌘T pour revenir à aujourd'hui.

**La décision qui compte est la valeur par défaut : le mouvement est éteint.**
`\.pulseonMotion` vaut `false`, et seule la fenêtre de l'app l'allume. Une
animation d'apparition part d'un état vide — anneau à zéro, chiffre à zéro — or
`ImageRenderer` rend une image **synchrone**, sans faire avancer une seule
image : une preview aurait capturé cet état et sorti un **anneau vide**. On
aurait cru à un bug de dessin, et surtout on aurait perdu l'outil qui trouve la
plupart des vrais défauts de ce projet. En partant de `false`, le repli est
« tout est dessiné », jamais « rien n'est dessiné » — même discipline que
partout : un doute se résout du côté qui montre ce qui a été mesuré.

Trois détails qui ne se devinent pas :

- **`Text` ne s'interpole pas.** SwiftUI ne sait pas animer entre deux chaînes ;
  c'est `Animatable` qui fait le travail, en interpolant `animatableData` et en
  redemandant le corps à chaque image. Et en Swift 6 la conformance doit être
  `nonisolated` — `View` porte l'isolation au fil principal, or le moteur
  d'animation interpole depuis chez lui.
- **L'anneau ne se rejoue pas à chaque relecture.** La journée est relue chaque
  minute ; rejouer le tracé ferait clignoter l'écran tout seul pendant qu'on le
  regarde.
- **Les flèches ne sont pas des `keyboardShortcut`.** Une flèche seule n'est pas
  un raccourci de menu, et l'affecter à un bouton invisible la volerait à tout
  champ de saisie. `onKeyPress` la rend au premier répondant qui en veut. Les
  raccourcis à modificateur, eux, passent par des boutons cachés plutôt que par
  `.commands` : la barre de menus de cet agent n'existe que le temps d'une
  fenêtre ouverte (voir `DockPresence`), donc un raccourci porté par la vue vit
  exactement aussi longtemps que la fenêtre qu'il pilote.

**Une entorse assumée, et bornée.** Le compteur qui monte affiche pendant une
demi-seconde des valeurs qui n'ont pas été mesurées — contraire à la règle
« ne jamais afficher un chiffre non mesuré ». Elle est tolérée le temps d'un
geste d'ouverture, et **la barre de menu ne compte jamais** : c'est le seul
endroit où le total est lu en continu, donc le seul où un chiffre faux aurait le
temps d'être cru.

### Ce qu'Arthur reproche à l'app, et ce qui reste à faire

Le 2026-08-24, questionné sur ce que « bof à utiliser » voulait dire, Arthur a
retenu **deux** raisons sur quatre : « ça fait figé, pas fini » et « je n'ai pas
de raison de l'ouvrir ». Elles ne se réparent pas de la même façon.

La première est traitée ci-dessus, et elle se referme complètement. **La seconde
est le vrai sujet, et aucune animation ne la règle** : l'app est un miroir qu'on
a déjà vu. Ce qui donne une raison de revenir, c'est quelque chose qui **change**
ou quelque chose à **explorer**. Les trois chantiers retenus avec lui, dans
l'ordre :

1. ~~**Le mouvement et le glissement**~~ — livré (PR #51).
2. **L'année en anneaux** — 365 petits ronds en damier, un par jour.
   `buildPeriod` est déjà générique, c'est surtout du dessin. C'est l'objet qu'on
   ouvre pour le plaisir, et celui où la signature visuelle du projet paye le
   plus.
3. **La fiche d'une app** — cliquer sur « Xcode » n'importe où mène à son écran :
   total, évolution semaine par semaine, et à quelles heures elle sert. C'est ce
   qui fait passer l'app de « papier peint » à « chose qu'on interroge » — **rien
   n'est cliquable aujourd'hui**, les onze boutons de `PulseonUI` sont tous de la
   navigation.

Deux autres idées gardées de côté, présentées et non retenues en priorité : le
**menu de la barre redessiné** (mini-anneau, apps du moment avec leurs icônes —
c'est l'écran le plus vu et le seul jamais dessiné) et **la grille heure × jour**
(« tu es sur ton Mac entre 14 h et 18 h, la télé après 21 h ») — le seul de la
liste qui apprendrait à Arthur quelque chose qu'il ne sait pas déjà.

### La direction artistique : éditoriale, arrêtée le 2026-08-24

**Choisie par Arthur sur planche** — trois directions rendues côte à côte sur la
même journée, à la taille de sa fenêtre : « la version editorial est vraiment
sympa ! j'adore la editorial sombre/light ».

Elle est née d'un reproche précis. Devant une première passe qui n'avait touché
qu'aux marges et à la disposition : « **tu m'as rajouté une feature ok mais
qu'en est-il du design de l'app ? le front n'a pas bougé ?** ». Il avait raison,
et c'est la leçon de méthode de la séance : **régler des marges n'est pas une
direction artistique**. Une DA change ce qu'on voit *avant* de lire.

Ce qu'elle est :

- **Pas de cartes.** Un filet fin annonce chaque bloc, et le bord gauche
  s'aligne sur la marge de la page au lieu d'un retrait de carte. L'écran cesse
  d'être une grille de boîtes et devient une page — la suite logique de la
  référence donnée dès le 2026-08-16 : *la donnée est le design*.
- **Les titres portent l'or**, à 21 points, resserrés. Sans cadre, c'est le titre
  seul qui dit « nouvelle rubrique » : l'or cesse d'être décoratif, il structure.
- **Les libellés de ligne passent de 13 à 16 points**, les durées de 15 à 18.
  C'est le second levier le plus visible après le grand nombre : à 13 points une
  liste se lit « tableau de bord », à 16 elle se lit « page ».
- **Les jauges s'affinent de 6 à 3 points.** Sans cadre autour, une jauge épaisse
  redevient l'élément le plus lourd de l'écran et vole la vedette au chiffre.
- **Le total au centre de l'anneau passe de 30 % à 38 % du cœur** — le levier le
  plus visible de tous.

**Deux directions ont été rendues à fond puis écartées le même jour**, à ne pas
reproposer :

| Direction | Ce qu'elle donnait | Pourquoi elle n'est pas retenue |
|---|---|---|
| **pleine** | cartes pleines, filet, ombre portée — ce qui existait | c'est elle qu'Arthur trouvait « trop simple » : un tableau de bord parmi d'autres |
| **verre** | surfaces translucides, champs de couleur violet/bleu, reflet, arête asymétrique | plus séduisante au premier regard, mais c'est une mode — et une mode datée se voit plus vite qu'une composition sobre |

**Le type `PulseonSkin` qui permettait de les rendre côte à côte a été
supprimé** une fois le choix fait. Une option qui survit à la décision qu'elle
servait devient une dette — même leçon que `RingScale`, retiré le jour où plus
personne ne l'appelait.

**Ce que le verre a appris au passage, et qui resservira** : au premier jet il
était indistinguable de la peau pleine. Ce qui manquait n'était pas la
transparence mais **le bord et le reflet** — un verre se reconnaît à ses arêtes.
Et un translucide posé sur un fond presque uni ne donne qu'un gris sale : il lui
faut de la matière à réfracter, d'où les deux champs de couleur du fond. Même
famille que l'accent unique décliné en opacités, qui donnait un olive sali.

**Un défaut trouvé en PNG, et qui guettait déjà l'ancienne direction** : dès que
la taille du grand nombre montait, le total passait à la ligne — « 1h41 » puis
« 1 » en dessous. Un total à deux chiffres d'heures dans une fenêtre étroite
l'aurait déclenché sans qu'on change quoi que ce soit. Les chiffres rétrécissent
désormais au lieu de se couper.

**Un second, révélé par le seul écran assez court pour ça** : le fond ne couvrait
que le contenu. Sur la chronologie, dont la carte est courte, la fenêtre
affichait une bande blanche au-dessus et en dessous — invisible sur l'écran du
jour, qui remplit sa hauteur. Les trois écrans bornent maintenant leur hauteur et
s'alignent en haut.

### Le battement de la journée

Le motif de l'icône, **fait de vraies données**. Pulseon portait un battement
dans sa marque et dans le symbole de sa barre de menu, et ne l'avait nulle part
dans ses écrans.

`DayPulse` (dans `PulseonCore`, pur et testé) donne, pour chaque quart d'heure,
la **part** de cette tranche passée devant un écran. Trois règles y sont tenues :

- **les appareils sont fusionnés, jamais additionnés.** Regarder la télé en étant
  sur son Mac ne fait pas 200 % d'une tranche : c'est `coveredTotal` contre
  `summedTotal`, et la leçon de la journée de 51 heures appliquée à un nouveau
  calcul ;
- **une source à compteur est écartée** (règle 1). La PlayStation n'a aucun
  horaire : la placer dans une tranche inventerait une heure. La carte le **dit**,
  sans quoi son absence se lirait comme un creux ;
- **la longueur du jour est fournie**, jamais supposée égale à 86 400 — une
  journée de changement d'heure décalerait toutes ses tranches.

**C'est le seul endroit où la palette de l'icône entre dans l'app**, et c'est
une exception raisonnée : le bleu et le violet sont ailleurs réservés à la
marque, l'or au temps mesuré. Ici la **forme** est celle de la marque, donc elle
en porte les couleurs — ce n'est pas une teinte de plus dans le vocabulaire des
données, c'est la marque qui se montre une fois.

**Il comble le vide qu'Arthur voulait bouché**, en bas de la colonne gauche —
~290 points sur sa fenêtre. **Pas avec du remplissage** : en répondant à la
question du projet, *quand*.

**Un défaut trouvé en PNG** : la carte annonçait « le plus dense vers 08:45 »
pour une journée dont le cœur était l'après-midi. Une journée de travail met
vingt tranches à 100 %, et « la plus haute » en désigne alors une au hasard.
`densestWindow(spanning:)` cherche la vraie fenêtre de deux heures la plus
chargée, et **garde la plus précoce à égalité** — arbitraire mais stable, sans
quoi deux ouvertures de la même journée afficheraient deux heures différentes.

### Ce que la barre de menu affiche

Le libellé porte **l'icône et le total du jour, qui défile à la seconde**
(`3h07:12`). Un compteur qui bouge en permanence en haut de l'écran est
confrontant par construction, et c'est voulu : macOS dit *combien* une fois
par semaine dans un écran que personne n'ouvre.

**`Label(_:systemImage:)` ne marche pas dans un `MenuBarExtra`**, et ça a
coûté une session : le libellé y est traité comme une icône de barre de menu,
donc le texte est **jeté en silence**. Le total n'apparaissait qu'une fois le
menu ouvert. Il faut un `Text` qui *interpole* l'image
(`Text("\(Image(systemName:)) \(titre)")`) pour garder les deux.

Le rafraîchissement vit indépendamment de la collecte : suspendre la collecte
ne doit pas figer l'affichage de ce qui est déjà enregistré.

**Défiler à la seconde ne coûte ni requête ni écriture.** Deux timers, pas un :
le disque est relu chaque minute et gardé en cache, tandis que le tick d'une
seconde ne fait qu'une addition — `DayDigestBuilder.build` borne les sessions
ouvertes sur le `now` qu'on lui passe, donc avancer d'une seconde ne demande
rien à SwiftData. Le titre n'est réassigné que s'il change, pour ne pas
réveiller les vues quand le compteur est gelé.

**L'horizon d'affichage est le dernier instant d'activité *observée*, jamais
l'heure courante** (`ActivityMonitor.observedActivityEnd`). La session en cours
est fermée *rétroactivement*, donc un compteur qui avancerait jusqu'à `now`
reculerait à chaque pause — et à l'écran, **reculer ressemble à une panne**.
Il ne peut pas reculer ici parce que l'affichage et la fermeture de session
appellent la **même** fonction (`activityEnd`), pas deux calculs qui se
ressemblent. Cet horizon vient du moniteur et non d'une fonction pure appelée
n'importe où, parce que lui seul se souvient du dernier instant où une vidéo
tournait : sans cette mémoire, la fin d'un film ferait dégringoler le compteur
de deux heures. Effet de bord gagné : l'affichage interrogeant chaque seconde,
la fin de session écrite en base est précise à la seconde au lieu du tick de
15 s.

**Une pause de moins d'une minute compte comme du temps d'écran**
(`graceInterval`), et c'est une correction de fond, pas un ajustement
d'affichage. Ne compter que les instants portant un événement clavier
découpait la journée en confettis et sous-comptait la lecture et la réflexion
— précisément les moments où on est le plus devant l'écran. Le collecteur
tolérait déjà la pause (la session ne se fragmente pas avant `idleThreshold`,
2 min) mais reprenait d'une main ce qu'il donnait de l'autre en fermant au
dernier geste.

L'écart entre les deux seuils **n'est pas un réglage arbitraire** : la grâce
(1 min) doit rester plus courte que le seuil d'inactivité (2 min) pour que
l'affichage soit déjà figé sur sa valeur définitive quand la session se ferme.
Les rapprocher rouvrirait le recul. Prix assumé et borné : partir sans rien
dire compte une minute de trop — préférable à un compteur qui a l'air cassé
dès qu'on lâche la souris deux secondes. La grâce s'ajoute au dernier *geste*,
jamais à la vidéo : une lecture qui s'arrête est un signal net.

`DurationFormat` (dans `PulseonCore`, donc partagé avec la future app iOS)
tient les trois formes : vivante pour la barre (`3h07:12`, puis `7m12`, puis
`42s`), resserrée (`3h07`) et longue pour le menu (`3 h 07`). L'unité `h`/`m`/`s`
n'est pas décorative : c'est elle qui empêche de lire le total comme l'horloge
juste à côté. La barre de menu est un espace partagé avec toutes les autres
apps, chaque caractère y coûte. **Tout est tronqué, jamais arrondi** : afficher
1 h à 59 min 40 annoncerait du temps qui n'a pas eu lieu. Quand la lecture
échoue, la barre affiche un tiret et pas un zéro.

Un vrai *Widget* macOS (centre de notifications, bureau) est autre chose : une
extension d'app, qui suppose un projet Xcode et une signature — même mur que
CloudKit.

### Le dashboard : l'anneau de la journée

Vit dans **`PulseonUI`**, un paquet à part et non dans l'app macOS, parce que
ce sont *les mêmes vues* qui serviront à l'app iOS : le jour où la cible iOS
existera, elle consomme ce paquet sans qu'une ligne de dessin soit réécrite.
D'où l'interdiction d'y toucher à AppKit, qui n'existe pas sur iPhone —
`.buttonStyle(.link)` s'y est déjà fait refuser.

**Direction visuelle : la maquette d'Arthur, livrée le 2026-08-17** après trois
propositions écartées. Fond bleu nuit profond, cartes à grand rayon, deux
accents (l'or et le bleu nuit de l'icône), l'anneau en tête, puis des lignes
denses — pastille, libellé, durée, part, jauge. Le détail vit dans la skill
`pulseon-design` ; ce qui suit est ce qui a demandé une décision technique.

**L'anneau dit une composition, jamais une progression.** La maquette portait un
objectif quotidien (« / 5h Daily Goal »), un badge « On Track » et un score
« objectif tenu 6 jours sur 7 ». Arthur les a retirés en validant le dessin :
« on reste sur une application sans jugement ». `RingLayout` fait donc **toujours
le tour complet**, ses arcs étant des parts de la journée. C'est ce qui rend
l'anneau compatible avec une app qui mesure sans dire si c'est bien.

**L'anneau principal reste seul en tête, et les catégories sont une rangée de
petits ronds en dessous** (`DayCategoryRings`) — un rond par catégorie, taille
proportionnelle à la durée, glyphe au centre. **Même concept que la rangée de la
semaine**, à un cran plus fin : là-bas un rond par journée, ici un rond par
catégorie.

**Deux formes ont été essayées et écartées le même jour, et il vaut mieux savoir
pourquoi :**

- **Une couronne intérieure concentrique.** Première question d'Arthur devant
  l'app installée : « à quoi correspond le deuxième anneau ? ». **C'est la
  question qui est le résultat, pas la réponse.** Sur sa machine un seul appareil
  est branché, donc la couronne extérieure était un cercle uni pendant que
  l'intérieure était bariolée : au premier regard, c'est la petite qui avait
  l'air d'être le graphique. Leçon transposable : **une forme qui demande une
  légende pour être comprise n'est pas plus dense, elle est plus opaque.**
- **Deux anneaux pleins côte à côte**, chacun titré. Lisible, mais il fallait
  écrire un chiffre au centre du second, or la somme des catégories n'est pas
  comparable au total de la journée — deux grands nombres côte à côte invitent à
  les comparer, et l'un des deux paraît faux. Écarté par Arthur : « je ne suis
  pas trop fan ».

La rangée de ronds ne pose ni l'un ni l'autre problème : **chacun porte sa propre
durée écrite au-dessus, et aucun ne prétend résumer les autres.**

**Le cœur de chaque rond porte le logo de l'app qui a dominé la catégorie**, et
le glyphe de la catégorie à défaut. `CategoryTotal.entities` étant déjà classé
par durée, la dominante est la première — rien à recalculer.

**Le repli n'est pas un cas rare traité par acquit de conscience, c'est le cas
normal d'au moins une catégorie.** « Jeu » sur PlayStation n'aura jamais d'icône
côté Mac ; une app désinstallée n'en a plus ; et surtout, une app utilisée avant
que `noteApp` ne tourne (le 2026-08-17 à 13 h 16 sur la machine d'Arthur) n'a
aucun identifiant de bundle en base, donc aucune icône — voir « Ce que les icônes
ne rattraperont pas ». Le rendu de démonstration le montre d'ailleurs sans le
chercher : Xcode et Brave sortent en vrai, IINA, Slack et Elden Ring retombent
sur leur glyphe. **Jamais de carré vide.**

**Tous les petits ronds de l'app font la même taille** — ceux des catégories
comme ceux des journées de la semaine. Décision d'Arthur le 2026-08-19 : « je me
fiche de la logique le rond grossit plus le temps est grand, laisse-les de la
même taille », étendue le même jour à la rangée de la semaine.

**Le diamètre a d'abord encodé la durée** (surface ∝ temps, donc diamètre en
racine carrée, parce que l'œil compare des surfaces). C'était défendable — un
anneau fait toujours le tour, donc la taille était le seul canal restant — mais
**la durée est déjà écrite au-dessus de chaque rond**, et une rangée de ronds
inégaux se lit moins bien qu'une rangée régulière. `RingScale`, le type pur qui
portait la règle, a donc été **supprimé** : plus aucun appelant, et une API que
personne n'appelle ressemble à une feature livrée. Ses cinq tests sont partis
avec.

**Ce qui reste vrai, et qui vaudra pour toute quantité future : jamais par le
remplissage.** Un anneau rempli aux deux tiers se lirait « objectif atteint à
66 % », or l'objectif quotidien a été retiré de la maquette et la règle « aucune
comparaison ne juge » l'interdit. Si une quantité devait un jour passer par la
forme, ce serait par la taille, jamais par un tour incomplet.

**`PeriodPresentation.busiestDay` a été supprimée au passage** : écrite dans la
PR #32, jamais lue par une vue. Exactement le symptôme que ce projet traque —
chercher l'appelant, pas la déclaration.

**Une légende de couleurs sous l'anneau principal** (`DeviceLegend`), la même que
sur l'écran de la semaine : sans elle, il faut descendre à la carte « Appareils »
pour savoir ce que dit une couleur, alors que la couleur est justement ce qu'on
lit d'un coup d'œil.

Il garantit aussi qu'**une part minuscule reste visible** (plancher de 1,2 % de
tour) : une minute sur huit heures fait 0,2 % de tour, soit un arc invisible, et
l'afficher à sa taille exacte reviendrait à dire qu'elle n'a pas eu lieu. Même
raisonnement que le plancher de 2 points de `TimelineGeometry`. Le plancher est
**pris sur les grandes parts et jamais ajouté au tour**, sinon la somme
dépasserait 1 et le dernier arc repasserait sur le premier.

**L'anneau règle aussi le défaut de conception signalé par Arthur** — « à
plusieurs devices c'est illisible ». Une piste par appareil allonge l'écran et
transforme les simultanéités en mur dès le troisième ; un appareil de plus n'est
ici qu'un arc de plus, à hauteur constante.

**La timeline en multipiste a été supprimée**, à sa demande : « j'aime bien le
rond plutôt que la timeline chrono qu'on a ». `TimelineGeometry` reste, pure et
testée, pour l'onglet Timeline de la maquette. Attention le jour où il se
construira : la maquette y place la PlayStation à 12:20, or elle ne connaît pas
ses horaires.

**Un pourcentage non nul ne s'affiche jamais « 0 % ».** Trois minutes dans une
journée font 0,4 %, tronqué à zéro juste à côté d'une durée non nulle — trouvé
en regardant le PNG, pas par un test. En dessous de 1 %, « < 1 % ».

**Les couleurs portent de l'information** : une par appareil et une par
catégorie, tenues partout. **Aucune n'est rouge** — le rouge dirait « trop ».

**La palette est une valeur, pas des constantes globales.** La maquette existe en
clair *et* en sombre, or une couleur en `static let` ne peut pas suivre
l'apparence du système et `PulseonUI` n'a pas le droit d'appeler AppKit pour la
résoudre. `PulseonTheme.palette(for:)` rend donc un `PulseonPalette` depuis le
`colorScheme`, que les vues reçoivent en paramètre — ce qui les rend au passage
rendables hors écran par la preview.

**Voir les vues sans lancer l'app.** `ImageRenderer` rend n'importe quelle vue
en PNG hors écran, ce qui permet de regarder le résultat sans fenêtre, sans
simulateur, et sans lancer une seconde instance du collecteur — qui écrirait
dans la même base.

**`ImageRenderer` ne rend rien de l'intérieur d'un `ScrollView`**, et le piège
s'est refermé une deuxième fois en construisant cet écran : la sortie est un
rectangle uni de la couleur du fond, ce qui ressemble à un bug de dessin alors
que la vue est simplement hors champ. D'où `DayDashboardContent`, séparé du
conteneur défilant et rendable seul. **Toute vue défilante doit garder son
contenu extractible**, sinon elle est invisible à la preview.

**La preview écrivait ses catégories à la main**, et ne pouvait donc pas voir un
bug de classement : elle décrivait le résultat attendu au lieu de le calculer.
Au premier rendu du changement ci-dessus, elle affichait encore l'ancien
classement — la vue était juste, l'image mentait. Elle passe désormais par le
vrai `CategoryDigestBuilder`, et seul le dictionnaire d'apps y est écrit à la
main. **Une preview qui ne traverse pas le code testé ne vérifie rien.**

`TimelineGeometry` tient le calcul de placement horaire, séparé des vues pour
être testable sans simulateur — même raison que `PulseonCore`. La longueur du
jour lui est **fournie**, jamais supposée égale à 86 400 : les journées de
changement d'heure font 23 ou 25 h.

`DayBrowser` (dans `PulseonMacKit`) choisit la journée affichée et va la
chercher. Il interdit de naviguer dans le futur — aucune donnée ne peut exister
demain — et relit chaque minute, parce qu'une journée en cours grandit pendant
qu'on la regarde. C'est lui qu'on remplacera pour iOS, pas le dessin. C'est
aussi lui qui **classe la journée par catégorie**, parce que le classement
demande de savoir lire la catégorie déclarée d'une app — ce que seul le côté
macOS sait faire. `PulseonCore` reçoit une fonction de classement et ne devine
rien.

### Deux nombres qui ne font pas le troisième

**Trouvé par Arthur devant l'app, le 2026-08-22** : « le rond indique 1h29 mais
j'ai 1h29 de télé et de pc ? donc ça devrait me montrer le double non ? ».

Le rond avait raison. Ses vrais chiffres du soir : Mac 1h16, télé 1h29, et
**1h15 pendant lesquelles les deux étaient allumés en même temps** — il regardait
la télé en étant sur son Mac. Ces minutes-là sont les mêmes minutes, donc
`coveredTotal` vaut 1h30 et non 2h45. C'est la distinction que le projet porte
depuis le début.

**Le défaut n'était pas le chiffre, c'était l'écran.** Juste sous le grand
nombre, la légende affichait « Mac 1h16 · TV 1h29 » : deux nombres qui ne font
pas le troisième. La note qui l'expliquait existait bien, mais **tout en bas de
la carte**, en gris pâle, sous la rangée de catégories — trop loin de la
contradiction pour la résoudre. Et elle énonçait une méthode de calcul
(« écrans simultanés comptés deux fois ») là où il fallait un fait de la soirée.

Elle est remplacée par une ligne posée **directement sous la légende** :
« deux écrans à la fois pendant 1h15 ». C'est un fait mesuré, et c'est
précisément ce qu'un total ne dira jamais.

**Le calcul n'est pas `summedTotal - coveredTotal`**, et ce n'est pas un détail :

- cette soustraction donne le temps compté en trop par l'addition, pas le temps
  passé sur plusieurs écrans. À **trois** appareils allumés une heure ensemble
  elle rend deux heures, alors qu'on n'a vécu qu'une heure de simultanéité ;
- elle inclurait le total d'une **source à compteur**. La PlayStation n'a aucun
  horaire : affirmer qu'elle tournait en même temps que la télé serait inventer
  un placement horaire, c'est-à-dire violer la règle 1.

`IntervalMath.simultaneity(of:)` balaie donc les vrais blocs, **après avoir
fusionné ceux de chaque appareil** — un appareil ne peut pas être allumé deux
fois en même temps, et l'oublier ferait passer un défaut d'écriture pour une
soirée sur deux écrans. C'est la leçon de la journée de 51 heures, appliquée à un
nouveau calcul.

Deux précisions de formulation qui sont des précisions de mesure :

- **« deux » ou « plusieurs » selon le pic observé.** Écrire « deux » un jour où
  trois écrans tournaient ensemble sous-entendrait une mesure qu'on n'a pas
  faite.
- **Jamais « les deux »**, qui renverrait aux pastilles de la légende — or elle
  peut en porter une troisième, la PlayStation, dont on ignore justement les
  horaires.

### L'anatomie de la journée

Un total dit *combien*, l'anneau dit *de quoi c'est fait*, et
`DayAnatomy` dit **comment la journée s'est déroulée** : premier écran, dernier
écran, plus longue traite, coupures. Deux journées de 6 h n'ont rien à voir selon
qu'elles tiennent d'une traite le matin ou en vingt reprises jusqu'à minuit —
c'est le parti pris du projet à l'échelle d'une carte.

**Quatre faits, et pas un de plus.** Le nombre de sessions, la durée moyenne
d'une traite, l'heure la plus chargée : chacun demanderait une ligne à
interpréter, or l'intérêt de la carte est qu'elle se lise d'un coup d'œil, comme
la rangée de ronds.

Ce qui a demandé une décision :

- **Les traites fusionnent tous les appareils.** Passer du Mac à la télé n'est
  pas une coupure : l'écran n'a pas cessé, seul l'écran a changé. Même raison qui
  fait exister `coveredTotal` à côté de `summedTotal`.
- **Une source à compteur est écartée** (règle 1). La PlayStation ne donne qu'un
  total : la faire entrer inventerait une heure de début. La carte le **dit**
  les jours où elle a du temps, plutôt que de la taire — une mise en garde
  permanente sur une source inactive serait du bruit.
- **Nil, jamais des zéros.** Sans le moindre horaire connu, la journée n'a pas
  d'anatomie et la carte n'existe pas. Zéro affirmerait qu'elle a commencé à
  minuit. Même règle que « pas encore branchée ≠ journée à zéro ».
- **Un seuil décide de ce qui mérite le nom de coupure** (5 min). Le collecteur
  tolère déjà deux minutes d'inactivité avant de fragmenter une session :
  annoncer « 47 coupures » sur une matinée décrirait le pas d'échantillonnage,
  pas la journée. **Le seuil ne touche aucun total**, il ne nomme que les trous.
  Et une nuit n'est pas une coupure : il n'y en a qu'**entre** deux traites.
- **L'amplitude n'est pas du temps d'écran** et ne doit jamais s'afficher comme
  tel : 2 h d'écran peuvent s'étaler sur 14 h.
- **Sur la journée en cours, « dernier écran » veut dire « jusqu'ici »**, et le
  taire laisserait lire une fin de journée qui n'a pas eu lieu.

**Deux défauts trouvés en PNG, invisibles à la compilation :**

- **`frame(maxWidth: .infinity)` rend une vue infiniment compressible, donc
  `ViewThatFits` retient toujours sa première proposition.** La rangée de quatre
  faits « tenait » en fenêtre étroite et c'est le texte qui se faisait tronquer
  (« la plus longue 54… ») au lieu de replier la rangée en deux lignes. Ce sont
  les `Spacer` qui écartent les colonnes, jamais les colonnes qui s'étirent — et
  le détail porte un `fixedSize` pour ne jamais *proposer* de se tronquer, ce qui
  est ce qui décide si la rangée tient.
- **La tête de lecture du jeu de démonstration précédait du temps d'écran.**
  `now` valait 19 h 24 alors que les blocs couraient jusqu'à 23 h 15 — un état
  que la vraie app ne peut pas produire, une session ouverte étant bornée à
  l'horizon d'activité. Il dormait là depuis des sessions ; c'est la carte
  « Déroulé » qui l'a révélé en annonçant « dernier écran 23:15 — jusqu'ici ».
  **Un jeu de démonstration incohérent valide des cas qui n'existent pas.**

### La fenêtre s'ouvre en grille, et ne défile plus

Demande d'Arthur le 2026-08-22, en voyant la carte « Déroulé » arriver dans une
colonne qui débordait déjà : « je voudrais que quand l'appli desktop est ouverte,
on ne doive pas scroller, genre en grille de 4 cases plutôt que de devoir
scroller ? comme ça on a toutes les informations importantes ». Sa fenêtre fait
**1512 × 949** et affichait une colonne de 720 centrée dedans : il fallait
défiler pour voir les appareils alors que la moitié de l'écran était vide.

| Écran | En grille | En colonne (fenêtre étroite) |
|---|---|---|
| Jour | 4 cases : anneau · répartition / déroulé · appareils | tout à la suite |
| Semaine | 3 cases : anneau · répartition / appareils | tout à la suite |
| Chronologie | une carte, **pleine largeur** | idem |

**Toutes les cases ne pèsent pas le même poids** (57 / 43). L'anneau porte le
total de la journée, sa composition par appareil, la comparaison aux journées
précédentes *et* la rangée de catégories : lui donner la même largeur qu'à la
carte des appareils, qui porte trois lignes, dirait qu'elles se valent. Il
grossit aussi (248 points contre 208).

**`WeightedColumns` est un `Layout` pur**, testé sans vue comme `RingLayout` et
`TimelineGeometry` : SwiftUI sait faire deux colonnes égales
(`frame(maxWidth: .infinity)` sur chacune), pas deux colonnes dans un rapport
donné.

**En dessous de 980 points, la grille cède la place à la colonne.** Deux colonnes
illisibles seraient pires qu'une colonne lisible qui défile. Et c'est un
`minWidth` **explicite** qui l'annonce à `ViewThatFits` : sans lui la grille
serait extensible, donc toujours retenue, et se ferait écraser au lieu de céder
— exactement le piège payé le même jour sur la carte « Déroulé ».

**La chronologie est le seul écran qui ne se borne pas à la colonne** (choix
d'Arthur le même jour). C'est le seul où la largeur porte de l'information :
doubler la largeur double la résolution horaire, un bloc de dix minutes passe de
5 à 10 points, et `TimelineGeometry` resserre d'elle-même la graduation de 3 h à
2 h. La règle « la maquette est une colonne, pas une surface à remplir » vaut
toujours pour les listes du jour et de la semaine, dont les jauges deviendraient
illisibles étirées sur 1500 points — **une chronologie n'a pas de jauge, elle a
des heures.**

**Limite assumée, mesurée plutôt que supposée** : `AppCategory` compte dix cas,
donc une journée en produit au plus dix. Jusqu'à **huit** catégories la fenêtre
ne défile pas ; à dix elle déborde d'environ 90 points et redevient défilante.
Arthur a tranché : **on laisse défiler** plutôt que de resserrer les lignes (ce
qui coûterait les icônes d'apps) ou de tronquer à « + 2 autres » (ce qui
cacherait des données mesurées, précisément ce que le projet évite partout
ailleurs).

**Deux défauts trouvés en PNG en élargissant, et par rien d'autre :**

- **La rangée des sept journées de la semaine s'étalait.** Chaque `DayRing` porte
  un `frame(maxWidth: .infinity)`, donc les ronds se sont retrouvés à 150 points
  les uns des autres dans la carte élargie : on lisait sept ronds, plus une
  semaine. Bornée à 560 points, elle redevient une bande.
- **La chronologie flottait** : une carte de 720 au milieu de 1512, à côté de
  deux onglets passés en pleine largeur. C'est ce rendu qui a posé la question.

### Lire l'historique

`DayDigestBuilder.buildPeriod(from:through:...)` agrège une plage de journées.
`PeriodDigest.days` contient **toutes** les journées, y compris les vides :
une semaine sans Mac le mercredi doit montrer un mercredi vide, pas sauter du
mardi au jeudi. Les trous font partie de ce qu'on a à dire.

`PeriodDigest.lanes` cumule les appareils sur la période, et ses `blocks` sont
**toujours vides** — ce n'est pas un oubli. Un bloc porte une position dans
une journée de 24 h ; sur sept jours cette position ne veut plus rien dire.
Une timeline se dessine à partir de `days`.

Le `coveredTotal` d'une période est la somme des totaux journaliers, et c'est
licite précisément parce que deux journées ne se chevauchent jamais — là où
deux appareils, eux, le peuvent.

**Deux pièges de performance, tous deux mesurés :**

- `sessions(from:to:)` ne bornait que le haut et filtrait le bas en Swift :
  pour afficher *aujourd'hui*, elle chargeait tout l'historique depuis le
  premier jour. Les deux bornes sont maintenant dans le prédicat.
- Agréger une plage en demandant au calendrier l'index du jour de chaque
  session coûtait **11,5 s pour un an** — 1,4 million d'opérations `Calendar`,
  qui sont lentes. Les frontières de journées sont désormais calculées une
  fois puis les sessions placées par dichotomie sur des nombres : **155 ms**,
  soit 74 fois plus vite. À retenir : jamais de `Calendar` dans une boucle
  chaude. Mais des frontières explicites, jamais une multiplication par
  86 400 : les journées de changement d'heure ne font pas 24 h.

**SwiftData refuse le déballage forcé dans un prédicat.** `session.end! > from`
compile, puis lève à l'exécution. Écrire `(session.end ?? horizon) > from`.
Le `??` est supporté, le `!` non — et si l'erreur est avalée par un `try?`,
la requête rend une liste vide impossible à distinguer d'une journée sans
activité. C'est pour ça que `sessions` et `samples` sont désormais `throws` :
une lecture qui échoue doit se voir, pas se déguiser en zéro.

### L'écran de la semaine

`buildPeriod` existait depuis la PR #21, couvert par neuf tests, et **appelé par
personne hors de ses tests**. Même angle mort que les icônes d'apps et
`DayComparison` : il ne lui manquait qu'un écran. `PeriodBrowser` le lit,
`WeekDashboard` le dessine.

**Il a d'abord été livré en graphique à colonnes, et Arthur l'a écarté le
2026-08-19** : « je n'aime pas les graphs en colonne, je me dis que si c'est en
colonne, autant garder l'ancienne app temps d'écran macOS ». L'argument est
produit avant d'être esthétique — **le rond est ce qui distingue Pulseon**, et il
tient les deux échelles : un grand anneau pour la semaine, sept petits pour les
journées. À ne pas reproposer.

**La quantité passe par la taille du rond, jamais par son remplissage.** Un
anneau rempli aux deux tiers se lirait « objectif atteint à 66 % » — c'est le
« / 5h Daily Goal » retiré de la maquette, et la règle « aucune comparaison ne
juge » l'interdit. Les arcs font donc toujours le tour, à toutes les échelles.

**Tous les ronds de journées font la même taille**, comme ceux des catégories —
voir « le dashboard » plus haut pour l'historique de cette décision et ce qui
reste interdit (encoder une quantité par un anneau incomplet).

**Quatre états de rond, jamais deux.** C'est la règle « pas encore branchée ≠
journée à zéro » poussée jusqu'au bout, avec un cas que la journée seule ne
rencontrait pas :

| État | Ce que ça veut dire | Comment ça se dessine |
|---|---|---|
| Journée mesurée avec du temps | on sait, et il y a à montrer | un anneau, arcs par appareil |
| Vrai zéro mesuré | une source branchée, rien n'a tourné | un **point plein** gris, « 0 min » |
| Journée non mesurée | le collecteur était éteint | un cercle **pointillé** vide, « — » |
| Journée à venir | elle n'a pas eu lieu | **rien du tout**, aucune valeur |

Le dernier est celui qu'on oublie : une semaine en cours contient toujours des
jours futurs, et les dessiner à zéro affirmerait qu'on n'a rien fait un jeudi qui
n'est pas arrivé. **Le pointillé a dû être renforcé** — tracé en `hairline`, il
disparaissait en apparence claire, et « on ne sait pas » redevenait
indiscernable d'un zéro. Trouvé en PNG, pas par un test.

**La moyenne exclut la journée en cours**, même règle que `DayComparison` : mêler
une matinée à des journées entières tire la moyenne vers le bas pour une raison
qui n'a rien à voir avec l'usage. Elle exclut aussi les journées non mesurées.
Sans aucune journée mesurée *et terminée*, `dailyAverage` rend **nil** et l'écran
se tait — zéro serait une affirmation fausse. **Aucune moyenne n'est tracée en
travers du dessin** : à l'horizontale, elle se lit comme une barre à battre.

**La semaine est celle du calendrier, pas « les sept derniers jours ».** Naviguer
suppose des bornes stables : sur une fenêtre glissante, reculer d'un cran
redécoupe chaque fois des journées différentes, et deux visites du même écran ne
montrent pas la même chose. C'est aussi le calendrier qui décide du premier jour
de la semaine — le supposer lundi casserait l'écran hors d'Europe.

**Une légende de couleurs sous le grand anneau** (`DeviceLegend`) : les cartes du
dessous portent les mêmes pastilles, mais un anneau dont il faut descendre pour
savoir ce que dit sa couleur perd ce qui fait son intérêt — la couleur est
justement ce qu'on lit d'un coup d'œil.

**Ce que la semaine partage avec le jour :** `Card`, `MeterRow`, `Chip`,
`NavButton`, `UnpluggedRow`, `BreakdownCard`, `DevicesCard` et `DeviceLegend`
vivent dans `Bricks.swift`. Le découpage des arcs est le **même `RingLayout`**
pour un rond de 18 points et pour celui de 178 — plancher des parts minuscules
compris. `CategoryTotal.merged` cumule les catégories des journées, licite parce
que **deux journées ne se chevauchent jamais**.

### L'onglet Chronologie

`TimelineGeometry` était pure, testée, et **lue par personne hors de ses tests**
depuis que la timeline avait quitté l'écran du jour. Le troisième onglet lui rend
un appelant, et rend surtout visible le parti pris du projet : « Temps d'écran »
dit *combien*, ceci dit **quand**.

**`RailLayout` vient de la PR #22, fermée sans merge.** Sa direction visuelle
avait été écartée, pas son raisonnement : le découpage en rail est du calcul pur,
couvert par dix tests, et il a été repris tel quel puis redessiné sur la palette
de la maquette. À retenir : une PR fermée n'est pas du code mort, et relire
pourquoi elle a été fermée évite de réécrire ce qui était bon dedans.

**Un rail unique, divisé en hauteur — jamais une piste par appareil.** C'est la
règle 6 de la skill `pulseon-design`, et elle est structurelle : une piste par
appareil allonge l'écran et transforme les simultanéités en mur dès le troisième
écran. Ici un appareil seul occupe toute la hauteur, deux la partagent en deux.
**Une simultanéité se lit au fait que le rail est divisé**, jamais au fait que la
page est plus longue — et c'est précisément ce qu'un total ne dira jamais.

**La PlayStation n'est pas sur le rail**, et c'est la règle 1 : elle n'a aucun
horaire, l'y placer serait inventer une heure. Elle vit sous un filet, dans une
section « Sans horaire connu », en contour pointillé, centrée, libellée dessous.
**Les cinq précautions sont cumulées parce qu'aucune ne suffit seule** : centré
sous un axe des heures, le bloc se lisait « joué vers midi ». Le risque résiduel
reste : il tombe visuellement sous « 12 h ». La largeur reste proportionnelle au
temps, seule chose qu'on sache de lui.

**La chronologie partage le `DayBrowser` de l'écran du jour**, elle n'a pas le
sien : deux navigations séparées feraient dériver les deux écrans, et changer
d'onglet changerait la date sans le dire.

**La tête de lecture n'existe que sur aujourd'hui** (règle 5) — une journée
passée est entièrement jouée. Elle est en `ink` et non en couleur d'accent, pour
ne pas entrer en concurrence avec les couleurs d'appareil qui, elles, portent de
l'information.

Une journée sans rien dit **laquelle des deux choses** s'est passée : « le
collecteur ne tournait pas » ou « il tournait et n'a rien vu passer ». La
deuxième est une affirmation, la première non.

### Comparer une journée aux précédentes

Un total seul ne veut rien dire, et c'est le manque qu'Arthur a ressenti en
ouvrant la fenêtre : « 9 h 39 », est-ce beaucoup ou est-ce sa normale ?
`DayComparison` répond, `DayBrowser` la calcule et **elle se lit sous l'anneau**,
là où la question se pose.

**Elle a passé une session entière calculée et jamais affichée** (PR #23 mergée
le 2026-08-16, montrée le 2026-08-18) — du back livré, invisible, exactement ce
que la convention « chaque feature porte son front » existe pour empêcher. Le
symptôme à reconnaître : une propriété publique qu'aucune vue ne lit.

`DayComparisonPhrase` tient les phrases, pure et testée hors simulateur — parce
qu'une phrase qui juge se corrige plus facilement quand un test la lit. Le seul
signe distinctif à l'écran est un chevron gris, **de la même valeur dans les deux
sens** : ni flèche verte, ni flèche rouge.

**La règle qui justifie tout le mécanisme : on compare à la même heure du
jour.** Une journée en cours confrontée à des journées entières donnerait
« toujours en dessous de ta moyenne » à 11 h du matin — un constat mécanique qui
n'apprend rien. Les journées de référence sont donc arrêtées à l'heure écoulée
de la journée affichée (`isPartial`), et seulement entières quand on regarde un
jour passé.

**Une journée sans aucune source mesurée est écartée de la moyenne.** Elle veut
dire « le collecteur était éteint », pas « zéro minute d'écran » : la compter
tirerait la moyenne vers le bas pour une raison qui n'a aucun rapport avec
l'usage. À l'inverse, une journée où une source était branchée et n'a rien
enregistré est un **vrai zéro**, et elle compte. C'est la même distinction que
`isConnected` porte partout ailleurs, ici sous le nom
`DayDigest.hasMeasuredSource`.

**En dessous de trois journées mesurées, on ne dit rien.** Une « moyenne » sur
une journée est cette journée-là présentée sous un nom trompeur. Se taire est
plus honnête que d'annoncer une tendance qui n'existe pas — et c'est aussi ce
qui se passe le premier jour d'utilisation.

**La comparaison ne juge pas.** Pulseon mesure l'usage d'un appareil, il ne
décide pas si c'est bien. Rien dans le type ne qualifie un écart, et **l'UI ne
doit pas colorer un dépassement en rouge** : ce serait transformer un miroir en
juge. Un écart de moins de cinq minutes n'est d'ailleurs pas un écart
(`isTypical`).

Deux détails d'exécution :

- **La comparaison n'est pas recalculée à chaque relecture.** La journée est
  relue chaque minute ; refaire quatorze requêtes par minute pour un chiffre qui
  bouge d'une minute serait absurde. Elle est donc recalculée au changement de
  journée, et au plus une fois toutes les cinq minutes sur la journée en cours.
  Une journée passée, elle, ne bougera plus jamais.
- **Limite assumée sur les sources à compteur** : n'ayant aucun horaire, leur
  total du jour ne peut pas être coupé à une heure précise. Sur une comparaison
  partielle elles sont donc comptées en entier des deux côtés — ce qui reste
  cohérent, le total d'aujourd'hui étant lui aussi « ce qui s'est accumulé
  jusqu'ici ».

### Sources à compteur : la plomberie commune

`CounterSource` est le contrat que remplit toute source incapable de dire un
horaire (la PlayStation, et toute future source du même genre) : elle rend des
**totaux cumulés par entité**, rien d'autre. `CounterPoller` l'interroge à
intervalle régulier (un quart d'heure) et range ce qu'elle dit sans rien
calculer — la conversion en temps du jour se fait à la lecture, par différence
entre deux relevés. C'est ce qui garantit qu'aucun horaire n'est inventé.

Rendre un dictionnaire vide et lever une erreur sont **deux réponses
différentes** : « la source répond, rien à déclarer » n'est pas « on ne sait
pas ». Le poller retient la dernière erreur pour que l'UI puisse dire qu'une
source est muette, au lieu de laisser croire qu'elle est à zéro.

`SessionStore.record(...)` **n'écrit pas un relevé identique au précédent**.
On ne joue pas toute la journée : réécrire le même total à chaque passage
referait exactement l'erreur du `lastSeen` en base. Sauter les doublons ne
gêne pas l'agrégation, qui cherche « le dernier relevé antérieur au jour » —
un relevé plus ancien fait l'affaire tant que le total n'a pas bougé. Un total
qui *baisse* est écrit tel quel : c'est ce que la source a dit, et c'est à
l'agrégation de refuser les deltas négatifs, ce qu'elle fait déjà.

### La TV : ce que le réseau dit, et ce qu'il ne dit pas

Le collecteur TV interroge l'API HTTP locale de la télé —
`GET http://<hôte>:8001/api/v2/` — qui rend un champ `PowerState`. C'est une
source à **intervalles**, comme le Mac : elle sait dire *quand* l'écran était
allumé, donc elle ouvre et ferme de vraies sessions et sa place sur la timeline
n'est pas inventée.

**Tout ce qui suit a été mesuré sur la télé d'Arthur** (Samsung `TQ55S90CATXXC`,
Tizen), allumée puis éteinte, le 2026-08-16 — pas déduit d'une documentation :

| Signal | Allumée | Éteinte | Verdict |
|---|---|---|---|
| Ping ICMP | répond | **répond aussi** | inutilisable |
| Annonce mDNS `_airplay._tcp` | présente | **présente aussi** | inutilisable |
| `GET :8001/api/v2/` | `PowerState: on` | connexion refusée, **ou** `standby` | **le bon signal** |
| Résolution de `Samsung.local` | résout | **résout aussi** | pas besoin d'IP fixe |

Quatre choses à ne pas perdre :

- **L'idée de départ — détecter la télé au ping — était fausse**, et seule la
  mesure l'a montré. La puce réseau reste vivante en veille : une détection au
  ping aurait compté une télé éteinte toute la nuit comme du temps d'écran. C'est
  exactement le risque qui avait été signalé avant de coder, et il s'est réalisé.
- **La télé éteinte a deux comportements**, tous deux observés à une heure
  d'intervalle : le port refuse la connexion, ou il répond `standby`. Sans doute
  selon la profondeur du sommeil. Les deux valent « éteinte » — n'en traiter qu'un
  laisserait l'autre mentir.
- **Interroger la télé ne la rallume pas** (vérifié, ç'aurait été rédhibitoire).
  Et l'API répond **sans authentification** en lecture : rien à déposer dans le
  Trousseau, contrairement à la PlayStation.
- **Viser le nom mDNS et non une IP.** `Samsung.local` résout même en veille, et
  `URLSession` sait le faire (≈ 0,5 s au premier appel). Une IP serait figée
  jusqu'au prochain bail DHCP.

**Trois états, pas deux.** `TVReading` distingue `on`, `off` et `unknown`, et le
troisième est celui qui protège le comptage : sans réseau, on ne sait rien de la
télé. `NetworkWitness` (sur `NWPathMonitor`) sert uniquement à trancher entre
« la télé refuse le port, donc elle est éteinte » et « le Mac n'a plus de réseau,
donc on ignore tout ». Il est **optimiste au démarrage** : avant la première mise à
jour du chemin réseau il répond « il y a du réseau », ce qui fait pencher le doute
vers le sous-comptage plutôt que vers une session laissée ouverte.

`TVDecision` porte la règle, pure et testée :

- **une extinction ferme la session au dernier instant où l'écran a été *observé*
  allumé**, jamais à l'heure courante. Entre deux relevés on ignore à quelle
  seconde l'écran s'est éteint : sous-compter d'un intervalle est permis, inventer
  ne l'est pas. Même discipline qu'`ActivityMonitor.endOfActivity` ;
- **ne rien savoir est toléré deux minutes**, puis la session est fermée au dernier
  instant observé. Sans tolérance, une micro-coupure Wi-Fi découperait une soirée
  de film en confettis ; sans limite, une panne d'une nuit compterait huit heures
  de télé qui n'ont pas eu lieu ;
- une **réponse incompréhensible** vaut `unknown`, jamais `off` : un changement de
  firmware ne doit pas effacer une soirée.

#### Ce que la télé sait nommer, et ce qu'elle ne nommera pas

Question posée par Arthur le 2026-08-19 (« on ne peut pas voir les apps que
j'utilise sur ma TV ? »), **répondue par la mesure le 2026-08-22**, télé allumée
sur YouTube, `Scripts/probe-tv-apps.sh` lancé depuis le réseau de la maison. La
télé **sait**, et le résultat est le même niveau de détail que côté Mac : « 2 h
de YouTube » au lieu de « 2 h de télé ». Rien ne sort de la machine — tout se
passe en HTTP sur le réseau local, sans tiers. (À ne pas confondre avec les
favicons de sites, qui, elles, exigeraient d'interroger un tiers.)

Ce que la mesure a donné, exactement :

| Point d'entrée | Réponse | Ce qu'on en fait |
|---|---|---|
| `/api/v2/applications/` (la liste) | **404** | pas de découverte possible |
| `/api/v2/applications/<id>` | 200 avec `name`, `running`, `visible` | **le bon signal** |
| `/api/v2/channels/` | 404 | rien |
| identifiant d'une app non installée | 404 | « pas là », appris une fois |

Quatre choses à ne pas perdre :

- **`running` ment, seul `visible` compte.** Pendant qu'Arthur regardait
  YouTube, trois apps déclaraient `running: true` (YouTube, Prime Video, Apple
  TV) pour un seul écran. Compter `running` aurait attribué la même soirée à
  trois apps à la fois. Même famille d'erreur que le ping ICMP pour l'état de
  l'écran : un signal qui existe, qu'on croit lire, et qui ne dit pas ce qu'on
  croit.
- **Le nom vient de la télé, jamais de nous.** `TVAppCatalog` ne code en dur que
  des identifiants ; le libellé est le champ `name` de la réponse, donc déjà
  localisé et déjà juste. Personne n'aurait deviné « Spotify - Musique et
  podcasts » ni « b.tv » depuis un catalogue écrit à la main.
- **La collecte est un balayage aveugle, et c'est une limite, pas un oubli.**
  La liste installée n'étant pas exposée, on interroge un catalogue
  d'identifiants. Une app qui n'y figure pas **ne prend pas un faux nom** : elle
  reste du temps de « Télé ». C'est le repli honnête, jamais une approximation.
  La seule autre voie connue est le WebSocket `samsung.remote.control`, qui donne
  la liste installée mais **exige un appairage** (message d'autorisation sur la
  télé, jeton à déposer au Trousseau comme celui de la PlayStation) — à garder
  pour le jour où le balayage montrera ses limites.
- **Un 404 s'apprend une fois.** `SamsungTVAppProbe` retient les absentes et
  cesse de les demander, ce qui permet un catalogue large sans le payer. Coût
  mesuré sur le réseau d'Arthur : **≈ 60 ms** quand l'app d'avant est encore à
  l'écran (une seule requête, le cas courant), 884 ms au premier balayage
  complet, 541 ms ensuite. Le pire cas est celui d'une entrée HDMI, une fois par
  minute (`TVMonitor.appInterval`), et seulement télé allumée.

**Le temps de télé nommé rejoint une vraie catégorie de contenu**, et le
non-nommé reste « Télé ». Les deux coexistent vraiment dans une même soirée, ce
que la preview montre côte à côte. Le cas non-nommé n'est pas résiduel : **la
PS5 d'Arthur est branchée sur cette télé**, donc une soirée de jeu se présente
comme un écran allumé sans app visible — exactement ce que `.tv` est là pour
dire.

**Changer d'app coupe la session, et la coupure est datée de l'instant du
relevé** — pas du dernier instant où l'ancienne app a été vue, contrairement à
une extinction. Ce n'est pas un relâchement de la règle : l'écran a été observé
allumé des deux côtés de la bascule, donc reculer la coupure creuserait un trou
dans du temps mesuré. Seul le partage entre deux apps est approché, à une minute
près.

**`.unknown` garde le nom précédent.** Ne pas avoir pu demander n'est pas « plus
aucune app » : sans cette distinction, une seule requête perdue ferait basculer
une soirée de Netflix dans « Télé ». Même discipline que les trois états de
`TVReading`.

**`StoredApp` porte désormais son appareil.** « Apple TV », « Spotify » et
« Netflix » existent des deux côtés ; la table étant indexée par nom, les deux
lignes se seraient disputé la même et **se seraient réécrites l'une l'autre à
chaque relevé** — l'erreur du `lastSeen` en base, doublée d'une catégorie
changeant de camp à chaque passage. La colonne est optionnelle et nil vaut
`.mac` : toutes les lignes écrites avant la télé sont des apps du Mac, par
construction, et un attribut optionnel est la seule migration que SwiftData
sache faire sans plan explicite.

**Les icônes, elles, restent cherchées du côté du Mac**, quel que soit
l'appareil, et c'est voulu : « Netflix » sur la télé et « Netflix » sur le Mac
sont le même produit et le même logo. Quand l'app n'est pas installée sur le
Mac — le cas courant — on rend nil et l'appelant affiche son repli.

**Le nom de la télé se dépose dans les réglages, pas dans le Trousseau** — ce
n'est pas un secret :

```
defaults write com.arthurlanllier.pulseon TVHost "Samsung.local"
```

Sans ce réglage, aucun collecteur TV ne démarre : interroger dans le vide
n'apporterait qu'une erreur toutes les trente secondes.

**Un bug que ce collecteur a révélé dans l'existant** : `closeOpenSession(at:)`
fermait les sessions de **tous** les appareils. Avec une seule source à
intervalles ça ne se voyait pas ; avec deux, la mise en veille du Mac aurait clos
la session d'une télé restée allumée, et rien ne l'aurait signalé — la base se
serait simplement mise à sous-compter la télé. Chaque collecteur ferme désormais
la sienne (`closeOpenSession(device:at:)`), et la version « tous » est réservée à
l'extinction de l'agent.

**La mesure exige que le Mac collecteur soit sur le même réseau que la télé.**
Constaté le 2026-08-17 en cherchant à joindre `Samsung.local` depuis le bureau :
ni DNS ni mDNS ne le résolvent hors du réseau domestique, le port ne répond pas.
Ce n'est pas un bug à corriger, c'est une conséquence de l'architecture : le Mac
est le seul collecteur du projet et Arthur l'emporte avec lui, donc le suivi Mac
lui-même s'arrête déjà quand il part — la télé hérite de la même limite plutôt
que d'en ajouter une nouvelle. Alternative écartée pour l'instant : l'API cloud
SmartThings de Samsung rendrait l'état de la télé lisible de partout, au prix
d'une dépendance externe de plus (compte Samsung, jeton OAuth) — pour un gain
faible, la télé ayant peu de chances d'être allumée précisément les jours où
Arthur est absent.

### Sortir ses données

`DataExport` écrit tout l'historique en CSV ou en JSON, depuis le menu de la
barre. **C'est l'envers de « rien ne sort de ta machine »** : rien n'en sort tout
seul, et tout doit pouvoir en sortir sur demande. Une app de mesure qui garde ses
mesures prisonnières demande de lui faire confiance sans contrepartie.

**On exporte le brut, jamais l'agrégat.** Un total par jour et par catégorie
serait plus commode à ouvrir dans un tableur, et ce serait **notre
interprétation** — le classement d'un navigateur, le seuil d'une coupure, la
fusion des intervalles sont tous des choix de Pulseon. Les sessions, elles, sont
ce qui a été mesuré. Même règle que la catégorie déclarée d'une app, stockée
brute pour que l'historique se reclasse si l'on change d'avis.

Ce qui ne s'invente pas, et se vérifie dans le fichier :

- **Une session ouverte n'a pas de fin.** Y écrire l'heure courante ferait passer
  une session en cours pour une session terminée, dans un fichier que plus
  personne ne pourra recouper avec la base.
- **Une entité absente reste vide**, jamais « Autre » : c'est une absence de
  mesure, pas une valeur.
- **Une source à compteur n'a ni début ni fin** — d'où la colonne `kind`, qui
  sépare les deux natures de mesure du projet. Les mélanger sans le dire
  produirait un fichier où des colonnes vides ressembleraient à des zéros.
- **Les champs inconnus sortent en `null`, jamais absents.** `JSONEncoder` omet
  les optionnels nuls par défaut ; l'encodage est donc écrit à la main. Une clé
  absente se lit « ce format n'a pas cette colonne », une clé à `null` se lit
  « on ne sait pas » — la distinction « pas branchée ≠ zéro », portée jusque dans
  le fichier.
- **Chaque instant porte son décalage horaire**, et le JSON porte le fuseau. Une
  heure locale muette est ambiguë deux fois par an : la nuit du passage à l'heure
  d'hiver contient deux fois 02:30. Un instant UTC serait exact et illisible, or
  le sujet se lit en heures de sa propre journée.
- **L'échappement RFC 4180 n'est pas décoratif** : le nom d'une app vient de la
  machine ou de la télé (« Spotify - Musique et podcasts »), et une seule virgule
  décalerait toutes les colonnes de sa ligne — un fichier qui ment sans prévenir.
  En revanche **on ne neutralise pas** les noms commençant par `=` ou `+`, qu'un
  tableur prendrait pour des formules : les préfixer protégerait le tableur en
  falsifiant le nom.

**Un bug attrapé par un test, et par rien d'autre** : `$0.end.map { Int($0.timeIntervalSince($0.start)...) }`
— à l'intérieur d'un `map` sur `end`, `$0` désigne la date de fin et non la
session, donc la durée se calculait entre la fin et elle-même. **Zéro partout, et
ça compile sans un mot.** Nommer la variable de fermeture dès qu'un `map`
s'imbrique dans un autre.

Vérifié sur la vraie base (une copie faite par `sqlite3 .backup`, pour ne pas
toucher à celle du collecteur) : **3 572 sessions**, huit colonnes sur chaque
ligne, les sessions ouvertes sans fin, le JSON relu par un parseur.

### Les secrets vont dans le Trousseau, pas dans un `.env`

`Secrets` est le seul fichier qui sait où vivent les secrets ; le collecteur
PSN, lui, l'ignore. La raison n'est pas la peur du `.gitignore`, qui marche
très bien : un jeton PSN appartient à **l'utilisateur**, pas au code. Un
secret de déploiement (mot de passe de base) se livre avec le service et un
`.env` lui convient. Ici, chaque personne installant Pulseon a le sien, saisi
à l'exécution — c'est exactement l'usage du Trousseau.

Le jeton se dépose à la main, une fois, sans jamais transiter par un fichier
du projet :

```
security add-generic-password -s "com.arthurlanllier.pulseon.psn" -a "npsso" -U -w
```

**Aucune valeur de secret ne doit finir dans un log**, ni tronquée, ni dans un
message d'erreur. `Secrets.Failure` ne porte que des statuts.

### `PulseonMacKit` : pourquoi le code macOS n'est pas dans l'exécutable

Tout le code macOS vit dans une bibliothèque, et la cible exécutable ne
contient plus que `PulseonApp.swift`. Sans ça, rien n'est testable : le `@main`
de l'app démarre SwiftUI **dans le processus de test**.

Deux pièges rencontrés en écrivant ces tests, tous deux sans message d'erreur
utile — le processus meurt sur un signal, c'est tout :

- **`ModelContext` ne retient pas son `ModelContainer`.** Un helper qui crée
  le conteneur en local et ne rend que le contexte laisse le conteneur être
  libéré, et tout accès ultérieur plante. Le conteneur doit rester vivant
  aussi longtemps que le contexte.
- Ça vaut aussi pour un objet qui les détient : `try TestBase().store` libère
  l'objet aussitôt. Il faut garder l'instance et passer par elle.

## Parti pris produit

L'app native « Temps d'écran » de macOS dit **combien**. Pulseon montre
**quand**.

L'élément signature était **la journée en multipiste**. Arthur l'a écartée le
2026-08-17 en livrant sa maquette : « j'aime bien le rond plutôt que la timeline
chrono qu'on a ». **L'anneau de composition** prend sa place en tête d'écran, et
la chronologie deviendra un onglet à part (écran 4 de la maquette).

Le parti pris, lui, ne bouge pas — ce qu'un total en barres ne dira jamais, ce
sont les chevauchements et les trous, et c'est à la future timeline de les
montrer.

**Règle à tenir, non négociable : ne jamais inventer de placement horaire.**
La PlayStation n'expose qu'un total cumulé sans horaires. Sa piste doit
rendre la quantité (largeur proportionnelle) tout en signalant visuellement
que l'heure est inconnue — hachures ou équivalent. Toute future source à
compteur suit la même convention. Une source qui n'a jamais rien écrit
s'affiche « pas encore branchée », visuellement distinct d'une journée à
zéro.

Corollaire déjà implémenté dans `DayDigest` : **deux totaux**, parce qu'ils
ne veulent pas dire la même chose. `summedTotal` additionne les appareils et
double-compte les écrans simultanés ; `coveredTotal` fusionne les
intervalles qui se chevauchent. À l'UI de choisir lequel elle met en avant.

### Le partage est fermé : Pulseon reste une app perso

**Tranché par Arthur le 2026-08-24** : « le projet dépasse un peu les standards,
c'est quelque chose que je vais garder pour moi sur mon PC », puis, sans qu'on le
lui redemande, « **je ne veux plus la commercialiser** ». C'est une décision de
périmètre, pas une humeur, et elle **referme** l'ambition de mise en ligne qui
montait depuis le 2026-08-17 (« le partage me branche beaucoup »). Dit deux fois
dans la même conversation : à ne pas reproposer.

Ce que ça retire de la roadmap, définitivement jusqu'à avis contraire :

- **La signature Developer ID et la notarisation.** Elles n'existaient que pour
  installer l'app sur la machine de quelqu'un d'autre. La signature ad-hoc suffit
  sur le Mac d'Arthur, et l'avertissement Gatekeeper n'a plus d'objet.
- **Le positionnement produit.** Plus de risque « un public attend l'iPhone en
  premier », plus de « le cœur partageable c'est le Mac » : la PlayStation et la
  télé ne sont plus des sources hors sujet, ce sont **les** sources.
- **L'onboarding pour un inconnu.** Personne d'autre n'installera Pulseon, donc
  aucune fonctionnalité ne se justifie plus par « il faudra bien expliquer ça à
  quelqu'un qui découvre ».

Ce que ça **ne** retire pas :

- **Le compte Apple payant reste nécessaire** pour CloudKit, l'app iOS et le
  widget — même pour un usage strictement personnel. C'est le seul mur qui
  survit à cette décision, et c'est celui qui compte.
**Première conséquence, tirée le jour même : la découverte réseau est écartée.**
Elle était née en 2026-08-17 comme un confort d'installation — remplacer le
`defaults write ... TVHost` par une liste sur laquelle cliquer. Arthur l'a
écartée d'une question : « j'en ai pas besoin non ? c'est pour mon usage perso à
la maison ». Sa télé est reliée depuis le 18/08, une fois pour toutes.

**Le repli tenté ne valait pas mieux, et c'est la vraie leçon.** L'idée de
seconde main était d'en faire un diagnostic : sur les dix jours mesurés au
2026-08-24, la télé n'a de temps que **quatre jours**, et les six autres sont des
« on ne sait pas ». Sauf que ces six jours-là, la télé n'était pas injoignable à
cause d'un mauvais réglage — **Arthur n'était pas chez lui**. Un écran qui
affiche « injoignable » les jours où il est au bureau lui apprend qu'il est au
bureau. Le chiffre était juste, la conclusion qu'on en tirait ne l'était pas.

Le code écrit ce jour-là vit sur la branche **`feat/device-discovery`**, non
mergée, avec le détail de ce qui y a été mesuré (une annonce mDNS ne prouve rien,
`NWBrowser` ne rend pas de nom d'hôte, seul `:8001/api/v2/` tranche). Comme
`RailLayout` dans la PR #22 fermée : ce n'est pas du code mort, c'est du
raisonnement mesuré qu'il vaut mieux relire que réécrire.

**Le test à faire passer à toute idée, désormais** : « qu'est-ce que ça change
pour Arthur, chez lui, sur sa machine ? ». Si la réponse suppose un autre
utilisateur, un autre réseau ou une autre installation, l'idée est hors sujet.


## Conventions de développement

- **Une branche par feature ou tâche complexe.** Pas de travail non-trivial
  directement sur `main`. Le découpage doit rester relisible : une PR = une
  feature identifiable, y compris côté UI.
- **Commits réguliers** au fil de l'avancement (pas un seul gros commit en
  fin de tâche).
- **Pas de dette de doc** : ce `CLAUDE.md` est mis à jour en même temps que
  le code.
- **Arthur relit et merge lui-même.** Relation tech lead / dev : livrer,
  signaler les choix discutables, ne pas merger à sa place.
- **Depuis le 2026-08-17 : chaque feature porte son back ET son front,
  systématiquement.** Le mode « back seul, front en pause » (PR #21, #23, #26)
  a produit du travail réel mais invisible plusieurs sessions de suite — c'est
  ce qui a fait perdre à Arthur le fil de l'avancement. **Le front se fait en
  composants système neutres** (`List`, `Text`, couleurs et polices par
  défaut) : ce n'est pas une direction visuelle, donc ça n'entre pas en
  conflit avec la pause déclarée sur `PulseonTheme` — voir la skill
  `pulseon-design`. Quand sa maquette arrivera, on repeint des écrans qui
  existent déjà plutôt que d'improviser l'ensemble d'un coup.

### Lancer les tests

```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build && swift test
```

**Le `export` n'est pas optionnel** tant que `xcode-select -p` renvoie
`/Library/Developer/CommandLineTools` : sans lui, les macros SwiftData
(`@Model`) ne s'expansent pas — le plugin n'existe que dans Xcode complet —
et le build casse sur une cascade d'erreurs `PersistentModel` trompeuses,
qui pointent le code alors que le problème est la toolchain.

**Piège de `#expect` : un optionnel comparé à une expression arithmétique
échoue alors que la comparaison est vraie.**
`#expect(totals.first?.total == 2 * 3600)` rapporte « 7200.0 == 7200 » comme un
échec. Un littéral seul (`== 1800`) passe, et la même expression sans optionnel
passe aussi — donc l'erreur ressemble à un bug de calcul et fait chercher au
mauvais endroit. Vérifié : la comparaison est bien vraie en Swift ordinaire, le
problème est l'expansion de la macro. Utiliser `try #require` pour déballer
avant de comparer, ce qui est de toute façon la forme idiomatique.

Aucun `sudo` n'est nécessaire, contrairement à ce qui était noté ici avant :
la licence est déjà acceptée, `DEVELOPER_DIR` suffit. Pour s'en passer
définitivement (et faire taire le `No such module 'Testing'` de l'éditeur,
car SourceKit, lui, ne lit pas cette variable), une seule fois dans un vrai
terminal — le `!` de Claude Code n'a pas de TTY, donc `sudo` y échoue :

```
sudo xcode-select -s /Applications/Xcode.app
```

## Doc de référence du code

Visite guidée du code, écrite pour Arthur qui apprend Swift depuis
zéro : https://claude.ai/code/artifact/65616a6f-3229-4a29-bc5f-4b3302b2926a

Elle décrit chaque paquet, le trajet d'une donnée, les pièges payés, et les
notions Swift accrochées à de vraies lignes du projet. **À mettre à jour quand
l'architecture bouge** — republier en passant la même URL en paramètre `url`
met à jour la même page, sans créer de doublon.

**Refaite le 2026-08-18** : elle décrivait encore 744 lignes en 6 fichiers, un
seul paquet côté Mac, et annonçait « l'app ne compile pas encore ». Elle
couvre maintenant les **4 429 lignes en 4 paquets**, et son plan a changé de
principe — une liste plate de fichiers ne dit plus rien à cette taille, donc
elle est organisée par paquet, chacun présenté par **la règle qu'il fait
respecter**. Elle décrit l'état de `local/build` (soit `main` + la maquette +
le correctif du double collecteur), c'est-à-dire ce qui tourne réellement sur
le Mac d'Arthur.

## Historique : la première version (abandonnée)

Un premier dashboard complet a été construit en Tauri + Svelte + Python,
puis abandonné le 2026-08-14 au profit du natif Apple (trop lourd, et pas
d'app iPhone possible). Le code reste accessible dans les branches et PR
fermées `chore/foundation`, `feat/collector-pc`, `feat/dashboard-*` (PR #1
à #6).

Ce qui a été repris : le modèle de données (sources à intervalles vs
sources à compteur cumulatif), la logique du collecteur Mac (PyObjC ne
faisait qu'appeler `NSWorkspace` et `Quartz`, mêmes API depuis Swift), et
tout le parti pris visuel ci-dessus.

## Roadmap

1. ~~Stack technique~~ — tranché deux fois, voir ci-dessus.
2. ~~`PulseonCore`~~ — modèles + agrégation journalière, couverts par des
   tests.
3. ~~App macOS~~ — agent barre de menu, collecte vérifiée, empaqueté en
   `.app`, démarrage automatique par `LaunchAgent`.
4. ~~Dashboard de la journée~~ — la maquette d'Arthur est implémentée
   (`PulseonUI` : anneau, cartes, catégories, icônes d'apps réelles,
   comparaison aux journées précédentes). Mergée par la PR #31 le 2026-08-18,
   après avoir vécu cinq jours sur la seule machine d'Arthur.
   - ~~L'historique sur plusieurs jours~~ — l'écran de la semaine est livré
     (voir « L'écran de la semaine »).
   - ~~L'onglet Timeline~~ (écran 4 de la maquette) — livré, sur un rail unique
     repris de la PR #22 (voir « L'onglet Chronologie »).
   - ~~L'anatomie de la journée~~ — livrée le 2026-08-22, carte « Déroulé » sur
     l'écran du jour (voir « L'anatomie de la journée »).
   - La fenêtre porte donc trois écrans : Jour / Semaine / Chronologie.
   - Porter ces vues sur iOS est l'étape B, et c'est un portage, pas une
     construction : il faudra un projet Xcode (SwiftPM seul ne fabrique pas
     d'app iOS) et le compte payant. Stack rediscutée puis reconfirmée le
     2026-08-15 : **rester en Swift**, Expo ne cible pas macOS, ne peut pas
     porter les collecteurs natifs, et remplacerait CloudKit par un backend
     à héberger.
5. Synchro CloudKit entre les deux (dépend de l'Apple Developer Program).
6. ~~Collecteur TV~~ — tourne, par l'API HTTP locale de la télé, et **nomme
   l'app à l'écran** depuis le 2026-08-22. Collecteur PlayStation toujours
   bloqué sur le jeton.
7. Réévaluer l'intégration iPhone.

### État au 2026-08-22 (fin de septième session)

**Quatre PR mergées (#43 à #46), 158 → 205 tests**, app rebâtie et réinstallée à
23:32, une seule instance. La séance a commencé par une question d'Arthur — « as-tu
une nouvelle liste de feature ? je sais plus trop où on en est » — et par un
constat : **la télé était allumée**, condition qu'on attendait depuis trois jours
pour lancer `Scripts/probe-tv-apps.sh`.

**La sonde a répondu, et c'est ce qui a orienté la soirée.** La télé sait nommer
l'app à l'écran. Détail dans « Ce que la télé sait nommer » ; les trois choses à
retenir : `running` ment (trois apps le déclaraient vrai pour un seul écran, seul
`visible` compte), la liste des apps installées n'est pas exposée (404, donc
balayage aveugle d'un catalogue), et **le nom vient de la télé** — personne
n'aurait deviné « Spotify - Musique et podcasts » ni « b.tv ».

**Vérifié en direct après réinstallation** : `tv | YouTube | en cours` en base,
identité `tv.samsung.app.111299001912` classée `public.app-category.video`. Les 37
lignes d'apps antérieures ont survécu à la migration de `StoredApp` (colonne
d'appareil optionnelle, nil = Mac).

**Trois autres livraisons**, toutes demandées ou validées par Arthur :

- **L'anatomie de la journée** — carte « Déroulé » : premier écran, dernier écran,
  plus longue traite, coupures.
- **L'export CSV / JSON** — le brut, jamais l'agrégat. Vérifié sur une copie de la
  vraie base : 3 572 sessions.
- **La grille** — sa demande en voyant « Déroulé » arriver dans une colonne qui
  débordait : « on ne doit pas scroller, genre en grille de 4 cases ». Les trois
  onglets tiennent maintenant dans sa fenêtre de 1512 × 949.

**Quatre défauts trouvés en regardant les PNG, aucun par un test :**

- **`frame(maxWidth: .infinity)` rend une vue infiniment compressible**, donc
  `ViewThatFits` retient toujours sa première proposition et l'écrase au lieu de
  la laisser céder. Payé **deux fois le même jour** : sur la rangée de la carte
  « Déroulé » (texte tronqué), puis à l'échelle de l'écran entier (la grille
  choisie en fenêtre étroite). Une proposition doit annoncer sa largeur réelle.
- **La tête de lecture du jeu de démonstration précédait ses propres blocs** —
  `now` à 19 h 24 pour des blocs allant jusqu'à 23 h 15, un état que la vraie app
  ne peut pas produire. Il dormait là depuis des sessions ; c'est la carte
  « Déroulé » qui l'a révélé. **Un jeu de démonstration incohérent valide des cas
  qui n'existent pas.**
- **La rangée des sept journées s'étalait** dans la carte élargie : chaque rond
  porte un `frame(maxWidth: .infinity)`, donc 150 points les séparaient. On lisait
  sept ronds, plus une semaine.
- **La chronologie flottait**, carte de 720 au milieu de 1512.

**Deux leçons de méthode :**

- **Un build incrémental périmé peut tuer toute la suite sur un signal 11**, sans
  un seul test en échec — ajouter une propriété stockée à un `struct` public change
  sa disposition mémoire. Le même jour, le paquet de preview refusait de compiler
  sur un `cannot find type` pour un type qui existait. **Réflexe avant de chercher
  un bug : `swift package clean`.**
- **Un `$0` dans un `map` imbriqué** faisait calculer la durée d'export entre la
  fin et elle-même. Zéro partout, et ça compile sans un mot.

**Ce qui attend Arthur** : rien de bloquant. Le collecteur PSN reste le seul front
fermé (jeton `npsso`), et le compte Apple payant conditionne toujours CloudKit,
l'app iOS et le widget.

**Ce que je ferais ensuite, par ordre de rendement :**

1. **Étendre le catalogue d'apps de la télé.** Il tient dix identifiants installés
   chez Arthur et sept autres à l'aveugle. Un balayage plus large, télé allumée,
   dirait ce qu'elle a vraiment — et chaque identifiant manquant est du temps qui
   reste « Télé » au lieu d'être nommé. Coût : une requête par identifiant, apprise
   une fois.
2. **L'écran du mois ou de l'année.** `buildPeriod` est déjà générique et l'écran
   de la semaine ne fait que l'appeler sur sept jours ; la base porte maintenant
   huit jours de données réelles, assez pour que la question se pose.
3. **Le vide sous le rail de la chronologie**, signalé le 2026-08-22 et laissé
   ouvert : cet onglet occupe une carte dans une fenêtre de 949 de haut. C'est du
   dessin, donc une décision d'Arthur.

### État au 2026-08-19 (fin de sixième session)

**Une seule PR, née d'une question d'Arthur devant l'app** : « pourquoi ma
musique a autant grimpé ? j'étais à peine à 1 h en partant du boulot ». C'était la
télé — 2 h 52 rangées en « Vidéo et musique » un soir où l'app Musique avait
tourné 6 secondes. **PR #42 mergée, 157 → 158 tests**, app rebâtie et réinstallée
à 23:46, une seule instance.

**Le fond du sujet n'était ni un bug ni une donnée fausse, mais une affirmation
non mesurée.** `Device.tv` valait `.media` par raccourci assumé (« une télé sert
à regarder »), défendu par un commentaire dans le code. Le raccourci tient tant
qu'on parle de l'appareil, et casse quand le total atterrit dans une catégorie de
contenu à côté d'IINA. Détail dans « Un écran n'est pas un contenu ».

**La séance a aussi vérifié l'état de la collecte**, ce qui était la question de
départ : une seule instance, une seule inscription BTM, aucun chevauchement
au-delà de 0 s, aucune session traînante, aucun crash depuis le 15/08. Le
redémarrage de 23:25 était un reboot de la machine, pas un plantage. **Le
correctif d'`InstanceLock` tient** : plus rien de comparable au 51 h du 18/08.

**Deux leçons de méthode :**

- **Une preview qui ne traverse pas le code testé ne vérifie rien.** Celle-ci
  écrivait ses catégories à la main, donc le premier rendu du correctif affichait
  encore l'ancien classement — la vue était juste, l'image mentait. C'est la
  même famille d'angle mort que « chercher l'appelant, pas la déclaration ».
- **Un `#expect` qui compare une valeur à elle-même et échoue est un build
  périmé, pas un bug.** Insérer deux cas au milieu d'un `enum` décale les indices,
  et un module compilé de façon incrémentale comparait les anciens aux nouveaux :
  `.other` sortait « égal » à `.tv`, à deux cas d'écart exactement.
  `swift package clean` suffit.
  **Deuxième manifestation, le 2026-08-22, et bien plus violente** : ajouter une
  propriété stockée à un `struct` public change sa disposition mémoire, et un
  module client compilé contre l'ancienne fait tomber toute la suite sur un
  **signal 11**, sans un seul test en échec — donc rien à lire pour comprendre.
  Le même jour, le paquet de preview refusait de compiler sur un
  `cannot find type` pour un type qui existait. **Réflexe à avoir avant de
  chercher un bug : `swift package clean`** (et `--package-path Tools/Preview`
  pour la preview, qui a son propre `.build`).

**Ce qui attend Arthur** : inchangé — `Scripts/probe-tv-apps.sh` à lancer chez
lui, télé allumée avec une app ouverte. Et une conséquence nouvelle à connaître :
**la PS5 étant branchée sur la télé et le collecteur PSN toujours bloqué, une
soirée de jeu s'affiche en « Télé », pas en « PlayStation »** — honnête, mais
incomplet.

### État au 2026-08-19 (fin de cinquième session)

**L'app est passée d'un écran à trois** : Jour, Semaine, Chronologie. Huit PR
mergées (#32 à #39), **126 → 157 tests**, et tout tourne sur la machine d'Arthur
— rebâti et réinstallé quatre fois dans la journée, une seule instance à chaque
fois.

**Le fil conducteur n'était pas les écrans, c'était le back invisible.** Deux
paquets entiers étaient écrits, testés, et appelés par personne hors de leurs
tests : `buildPeriod` (9 tests, depuis la PR #21) et `TimelineGeometry` (6 tests,
depuis que la timeline avait quitté l'écran du jour). Il ne leur manquait qu'un
écran. `RailLayout` a été **récupéré de la PR #22**, fermée pour sa direction
visuelle et non pour son raisonnement — une PR fermée n'est pas du code mort.

**L'écran du jour a changé quatre fois avant de convenir**, et chaque version est
passée par un PNG avant d'être montrée : anneau intérieur concentrique → deux
anneaux côte à côte → ronds de catégories à taille variable → ronds uniformes,
portant le logo de l'app dominante. Le retour le plus utile de la journée a été
une question, pas une critique : « à quoi correspond le deuxième anneau ? ».
**Une forme qui a besoin d'une légende pour être comprise n'est pas plus dense,
elle est plus opaque.**

**Trois suppressions valent d'être notées**, parce qu'elles sont l'inverse exact
du problème du matin : `RingScale` et ses 5 tests, `PeriodPresentation.scale`, et
`busiestDay` — cette dernière écrite dans la PR #32 et jamais lue par une vue.
Une API sans appelant ressemble à une feature livrée ; le compilateur ne dit rien
sur une propriété publique inutilisée. **Chercher l'appelant, pas la
déclaration** — dans les deux sens.

**Ce qui attend Arthur, et rien d'autre :**

- **`Scripts/probe-tv-apps.sh`**, à lancer chez lui, télé allumée avec une app
  ouverte. Question ouverte : la télé peut-elle nommer l'app à l'écran ? Ce
  serait local, donc compatible avec la promesse du projet — mais Samsung a
  fermé une grande partie de son API locale depuis 2022 et sa télé est de 2023.
  **On mesure avant de coder** (voir la section TV).
- **La TV n'a qu'une session en base** (1,6 h le 18/08), et ce n'est pas un bug :
  Arthur n'était pas sur le réseau de la télé. Vérifié avec lui.

**Ce que je ferais ensuite, par ordre de rendement :**

1. **L'anatomie de la journée** — premier écran, dernier écran, plus longue
   traite, coupures. Pur `PulseonCore`, testable sans simulateur, et c'est la
   substance que n'importe quel écran affichera.
2. **L'export CSV/JSON** — du core pur, et l'argument « tes données
   t'appartiennent ».
3. **Les apps de la télé**, si la sonde répond.

~~**Un décalage connu, qui ne se verra qu'une fois la télé branchée pour de
bon**~~ — **réglé en sixième session, et il s'est réalisé exactement comme
annoncé, le soir même.** Le cœur d'un rond portait le logo de l'app dominante, or
une télé n'a pas d'entité : ses blocs alimentaient « Vidéo et musique » sans
jamais apparaître dans la liste des apps. La correction retenue n'est pas celle
qui était proposée ici (afficher le glyphe de l'appareil) — **la télé et la
PlayStation ont chacune leur catégorie**, donc le problème disparaît à la racine
plutôt que d'être rattrapé au dessin. Voir « Un écran n'est pas un contenu ».

### État au 2026-08-18 (fin de quatrième session)

**Cette session** : les icônes d'apps ont été **branchées pour de vrai** — la
session précédente avait posé les deux bouts du tuyau (`AppIconSource` d'un côté,
`AppRegistry.icon(ofApp:)` de l'autre) sans jamais les relier, et aucune icône
n'apparaissait à l'écran. Même diagnostic pour `DayComparison`, calculée depuis
la PR #23 et affichée nulle part. **Les deux relevaient du même angle mort : une
API publique que personne n'appelle ressemble, dans un diff, à une feature
livrée.** Le réflexe à garder : chercher l'appelant, pas la déclaration.

**Vérifié sur la machine, pas seulement en test** : `Pulseon.app` a été rebâti et
réinstallé le 2026-08-18 à 17:15, une seule instance tourne, et la base s'est
remise à écrire aussitôt. Les logos des apps sont à l'écran dans la vraie
fenêtre.

**Et une leçon de méthode qui n'a rien coûté sauf du temps** : les previews ont
été rendues en `--quiet` toute la session, donc lues par moi et **jamais ouvertes
sur l'écran d'Arthur**. Il a dit « je ne vois aucun changement », puis « je ne
vois pas les logos » — juste les deux fois, pour deux causes distinctes : l'app
installée datait d'avant la session, et les images n'avaient été montrées à
personne. Détail dans la skill `pulseon-preview`. **Un résultat visuel qu'on
annonce sans l'ouvrir demande de croire sur parole ce qu'on a demandé à voir.**

### État au 2026-08-18 (fin de troisième session)

**Ce qui tourne pour de vrai** : le collecteur Mac est installé dans
`/Applications`, démarre à l'ouverture de session, affiche le total du jour qui
défile à la seconde dans la barre de menu, et la fenêtre du dashboard s'ouvre par
⌘J — avec la maquette d'Arthur, anneau en tête. Le collecteur TV est codé et
n'attend qu'un `defaults write ... TVHost`.

**Toutes les PR en attente de la session précédente ont été mergées** : #21
(catégories et identité des apps), #23 (comparaison entre journées), #25 et #27
(doc), #26 (la TV par son API locale), #28 (stratégie back+front).

**Trois PR fermées sans merge, par Arthur, et chacune pour une raison
différente** — c'est le genre de décision qu'on ne devine pas en relisant le
code :

| PR | Sujet | Pourquoi elle n'est pas dans `main` |
|---|---|---|
| #22 | Refonte visuelle proposée | direction visuelle non retenue ; Arthur a fourni sa maquette |
| #24 | Source Steam | jamais demandée — voir la leçon plus bas |
| #29 | La maquette implémentée | fermée le 2026-08-17, mais **le code vit toujours sur `feat/app-icons`** |

**Ce qui n'est nulle part sur le serveur** : `feat/app-icons` (5 commits — la
maquette, les dégradés, la colonne bornée, les icônes d'apps) est **locale et
non poussée**. C'est pourtant le code qui tourne sur le Mac d'Arthur. À ne pas
perdre : une réinstallation depuis `main` lui ferait perdre son dashboard.

**PR ouverte** : #30, le double collecteur (voir « Un seul collecteur, ou la
journée de 51 heures »). 117 tests sur la branche, 126 une fois combinée à
`feat/app-icons` qui apporte les siens.

**Ce qui bloque, et sur quoi :**

- **PlayStation** : jeton `npsso` indisponible, et de toute façon indistribuable
  en l'état — demander à un inconnu de l'extraire à la main d'un navigateur ferait
  perdre tout le monde. Il faudrait un vrai parcours de connexion.
- **TV** : plus bloquée côté code. Il reste **un geste côté Arthur** :
  `defaults write com.arthurlanllier.pulseon TVHost "Samsung.local"` — sans ce
  réglage le collecteur ne démarre pas. Et la mesure exige que le Mac soit sur le
  réseau de la télé.
- **Widget macOS, CloudKit, app iOS, distribution** : même mur, le compte Apple
  payant (~99 €/an). Il couvre un nombre illimité d'apps, sans frais par app.

**Ce que je ferais ensuite, par ordre de rendement :**

1. ~~**Pousser `feat/app-icons`**~~ — fait en quatrième session, avec les icônes
   réellement branchées et la comparaison à l'écran.
2. **L'anatomie de la journée** — premier écran, dernier écran, plus longue
   traite, coupures. Pur `PulseonCore`, testable sans simulateur, aucun design,
   et c'est la substance que n'importe quel écran affichera.
3. ~~**L'export CSV/JSON**~~ — livré le 2026-08-22 (voir « Sortir ses
   données »).
4. **L'onglet Timeline** (écran 4 de la maquette) : `TimelineGeometry` est déjà
   là, pure et testée. Attention le jour où il se construira — la maquette y
   place la PlayStation à 12:20, or elle ne connaît pas ses horaires.

**Deux leçons de méthode, payées cash, à ne pas réapprendre :**

- **La PR #24 (Steam) a été écrite sans qu'Arthur l'ait demandée.** « On fait le
  cœur du métier » avait été traduit en « une nouvelle source de données », et la
  source choisie était celle qui m'arrangeait techniquement. **Les sources du
  projet sont Mac, PlayStation et TV.** Le code dort sur `feat/steam-source` ; le
  branchement générique d'un `CounterPoller` dans `CollectionEngine` y est
  réutilisable tel quel pour la PlayStation.
- **Un symptôme spectaculaire cache souvent un dégât plus discret.** Le « 51 h »
  du 2026-08-18 se voyait ; les heures de machine éteinte écrites en base comme
  du temps d'écran, non. Chercher la donnée fausse *et fermée*, pas celle qui
  saute aux yeux.

**Références visuelles données par Arthur le 2026-08-16** : **Flighty** (couleur
strictement sémantique, hiérarchie typographique sans milieu, forte densité de
faits utiles par ligne), **Notion Calendar** (même philosophie en neutre), et une
app de fitness fond noir à accent vert acide qu'il a apportée puis dont il n'a pas
retenu l'implémentation. La règle commune tient : *la donnée est le design*.
Détail dans la skill `pulseon-design`. **Sa maquette du 2026-08-17 fait
désormais foi** pour la journée.

## Continuité entre sessions Claude

Ce fichier est relu automatiquement à chaque nouvelle session dans ce
dossier, et la mémoire long-terme complète avec le *pourquoi* des décisions.
Le tenir à jour à chaque décision structurante est ce qui assure la
continuité — pas besoin de recopier la conversation.

Ne pas relancer la discussion iPhone sans relire la section contrainte.

## Skills Claude

### Maison (à charger avant de toucher aux vues)

- **`pulseon-design`** — les règles non négociables du dessin (ne jamais inventer
  un horaire, « pas branchée » ≠ « zéro », tronquer et non arrondir, un seul rail
  et non une piste par appareil, aucune comparaison qui juge) et ce que les
  previews ont déjà trouvé. **La direction visuelle elle-même est en attente des
  maquettes d'Arthur** : la skill liste les trois directions essayées et écartées,
  pour qu'aucune session ne les repropose.
- **`pulseon-preview`** — `./Scripts/preview.sh` rend les vues en PNG hors
  écran, puis on les regarde. Lancer l'app à la place corromprait la base (deux
  collecteurs sur le même store) et suppose quelqu'un devant l'écran. A trouvé
  en une session trois défauts qu'aucun test ne voyait, dont une grille horaire
  qui partait de midi.

### Installées via `npx skills add` (voir `skills-lock.json`)

- `frontend-design` (anthropics/skills) — direction visuelle
- `webapp-testing` (anthropics/skills) — tests navigateur via Playwright,
  **devenu sans objet** depuis l'abandon du front web
- `handoff` (mattpocock/skills) — compresse une session en doc pour reprise

`agent-manager-skill` (fractalmind-ai) a été volontairement écartée —
auteur moins connu, capacités puissantes (tmux/cron), bloquée par le
classificateur de sécurité de Claude Code.
