#!/usr/bin/env bash
# Fase 14: force push della history bonificata sul repo ORIGINALE, con LEASE per ref e gate G5-push.
# Uso:
#   push-cleaned.sh <work-dir> <REMOTE_URL> --prepare   scrive push-plan.md e crea il gate G5-push (DA_LEGGERE)
#   push-cleaned.sh <work-dir> <REMOTE_URL>             richiede G5-push APPROVATO (gate.sh approve G5-push,
#                                                       da terminale dell'utente) ed esegue il push
# Prerequisiti: verify-final.sh <work> post-cleanup con esito OK; preimage (snapshot-remote.sh, Fase 3) sullo
# stesso URL. Se il repo è pubblico / ha fork / visibilità non verificabile la frase del gate diventa più forte.
# Vengono pubblicati SOLO i ref cambiati o nuovi (i ref invariati non si toccano). Ogni ref ha un lease
# (--force-with-lease=<ref>:<sha-preimage>): se il remoto è cambiato dopo lo snapshot il ref è rifiutato.
# Nessun fallback a --force. Branch/tag orfani sul remoto NON vengono eliminati.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"

[ $# -ge 2 ] || die "Uso: $0 <work-dir> <REMOTE_URL> [--prepare]"
WORK="$1"; URL="$2"; shift 2
PREPARE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --prepare) PREPARE=1; shift;;
    *) die "Opzione sconosciuta: $1";;
  esac
done
grep -q '^VERIFY_post_cleanup=OK' "$REPORT_DIR/state.env" 2>/dev/null \
  || die "Verifica post-cleanup non superata/non eseguita (verify-final.sh <work> post-cleanup ...): push rifiutato."
case "$URL" in *://*@*) die "URL con credenziali non ammesso: usare il credential helper di git";; esac

PRE="$REPORT_DIR/remote-preimage.txt"
[ -s "$PRE" ] || die "Preimage remoto mancante: eseguire snapshot-remote.sh <URL> PRIMA della riscrittura. Push rifiutato."
PREIMAGE_URL="$( . "$REPORT_DIR/state.env"; printf '%s' "${PREIMAGE_URL:-}" )"
[ "$PREIMAGE_URL" = "$URL" ] || die "L'URL di push ($URL) differisce da quello dello snapshot (${PREIMAGE_URL:-?}). Push rifiutato."

# Protezioni: se presenti/non verificabili, serve G2 approvato (check-protections crea il gate)
prc=0; "$HERE/check-protections.sh" "$URL" >"$REPORT_DIR/.prot.out" 2>&1 || prc=$?
"$HERE/gate.sh" require G2-protezioni --optional || die "Push bloccato: gate G2-protezioni non approvato (protezioni presenti o non verificate)."

vrc=0; vis="$("$HERE/check-visibility.sh" "$URL" 2>&1)" || vrc=$?

PLAN="$REPORT_DIR/push-plan.md"
plan_rows="$(mktemp)"; trap 'rm -f "$plan_rows"' EXIT
nforce=0; nnew=0; nskip=0
while read -r ref sha; do
  old="$(awk -v r="$ref" '$2==r{print $1}' "$PRE")"
  if [ -z "$old" ]; then act="NUOVO"; nnew=$((nnew + 1))
  elif [ "$old" = "$sha" ]; then act="INVARIATO (non pubblicato)"; nskip=$((nskip + 1))
  else act="FORCE (lease ${old:0:10} -> ${sha:0:10})"; nforce=$((nforce + 1)); fi
  printf '| %s | %s |\n' "$ref" "$act"
done < <(gr "$WORK" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags) > "$plan_rows"
orphans="$(comm -13 <(gr "$WORK" for-each-ref --format='%(refname)' refs/heads refs/tags | sort) <(awk '{print $2}' "$PRE" | sort))"

{
  echo "# Piano di push (repo ORIGINALE)"; echo
  echo "- Destinazione: $URL"
  echo "- Ref da riscrivere con force: **$nforce** - nuovi: $nnew - invariati: $nskip"
  echo; echo "## Visibilità e fork"; echo '```'; echo "$vis"; echo '```'
  echo; echo "## Protezioni"; echo '```'; cat "$REPORT_DIR/protections.md" 2>/dev/null || echo "(non verificate)"; echo '```'
  echo; echo "## Ref"; echo "| ref | azione |"; echo "|---|---|"; cat "$plan_rows"
  echo; echo "## Ref presenti sul remoto ma assenti dopo la bonifica (NON eliminati)"
  if [ -n "$orphans" ]; then echo "$orphans" | sed 's/^/- /'; else echo "(nessuno)"; fi
} > "$PLAN"

phrase="Confermo il force push"
[ "$vrc" -eq 0 ] || phrase="Confermo il force push su repository pubblico o non verificato"

if [ "$PREPARE" -eq 1 ]; then
  "$HERE/gate.sh" create G5-push --title "Force push sul repository originale" --phrase "$phrase" \
    --artifact "$PLAN" --artifact "$(realpath "$REPORT_DIR/verify-post-cleanup.md" 2>/dev/null || echo "$REPORT_DIR/verify-post-cleanup.md")" \
    --summary "Force push (con lease) di $nforce ref (+$nnew nuovi) su $URL. Visibilità/fork: exit $vrc. Protezioni: exit $prc. Leggi push-plan.md."
  exit 0
fi

"$HERE/gate.sh" require G5-push || die "Push bloccato: gate G5-push non approvato (prima: push-cleaned.sh ... --prepare)."
[ "$(sed -n 's/^phrase: //p' "$REPORT_DIR/gates/G5-push.md")" = "$phrase" ] \
  || die "La visibilità del repo è cambiata dopo l'approvazione: rifare --prepare e approvare di nuovo."
[ $((nforce + nnew)) -gt 0 ] || { ok "Nessun ref da pubblicare: il remoto è già allineato."; exit 0; }

# filter-repo può lasciare un 'origin' con mirror=true: impostare il remote in modo esplicito
gr "$WORK" remote remove origin 2>/dev/null || true
gr "$WORK" remote add origin "$URL"
gr "$WORK" config --unset-all remote.origin.mirror 2>/dev/null || true

args=(); refspecs=()
while read -r ref sha; do
  old="$(awk -v r="$ref" '$2==r{print $1}' "$PRE")"
  [ "$old" != "$sha" ] || continue
  args+=("--force-with-lease=$ref:$old")
  refspecs+=("$ref:$ref")
done < <(gr "$WORK" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags)

info "git push origin (lease per ref) - ${#refspecs[@]} ref"
gr "$WORK" push origin "${args[@]}" "${refspecs[@]}" \
  || die "Push rifiutato (lease non soddisfatto: il remoto è cambiato dopo lo snapshot, oppure protezione attiva). Nessun fallback a --force."
state_set PUSH_DONE 1
ok "Push completato. Ora: clone fresco + verify-final.sh + verify-anonymous.sh (Fase 15)."
if [ -n "$orphans" ]; then
  warn "Ref presenti sul remoto ma non nella history bonificata (NON eliminati, richiedono approvazione):"
  echo "$orphans" | sed 's/^/   - /'
fi
