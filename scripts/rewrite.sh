#!/usr/bin/env bash
# Fasi 11-12: bonifica reale + pulizia. DISTRUTTIVO sulla copia di lavoro (mai sul backup).
# Uso: rewrite.sh <source-repo-or-mirror> <workdir> --approval "Confermo la riscrittura della history"
#                 [--paths F] [--replace F]
# Rifiuta di girare se: frase non esatta, dry-run non eseguito, regole cambiate dopo il dry-run.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[ $# -ge 2 ] || die "Uso: $0 <source> <workdir> --approval '<frase>' [--paths F] [--replace F]"
SRC="$1"; WORK="$2"; shift 2
PATHS=""; REPL=""; APPROVAL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --paths) PATHS="$2"; shift 2;;
    --replace) REPL="$2"; shift 2;;
    --approval) APPROVAL="$2"; shift 2;;
    --no-message-rewrite) REPLACE_MESSAGES=0; shift;;
    *) die "Opzione sconosciuta: $1";;
  esac
done
[ "$APPROVAL" = "Confermo la riscrittura della history" ] || die "Approvazione mancante o non esatta. Riscrittura NON eseguita."
[ -f "$REPORT_DIR/dryrun.sha256" ] || die "Dry run non eseguito (Fase 9): riscrittura rifiutata."
[ "$(cat "$REPORT_DIR/dryrun.sha256")" = "$(rules_hash "$PATHS" "$REPL")" ] \
  || die "Le regole sono cambiate dopo il dry run: rieseguire dry-run.sh e richiedere nuova approvazione."
[ ! -e "$WORK" ] || die "$WORK esiste già"
need git; git filter-repo --version >/dev/null 2>&1 || die "git-filter-repo mancante"
build_fr_args "$PATHS" "$REPL"

info "Fase 11 - clone fresco di lavoro"
git clone --mirror --no-local "$SRC" "$WORK" >/dev/null 2>&1
info "git filter-repo ${FR_ARGS[*]}"
fr_run "$WORK" "${FR_ARGS[@]}"

info "Fase 12 - pulizia"
gr "$WORK" reflog expire --expire=now --all
gr "$WORK" gc --prune=now --aggressive

state_set VERIFY_post_cleanup PENDING; state_set REWRITE_DONE 1; state_set WORK_DIR "$WORK"
ok "Riscrittura completata in $WORK. Ora: scan-secrets.sh + verify-final.sh (NON fare push senza approvazione)."
