#!/usr/bin/env bash
# Installa la skill in GitHub Copilot CLI.
# Uso: ./install.sh [--project] [--copy] [--uninstall]
#   (default)    installa per l'utente in ~/.copilot/skills/git-history-cleanup-assistant
#   --project    installa nel repository corrente: ./.github/skills/git-history-cleanup-assistant
#   --copy       copia i file invece di creare un symlink
#   --uninstall  rimuove l'installazione
set -euo pipefail

NAME="git-history-cleanup-assistant"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="${COPILOT_SKILLS_DIR:-$HOME/.copilot/skills}"
MODE=link; UNINSTALL=0

for a in "$@"; do
  case "$a" in
    --project) DEST_DIR="$PWD/.github/skills";;
    --copy) MODE=copy;;
    --uninstall) UNINSTALL=1;;
    -h|--help) sed -n '2,7p' "${BASH_SOURCE[0]}"; exit 0;;
    *) echo "Opzione sconosciuta: $a" >&2; exit 1;;
  esac
done
DEST="$DEST_DIR/$NAME"

if [ "$UNINSTALL" -eq 1 ]; then
  rm -rf "$DEST"; echo "Rimossa: $DEST"; exit 0
fi

[ -f "$SRC/SKILL.md" ] || { echo "SKILL.md non trovato in $SRC" >&2; exit 1; }
mkdir -p "$DEST_DIR"
if [ -e "$DEST" ] || [ -L "$DEST" ]; then
  [ "$(readlink -f "$DEST")" = "$SRC" ] && { echo "Già installata (symlink a $SRC)."; exit 0; }
  echo "Esiste già $DEST: rimuoverlo o usare --uninstall prima di reinstallare." >&2; exit 1
fi

if [ "$MODE" = copy ]; then
  mkdir -p "$DEST"
  cp -r "$SRC/SKILL.md" "$SRC/references" "$SRC/scripts" "$DEST/"
else
  ln -s "$SRC" "$DEST"
fi
chmod +x "$SRC"/scripts/*.sh "$SRC"/scripts/*.py 2>/dev/null || true
echo "Skill installata in $DEST ($MODE)."
echo "Riavvia Copilot CLI (o usa /skills) e chiedi ad es.: \"ripulisci la history del mio repo dai secret\"."

for t in git git-filter-repo jq python3 gitleaks trufflehog; do
  command -v "$t" >/dev/null 2>&1 || echo "Nota: '$t' non installato (la skill ti proporrà come installarlo)."
done
