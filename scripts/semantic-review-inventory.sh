#!/usr/bin/env bash
# Fase 5b/13b: inventario per la revisione semantica (Layer 4).
# Congela ref, commit e tutte le versioni distinte dei blob raggiungibili, così la copertura storica
# non dipende soltanto dalla versione più recente di ogni path nei tip dei ref.
# Uso: semantic-review-inventory.sh <repo> <label>
# Output: $REPORT_DIR/<label>-semantic-scope.md  (ref congelati, file testuali, file binari/grandi esclusi)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
[ $# -eq 2 ] || die "Uso: $0 <repo> <label>"
repo="$1"; label="$2"; MAX="${SEMANTIC_MAX_BYTES:-200000}"
out="$REPORT_DIR/$label-semantic-scope.md"
sample="$(mktemp "$REPORT_DIR/.semantic-sample.XXXXXX")"
entries="$(mktemp "$REPORT_DIR/.semantic-entries.XXXXXX")"
trap 'rm -f "$sample" "$entries"' EXIT
chmod 600 "$sample"
need python3
if ! gr "$repo" rev-list --objects --all \
    | gr "$repo" cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' \
    | awk '$1=="blob" && NF>=4 { print $2 " " substr($0, index($0, $4)) }' \
    | sort -u -k1,1 > "$entries"; then
  die "Impossibile enumerare tutti i blob raggiungibili"
fi

{
  echo "# Scope revisione semantica ($label)"
  echo
  echo "Generato: $(date -u +%FT%TZ)"
  echo
  echo "## Ref congelati"
  gr "$repo" for-each-ref --format='- %(refname) %(objectname:short)' refs/heads refs/tags
  echo
  echo "## Commit da rivedere (messaggi)"
  gr "$repo" rev-list --all --format='%H' | sed -n 's/^commit /- /p'
  echo
  echo "## Versioni testuali distinte (tutta la history raggiungibile, <= ${MAX} byte)"
  echo "L'inventario include ogni blob distinto; un blob identico riutilizzato in più path può comparire una sola volta."
  skipped=""
  while IFS= read -r entry; do
    sha="${entry%% *}"; path="${entry#* }"
    [ -n "$path" ] || continue
    size="$(gr "$repo" cat-file -s "$sha" 2>/dev/null)" || die "Impossibile leggere dimensione blob $sha"
    if [ "$size" -gt "$MAX" ]; then skipped+="- $path ($size byte, troppo grande)"$'\n'; continue; fi
    gr "$repo" cat-file blob "$sha" > "$sample" 2>/dev/null || die "Impossibile leggere blob $sha ($path)"
    if python3 -c 'import sys; sys.exit(0 if b"\0" in open(sys.argv[1], "rb").read(8000) else 1)' "$sample"; then
      skipped+="- $path (binario)"$'\n'; continue
    fi
    echo "- $path @ ${sha:0:10}"
  done < "$entries"
  echo
  echo "## Esclusi dalla copertura (da dichiarare come NON verificati)"
  printf '%s' "${skipped:-"(nessuno)"}"
} > "$out"

grep -c '^- .* @ ' "$out" | xargs -I{} echo "Versioni testuali nello scope: {}"
ok "Scope salvato in $out"
info "Applicare references/ai_semantic_review_prompt.md su questo scope e registrare i risultati FUORI dal repo."
