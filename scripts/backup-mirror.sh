#!/usr/bin/env bash
# Fasi 2-3: verifica accessi + backup mirror, con gate G1-backup.
# Uso: backup-mirror.sh <SOURCE_REPO> <BACKUP_REPO> [--dir <mirror-dir>] [--confirm] [--allow-nonempty]
#   Senza --confirm: clona (o riusa) il mirror locale, lo verifica, scrive backup-summary.md e crea il gate
#                    G1-backup (DA_LEGGERE). NON pubblica sul backup.
#   Con --confirm:   richiede G1-backup APPROVATO dall'utente (gate.sh approve G1-backup, da terminale),
#                    poi esegue il push sul repo di backup e lo verifica ref per ref.
# Il mirror locale esistente viene RIUSATO se punta allo stesso sorgente e i suoi ref coincidono ancora col remoto.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"

[ $# -ge 2 ] || die "Uso: $0 <SOURCE_REPO> <BACKUP_REPO> [--dir D] [--confirm] [--allow-nonempty]"
SRC="$1"; BKP="$2"; shift 2
MIRROR="$REPORT_DIR/backup-mirror.git"; CONFIRM=0; NONEMPTY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) MIRROR="$2"; shift 2;;
    --confirm) CONFIRM=1; shift;;
    --allow-nonempty) NONEMPTY=1; shift;;
    *) die "Opzione sconosciuta: $1";;
  esac
done
need git

if [ "$CONFIRM" -eq 1 ]; then
  "$HERE/gate.sh" require G1-backup || die "Push sul backup bloccato dal gate G1-backup."
fi

info "Fase 2 - accesso in lettura al sorgente"
git ls-remote "$SRC" >/dev/null || die "Impossibile leggere il sorgente: $SRC"
ok "Sorgente leggibile"

info "Fase 2 - accesso al repo di backup"
bk_refs="$(git ls-remote "$BKP" 2>/dev/null)" || die "Repo di backup non raggiungibile (deve esistere, vuoto e privato): $BKP"
if [ -n "$bk_refs" ] && [ "$NONEMPTY" -eq 0 ] && [ "$CONFIRM" -eq 0 ]; then
  die "Il repo di backup NON è vuoto. Rischio di sovrascrittura: usa un repo vuoto o --allow-nonempty con approvazione."
fi

if [ -e "$MIRROR" ]; then
  cur="$(git --git-dir="$MIRROR" config remote.origin.url 2>/dev/null || true)"
  [ "$cur" = "$SRC" ] || die "$MIRROR esiste ma punta a un altro sorgente ($cur): rimuoverlo o usare --dir"
  diff <(git --git-dir="$MIRROR" for-each-ref --format='%(objectname) %(refname)' refs/heads refs/tags | sort) \
       <(git ls-remote --refs "$SRC" 'refs/heads/*' 'refs/tags/*' | awk '{print $1" "$2}' | sort) >/dev/null \
    || die "Il sorgente è cambiato dopo la creazione del mirror: rimuovere $MIRROR e ripartire (il backup deve riflettere lo stato attuale)."
  info "Riuso il mirror esistente $MIRROR (coincide col sorgente)"
else
  info "Fase 3 - git clone --mirror"
  git clone --mirror "$SRC" "$MIRROR"
fi

info "Verifica branch/tag/refs"
heads="$(count_refs "$MIRROR" refs/heads)"; tags="$(count_refs "$MIRROR" refs/tags)"
total="$(git --git-dir="$MIRROR" for-each-ref | wc -l | tr -d ' ')"
others="$(git --git-dir="$MIRROR" for-each-ref --format='%(refname)' | grep -Ev '^refs/(heads|tags)/' || true)"
nothers="$(printf '%s' "$others" | grep -c . || true)"
git --git-dir="$MIRROR" fsck --no-progress >/dev/null 2>&1 && ok "fsck OK" || warn "fsck ha segnalato avvisi"
echo "  branch: $heads  tag: $tags  ref totali: $total"
[ "$nothers" -eq 0 ] || warn "Ref aggiuntivi nel mirror (non pubblicati sul backup: refs/pull, refs/merge-requests, ecc.): $nothers"
state_set MIRROR_DIR "$MIRROR"; state_set BACKUP_URL "$BKP"; state_set SOURCE_URL "$SRC"
state_set BRANCH_COUNT "$heads"; state_set TAG_COUNT "$tags"
info "Snapshot dei ref remoti (preimage per il push con lease)"
"$HERE/snapshot-remote.sh" "$SRC"

SUMMARY="$REPORT_DIR/backup-summary.md"
{
  echo "# Backup mirror"; echo
  echo "- Sorgente: $SRC"; echo "- Repo di backup: $BKP"
  echo "- Mirror locale: $MIRROR"
  echo "- Branch: $heads - Tag: $tags - Ref totali: $total (non pubblicati: $nothers)"
  echo "- Il backup conterrà i secret ORIGINALI: deve essere privato e va eliminato a fine lavoro."
  echo; echo "## Ref che verranno pubblicati sul backup"
  git --git-dir="$MIRROR" for-each-ref --format='- %(refname:short) %(objectname:short)' refs/heads refs/tags
} > "$SUMMARY"

if [ "$CONFIRM" -ne 1 ]; then
  "$HERE/gate.sh" create G1-backup --title "Backup su repository di backup" --phrase "Confermo il backup" \
    --artifact "$SUMMARY" --summary "Push del mirror ($heads branch, $tags tag) su $BKP. Il backup contiene i secret originali."
  warn "Push sul backup NON eseguito: serve l'approvazione dell'utente del gate G1-backup, poi rilanciare con --confirm."
  exit 0
fi

info "Push sul backup (solo heads e tags)"
git --git-dir="$MIRROR" push --force "$BKP" '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*'

info "Verifica backup remoto"
diff <(git --git-dir="$MIRROR" for-each-ref --format='%(objectname) %(refname)' refs/heads refs/tags | sort) \
     <(git ls-remote "$BKP" 'refs/heads/*' 'refs/tags/*' | grep -v '\^{}' | awk '{print $1" "$2}' | sort) \
  && ok "Backup completo: $heads branch, $tags tag identici al sorgente" \
  || die "Il backup non coincide con il mirror"
state_set BACKUP_DONE 1
