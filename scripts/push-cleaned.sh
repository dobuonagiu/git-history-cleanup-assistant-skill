#!/usr/bin/env bash
# Fase 14: force push della history bonificata. DISTRUTTIVO sul remoto.
# Uso: push-cleaned.sh <work-dir> <REMOTE_URL> --approval "Confermo il force push"
# Prerequisiti: verify-final.sh del work dir con esito OK (state.env: VERIFY_post_cleanup=OK).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[ $# -ge 2 ] || die "Uso: $0 <work-dir> <REMOTE_URL> --approval 'Confermo il force push'"
WORK="$1"; URL="$2"; shift 2
APPROVAL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --approval) APPROVAL="$2"; shift 2;;
    *) die "Opzione sconosciuta: $1";;
  esac
done
[ "$APPROVAL" = "Confermo il force push" ] || die "Approvazione mancante o non esatta. Force push NON eseguito."
grep -q '^VERIFY_post_cleanup=OK' "$REPORT_DIR/state.env" 2>/dev/null \
  || die "Verifica post-cleanup non superata/non eseguita (verify-final.sh <work> post-cleanup ...): push rifiutato."

# filter-repo può lasciare un 'origin' con mirror=true: impostare il remote in modo esplicito
gr "$WORK" remote remove origin 2>/dev/null || true
gr "$WORK" remote add origin "$URL"
gr "$WORK" config --unset-all remote.origin.mirror 2>/dev/null || true

info "git push origin --force --all"
gr "$WORK" push origin --force --all
info "git push origin --force --tags"
gr "$WORK" push origin --force --tags
state_set PUSH_DONE 1
ok "Push completato. Ora: clone fresco + verify-final.sh (Fase 15)."
warn "Branch/tag eliminati dalla riscrittura restano sul remoto: verificare e cancellare solo con approvazione."
