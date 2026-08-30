#!/bin/bash
# Cherche ce que l'API PlayStation sait dire des **temps de jeu**.
#
#   ./Scripts/probe-psn.sh
#
# Le jeton `npsso` est lu dans le Trousseau, jamais passé en argument : un
# argument finirait dans l'historique du shell, et ce jeton vaut une session
# complète sur le compte Sony. Pour le déposer, une seule fois :
#
#   security add-generic-password -s "com.arthurlanllier.pulseon.psn" \
#       -a "npsso" -U -w
#
# (la commande demande la valeur sans l'afficher — à lancer dans un vrai
# terminal, le `!` de Claude Code n'a pas de TTY)
#
# Pourquoi une sonde et pas directement du code : sur la télé, supposer a déjà
# coûté cher — l'idée de détecter l'écran au ping était évidente et fausse.
# Ici les inconnues sont du même genre : l'API PSN n'est pas documentée par
# Sony, elle est **constatée**. On mesure d'abord, on code ensuite.
#
# Ce script parle à Sony, et à personne d'autre. Aucune valeur de jeton n'est
# affichée, pas même tronquée.

set -uo pipefail

NPSSO=$(security find-generic-password -s "com.arthurlanllier.pulseon.psn" \
    -a "npsso" -w 2>/dev/null)

if [ -z "$NPSSO" ]; then
    echo "Aucun jeton npsso dans le Trousseau."
    echo
    echo "1. Connecte-toi sur https://www.playstation.com (compte PSN)"
    echo "2. Ouvre https://ca.account.sony.com/api/v1/ssocookie"
    echo "3. Copie la valeur de \"npsso\" (64 caractères)"
    echo "4. Dépose-la, dans un vrai terminal :"
    echo '     security add-generic-password -s "com.arthurlanllier.pulseon.psn" -a "npsso" -U -w'
    exit 1
fi

echo "→ Jeton trouvé dans le Trousseau (${#NPSSO} caractères)"
echo

# Ces deux valeurs sont celles de l'app mobile PlayStation officielle. Elles
# sont publiques (n'importe quel client les envoie en clair) et ne sont pas un
# secret : le secret, c'est le npsso.
CLIENT_ID="09515159-7237-4370-9b40-3806e67c0891"
BASIC="MDk1MTUxNTktNzIzNy00MzcwLTliNDAtMzgwNmU2N2MwODkxOnVjUGprYTV0bnRCMktxc1A="
REDIRECT="com.scee.psxandroid.scecompcall://redirect"

# ── 1. Le npsso s'échange contre un code d'autorisation ──────────────────────
# La réponse est une redirection 302 dont l'en-tête `location` porte le code.
# `-o /dev/null -D -` : on jette le corps, on garde les en-têtes.
echo "── 1. npsso → code d'autorisation"
AUTH_HEADERS=$(curl -s -o /dev/null -D - --max-time 15 \
    -H "Cookie: npsso=$NPSSO" \
    "https://ca.account.sony.com/api/authz/v3/oauth/authorize?access_type=offline&client_id=$CLIENT_ID&redirect_uri=$REDIRECT&response_type=code&scope=psn:mobile.v2.core%20psn:clientapp" \
    2>/dev/null)

STATUS=$(printf '%s' "$AUTH_HEADERS" | head -1)
LOCATION=$(printf '%s' "$AUTH_HEADERS" | grep -i '^location:' | tr -d '\r' | cut -d' ' -f2-)
echo "   statut   : $STATUS"

CODE=$(printf '%s' "$LOCATION" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p')
if [ -z "$CODE" ]; then
    echo "   ✗ Aucun code dans la redirection."
    echo "     location : ${LOCATION:-aucune}"
    echo
    echo "   Cause la plus probable : le npsso a expiré (il vit ~2 mois)."
    echo "   Reprendre à l'étape 2 ci-dessus pour en déposer un neuf."
    exit 1
fi
echo "   ✓ code obtenu (${#CODE} caractères)"
echo

# ── 2. Le code s'échange contre un jeton d'accès ─────────────────────────────
echo "── 2. code → jeton d'accès"
TOKENS=$(curl -s --max-time 15 -X POST \
    -H "Authorization: Basic $BASIC" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "code=$CODE" \
    --data-urlencode "redirect_uri=$REDIRECT" \
    --data-urlencode "grant_type=authorization_code" \
    --data-urlencode "token_format=jwt" \
    "https://ca.account.sony.com/api/authz/v3/oauth/token" 2>/dev/null)

ACCESS=$(printf '%s' "$TOKENS" | jq -r '.access_token // empty')
if [ -z "$ACCESS" ]; then
    echo "   ✗ Pas de jeton d'accès. Réponse :"
    printf '%s\n' "$TOKENS" | jq . 2>/dev/null || printf '%s\n' "$TOKENS"
    exit 1
fi
# Ce qui nous intéresse pour le collecteur : combien de temps ce jeton vit,
# et si un jeton de rafraîchissement évite de repasser par le npsso.
printf '   ✓ jeton d'"'"'accès obtenu — expire_in=%s, refresh_expires_in=%s, refresh=%s\n' \
    "$(printf '%s' "$TOKENS" | jq -r '.expires_in // "?"')" \
    "$(printf '%s' "$TOKENS" | jq -r '.refresh_token_expires_in // "?"')" \
    "$(printf '%s' "$TOKENS" | jq -r 'if .refresh_token then "oui" else "non" end')"
echo

# ── 3. Ce que l'API veut bien dire des jeux ──────────────────────────────────
ask() {
    local label="$1" url="$2"
    local body code
    body=$(curl -s --max-time 15 -w $'\n%{http_code}' \
        -H "Authorization: Bearer $ACCESS" "$url" 2>/dev/null)
    code=$(printf '%s' "$body" | tail -1)
    body=$(printf '%s' "$body" | sed '$d')

    echo "── $label"
    echo "   $url"
    echo "   statut : $code"
    if [ "$code" = "200" ]; then
        printf '%s\n' "$body" | jq . 2>/dev/null | head -60 || printf '%s\n' "$body" | head -c 1200
    else
        printf '%s\n' "$body" | head -c 400
    fi
    echo
    echo
}

ask "3. La liste des jeux joués (playDuration)" \
    "https://m.np.playstation.com/api/gamelist/v2/users/me/titles?limit=200&offset=0"

ask "4. Le profil (pour vérifier de quel compte on parle)" \
    "https://m.np.playstation.com/api/userProfile/v1/internal/users/me/profiles"

ask "5. Ce qui est en cours, s'il existe quelque chose" \
    "https://m.np.playstation.com/api/userProfile/v1/internal/users/me/basicPresences?type=primary"

echo "── Ce qu'on cherche dans tout ça"
echo "   • un total cumulé par jeu (playDuration, format ISO 8601 \"PT1H23M\")"
echo "   • le nom lisible du jeu, pour ne pas afficher un identifiant"
echo "   • combien de jeux la liste porte, et si elle pagine"
echo "   • si 'basicPresences' dit quelque chose du temps réel (probablement non :"
echo "     s'il ne donne qu'un état en ligne/hors ligne, la PS5 reste une source"
echo "     à compteur, et aucun horaire ne doit être inventé)"
