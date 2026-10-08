#!/usr/bin/env bash
# Fasi 5/13/15: scansione secret sull'intera history (gitleaks + trufflehog).
# Uso: scan-secrets.sh <repo-path> <label>
# Output (valori mascherati): $REPORT_DIR/<label>-gitleaks.json, <label>-trufflehog.json
set -uo pipefail
source "$(dirname "$0")/lib.sh"

[ $# -eq 2 ] || die "Uso: $0 <repo-path> <label>"
repo="$(cd "$1" && pwd)"; label="$2"
GL="$REPORT_DIR/$label-gitleaks.json"; TH="$REPORT_DIR/$label-trufflehog.json"
need jq
# I tool esterni (gitleaks/trufflehog) chiamano git su mirror bare: consentire safe.bareRepository
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all
status=0; gl_n="n/a"; th_n="n/a"

if command -v gitleaks >/dev/null 2>&1; then
  info "gitleaks git ($label)"
  gitleaks git --no-banner --redact --exit-code 0 --report-format json --report-path "$GL" "$repo" >/dev/null 2>"$REPORT_DIR/$label-gitleaks.log" \
    || { fail "gitleaks fallito (vedi $REPORT_DIR/$label-gitleaks.log)"; status=2; }
  [ -f "$GL" ] && gl_n="$(jq 'length' "$GL")"
else
  warn "gitleaks non installato: scansione saltata"; status=2
fi

if command -v trufflehog >/dev/null 2>&1; then
  info "trufflehog git ($label)"
  # Maschera i valori grezzi: Raw/RawV2/Redacted non devono finire nei report.
  trufflehog git "file://$repo" --json --no-update --results=verified,unverified,unknown 2>"$REPORT_DIR/$label-trufflehog.log" \
    | jq -c 'del(.Raw,.RawV2) | .Redacted = (.Redacted // "****")' > "$TH" \
    || { fail "trufflehog fallito (vedi $REPORT_DIR/$label-trufflehog.log)"; status=2; }
  [ -f "$TH" ] && th_n="$(jq -s 'length' "$TH")"
else
  warn "trufflehog non installato: scansione saltata"; status=2
fi
chmod 600 "$REPORT_DIR"/"$label"-*.json 2>/dev/null || true

echo "[$label] gitleaks: $gl_n finding | trufflehog: $th_n finding"
state_set "SECRETS_${label//[^A-Za-z0-9]/_}_GITLEAKS" "$gl_n"
state_set "SECRETS_${label//[^A-Za-z0-9]/_}_TRUFFLEHOG" "$th_n"

# Exit: 0 = pulito, 1 = secret trovati, 2 = scansione incompleta
[ "$status" -eq 2 ] && exit 2
{ [ "$gl_n" != "0" ] || [ "$th_n" != "0" ]; } && exit 1
exit 0
