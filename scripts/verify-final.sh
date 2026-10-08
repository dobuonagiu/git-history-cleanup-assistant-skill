#!/usr/bin/env bash
# Fasi 13/15: verifica finale (rescan + file rimossi + esclusioni preservate).
# Uso: verify-final.sh <repo-path> <label> [--removed F] [--replace F] [--keep F] [--baseline <backup-mirror>]
# Exit: 0 = tutto OK, 1 = problemi, 2 = scansione incompleta
set -uo pipefail
source "$(dirname "$0")/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"

[ $# -ge 2 ] || die "Uso: $0 <repo-path> <label> [--removed F] [--replace F] [--keep F] [--baseline REPO]"
REPO="$1"; LABEL="$2"; shift 2
REMOVED=""; REPL=""; KEEP=""; BASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --removed) REMOVED="$2"; shift 2;;
    --replace) REPL="$2"; shift 2;;
    --keep) KEEP="$2"; shift 2;;
    --baseline) BASE="$2"; shift 2;;
    *) die "Opzione sconosciuta: $1";;
  esac
done
problems=0; incomplete=0
R="$REPORT_DIR/verify-$LABEL.md"
{ echo "# Verifica $LABEL"; echo; echo "Repo: $REPO"; echo; } > "$R"
log() { echo "$*" | tee -a "$R"; }

# 1. Rescan secret
"$HERE/scan-secrets.sh" "$REPO" "$LABEL"; rc=$?
case $rc in
  0) log "- Secret: nessun finding (PASS)";;
  1) log "- Secret: finding residui (FAIL) - vedi $REPORT_DIR/$LABEL-*.json"; problems=1;;
  *) log "- Secret: scansione incompleta (tool mancanti/errori)"; incomplete=1;;
esac

# 2. File rimossi assenti dalla history
if [ -n "$REMOVED" ]; then
  present="$(gr "$REPO" log --all --name-only --format= | sort -u | python3 "$HERE/match_paths.py" "$REMOVED")"
  if [ -z "$present" ]; then log "- File da rimuovere: assenti dalla history (PASS)"
  else log "- File da rimuovere ANCORA presenti (FAIL):"; echo "$present" | sed 's/^/    /' | tee -a "$R"; problems=1; fi
fi

# 3. Valori letterali sostituiti assenti
if [ -n "$REPL" ]; then
  bad=0
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    pat="${line%%==>*}"
    case "$pat" in regex:*|glob:*) continue;; esac
    [ -n "$(gr "$REPO" log --all --format=%h -S"${pat#literal:}" | head -1)" ] && bad=1
  done < "$REPL"
  if [ "$bad" -eq 0 ]; then log "- Valori da sostituire: non più presenti (PASS)"; else log "- Valori da sostituire ANCORA presenti (FAIL)"; problems=1; fi
fi

# 4. Esclusioni preservate
if [ -n "$KEEP" ]; then
  tips() { gr "$1" for-each-ref --format='%(refname)' refs/heads | while read -r r; do gr "$1" ls-tree -r --name-only "$r"; done | sort -u; }
  now="$(tips "$REPO")"
  was=""; [ -n "$BASE" ] && was="$(tips "$BASE")"
  keepmiss=0
  while IFS= read -r k; do
    [[ "$k" =~ ^[[:space:]]*(#|$) ]] && continue
    if echo "$now" | grep -qxF "$k"; then log "- Preservato: $k (PASS)"
    elif [ -n "$BASE" ] && ! echo "$was" | grep -qxF "$k"; then log "- Assente anche nel baseline: $k (n/a)"
    else log "- Esclusione PERSA: $k (FAIL)"; keepmiss=1; fi
  done < "$KEEP"
  [ "$keepmiss" -eq 0 ] || problems=1
fi

log
if [ "$problems" -ne 0 ]; then log "ESITO: FALLITO"; exit 1; fi
if [ "$incomplete" -ne 0 ]; then log "ESITO: INCOMPLETO (installare i tool mancanti e rieseguire)"; exit 2; fi
log "ESITO: OK"
log "Ricorda: rigenerare tutte le credenziali esposte."
state_set "VERIFY_${LABEL//[^A-Za-z0-9]/_}" OK
