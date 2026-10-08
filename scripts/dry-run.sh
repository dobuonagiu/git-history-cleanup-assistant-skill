#!/usr/bin/env bash
# Fase 9: DRY RUN. Nessuna modifica al sorgente: opera su un mirror usa-e-getta.
# Uso: dry-run.sh <source-repo-or-mirror> <workdir> [--paths F] [--replace F] [--keep F]
#   --paths   file con path/glob:/regex: da eliminare dalla history (azione A)
#   --replace file per --replace-text (azione B)  [literal==>repl | regex:...==>repl]
#   --keep    file con path da preservare (esclusioni): segnala conflitti
set -euo pipefail
source "$(dirname "$0")/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"

[ $# -ge 2 ] || die "Uso: $0 <source> <workdir> [--paths F] [--replace F] [--keep F]"
SRC="$1"; WORK="$2"; shift 2
PATHS=""; REPL=""; KEEP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --paths) PATHS="$2"; shift 2;;
    --replace) REPL="$2"; shift 2;;
    --keep) KEEP="$2"; shift 2;;
    --no-message-rewrite) REPLACE_MESSAGES=0; shift;;
    *) die "Opzione sconosciuta: $1";;
  esac
done
need git; need python3; git filter-repo --version >/dev/null 2>&1 || die "git-filter-repo mancante"
[ ! -e "$WORK" ] || die "$WORK esiste già"
build_fr_args "$PATHS" "$REPL"

info "Clone usa-e-getta in $WORK"
git clone --mirror --no-local "$SRC" "$WORK" >/dev/null 2>&1
info "git filter-repo --dry-run ${FR_ARGS[*]}"
fr_run "$WORK" "${FR_ARGS[@]}" --dry-run >"$REPORT_DIR/dryrun.log" 2>&1 || die "filter-repo --dry-run fallito (vedi $REPORT_DIR/dryrun.log)"

FR_DIR="$WORK/filter-repo"; [ -d "$FR_DIR" ] || FR_DIR="$WORK/.git/filter-repo"
ORIG="$FR_DIR/fast-export.original"; FILT="$FR_DIR/fast-export.filtered"
[ -f "$ORIG" ] && [ -f "$FILT" ] || die "Output dry-run non trovato in $FR_DIR"

paths_of() { grep -a '^M ' "$1" | cut -d' ' -f4- | sed 's/^"//; s/"$//' | sort -u; }
paths_of "$ORIG" > "$WORK.orig.paths"; paths_of "$FILT" > "$WORK.filt.paths"
REMOVED="$REPORT_DIR/dryrun-removed-files.txt"
comm -23 "$WORK.orig.paths" "$WORK.filt.paths" > "$REMOVED"
rm -f "$WORK.orig.paths" "$WORK.filt.paths"

# Commit coinvolti: path rimossi + occorrenze dei valori da sostituire
AFFECTED="$REPORT_DIR/dryrun-affected-commits.txt"; : > "$AFFECTED"
if [ -s "$REMOVED" ]; then
  xargs -d '\n' -a "$REMOVED" -n 200 git --git-dir="$WORK" log --all --format=%H -- >> "$AFFECTED" || die "git log fallito"
fi
if [ -n "$REPL" ]; then
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    pat="${line%%==>*}"
    if [[ "$pat" == regex:* ]]; then
      gr "$WORK" log --all --format=%H -G"${pat#regex:}" >> "$AFFECTED" 2>/dev/null || true
      [ "${REPLACE_MESSAGES:-1}" = "1" ] && { gr "$WORK" log --all --format=%H -E --grep="${pat#regex:}" >> "$AFFECTED" 2>/dev/null || true; }
    elif [[ "$pat" == glob:* ]]; then warn "regola glob: in replace non analizzabile nel dry-run: $pat"
    else
      gr "$WORK" log --all --format=%H -S"${pat#literal:}" >> "$AFFECTED" 2>/dev/null || true
      [ "${REPLACE_MESSAGES:-1}" = "1" ] && { gr "$WORK" log --all --format=%H -F --grep="${pat#literal:}" >> "$AFFECTED" 2>/dev/null || true; }
    fi
  done < "$REPL"
fi
sort -u "$AFFECTED" -o "$AFFECTED"

REFS="$REPORT_DIR/dryrun-affected-refs.txt"; : > "$REFS"
while IFS= read -r c; do
  gr "$WORK" for-each-ref --contains "$c" --format='%(refname)' refs/heads refs/tags
done < "$AFFECTED" | sort -u > "$REFS"

n_files="$(wc -l < "$REMOVED" | tr -d ' ')"; n_commits="$(wc -l < "$AFFECTED" | tr -d ' ')"
n_br="$(grep -c '^refs/heads/' "$REFS" || true)"; n_tag="$(grep -c '^refs/tags/' "$REFS" || true)"
total_commits="$(gr "$WORK" rev-list --all --count)"

echo
echo "===== RISULTATO DRY RUN (nessuna modifica reale) ====="
echo "File eliminati dalla history : $n_files   (elenco: $REMOVED)"
echo "Commit con contenuto toccato : $n_commits / $total_commits   (elenco: $AFFECTED; tutti i discendenti cambieranno SHA)"
echo "Branch modificati            : $n_br"; grep '^refs/heads/' "$REFS" | sed 's#refs/heads/#   - #' || true
echo "Tag modificati               : $n_tag"; grep '^refs/tags/' "$REFS" | sed 's#refs/tags/#   - #' || true

# Conflitti con le esclusioni
if [ -n "$KEEP" ]; then
  conflicts="$(python3 "$HERE/match_paths.py" "$KEEP" < "$REMOVED" || true)"
  if [ -n "$conflicts" ]; then
    fail "CONFLITTO: la bonifica rimuoverebbe file da preservare:"; echo "$conflicts" | sed 's/^/   ! /'
    exit 3
  fi
  ok "Nessun conflitto con keep-list"
fi

rules_hash "$PATHS" "$REPL" > "$REPORT_DIR/dryrun.sha256"
state_set DRYRUN_DONE 1; state_set FILES_REMOVED_COUNT "$n_files"
state_set BRANCH_MODIFIED_COUNT "$n_br"; state_set TAG_MODIFIED_COUNT "$n_tag"
info "Chiedere ora all'utente la frase: Confermo la riscrittura della history"
