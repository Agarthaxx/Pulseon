# Screen Time Tracker

Dashboard perso pour suivre le temps passé sur PC, PlayStation, TV, et
(potentiellement, plus tard) iPhone.

## Sources de données et statut

| Source     | Statut       | Méthode                                                                 |
|------------|--------------|--------------------------------------------------------------------------|
| PC (Mac)   | À faire      | Script local (temps d'écran allumé / app active)                        |
| PlayStation| À faire      | API non-officielle `psn-api` — poll quotidien de `playDuration` par jeu, temps journalier = delta entre deux polls |
| TV         | À faire      | Prise connectée avec mesure de conso (type Shelly / TP-Link Kasa) — détecte allumage/extinction |
| iPhone     | Différé      | Voir contrainte ci-dessous                                              |

## Décisions et contraintes connues

- **iPhone : pas d'automatisation 100% fiable possible.** Le framework
  DeviceActivity d'Apple ne laisse pas une app tierce (même perso) accéder
  aux chiffres bruts : `DeviceActivityReport` n'affiche qu'une vue système
  fermée, et `DeviceActivityMonitor` ne donne que des callbacks sur des
  seuils définis à l'avance, pas un flux de données exploitable. Décision :
  on démarre sans iPhone, à revoir plus tard (soit affichage de la vue
  Apple native à côté du reste, soit semi-manuel via Shortcuts).
- **PlayStation** : pas de temps de jeu en temps réel exposé par l'API,
  seulement un total cumulé par jeu (`playDuration`), mis à jour avec un
  délai. On reconstitue le temps journalier par différence entre deux
  relevés.

## Architecture d'exécution

- **Collecte de données** et **dashboard** sont deux choses séparées :
  - La collecte (script PC, poll API PlayStation) doit tourner en arrière-plan
    en continu, indépendamment de toute fenêtre ouverte.
  - Le dashboard ne fait que lire les données déjà accumulées quand on l'ouvre.
- Sur macOS, la collecte en arrière-plan se fait via **launchd** (LaunchAgents)
  — équivalent système d'un cron, lance un script à intervalle régulier ou à
  la connexion, sans app ni terminal ouvert.
- La prise connectée (TV) a sa propre logique côté cloud/webhook, indépendante
  du Mac.

## Continuité entre sessions Claude

Pas besoin de copier-coller la conversation d'une session à l'autre. Ce
fichier `CLAUDE.md` est relu automatiquement à chaque nouvelle session de
travail dans ce dossier, et la mémoire long-terme de Claude complète avec le
contexte (pourquoi les décisions ont été prises). Garder ce fichier à jour à
chaque décision structurante est ce qui assure cette continuité.

## Conventions de développement

- **Une branche par feature ou tâche complexe.** Pas de travail non-trivial
  directement sur `main`.
- **Commits réguliers** au fil de l'avancement (pas un seul gros commit en
  fin de tâche) — pour pouvoir suivre la progression et revenir en arrière
  facilement.
- **Pas de dette de doc** : ce `CLAUDE.md` (et toute doc pertinente) est mis à
  jour en même temps que le code, pas après coup.

## Skills Claude installées (test)

Installées via `npx skills add` dans `.claude/skills/` (voir `skills-lock.json`
à la racine pour les sources exactes) :
- `frontend-design` (anthropics/skills) — qualité visuelle du dashboard
- `webapp-testing` (anthropics/skills) — tests navigateur via Playwright
- `handoff` (mattpocock/skills) — compresse une session en doc pour reprise

`agent-manager-skill` (fractalmind-ai) a été volontairement écartée pour
l'instant — auteur moins connu, capacités puissantes (gestion de processus
via tmux/cron), bloquée par le classificateur de sécurité de Claude Code. À
réévaluer manuellement si besoin.

## Roadmap

1. Stack technique (à définir)
2. Collecte automatique PC + PlayStation + TV, orchestrée via launchd
3. Dashboard unifié (probablement un Artifact ou une petite app locale)
4. Réévaluer l'intégration iPhone

## Notes pour reprendre le fil

Ce fichier doit être tenu à jour à chaque décision structurante ou
changement de scope. Ne pas relancer la discussion iPhone sans relire la
section contrainte ci-dessus.
