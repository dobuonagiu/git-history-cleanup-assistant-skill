#!/usr/bin/env bash
# Gate di sicurezza su file Markdown con stato. Gli script distruttivi rifiutano di procedere
# finché il gate corrispondente non è APPROVATO.
#
# Uso:
#   gate.sh create <id> --title T --phrase "frase" [--artifact FILE]... [--summary TESTO | --summary-file F]
#   gate.sh status [id]
#   gate.sh require <id> [--optional]     exit 0 solo se APPROVATO e artefatti invariati; altrimenti exit 4
#   gate.sh approve <id>                  SOLO da terminale interattivo (TTY) dell'utente: mostra il gate
#                                         e richiede di digitare la frase esatta
#   gate.sh reject <id> [--reason R]      porta il gate a RIFIUTATO (bloccante)
#
# Stati: DA_LEGGERE -> APPROVATO   (oppure RIFIUTATO). Il file è in $REPORT_DIR/gates/<id>.md
# Se un artefatto cambia dopo la creazione, l'hash non coincide più e il gate non è valido: va ricreato.
# NOTA: è un controllo procedurale. L'agente non deve mai modificare questi file né lanciare "approve".
set -uo pipefail
source "$(dirname "$0")/lib.sh"
GATES="$REPORT_DIR/gates"; mkdir -p "$GATES"
SELF="$(cd "$(dirname "$0")" && pwd)/gate.sh"

