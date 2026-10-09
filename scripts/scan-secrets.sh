#!/usr/bin/env bash
# Fasi 5/13/15: scansione secret sull'intera history (gitleaks + trufflehog).
# Uso: scan-secrets.sh <repo-path> <label>
# Output (valori MASCHERATI, mai in chiaro): $REPORT_DIR/<label>-gitleaks.json, <label>-trufflehog.json
#  - gitleaks gira senza --redact (che renderebbe ogni valore "REDACTED", impedendo di distinguere i
#    falsi positivi) e il valore viene mascherato qui: primi 2 caratteri + lunghezza.
#  - trufflehog non gestisce i mirror bare: per i repo bare usa una copia di scansione temporanea.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

[ $# -eq 2 ] || die "Uso: $0 <repo-path> <label>"
repo="$(cd "$1" && pwd)"; label="$2"
GL="$REPORT_DIR/$label-gitleaks.json"; TH="$REPORT_DIR/$label-trufflehog.json"
need jq
# I tool esterni (gitleaks/trufflehog) chiamano git su mirror bare: consentire safe.bareRepository
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all
status=0; gl_n="n/a"; th_n="n/a"
RAW="$REPORT_DIR/.$label-gitleaks.raw"; SCANDIR=""
cleanup() { rm -f "$RAW"; [ -z "$SCANDIR" ] || rm -rf "$SCANDIR"; }
trap cleanup EXIT

if command -v gitleaks >/dev/null 2>&1; then
  info "gitleaks git ($label)"
  umask 077
  gitleaks git --no-banner --exit-code 0 --report-format json --report-path "$RAW" \
    ${GITLEAKS_CONFIG:+--config "$GITLEAKS_CONFIG"} "$repo" >/dev/null 2>"$REPORT_DIR/$label-gitleaks.log" \
    || { fail "gitleaks fallito (vedi $REPORT_DIR/$label-gitleaks.log)"; status=2; }
  if [ -s "$RAW" ]; then
    jq '[ .[] | (.Secret // "") as $s
          | del(.Secret, .Match, .Message)
          | . + {SecretMasked: (($s[0:2]) + "***(len " + ($s | length | tostring) + ")")} ]' "$RAW" > "$GL"
    gl_n="$(jq 'length' "$GL")"
  fi
else
  warn "gitleaks non installato: scansione saltata"; status=2
fi

if command -v trufflehog >/dev/null 2>&1; then
  info "trufflehog git ($label)"
  th_target="$repo"
  if [ -f "$repo/HEAD" ] && [ -d "$repo/objects" ]; then
    SCANDIR="$(mktemp -d "$REPORT_DIR/.scan-XXXXXX")"
    git clone -q --mirror --no-local "$repo" "$SCANDIR/.git" \
      && git -C "$SCANDIR" config core.bare false && git -C "$SCANDIR" read-tree --empty \
      || { fail "impossibile preparare la copia di scansione per trufflehog"; status=2; }
    th_target="$SCANDIR"
  fi
  # Maschera i valori grezzi: Raw/RawV2/Redacted non devono finire nei report.
  trufflehog git "file://$th_target" --json --no-update --results=verified,unverified,unknown 2>"$REPORT_DIR/$label-trufflehog.log" \
    | jq -c 'del(.Raw,.RawV2) | .Redacted = (.Redacted // "****")' > "$TH" \
    || { fail "trufflehog fallito (vedi $REPORT_DIR/$label-trufflehog.log)"; status=2; }
  grep -q '"msg":"error running scan"' "$REPORT_DIR/$label-trufflehog.log" 2>/dev/null \
    && { fail "trufflehog ha riportato un errore di scansione (vedi $REPORT_DIR/$label-trufflehog.log)"; status=2; }
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
