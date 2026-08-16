# Pulseon

App native Apple pour suivre le temps passé sur Mac, PlayStation, TV, et
(potentiellement, plus tard) iPhone. **iOS d'abord**, macOS ensuite.

## Sources de données et statut

| Source      | Statut  | Méthode                                                                 |
|-------------|---------|-------------------------------------------------------------------------|
| Mac         | À faire | `NSWorkspace` (app active) + `Quartz` (inactivité), depuis l'app macOS  |
| PlayStation | À faire | API non-officielle PSN — poll de `playDuration` par jeu, temps journalier = delta entre deux relevés |
| TV          | À faire | Prise connectée avec mesure de conso (type Shelly / TP-Link Kasa) — détecte allumage/extinction |
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

Le démarrage automatique s'active ensuite depuis le menu de l'app.

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

**Et une leçon sur la vérification** : `lsappinfo info -only ApplicationType`
répond `Foreground` dès que l'app est active, *quelle que soit* sa politique
d'activation. Ça ne distingue pas `.regular` de `.accessory` — le relevé
automatique n'a rien prouvé, c'est l'œil d'Arthur qui a validé. À retenir avant
de bâtir une sonde : vérifier qu'elle mesure bien ce qu'on croit.

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

### Le dashboard : la journée en multipiste

Vit dans **`PulseonUI`**, un paquet à part et non dans l'app macOS, parce que
ce sont *les mêmes vues* qui serviront à l'app iOS : le jour où la cible iOS
existera, elle consomme ce paquet sans qu'une ligne de dessin soit réécrite.
D'où l'interdiction d'y toucher à AppKit, qui n'existe pas sur iPhone —
`.buttonStyle(.link)` s'y est déjà fait refuser.

**Direction visuelle : la station de travail.** Le vocabulaire du projet était
déjà celui d'un séquenceur (« multipiste », « piste », « signal », « marqueur
d'heure courante », une icône `waveform`), donc la journée est dessinée comme
un rack d'appareil de mesure. Le rack **reste sombre même en apparence
claire** : un instrument ne change pas de couleur avec le papier peint, et les
blocs d'activité ne se lisent qu'en couleur saturée sur fond sombre. Le reste
de la fenêtre suit le système, comme n'importe quelle app native.

La signature est **la tête de lecture** : une ligne rouge qui traverse les
pistes à l'heure courante, avec l'heure en cartouche. Rouge parce que c'est la
couleur de l'enregistrement en cours sur une station audio — ici, la journée
en train de s'écrire. Elle n'apparaît **que sur aujourd'hui** : une journée
passée est entièrement jouée, y planter une tête de lecture ne voudrait rien
dire. Ce rouge ne sert qu'à ça, aucun autre élément ne le porte.

**Les couleurs portent de l'information** : une par appareil, tenue partout
(pastille du détail comprise). Elles ne se choisissent pas à l'humeur.

**Une source à compteur ne doit occuper aucune position dans la journée.** La
première version calait le bloc PlayStation à gauche : hachuré, certes, mais il
se lisait « joué de minuit à 1 h 48 ». Les hachures ne suffisent pas si la
*position*, elle, ment. Le bloc est donc **centré**, sa piste n'a **pas de
graduations horaires** — une grille donnerait un sens à une position qui n'en a
aucun — et le libellé « heure inconnue » est posé à côté, où il reste lisible
même quand le bloc est court.

