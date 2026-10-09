#!/usr/bin/env bash
# Fase 9: DRY RUN. Nessuna modifica al sorgente: opera su un mirror usa-e-getta.
# Uso: dry-run.sh <source-repo-or-mirror> <workdir> [--paths F] [--replace F] [--keep F]
#                 [--max-blob-size 5M] [--allow-keep-modified] [--no-message-rewrite]
#   --paths   file con path/glob:/regex: da eliminare dalla history (azione A: ELIMINA FILE)
#   --replace file per --replace-text (azione B)  [literal==>repl | regex:...==>repl]
#   --keep    file con path da preservare (esclusioni): conflitto (exit 3) se una regola li elimina
#             o ne MODIFICA il contenuto (sostituzioni); --allow-keep-modified accetta le sole modifiche
#   --max-blob-size  elimina dalla history ogni file più grande della soglia (K/M/G), es. 5M
# Prerequisiti: gate G3-classificazione APPROVATO (e G2-protezioni se esiste).
# Al termine crea il gate G4-riscrittura (DA_LEGGERE): l'utente deve leggerlo e approvarlo da terminale.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"

[ $# -ge 2 ] || die "Uso: $0 <source> <workdir> [--paths F] [--replace F] [--keep F]"
SRC="$1"; WORK="$2"; shift 2
PATHS=""; REPL=""; KEEP=""; ALLOW_KEEP_MOD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --paths) PATHS="$2"; shift 2;;
    --replace) REPL="$2"; shift 2;;
    --keep) KEEP="$2"; shift 2;;
    --no-message-rewrite) REPLACE_MESSAGES=0; shift;;
    --max-blob-size) MAX_BLOB="$2"; shift 2;;
    --allow-keep-modified) ALLOW_KEEP_MOD=1; shift;;
    *) die "Opzione sconosciuta: $1";;
  esac
done
need git; need python3; git filter-repo --version >/dev/null 2>&1 || die "git-filter-repo mancante"
"$HERE/gate.sh" require G3-classificazione || die "Dry-run bloccato: la classificazione (G3) non è approvata dall'utente."
"$HERE/gate.sh" require G2-protezioni --optional || die "Dry-run bloccato: le protezioni (G2) non sono confermate dall'utente."
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
REPLFILES="$REPORT_DIR/dryrun-replace-files.txt"; : > "$REPLFILES"
if [ -n "$REPL" ]; then
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    pat="${line%%==>*}"
    if [[ "$pat" == regex:* ]]; then
      gr "$WORK" log --all --format= --name-only -G"${pat#regex:}" >> "$REPLFILES" 2>/dev/null || true
      gr "$WORK" log --all --format=%H -G"${pat#regex:}" >> "$AFFECTED" 2>/dev/null || true
      [ "${REPLACE_MESSAGES:-1}" = "1" ] && { gr "$WORK" log --all --format=%H -E --grep="${pat#regex:}" >> "$AFFECTED" 2>/dev/null || true; }
    elif [[ "$pat" == glob:* ]]; then warn "regola glob: in replace non analizzabile nel dry-run: $pat"
    else
      gr "$WORK" log --all --format= --name-only -S"${pat#literal:}" >> "$REPLFILES" 2>/dev/null || true
      gr "$WORK" log --all --format=%H -S"${pat#literal:}" >> "$AFFECTED" 2>/dev/null || true
      [ "${REPLACE_MESSAGES:-1}" = "1" ] && { gr "$WORK" log --all --format=%H -F --grep="${pat#literal:}" >> "$AFFECTED" 2>/dev/null || true; }
    fi
  done < "$REPL"
fi
sort -u "$AFFECTED" -o "$AFFECTED"; grep -v '^$' "$REPLFILES" | sort -u > "$REPLFILES.tmp" || true; mv "$REPLFILES.tmp" "$REPLFILES"

REFS="$REPORT_DIR/dryrun-affected-refs.txt"; : > "$REFS"
while IFS= read -r c; do
  gr "$WORK" for-each-ref --contains "$c" --format='%(refname)' refs/heads refs/tags
done < "$AFFECTED" | sort -u > "$REFS"

n_files="$(wc -l < "$REMOVED" | tr -d ' ')"; n_commits="$(wc -l < "$AFFECTED" | tr -d ' ')"
n_br="$(grep -c '^refs/heads/' "$REFS" || true)"; n_tag="$(grep -c '^refs/tags/' "$REFS" || true)"
total_commits="$(gr "$WORK" rev-list --all --count)"

DEFBR="$(gr "$WORK" symbolic-ref --short HEAD 2>/dev/null || true)"
default_hit=0; [ -z "$DEFBR" ] || ! grep -qx "refs/heads/$DEFBR" "$REFS" || default_hit=1

