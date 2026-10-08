#!/usr/bin/env bash
# Fase 0: Repository Assessment (sola lettura).
# Uso: assess-repo.sh [path-repo]   (default: .)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

repo="${1:-.}"
gr "$repo" rev-parse --git-dir >/dev/null 2>&1 || die "Non è un repository Git: $repo"

default_branch="$(gr "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
[ -n "$default_branch" ] || default_branch="$(gr "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null || echo '<sconosciuto>')"

out="$REPORT_DIR/assessment.md"
{
  echo "# Repository Assessment"
  echo
  echo "- Percorso: $(cd "$repo" && pwd)"
  echo "- Default branch: $default_branch"
  echo
  echo "## Remote configurati"
  echo '```'; gr "$repo" remote -v; echo '```'
  echo "## Branch locali"
  echo '```'; gr "$repo" for-each-ref --format='%(refname:short)' refs/heads; echo '```'
  echo "## Branch remoti"
  echo '```'; gr "$repo" for-each-ref --format='%(refname:short)' refs/remotes; echo '```'
  echo "## Tag"
  echo '```'; gr "$repo" tag; echo '```'
  echo
  echo "Commit totali (tutti i ref): $(gr "$repo" rev-list --all --count)"
} | tee "$out"

state_set SOURCE_DEFAULT_BRANCH "$default_branch"
info "Report salvato in $out"
