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

**Limite connue, pas encore traitée** : l'exécutable SwiftPM n'est pas un
`.app`. Pas de `LSUIElement`, pas de lancement à l'ouverture de session, pas
de signature — et **CloudKit (étape 5) exigera un vrai bundle**. Il faudra
donc soit un projet Xcode, soit un bundle fabriqué à la main. À trancher
avant l'étape 5, pas après.

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
3. App macOS : agent barre de menu qui collecte l'usage Mac. **Le collecteur
   tourne et persiste** ; restent l'empaquetage en `.app` et le lancement
   automatique à l'ouverture de session.
4. App iOS : le dashboard, avec la journée en multipiste.
5. Synchro CloudKit entre les deux (dépend de l'Apple Developer Program).
6. Collecteur PlayStation, puis TV.
7. Réévaluer l'intégration iPhone.

## Continuité entre sessions Claude

Ce fichier est relu automatiquement à chaque nouvelle session dans ce
dossier, et la mémoire long-terme complète avec le *pourquoi* des décisions.
Le tenir à jour à chaque décision structurante est ce qui assure la
continuité — pas besoin de recopier la conversation.

Ne pas relancer la discussion iPhone sans relire la section contrainte.

## Skills Claude installées (test)

Installées via `npx skills add` dans `.claude/skills/` (voir
`skills-lock.json`) :
- `frontend-design` (anthropics/skills) — direction visuelle
- `webapp-testing` (anthropics/skills) — tests navigateur via Playwright,
  **devenu sans objet** depuis l'abandon du front web
- `handoff` (mattpocock/skills) — compresse une session en doc pour reprise

`agent-manager-skill` (fractalmind-ai) a été volontairement écartée —
auteur moins connu, capacités puissantes (tmux/cron), bloquée par le
classificateur de sécurité de Claude Code.