# Conflitti con le esclusioni (keep-list): file ELIMINATI o MODIFICATI nel contenuto
conflicts=""; kmod=""
if [ -n "$KEEP" ]; then
  conflicts="$(python3 "$HERE/match_paths.py" "$KEEP" < "$REMOVED" || true)"
  kmod="$(python3 "$HERE/match_paths.py" "$KEEP" < "$REPLFILES" || true)"
fi

REPORT="$REPORT_DIR/dryrun-report.md"
{
  echo "# Dry run - riepilogo (NESSUNA modifica reale è stata fatta)"; echo
  echo "- File eliminati dalla history: **$n_files** (elenco: dryrun-removed-files.txt)"
  echo "- Commit con contenuto toccato: **$n_commits / $total_commits** (tutti i discendenti cambieranno SHA)"
  echo "- Branch riscritti (sarà necessario il force push): **$n_br**"
  echo "- Tag riscritti: **$n_tag**"
  [ "$default_hit" -eq 0 ] || echo "- ⚠ **Il branch di default ($DEFBR) verrà riscritto**: il force push richiede che protezioni/ruleset lo consentano."
  [ -z "${MAX_BLOB:-}" ] || echo "- Soglia file grandi: eliminati i blob > $MAX_BLOB"
  [ "${REPLACE_MESSAGES:-1}" = "1" ] || echo "- Messaggi di commit NON riscritti (--no-message-rewrite)"
  echo; echo "## File eliminati"
  if [ -s "$REMOVED" ]; then sed 's/^/- /' "$REMOVED" | head -200; else echo "(nessuno)"; fi
  echo; echo "## File il cui contenuto verrà MODIFICATO dalle sostituzioni"
  if [ -s "$REPLFILES" ]; then sed 's/^/- /' "$REPLFILES" | head -200; else echo "(nessuno)"; fi
  echo; echo "## Branch riscritti"; grep '^refs/heads/' "$REFS" | sed 's#refs/heads/#- #' || true
  echo; echo "## Tag riscritti"; grep '^refs/tags/' "$REFS" | sed 's#refs/tags/#- #' || true
  echo; echo "## Keep-list"
  if [ -z "$KEEP" ]; then echo "(non fornita)"; else
    echo "Conflitti (eliminati): ${conflicts:-nessuno}"; echo "Modificati dalle sostituzioni: ${kmod:-nessuno}"; fi
} > "$REPORT"

echo
echo "===== RISULTATO DRY RUN (nessuna modifica reale) ====="
sed -n '3,9p' "$REPORT"
echo "Report completo: $REPORT"

if [ -n "$conflicts" ]; then
  fail "CONFLITTO: la bonifica eliminerebbe file da preservare:"; echo "$conflicts" | sed 's/^/   ! /'
  exit 3
fi
if [ -n "$kmod" ]; then
  if [ "$ALLOW_KEEP_MOD" -eq 1 ]; then
    warn "File in keep-list con contenuto MODIFICATO dalle sostituzioni (accettato con --allow-keep-modified):"; echo "$kmod" | sed 's/^/   ~ /'
  else
    fail "CONFLITTO: le sostituzioni modificherebbero file in keep-list:"; echo "$kmod" | sed 's/^/   ~ /'
    echo "Scegli: rimuovi la regola/il file dalla keep-list, accetta la modifica con --allow-keep-modified, oppure restringi la regola."
    exit 3
  fi
elif [ -n "$KEEP" ]; then ok "Nessun conflitto con keep-list"; fi

rules_hash "$PATHS" "$REPL" > "$REPORT_DIR/dryrun.sha256"
state_set DRYRUN_DONE 1; state_set FILES_REMOVED_COUNT "$n_files"
state_set BRANCH_MODIFIED_COUNT "$n_br"; state_set TAG_MODIFIED_COUNT "$n_tag"

arts=(--artifact "$REPORT" --artifact "$REMOVED" --artifact "$AFFECTED" --artifact "$REFS")
[ -z "$PATHS" ] || arts+=(--artifact "$(realpath "$PATHS")")
[ -z "$REPL" ] || arts+=(--artifact "$(realpath "$REPL")")
[ -z "$KEEP" ] || arts+=(--artifact "$(realpath "$KEEP")")
"$HERE/gate.sh" create G4-riscrittura --title "Riscrittura della history" --phrase "Confermo la riscrittura della history" \
  "${arts[@]}" --summary "Eliminati $n_files file; $n_commits commit toccati su $total_commits; riscritti $n_br branch e $n_tag tag$([ "$default_hit" -eq 1 ] && echo " (INCLUSO il branch di default $DEFBR)"). Leggi dryrun-report.md."
