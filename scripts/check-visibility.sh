#!/usr/bin/env bash
# Fase 2/14: visibilità e fork del repository (mai dedurli dal nome/URL).
# Uso: check-visibility.sh <REMOTE_URL>
# Exit: 0 = privato e senza fork (o provider non verificabile: vedi output)
#       10 = pubblico oppure con fork (la frase del gate G5 diventa più forte)
#       2  = GitHub ma verifica impossibile (gh mancante / non autenticato / errore)
set -uo pipefail
source "$(dirname "$0")/lib.sh"

[ $# -eq 1 ] || die "Uso: $0 <REMOTE_URL>"
URL="$1"

# https://github.com/owner/repo(.git) | git@github.com:owner/repo(.git) | ssh://git@github.com/owner/repo
if [[ "$URL" =~ github\.com[:/]+([^/]+)/([^/]+)$ ]]; then
  slug="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
else
  warn "Provider non GitHub (o URL non riconosciuto): visibilità/fork NON verificati automaticamente."
  warn "Verificali dal pannello del provider e annotali nel report."
  state_set VISIBILITY unverified
  exit 0
fi

command -v gh >/dev/null 2>&1 || { warn "gh non installato: visibilità di $slug NON verificata."; state_set VISIBILITY unverified; exit 2; }
json="$(gh repo view "$slug" --json visibility,forkCount,isFork,nameWithOwner,isArchived 2>&1)" \
  || { warn "gh repo view fallito per $slug: $json"; state_set VISIBILITY unverified; exit 2; }

vis="$(echo "$json" | jq -r '.visibility')"; forks="$(echo "$json" | jq -r '.forkCount')"
isfork="$(echo "$json" | jq -r '.isFork')"; archived="$(echo "$json" | jq -r '.isArchived')"
echo "Repository : $slug"
echo "Visibilità : $vis"
echo "Fork       : $forks (questo repo è un fork: $isfork)"
state_set VISIBILITY "$vis"; state_set FORK_COUNT "$forks"

[ "$archived" != "true" ] || warn "Repository archiviato: il push fallirà finché non viene riattivato."
if [ "$vis" = "PUBLIC" ] || [ "$forks" != "0" ]; then
  warn "ATTENZIONE: repo pubblico e/o con fork. I fork e i cloni conservano la vecchia history,"
  warn "i commit restano raggiungibili via SHA/cache. Le credenziali vanno ruotate comunque."
  exit 10
fi
ok "Privato e senza fork"
