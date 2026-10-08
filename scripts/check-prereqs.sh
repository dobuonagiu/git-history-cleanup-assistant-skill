#!/usr/bin/env bash
# Fase 1: verifica prerequisiti. Non installa nulla: stampa i comandi suggeriti.
set -u
missing=0

check() { # <nome> <comando versione> <hint>
  local name="$1" cmd="$2" hint="$3" out
  if command -v "$name" >/dev/null 2>&1 && out=$(eval "$cmd" 2>&1 | head -1); then
    printf '[ OK ] %-16s %s\n' "$name" "$out"
  else
    printf '[MISS] %-16s non installato\n         Suggerito: %s\n' "$name" "$hint"
    missing=$((missing + 1))
  fi
}

check git "git --version" "sudo apt install git"
check gitleaks "gitleaks version" "brew install gitleaks | sudo apt install gitleaks | release: https://github.com/gitleaks/gitleaks/releases (serve >= 8.19 per 'gitleaks git')"
check trufflehog "trufflehog --version" "brew install trufflehog | curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b ~/.local/bin  (NON 'pip install trufflehog')"
if command -v git-filter-repo >/dev/null 2>&1; then
  printf '[ OK ] %-16s %s\n' git-filter-repo "$(git filter-repo --version 2>&1 | head -1)"
else
  printf '[MISS] %-16s non installato\n         Suggerito: sudo apt install git-filter-repo | pip install git-filter-repo\n' git-filter-repo
  missing=$((missing + 1))
fi
check jq "jq --version" "sudo apt install jq"
check curl "curl --version | cut -c1-40" "sudo apt install curl"
if command -v gh >/dev/null 2>&1; then
  printf '[ OK ] %-16s %s (opzionale: controllo visibilità/fork)\n' gh "$(gh --version 2>&1 | head -1)"
else
  printf '[ -- ] %-16s non installato (opzionale: controllo visibilità/fork su GitHub; https://cli.github.com)\n' gh
fi
check python3 "python3 --version" "sudo apt install python3"

# gitleaks >= 8.19 per il sottocomando "git"
if command -v gitleaks >/dev/null 2>&1 && ! gitleaks git --help >/dev/null 2>&1; then
  echo "[WARN] gitleaks installato ma senza il sottocomando 'git' (aggiornare a >= 8.19)"
  missing=$((missing + 1))
fi

echo
if [ "$missing" -gt 0 ]; then
  echo "Mancano $missing prerequisiti: chiedere conferma all'utente prima di installare."
  exit 1
fi
echo "Tutti i prerequisiti sono presenti."
