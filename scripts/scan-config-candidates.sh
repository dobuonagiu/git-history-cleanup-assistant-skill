#!/usr/bin/env bash
# Fase 5d: individua campi di configurazione che possono contenere credenziali statiche o host interni.
# Riporta solo categoria, commit e path; non stampa mai la riga o il valore.
# Uso: scan-config-candidates.sh <repo-path> <label>
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[ $# -eq 2 ] || die "Uso: $0 <repo-path> <label>"
repo="$1"; label="$2"
[ -d "$repo" ] || die "Repository inesistente: $repo"
need git

out="$REPORT_DIR/$label-config-candidates.tsv"
tmp="$(mktemp "$REPORT_DIR/.config-candidates.XXXXXX")"
raw="$(mktemp "$REPORT_DIR/.config-candidates-raw.XXXXXX")"
trap 'rm -f "$tmp" "$raw"' EXIT
gr "$repo" rev-parse --git-dir >/dev/null 2>&1 || die "Repository Git non valido: $repo"
printf 'CATEGORIA\tCOMMIT\tPATH\n' > "$tmp"

scan_rule() {
  local category="$1" regex="$2" commit="" path=""
  if ! gr "$repo" log --all -m -G"$regex" --format='COMMIT:%H' --name-only > "$raw" 2>/dev/null; then
    die "Scansione incompleta per la regola $category"
  fi
  while IFS= read -r entry; do
    if [[ "$entry" == COMMIT:* ]]; then
      commit="${entry#COMMIT:}"
    elif [ -n "$entry" ]; then
      printf '%s\t%s\t%s\n' "$category" "${commit:0:12}" "$entry" >> "$tmp"
    fi
  done < "$raw"
}

scan_rule "credential-field" '(^|[^[:alnum:]_])(password|passwd|passphrase|pwd|secret|token|access[_-]?key|api[_-]?key|client[_-]?secret|username)["'\'']?[[:space:]]*[:=]'
scan_rule "escaped-json-credential-field" '\\u0022(password|passwd|passphrase|pwd|secret|token|access[_-]?key|api[_-]?key|client[_-]?secret|username)\\u0022[[:space:]]*[:=]'
scan_rule "redis-host-or-credential" '(^|[^[:alnum:]_])(spring[.]data[.]redis|spring[.]redis|redis)[._-](host|user(name)?|password|passwd|pwd)["'\'']?[[:space:]]*[:=]'
scan_rule "kafka-broker-endpoint" '(^|[^[:alnum:]_])(spring[.]kafka[.]bootstrap-servers|kafka[._-](bootstrap[-.]servers?|brokers?|host))["'\'']?[[:space:]]*[:=]'
scan_rule "redis-uri-credential" 'redis(s)?://[^[:space:]@/]+:[^[:space:]@/]+@'
scan_rule "kafka-jaas-credential" '(username|password)[[:space:]]*=[[:space:]]*'
scan_rule "credentialed-connection-uri" '://[^[:space:]@/]+:[^[:space:]@/]+@'

sort -u "$tmp" > "$out"
chmod 600 "$out"
count=$(( $(wc -l < "$out") - 1 ))
echo "[$label] $count occorrenze candidate in campi di configurazione (solo categoria, commit e path) -> $out"
if [ "$count" -gt 0 ]; then
  column -t -s $'\t' "$out" | head -40
  [ "$count" -le 40 ] || echo "... altre occorrenze nel report completo"
fi