**Voir les vues sans lancer l'app.** `ImageRenderer` rend n'importe quelle vue
en PNG hors écran, ce qui permet de regarder le résultat sans fenêtre, sans
simulateur, et sans lancer une seconde instance du collecteur — qui écrirait
dans la même base. Ça a trouvé deux défauts qu'aucun test ne pouvait voir :
une étiquette « PLAYSTATIO/N » coupée, et une grille horaire qui partait de
midi. Ce dernier mérite d'être retenu : **un `ZStack` de rectangles d'un point
ne mesure qu'un point de large**, donc l'`overlay` le centrait dans la piste et
toute la matinée n'avait aucune graduation. Rien ne le signale, ni le
compilateur ni les tests. D'où `.frame(maxWidth: .infinity, alignment:
.leading)`.

`TimelineGeometry` tient tout le calcul de placement, séparé des vues pour être
testable sans simulateur — même raison que `PulseonCore`. La longueur du jour
lui est **fournie**, jamais supposée égale à 86 400 : les journées de
changement d'heure font 23 ou 25 h, et une timeline qui l'ignore décale toute
la soirée de ces jours-là. Elle garantit aussi qu'une minute d'activité reste
visible (plancher de 2 points) : 60 s sur 24 h font 0,7 point, et une minute
invisible reviendrait à dire qu'elle n'a pas eu lieu.

`DayBrowser` (dans `PulseonMacKit`) choisit la journée affichée et va la
chercher. Il interdit de naviguer dans le futur — aucune donnée ne peut exister
demain — et relit chaque minute, parce qu'une journée en cours grandit pendant
qu'on la regarde. C'est lui qu'on remplacera pour iOS, pas le dessin.

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

### Comparer une journée aux précédentes

Un total seul ne veut rien dire, et c'est le manque qu'Arthur a ressenti en
ouvrant la fenêtre : « 9 h 39 », est-ce beaucoup ou est-ce sa normale ?
`DayComparison` répond, et `DayBrowser` l'expose à côté de la journée.

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

L'élément signature est **la journée en multipiste** : une piste par
appareil sur 24 h, l'activité tracée en signal, avec un marqueur sur l'heure
courante. On y voit les chevauchements et les trous — ce qu'un total en
barres ne dira jamais. La donnée est faite d'intervalles parallèles, le
multipiste est sa forme naturelle.

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

Aucun `sudo` n'est nécessaire, contrairement à ce qui était noté ici avant :
la licence est déjà acceptée, `DEVELOPER_DIR` suffit. Pour s'en passer
définitivement (et faire taire le `No such module 'Testing'` de l'éditeur,
car SourceKit, lui, ne lit pas cette variable), une seule fois dans un vrai
terminal — le `!` de Claude Code n'a pas de TTY, donc `sudo` y échoue :

```
sudo xcode-select -s /Applications/Xcode.app
```

## Doc de référence du code

Visite guidée des 744 lignes, écrite pour Arthur qui apprend Swift depuis
zéro : https://claude.ai/code/artifact/65616a6f-3229-4a29-bc5f-4b3302b2926a

Elle décrit chaque fichier, le trajet d'une donnée, et les notions Swift
accrochées à de vraies lignes du projet. **À mettre à jour quand
l'architecture bouge** — republier le même fichier met à jour la même URL.

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
4. Dashboard : la journée en multipiste. **Ébauche livrée côté macOS**
   (`PulseonUI`), volontairement d'abord dans une fenêtre Mac — l'app existe,
   elle a les vraies données en local, et ça ne demande ni compte payant ni
   projet Xcode. Reste **en attente de la liste d'Arthur** pour la suite : ne
   pas la lui inventer.
   - Porter ces vues sur iOS est l'étape B, et c'est un portage, pas une
     construction : il faudra un projet Xcode (SwiftPM seul ne fabrique pas
     d'app iOS) et le compte payant. Stack rediscutée puis reconfirmée le
     2026-08-15 : **rester en Swift**, Expo ne cible pas macOS, ne peut pas
     porter les collecteurs natifs, et remplacerait CloudKit par un backend
     à héberger.
5. Synchro CloudKit entre les deux (dépend de l'Apple Developer Program).
6. Collecteur PlayStation, puis TV.
7. Réévaluer l'intégration iPhone.

### État au 2026-08-16 (fin de session de nuit)

Ce qui tourne : le collecteur Mac est installé dans `/Applications`, démarre à
l'ouverture de session, et affiche le total du jour dans la barre de menu — qui
**défile désormais à la seconde** (`3h07:12`). Le **dashboard existe** : fenêtre
macOS ouverte depuis le menu (« Ouvrir la journée », ⌘J), avec la journée en
multipiste. 52 tests verts sur `main`.

Livré cette nuit, tout mergé (PR #17 et #18) : le libellé de la barre de menu
qui ne s'affichait pas, le compteur à la seconde, les pauses courtes comptées
comme du temps d'écran, et l'ébauche du dashboard.

Ce qui n'a **pas** été vérifié à l'œil : le dashboard n'a été regardé qu'en PNG
rendus hors écran, jamais dans la vraie fenêtre avec les vraies données. À faire
au prochain démarrage — les chevrons de navigation ‹ › en particulier, que
`ImageRenderer` ne sait pas rendre.

Ce qui bloque, et sur quoi :

- **PlayStation** : toute la plomberie est prête (`CounterSource`,
  `CounterPoller`, `record()` dédoublonné, `PlayDuration`, `Secrets`). Il ne
  manque que le client HTTP — et le jeton, qu'Arthur n'a pas pu récupérer,
  n'arrivant plus à se connecter à son compte PSN. Le jeton se dépose à la
  main dans le Trousseau, **jamais dans la conversation ni dans un fichier**.
- **TV** : bloquée matériellement, pas de prise connectée. Viser une Shelly
  (API HTTP locale, sans cloud). Ce sera une source à **intervalles**, pas à
  compteur : `openSession` / `closeOpenSession`, comme le Mac.
- **Widget macOS** (le vrai, centre de notifications) : extension d'app, donc
  projet Xcode et signature — même mur que CloudKit.

~~Point en suspens : le texte de la barre de menu s'affiche-t-il sans
cliquer ?~~ **Non, il ne s'affichait pas** — le doute était fondé. Corrigé
depuis (`Label` → `Text` interpolé, voir « Ce que la barre de menu affiche »),
et le compteur défile désormais à la seconde. À retenir : quand Arthur décrit
un comportement observé, prendre la formulation au pied de la lettre plutôt
que la reformuler dans le sens attendu.

Dette de doc connue : la visite guidée du code (lien plus haut) décrit
744 lignes et sept fichiers de moins que la réalité — dix maintenant, avec
`PulseonUI`. À reprendre, puisqu'elle sert à Arthur pour lire son propre code.

Références visuelles données par Arthur le 2026-08-16, à respecter quand le
design évolue : **Flighty** (couleur strictement sémantique, hiérarchie
typographique sans milieu, forte densité de faits utiles par ligne) et **Notion
Calendar** (même philosophie en neutre et discret). Le point commun, qui est la
règle : *la donnée est le design*. Voir la skill `pulseon-design`.

## Continuité entre sessions Claude

Ce fichier est relu automatiquement à chaque nouvelle session dans ce
dossier, et la mémoire long-terme complète avec le *pourquoi* des décisions.
Le tenir à jour à chaque décision structurante est ce qui assure la
continuité — pas besoin de recopier la conversation.

Ne pas relancer la discussion iPhone sans relire la section contrainte.

## Skills Claude

### Maison (à charger avant de toucher aux vues)

- **`pulseon-design`** — la direction visuelle : l'instrument de mesure, les
  couleurs par appareil, la typographie d'afficheur, les règles non négociables
  (ne jamais inventer un horaire, « pas branchée » ≠ « zéro », tronquer et non
  arrondir) et la liste de ce qui trahit un design généré. Sans elle, chaque
  session redécouvre la direction et l'app dérive.
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