field() { sed -n "s/^$2: //p" "$1" | head -1; }                      # field <file> <key>
set_field() {                                                         # set_field <file> <key> <value>
  awk -v k="$2" -v v="$3" 'BEGIN{d=0;done=0}
    /^---$/ {d++; if(d==2 && !done){print k": "v; done=1}}
    d==1 && index($0,k": ")==1 && !done {print k": "v; done=1; next}
    {print}' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
artifacts_hash() {                                                    # artifacts_hash <gate-file>
  grep '^artifact: ' "$1" | sed 's/^artifact: //' | sort | while IFS= read -r a; do
    if [ -d "$a" ]; then echo "dir:$a"; elif [ -f "$a" ]; then sha256sum "$a" | cut -d' ' -f1; else echo "missing:$a"; fi
  done | sha256sum | cut -d' ' -f1
}
gate_file() { echo "$GATES/$1.md"; }

cmd="${1:-}"; shift || true
case "$cmd" in
  create)
    id="${1:?id gate}"; shift
    title="$id"; phrase=""; summary=""; arts=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --title) title="$2"; shift 2;;
        --phrase) phrase="$2"; shift 2;;
        --artifact) arts+=("$(realpath -m "$2")"); shift 2;;
        --summary) summary="$2"; shift 2;;
        --summary-file) summary="$(cat "$2")"; shift 2;;
        *) die "Opzione sconosciuta: $1";;
      esac
    done
    [ -n "$phrase" ] || die "--phrase obbligatoria"
    f="$(gate_file "$id")"; real="$f"; f="$f.new"
    {
      echo "---"
      echo "gate: $id"
      echo "status: DA_LEGGERE"
      echo "phrase: $phrase"
      for a in "${arts[@]}"; do echo "artifact: $a"; done
      echo "artifacts_sha256: pending"
      echo "created: $(date -u +%FT%TZ)"
      echo "---"
      echo "# GATE $id - $title"
      echo
      echo "**Stato: DA_LEGGERE** - nessuna operazione successiva può partire finché non è APPROVATO."
      echo
      echo "## Riepilogo"
      echo
      printf '%s\n' "${summary:-"(vedi artefatti)"}"
      echo
      echo "## Da leggere prima di approvare"
      for a in "${arts[@]}"; do echo "- \`$a\`"; done
      [ "${#arts[@]}" -gt 0 ] || echo "- (nessun artefatto)"
      echo
      echo "## Come approvare (solo tu, da un terminale interattivo)"
      echo
      echo '```bash'
      echo "$SELF approve $id"
      echo '```'
      echo "Ti verrà chiesto di digitare esattamente: \`$phrase\`"
      echo "Per rifiutare: \`$SELF reject $id\`"
      echo
      echo "## Storico"
      echo "- $(date -u +%FT%TZ) creato (DA_LEGGERE)"
    } > "$f"
    set_field "$f" artifacts_sha256 "$(artifacts_hash "$f")"
    # Idempotente: un gate già APPROVATO con stessi artefatti e frase resta valido
    if [ -f "$real" ] && [ "$(field "$real" status)" = APPROVATO ] \
       && [ "$(field "$real" artifacts_sha256)" = "$(field "$f" artifacts_sha256)" ] \
       && [ "$(field "$real" phrase)" = "$phrase" ]; then
      rm -f "$f"; ok "Gate $id già APPROVATO con gli stessi artefatti: invariato"; exit 0
    fi
    mv "$f" "$real"; f="$real"
    ok "Gate creato: $f (stato DA_LEGGERE)"
    echo "Chiedi all'utente di leggere il file e di approvare da terminale: $SELF approve $id"
    ;;

  status)
    if [ -n "${1:-}" ]; then files=("$(gate_file "$1")"); else files=("$GATES"/*.md); fi
    [ -e "${files[0]}" ] || { echo "(nessun gate)"; exit 0; }
    printf '%-26s %-12s %s\n' GATE STATO NOTE
    for f in "${files[@]}"; do
      [ -f "$f" ] || die "Gate inesistente: $f"
      st="$(field "$f" status)"; note=""
      if [ "$st" = APPROVATO ] && [ "$(field "$f" artifacts_sha256)" != "$(artifacts_hash "$f")" ]; then note="NON VALIDO: artefatti cambiati"; fi
      printf '%-26s %-12s %s\n' "$(field "$f" gate)" "$st" "$note"
    done
    ;;

  require)
    id="${1:?id gate}"; shift; optional=0
    [ "${1:-}" = "--optional" ] && optional=1
    f="$(gate_file "$id")"
    if [ ! -f "$f" ]; then
      [ "$optional" -eq 1 ] && exit 0
      fail "Gate $id non ancora creato: crealo (gate.sh create) e fallo approvare all'utente."; exit 4
    fi
    st="$(field "$f" status)"
    if [ "$st" != APPROVATO ]; then
      fail "GATE $id in stato $st: operazione bloccata."
      echo "L'utente deve leggere $f e approvare da terminale:  $SELF approve $id" >&2; exit 4
    fi
    if [ "$(field "$f" artifacts_sha256)" != "$(artifacts_hash "$f")" ]; then
      fail "GATE $id approvato ma gli artefatti sono cambiati dopo l'approvazione: ricreare il gate e rifarlo approvare."; exit 4
    fi
    ;;

  approve)
    id="${1:?id gate}"; f="$(gate_file "$id")"; [ -f "$f" ] || die "Gate inesistente: $f"
    if [ ! -t 0 ] || [ ! -t 1 ]; then
      die "L'approvazione richiede un terminale interattivo dell'utente (TTY). L'agente non può approvare."
    fi
    [ "$(field "$f" status)" != RIFIUTATO ] || die "Gate rifiutato: va ricreato."
    [ "$(field "$f" artifacts_sha256)" = "$(artifacts_hash "$f")" ] || die "Artefatti cambiati dopo la creazione del gate: ricrearlo."
    cat "$f"; echo
    phrase="$(field "$f" phrase)"
    printf 'Hai letto il gate? Per APPROVARE digita esattamente: %s\n> ' "$phrase"
    read -r ans < /dev/tty
    if [ "$ans" != "$phrase" ]; then echo "Frase non corrispondente: gate NON approvato."; exit 1; fi
    set_field "$f" status APPROVATO
    set_field "$f" approved_at "$(date -u +%FT%TZ)"
    set_field "$f" approved_by "${USER:-?}@$(hostname) tty=$(tty)"
    echo "- $(date -u +%FT%TZ) APPROVATO da ${USER:-?}@$(hostname) ($(tty))" >> "$f"
    sed -i 's/^\*\*Stato: DA_LEGGERE\*\*.*/**Stato: APPROVATO**/' "$f"
    ok "Gate $id APPROVATO"
    ;;

  reject)
    id="${1:?id gate}"; shift; reason=""
    [ "${1:-}" = "--reason" ] && reason="${2:-}"
    f="$(gate_file "$id")"; [ -f "$f" ] || die "Gate inesistente: $f"
    set_field "$f" status RIFIUTATO
    echo "- $(date -u +%FT%TZ) RIFIUTATO ${reason:+($reason)}" >> "$f"
    sed -i 's/^\*\*Stato: .*/**Stato: RIFIUTATO**/' "$f"
    warn "Gate $id RIFIUTATO: il processo non può proseguire."
    ;;

  *) sed -n '2,15p' "${BASH_SOURCE[0]}"; exit 1;;
esac
