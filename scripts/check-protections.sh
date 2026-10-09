#!/usr/bin/env bash
# Fase 4: protezioni che bloccano il force push (GitHub: branch protection + rulesets, via gh).
# Uso: check-protections.sh <REMOTE_URL>
# Exit: 0 = nessuna protezione rilevata
#       10 = protezioni presenti  -> crea il gate G2-protezioni (DA_LEGGERE)
#       2  = non verificabile (provider non GitHub, gh mancante/senza permessi) -> crea il gate G2-protezioni
# Il gate G2 va approvato dall'utente (gate.sh approve G2-protezioni) dopo aver rimosso/aggirato le protezioni.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
[ $# -eq 1 ] || die "Uso: $0 <REMOTE_URL>"
URL="$1"; R="$REPORT_DIR/protections.md"
need jq

mk_gate() { # <summary>
  "$HERE/gate.sh" create G2-protezioni --title "Protezioni del repository" \
    --phrase "Confermo che le protezioni sono state rimosse o aggirate" \
    --artifact "$R" --summary "$1"
}

if ! [[ "$URL" =~ github\.com[:/]+([^/]+)/([^/]+)$ ]]; then
  { echo "# Protezioni ($URL)"; echo; echo "Provider non GitHub: verifica MANUALE di branch protection, push restrictions, approvazioni e check obbligatori (vedi references/branch-protection.md)."; } > "$R"
  warn "Provider non GitHub: protezioni non verificabili automaticamente."
  mk_gate "Verifica manuale richiesta: protezioni non controllabili automaticamente. Conferma di averle verificate/rimosse."
  exit 2
fi
slug="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
command -v gh >/dev/null 2>&1 || { warn "gh mancante"; { echo "# Protezioni ($slug)"; echo; echo "gh non installato: verifica manuale."; } > "$R"; mk_gate "gh non disponibile: verifica manuale."; exit 2; }

prot="$(gh api "repos/$slug/branches" --paginate --jq '.[] | select(.protected) | .name' 2>/dev/null)" || prot="?"
rs="$(gh api "repos/$slug/rulesets" --paginate 2>/dev/null)" || rs="?"
if [ "$prot" = "?" ] || [ "$rs" = "?" ]; then
  { echo "# Protezioni ($slug)"; echo; echo "Impossibile leggere branch protette/rulesets (permessi insufficienti?): verifica manuale."; } > "$R"
  warn "Lettura protezioni non riuscita (permessi?)"; mk_gate "Lettura delle protezioni non riuscita: verifica manuale richiesta."; exit 2
fi

{
  echo "# Protezioni di $slug"; echo
  echo "## Branch protette"
  if [ -n "$prot" ]; then echo "$prot" | sed 's/^/- /'; else echo "(nessuna)"; fi
  echo; echo "## Rulesets attivi (target branch)"
  n=0
  for id in $(echo "$rs" | jq -r '.[] | select(.enforcement=="active" and .target=="branch") | .id'); do
    d="$(gh api "repos/$slug/rulesets/$id" 2>/dev/null)" || continue
    n=$((n + 1))
    echo "$d" | jq -r '"- **\(.name)** | refs: \(.conditions.ref_name.include // [] | join(",")) | regole: \([.rules[].type] | join(",")) | bypass: \(if (.bypass_actors // [] | length) == 0 then "NESSUNO" else ([.bypass_actors[] | "\(.actor_type)#\(.actor_id)"] | join(",")) end)"'
  done
  [ "$n" -gt 0 ] || echo "(nessuno)"
  echo
  echo "Il force push richiede: nessuna regola non_fast_forward/update/pull_request sui ref coinvolti, oppure un bypass actor che ti include."
} > "$R"
cat "$R"

nprot="$(echo "$prot" | grep -c . || true)"; nrs="$(echo "$rs" | jq '[.[] | select(.enforcement=="active" and .target=="branch")] | length')"
state_set PROTECTIONS "branches=$nprot rulesets=$nrs"
if [ "${nprot:-0}" -gt 0 ] || [ "${nrs:-0}" -gt 0 ]; then
  mk_gate "Presenti $nprot branch protette e $nrs ruleset attivi: il force push verrebbe rifiutato. Rimuovili/aggirali (es. bypass actor) e solo dopo approva il gate."
  exit 10
fi
ok "Nessuna protezione rilevata"
exit 0
