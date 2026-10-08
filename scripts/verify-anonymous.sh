#!/usr/bin/env bash
# Fase 15: verifica ANONIMA dopo il push (senza credenziali) + superfici di esposizione.
# Uso: verify-anonymous.sh <REMOTE_URL> [--commits FILE] [--sha SHA ...]
#   --commits  file con SHA vecchi (default: $REPORT_DIR/dryrun-affected-commits.txt)
# Controlla, senza autenticazione:
#   - il repo è leggibile anonimamente? (git ls-remote con credenziali disabilitate)
#   - i vecchi commit sono ancora raggiungibili via URL (200) o no (404)?
# Interpretazione: 404 non prova la rimozione se il repo è privato. Un 200 su GitHub è atteso finché
# il provider non fa gc: NON è un errore di bonifica, ma va riportato come esposizione residua.
# Variabile: COMMIT_URL_TEMPLATE (default https://github.com/<owner>/<repo>/commit/<sha>)
set -uo pipefail
source "$(dirname "$0")/lib.sh"
[ $# -ge 1 ] || die "Uso: $0 <REMOTE_URL> [--commits FILE] [--sha SHA]"
URL="$1"; shift
FILE="$REPORT_DIR/dryrun-affected-commits.txt"; SHAS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --commits) FILE="$2"; shift 2;;
    --sha) SHAS+=("$2"); shift 2;;
    *) die "Opzione sconosciuta: $1";;
  esac
done
[ "${#SHAS[@]}" -gt 0 ] || { [ -f "$FILE" ] && mapfile -t SHAS < "$FILE"; }
[ "${#SHAS[@]}" -gt 0 ] || die "Nessun SHA da verificare (usare --sha o --commits)"

R="$REPORT_DIR/anonymous-check.md"; : > "$R"
log() { echo "$*" | tee -a "$R"; }
need curl

log "# Verifica anonima ($URL)"
anon_rc=0
GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/true git -c credential.helper= ls-remote "$URL" >/dev/null 2>&1 || anon_rc=$?
if [ "$anon_rc" -eq 0 ]; then log "- Repo leggibile ANONIMAMENTE (pubblico)"; else log "- Repo non leggibile anonimamente (privato o non raggiungibile)"; fi

if [ -z "${COMMIT_URL_TEMPLATE:-}" ]; then
  if [[ "$URL" =~ github\.com[:/]+([^/]+)/([^/]+)$ ]]; then
    COMMIT_URL_TEMPLATE="https://github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}/commit/<sha>"
  else
    log "- Provider non GitHub: raggiungibilità dei vecchi commit NON verificata (impostare COMMIT_URL_TEMPLATE)"
    exit 0
  fi
fi

reach=0; gone=0
for sha in "${SHAS[@]}"; do
  [ -n "$sha" ] || continue
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "${COMMIT_URL_TEMPLATE//<sha>/$sha}" || echo 000)"
  case "$code" in
    200) reach=$((reach + 1)); log "- ${sha:0:10}: ANCORA raggiungibile anonimamente (HTTP 200)";;
    404) gone=$((gone + 1)); log "- ${sha:0:10}: non raggiungibile (HTTP 404)";;
    *)   log "- ${sha:0:10}: non determinabile (HTTP $code)";;
  esac
done
log
log "Raggiungibili: $reach  Non raggiungibili: $gone"
if [ "$reach" -gt 0 ]; then
  log "RESIDUO: vecchi commit ancora visibili (cache/oggetti orfani/PR/fork). Rotare le credenziali e valutare richiesta al supporto del provider."
  exit 1
fi
[ "$anon_rc" -ne 0 ] && log "Nota: repo privato, un 404 anonimo non prova la rimozione degli oggetti."
exit 0
