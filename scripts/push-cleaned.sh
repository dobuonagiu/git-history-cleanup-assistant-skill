#!/usr/bin/env bash
# Fase 14: force push della history bonificata con LEASE per ref. DISTRUTTIVO sul remoto.
# Uso: push-cleaned.sh <work-dir> <REMOTE_URL> --approval "Confermo il force push" [--ack-exposure]
# Prerequisiti:
#   - verify-final.sh <work> post-cleanup ... con esito OK
#   - remote-preimage.txt (snapshot-remote.sh, Fase 3) sullo stesso URL
#   - se il repo è pubblico / ha fork / visibilità non verificabile: --ack-exposure esplicito dell'utente
# Usa --force-with-lease=<ref>:<sha-atteso> per ogni ref: se il remoto è cambiato dopo lo snapshot
# il push di quel ref viene rifiutato. Non esiste fallback a --force.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"

[ $# -ge 2 ] || die "Uso: $0 <work-dir> <REMOTE_URL> --approval 'Confermo il force push' [--ack-exposure]"
WORK="$1"; URL="$2"; shift 2
APPROVAL=""; ACK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --approval) APPROVAL="$2"; shift 2;;
    --ack-exposure) ACK=1; shift;;
    *) die "Opzione sconosciuta: $1";;
  esac
done
[ "$APPROVAL" = "Confermo il force push" ] || die "Approvazione mancante o non esatta. Force push NON eseguito."
grep -q '^VERIFY_post_cleanup=OK' "$REPORT_DIR/state.env" 2>/dev/null \
  || die "Verifica post-cleanup non superata/non eseguita (verify-final.sh <work> post-cleanup ...): push rifiutato."
case "$URL" in *://*@*) die "URL con credenziali non ammesso: usare il credential helper di git";; esac

PRE="$REPORT_DIR/remote-preimage.txt"
[ -s "$PRE" ] || die "Preimage remoto mancante: eseguire snapshot-remote.sh <URL> PRIMA della riscrittura. Push rifiutato."
PREIMAGE_URL="$( . "$REPORT_DIR/state.env"; printf '%s' "${PREIMAGE_URL:-}" )"
[ "$PREIMAGE_URL" = "$URL" ] || die "L'URL di push ($URL) differisce da quello dello snapshot (${PREIMAGE_URL:-?}). Push rifiutato."

info "Controllo visibilità/fork"
vrc=0; "$HERE/check-visibility.sh" "$URL" || vrc=$?
if [ "$vrc" -ne 0 ] && [ "$ACK" -ne 1 ]; then
  die "Repo pubblico/con fork o visibilità non verificata (exit $vrc): chiedere all'utente e rilanciare con --ack-exposure."
fi

# filter-repo può lasciare un 'origin' con mirror=true: impostare il remote in modo esplicito
gr "$WORK" remote remove origin 2>/dev/null || true
gr "$WORK" remote add origin "$URL"
gr "$WORK" config --unset-all remote.origin.mirror 2>/dev/null || true

# Un lease per ogni ref locale: sha atteso dal preimage, vuoto = il ref non deve esistere sul remoto
args=(); refspecs=()
while read -r ref; do
  exp="$(awk -v r="$ref" '$2==r{print $1}' "$PRE")"
  args+=("--force-with-lease=$ref:$exp")
  refspecs+=("$ref:$ref")
done < <(gr "$WORK" for-each-ref --format='%(refname)' refs/heads refs/tags)
[ "${#refspecs[@]}" -gt 0 ] || die "Nessun ref da pubblicare"

orphans="$(comm -13 <(gr "$WORK" for-each-ref --format='%(refname)' refs/heads refs/tags | sort) <(awk '{print $2}' "$PRE" | sort))"

info "git push origin (lease per ref) - ${#refspecs[@]} ref"
gr "$WORK" push origin "${args[@]}" "${refspecs[@]}" \
  || die "Push rifiutato (lease non soddisfatto: il remoto è cambiato dopo lo snapshot, oppure protezione attiva). Nessun fallback a --force."
state_set PUSH_DONE 1
ok "Push completato. Ora: clone fresco + verify-final.sh + verify-anonymous.sh (Fase 15)."
if [ -n "$orphans" ]; then
  warn "Ref presenti sul remoto ma non nella history bonificata (NON eliminati, richiedono approvazione):"
  echo "$orphans" | sed 's/^/   - /'
fi
