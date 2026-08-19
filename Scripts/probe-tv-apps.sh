#!/bin/bash
# Cherche ce que l'API locale de la télé sait dire des **applications**.
#
# À lancer depuis le réseau de la télé, **écran allumé**, et de préférence avec
# une app ouverte dessus (Netflix, YouTube…) pour que la différence se voie.
#
#   ./Scripts/probe-tv-apps.sh            # hôte lu dans les réglages Pulseon
#   ./Scripts/probe-tv-apps.sh 192.168.1.42
#
# Pourquoi une sonde et pas directement du code : sur cette télé, supposer a
# déjà coûté cher. L'idée de détecter l'écran au ping paraissait évidente et
# était fausse — la puce réseau répond en veille, donc une nuit éteinte aurait
# compté comme du temps d'écran. Seule la mesure l'a montré. On mesure d'abord,
# on code ensuite.
#
# Rien ne sort du réseau local : ce script ne parle qu'à la télé.

set -uo pipefail

HOST="${1:-$(defaults read com.arthurlanllier.pulseon TVHost 2>/dev/null)}"
PORT=8001

if [ -z "$HOST" ]; then
    echo "Aucun hôte. Passe-le en argument, ou règle-le :"
    echo '  defaults write com.arthurlanllier.pulseon TVHost "Samsung.local"'
    exit 1
fi

BASE="http://$HOST:$PORT/api/v2"
echo "→ Télé visée : $BASE"
echo

# `--max-time` court : une télé qui ne répond pas doit le dire vite, pas geler
# la sonde. `-s` sans `-f` pour garder le corps des réponses d'erreur, qui est
# souvent la partie instructive.
probe() {
    local label="$1" path="$2"
    local code body
    body=$(curl -s --max-time 5 -w $'\n%{http_code}' "$BASE$path" 2>/dev/null)
    code=$(printf '%s' "$body" | tail -1)
    body=$(printf '%s' "$body" | sed '$d')

    printf '%-34s ' "$label"
    case "$code" in
        200) echo "200 OK";  printf '%s\n' "$body" | head -c 600; echo; echo ;;
        000) echo "pas de réponse (port fermé, hôte injoignable, ou télé éteinte)" ;;
        *)   echo "HTTP $code"; [ -n "$body" ] && { printf '   %s\n' "$(printf '%s' "$body" | head -c 200)"; } ;;
    esac
}

echo "== Ce qui marche déjà (référence) =="
probe "/ (PowerState)" "/"

echo "== Liste des apps installées =="
# Présent sur les modèles anciens ; souvent retiré depuis 2022.
probe "/applications/" "/applications/"

echo "== État d'une app connue =="
# On ne peut interroger que des identifiants qu'on connaît déjà : cette API ne
# découvre rien, elle répond « celle-ci tourne-t-elle ? ». Si ça marche, la
# collecte consisterait à balayer cette liste à chaque relevé.
probe "Netflix (3201907018807)"     "/applications/3201907018807"
probe "YouTube (111299001912)"      "/applications/111299001912"
probe "Prime Video (3201910019365)" "/applications/3201910019365"
probe "Disney+ (3201901017640)"     "/applications/3201901017640"
probe "Spotify (3201606009684)"     "/applications/3201606009684"

echo "== Autres pistes =="
probe "/channels/" "/channels/"

cat <<'NOTE'
Comment lire ce qui précède
---------------------------
* Une réponse 200 sur « /applications/... » avec un champ `visible` ou `running`
  est LE signal utile : la télé dirait alors quelle app est à l'écran, au même
  niveau de détail que le nom d'app côté Mac — sans rien révéler du contenu.
* Des 404 partout signifient que Samsung a fermé cette API sur ce millésime.
  Il resterait la voie WebSocket (`samsung.remote.control`), qui exige un
  appairage : un message d'autorisation s'affiche sur la télé et rend un jeton.
  Plus intrusif à installer, mais toujours 100 % local.
* Rien du tout, alors que la télé est allumée et le Mac sur le même réseau,
  signifie que même le point d'entrée de référence ne répond pas : la mesure ne
  vaut rien, il faut recommencer dans de bonnes conditions.
NOTE
