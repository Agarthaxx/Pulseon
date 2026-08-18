---
name: pulseon-preview
description: Rendre les vues SwiftUI de Pulseon en PNG et les regarder, sans lancer l'app. À utiliser après toute modification d'une vue, et avant de dire qu'elle est finie.
---

# Regarder les vues de Pulseon

```
./Scripts/preview.sh          # rend et ouvre les images
./Scripts/preview.sh --quiet  # rend seulement, affiche les chemins
```

Puis **lire les PNG** (l'outil de lecture de fichiers affiche les images). Les
chemins sont affichés par le script.

## Rendre pour soi ne suffit pas : ouvrir pour Arthur

**Payé le 2026-08-18.** Toute une session rendue en `--quiet` : les images ont
été lues par l'agent, jamais ouvertes sur l'écran d'Arthur. Il a donc annoncé
« je ne vois aucun changement » puis « je ne vois pas les logos » — et il avait
raison **deux fois**, pour deux causes différentes qu'il fallait démêler
séparément :

1. l'app installée dans `/Applications` datait d'avant la session — le code
   d'une branche ne change rien à ce qui tourne, il faut rebâtir et réinstaller ;
2. les PNG existaient bien, avec les logos dedans, mais **personne ne les lui
   avait montrés**.

D'où la règle : `--quiet` pour un enchaînement automatique, mais **`open` sur les
images dès qu'on annonce un résultat visuel**. Décrire un rendu qu'on est seul à
voir, c'est demander à Arthur de croire sur parole ce qu'il a précisément
demandé à voir.

Et **une preview ne remplace jamais l'app** quand la question est « est-ce que ça
marche chez moi » : la preview affiche un jeu de démonstration avec les apps qui
se trouvent sur la machine, l'app affiche ses vraies données. Installer demande
de quitter le collecteur en cours — donc de le demander d'abord.

## Pourquoi ça existe

Une vue qui compile et dont les tests passent peut être visiblement fausse. En
une seule session, ce rendu a trouvé :

- une étiquette de piste coupée en deux lignes (« PLAYSTATIO / N ») ;
- un bloc PlayStation calé à gauche, qui se lisait « joué de minuit à 1 h 48 »
  alors que son horaire est justement inconnu ;
- une grille horaire qui partait de midi — un `ZStack` de rectangles d'un point
  ne mesure qu'un point de large, donc l'`overlay` le centrait dans la piste, et
  toute la matinée n'avait aucune graduation.

Aucun de ces défauts ne produit d'erreur de compilation ni d'échec de test.
**Un design qu'on ne regarde pas est un design qu'on ne corrige pas.**

## Pourquoi pas simplement lancer l'app

Deux raisons, toutes deux vérifiées :

- **Lancer une seconde instance corrompt les données.** L'app démarre le
  collecteur, qui écrirait dans la même base que l'instance déjà en cours.
- **Une capture d'écran suppose quelqu'un devant l'écran.** L'autorisation
  d'enregistrement d'écran n'est pas accordée au terminal, donc `screencapture`
  échoue — et de toute façon Arthur n'est pas toujours là.

`ImageRenderer` rend n'importe quelle vue SwiftUI hors écran, sans fenêtre, sans
simulateur et sans toucher à la base.

## Ce qui est rendu

`Tools/Preview/Sources/Preview/main.swift`, un paquet séparé du paquet
principal parce qu'il n'a rien à faire dans l'app livrée :

| Image | Ce qu'elle vérifie |
|---|---|
| `pulseon-dark` / `pulseon-light` | La journée type dans les deux apparences |
| `pulseon-empty` | Une journée passée sans aucune source branchée |
| `pulseon-failed` | L'échec de lecture, qui ne doit pas ressembler à zéro |
| `pulseon-narrow` | Fenêtre étroite : la règle s'allège, rien ne déborde |
| `pulseon-mac-only` | Le cas réel d'Arthur : un seul appareil branché |
| `pulseon-wide` | Fenêtre large : la colonne reste bornée |

**Ajouter un cas quand on ajoute un état.** Un état qu'on ne rend pas est un
état qu'on ne regarde jamais — et ce sont les états rares (vide, en erreur,
étroit) qui sont livrés cassés.

## Ce que le rendu hors écran sait faire, et ce qu'il ne sait pas

**Corrigé le 2026-08-18, l'ancienne note était trop large et faisait ignorer de
vrais défauts.** Les `Image(systemName:)` posées dans une vue se rendent très
bien — les pastilles de catégorie, les chevrons de navigation et la flèche de la
comparaison sortent nettes. Ce qui ne se rend pas, c'est un `Button` **au style
par défaut**, remplacé par un carré jaune : d'où les `.buttonStyle(.plain)` du
dashboard, qui ne sont pas cosmétiques.

Les **icônes d'apps**, elles, sont réelles : `AppIconSource` interroge le vrai
`NSWorkspace` de la machine. Une app absente du Mac n'a donc pas de logo dans la
preview (« IINA », « Slack » dans le jeu de démonstration) — ce n'est pas un
défaut de la vue, et ça montre au passage le repli qu'on veut vérifier : le nom
seul, jamais un carré vide.

## Quoi regarder

- Les blocs tombent-ils en face de leur heure sur la règle ?
- Les blocs très courts restent-ils visibles ? (une minute sur 24 h fait 0,7
  point : il y a un plancher, vérifier qu'il tient)
- Les étiquettes sont-elles coupées, tronquées, sur deux lignes ?
- La tête de lecture est-elle à la bonne heure, et absente sur une journée
  passée ?
- La piste PlayStation ment-elle sur l'horaire ? (voir la skill
  `pulseon-design`, règle non négociable n° 1)
