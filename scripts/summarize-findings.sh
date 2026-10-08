#!/usr/bin/env bash
# Fasi 5-6: tabella dei finding (valori mascherati).
# Uso: summarize-findings.sh <repo-path> <label>
# Colonne: tipo, file, commit, autore, gravità, branch coinvolti
set -euo pipefail
source "$(dirname "$0")/lib.sh"
[ $# -eq 2 ] || die "Uso: $0 <repo-path> <label>"
repo="$1"; label="$2"; need jq
GL="$REPORT_DIR/$label-gitleaks.json"; TH="$REPORT_DIR/$label-trufflehog.json"
OUT="$REPORT_DIR/$label-findings.tsv"

{
  [ -s "$GL" ] && jq -r '.[] | ["gitleaks:"+.RuleID, .File, .Commit, (.Email // .Author), "HIGH", ""] | @tsv' "$GL"
  [ -s "$TH" ] && jq -r '[ "trufflehog:"+.DetectorName, (.SourceMetadata.Data.Git.file // ""), (.SourceMetadata.Data.Git.commit // ""),
      (.SourceMetadata.Data.Git.email // ""), (if .Verified then "CRITICAL (verificato attivo)" else "HIGH" end), ""] | @tsv' "$TH"
} 2>/dev/null | sort -u > "$OUT.raw" || true

printf 'TIPO\tFILE\tCOMMIT\tAUTORE\tGRAVITA\tBRANCH\n' > "$OUT"
while IFS=$'\t' read -r t f c a s _; do
  [ -n "$c" ] || continue
  br="$(gr "$repo" for-each-ref --contains "$c" --format='%(refname:short)' refs/heads refs/tags 2>/dev/null | paste -sd, - || true)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$t" "$f" "${c:0:10}" "$a" "$s" "${br:-?}"
done < "$OUT.raw" >> "$OUT"
rm -f "$OUT.raw"

column -t -s $'\t' "$OUT"
echo
echo "Totale: $(($(wc -l < "$OUT") - 1)) finding. Salvato in $OUT"
echo "RICORDA: ogni credenziale trovata va considerata compromessa e rigenerata."
