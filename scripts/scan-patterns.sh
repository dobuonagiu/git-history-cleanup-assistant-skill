#!/usr/bin/env bash
# Fase 5/13: pattern custom (contesto privato che gitleaks non copre): IP privati, chiavi PEM,
# domini/IP/identità interni, PII. Output senza mai stampare il valore trovato.
# Uso: scan-patterns.sh <repo> <label> [--patterns-file F]
# Formato patterns-file: una regola per riga  nome::regex-ERE   ('#' commenti). Vedi references/patterns.example
# Exit: 0 = nessun match, 1 = match trovati
set -uo pipefail
source "$(dirname "$0")/lib.sh"
[ $# -ge 2 ] || die "Uso: $0 <repo> <label> [--patterns-file F]"
repo="$1"; label="$2"; shift 2
PF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --patterns-file) PF="$2"; shift 2;;
    *) die "Opzione sconosciuta: $1";;
  esac
done
[ -z "$PF" ] || [ -f "$PF" ] || die "patterns-file inesistente: $PF"

rules="$REPORT_DIR/$label-patterns.rules"
cat > "$rules" <<'EOF'
private-ipv4-10::\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b
private-ipv4-172::\b172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}\b
private-ipv4-192::\b192\.168\.[0-9]{1,3}\.[0-9]{1,3}\b
private-key-block::-----BEGIN ([A-Z]+ )?PRIVATE KEY-----
EOF
[ -z "$PF" ] || grep -Ev '^\s*(#|$)' "$PF" >> "$rules"

out="$REPORT_DIR/$label-patterns.tsv"
printf 'REGOLA\tCOMMIT\tFILE\n' > "$out"
total=0
while IFS= read -r line; do
  name="${line%%::*}"; re="${line#*::}"
  [ -n "$name" ] && [ -n "$re" ] || continue
  # contenuto: -G elenca i commit il cui diff contiene il pattern (nessun valore stampato)
  while read -r c; do
    if [[ "$c" == COMMIT:* ]]; then cur="${c#COMMIT:}"; continue; fi
    [ -n "$c" ] || continue
    printf '%s\t%s\t%s\n' "$name" "${cur:0:10}" "$c" >> "$out"; total=$((total + 1))
  done < <(gr "$repo" log --all -G"$re" --format='COMMIT:%H' --name-only 2>/dev/null)
  # messaggi di commit
  while read -r c; do
    printf '%s\t%s\t%s\n' "$name" "${c:0:10}" "(messaggio di commit)" >> "$out"; total=$((total + 1))
  done < <(gr "$repo" log --all -E --grep="$re" --format=%H 2>/dev/null)
done < "$rules"

chmod 600 "$out"
echo "[$label] pattern custom: $total match (solo posizioni, mai i valori) -> $out"
[ "$total" -gt 0 ] && { column -t -s $'\t' "$out" | head -40; exit 1; }
exit 0
