#!/usr/bin/env bash
# Funzioni comuni. Uso: source "$(dirname "$0")/lib.sh"

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
# Uso: build_fr_args <paths-file|""> <replace-file|"">
build_fr_args() {
  FR_ARGS=()
  if [ -n "${1:-}" ]; then
    [ -s "$1" ] || die "File regole vuoto o inesistente: $1"
    grep -Ev '^\s*(#|$)' "$1" > "$REPORT_DIR/paths.clean"
    FR_ARGS+=(--invert-paths --paths-from-file "$REPORT_DIR/paths.clean")
  fi
  if [ -n "${2:-}" ]; then
    [ -s "$2" ] || die "File regole vuoto o inesistente: $2"
    grep -Ev '^\s*(#|$)' "$2" > "$REPORT_DIR/replace.clean"
    FR_ARGS+=(--replace-text "$REPORT_DIR/replace.clean")
  fi
  [ "${#FR_ARGS[@]}" -gt 0 ] || die "Servono --paths e/o --replace"
}

# Hash delle regole approvate (collega dry-run e rewrite)
rules_hash() { # <paths|""> <replace|"">
  { [ -n "${1:-}" ] && cat "$1"; [ -n "${2:-}" ] && cat "$2"; true; } | sha256sum | cut -d' ' -f1
}
