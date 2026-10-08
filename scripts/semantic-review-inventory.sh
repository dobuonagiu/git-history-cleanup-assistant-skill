#!/usr/bin/env bash
# Fase 5b/13b: inventario per la revisione semantica (Layer 4).
# Congela ref (SHA) e insieme dei file da rivedere, così la copertura è dichiarata e verificabile.
# Uso: semantic-review-inventory.sh <repo> <label>
# Output: $REPORT_DIR/<label>-semantic-scope.md  (ref congelati, file testuali, file binari/grandi esclusi)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
[ $# -eq 2 ] || die "Uso: $0 <repo> <label>"
repo="$1"; label="$2"; MAX="${SEMANTIC_MAX_BYTES:-200000}"
out="$REPORT_DIR/$label-semantic-scope.md"

{
  echo "# Scope revisione semantica ($label)"
  echo
  echo "Generato: $(date -u +%FT%TZ)"
  echo
  echo "## Ref congelati"
  gr "$repo" for-each-ref --format='- %(refname) %(objectname:short)' refs/heads refs/tags
  echo
  echo "## Commit da rivedere (messaggi)"
  echo "Totale: $(gr "$repo" rev-list --all --count)"
  echo
  echo "## File testuali (tutti i ref, versione più recente per path, <= ${MAX} byte)"
  skipped=""
  while read -r sha path; do
    [ -n "$path" ] || continue
    size="$(gr "$repo" cat-file -s "$sha" 2>/dev/null || echo 0)"
    if [ "$size" -gt "$MAX" ]; then skipped+="- $path ($size byte, troppo grande)"$'\n'; continue; fi
    if gr "$repo" cat-file -p "$sha" 2>/dev/null | head -c 8000 | grep -qP '\x00'; then skipped+="- $path (binario)"$'\n'; continue; fi
    echo "- $path @ ${sha:0:10}"
  done < <(gr "$repo" for-each-ref --format='%(refname)' refs/heads refs/tags \
            | while read -r r; do gr "$repo" ls-tree -r "$r" | awk '{print $3" "$4}'; done | sort -u -k2,2)
  echo
  echo "## Esclusi dalla copertura (da dichiarare come NON verificati)"
  printf '%s' "${skipped:-"(nessuno)"}"
} > "$out"

grep -c '^- .* @ ' "$out" | xargs -I{} echo "File testuali nello scope: {}"
ok "Scope salvato in $out"
info "Applicare references/ai_semantic_review_prompt.md su questo scope e registrare i risultati FUORI dal repo."
