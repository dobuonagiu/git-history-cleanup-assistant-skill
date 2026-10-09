#!/usr/bin/env bash
# Funzioni comuni. Uso: source "$(dirname "$0")/lib.sh"

# Se si lavora già dentro cleanup-reports/ non annidare un secondo cleanup-reports/
if [ -z "${CLEANUP_REPORTS:-}" ] && [ "$(basename "$PWD")" = "cleanup-reports" ]; then CLEANUP_REPORTS="$PWD"; fi
REPORT_DIR="$(realpath -m "${CLEANUP_REPORTS:-$PWD/cleanup-reports}")"
mkdir -p "$REPORT_DIR"
chmod 700 "$REPORT_DIR" 2>/dev/null || true

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; }
die()  { fail "$*"; exit 1; }

# git su repo normale o bare (compatibile con safe.bareRepository=explicit): gr <repo> <args...>
gr() {
  local r="$1"; shift
  if [ -f "$r/HEAD" ] && [ -d "$r/objects" ]; then git --git-dir="$r" "$@"; else git -C "$r" "$@"; fi
}

# filter-repo su mirror bare: richiede cwd = repo e GIT_DIR=.
fr_run() { local w="$1"; shift; ( cd "$w" && GIT_DIR=. git filter-repo "$@" ); }

need() { command -v "$1" >/dev/null 2>&1 || die "Tool mancante: $1 (esegui check-prereqs.sh)"; }

# Salva chiave=valore in state.env
state_set() {
  local f="$REPORT_DIR/state.env" k="$1" v="$2"
  touch "$f"
  grep -v "^$k=" "$f" > "$f.tmp" 2>/dev/null || true
  printf '%s=%q\n' "$k" "$v" >> "$f.tmp"
  mv "$f.tmp" "$f"
}

# Elenco dei ref di un repo (branch e tag)
count_refs() { # <repo> <prefix>
  gr "$1" for-each-ref --format='%(refname)' "$2" | wc -l | tr -d ' '
}

# Costruisce FR_ARGS (argomenti git filter-repo) da file di regole; ignora righe vuote e commenti '#'.
# Uso: build_fr_args <paths-file|""> <replace-file|"">     (variabili: REPLACE_MESSAGES=1|0, MAX_BLOB=<size>)
# Un paths-file senza regole attive viene ignorato (nessun file da eliminare).
build_fr_args() {
  FR_ARGS=()
  if [ -n "${1:-}" ]; then
    [ -f "$1" ] || die "File regole inesistente: $1"
    grep -Ev '^\s*(#|$)' "$1" > "$REPORT_DIR/paths.clean" || true
    if [ -s "$REPORT_DIR/paths.clean" ]; then
      FR_ARGS+=(--invert-paths --paths-from-file "$REPORT_DIR/paths.clean")
    else
      warn "$1 non contiene regole attive: nessun file verrà eliminato per path"
    fi
  fi
  if [ -n "${2:-}" ]; then
    [ -f "$2" ] || die "File regole inesistente: $2"
    grep -Ev '^\s*(#|$)' "$2" > "$REPORT_DIR/replace.clean" || true
    if [ -s "$REPORT_DIR/replace.clean" ]; then
      FR_ARGS+=(--replace-text "$REPORT_DIR/replace.clean")
      # Di default riscrive anche i messaggi di commit (stesso file di regole)
      [ "${REPLACE_MESSAGES:-1}" = "1" ] && FR_ARGS+=(--replace-message "$REPORT_DIR/replace.clean")
    else
      warn "$2 non contiene regole attive: nessuna sostituzione"
    fi
  fi
  # Elimina dalla history ogni file (blob) più grande della soglia, es. 5M
  [ -z "${MAX_BLOB:-}" ] || FR_ARGS+=(--strip-blobs-bigger-than "$MAX_BLOB")
  [ "${#FR_ARGS[@]}" -gt 0 ] || die "Nessuna regola attiva: servono --paths, --replace e/o --max-blob-size"
}

# Hash delle regole approvate (collega dry-run e rewrite)
rules_hash() { # <paths|""> <replace|"">
  { [ -n "${1:-}" ] && cat "$1"; [ -n "${2:-}" ] && cat "$2"; echo "msg=${REPLACE_MESSAGES:-1} maxblob=${MAX_BLOB:-}"; } | sha256sum | cut -d' ' -f1
}
