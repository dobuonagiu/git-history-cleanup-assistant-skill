#!/usr/bin/env bash
# Fase 3/14: salva i SHA dei ref remoti (heads e tags) PRIMA della riscrittura.
# Servono come "expected value" per il push con lease (push-cleaned.sh).
# Uso: snapshot-remote.sh <REMOTE_URL>
# Output: $REPORT_DIR/remote-preimage.txt  (righe: <sha> <refname>)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[ $# -eq 1 ] || die "Uso: $0 <REMOTE_URL>"
URL="$1"
case "$URL" in
  *://*@*) die "URL con credenziali non ammesso: usare il credential helper di git";;
esac

out="$REPORT_DIR/remote-preimage.txt"
git ls-remote --refs "$URL" 'refs/heads/*' 'refs/tags/*' | awk '{print $1" "$2}' | sort -k2 > "$out" \
  || die "Impossibile leggere il remoto: $URL"
[ -s "$out" ] || die "Nessun ref letto dal remoto: snapshot non valido"

state_set PREIMAGE_URL "$URL"
state_set PREIMAGE_AT "$(date -u +%FT%TZ)"
ok "Preimage salvato: $(wc -l < "$out" | tr -d ' ') ref in $out"
