#!/usr/bin/env bash
# Fasi 11-12: bonifica reale + pulizia. DISTRUTTIVO sulla copia di lavoro (mai sul backup).
# Uso: rewrite.sh <source-repo-or-mirror> <workdir> [--paths F] [--replace F] [--max-blob-size 5M] [--no-message-rewrite]
# Rifiuta di girare se: il gate G4-riscrittura non è APPROVATO dall'utente (gate.sh approve G4-riscrittura,
# da terminale), il dry-run non è stato eseguito o le regole/artefatti sono cambiati dopo il dry-run.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
[ $# -ge 2 ] || die "Uso: $0 <source> <workdir> [--paths F] [--replace F] [--max-blob-size 5M]"
SRC="$1"; WORK="$2"; shift 2
PATHS=""; REPL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --paths) PATHS="$2"; shift 2;;
    --replace) REPL="$2"; shift 2;;
    --max-blob-size) MAX_BLOB="$2"; shift 2;;
    --no-message-rewrite) REPLACE_MESSAGES=0; shift;;
    *) die "Opzione sconosciuta: $1";;
  esac
done
"$HERE/gate.sh" require G4-riscrittura || die "Riscrittura NON eseguita: gate G4-riscrittura non approvato."
"$HERE/gate.sh" require G2-protezioni --optional || die "Riscrittura NON eseguita: gate G2-protezioni non approvato."
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
