#!/usr/bin/env bash
# Fasi 2-3: verifica accessi + backup mirror.
# Uso: backup-mirror.sh <SOURCE_REPO> <BACKUP_REPO> [--dir <mirror-dir>] [--confirm] [--allow-nonempty]
#   Senza --confirm: clona il mirror in locale e lo verifica, NON pubblica sul backup.
#   Con --confirm (approvazione utente): esegue il push sul repo di backup e verifica i ref remoti.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

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

info "Fase 2 - accesso in lettura al sorgente"
git ls-remote "$SRC" >/dev/null || die "Impossibile leggere il sorgente: $SRC"
ok "Sorgente leggibile"

info "Fase 2 - accesso al repo di backup"
bk_refs="$(git ls-remote "$BKP" 2>/dev/null)" || die "Repo di backup non raggiungibile (deve esistere, vuoto e privato): $BKP"
if [ -n "$bk_refs" ] && [ "$NONEMPTY" -eq 0 ]; then
  die "Il repo di backup NON è vuoto. Rischio di sovrascrittura: usa un repo vuoto o --allow-nonempty con approvazione."
fi
ok "Backup raggiungibile"

[ ! -e "$MIRROR" ] || die "Esiste già $MIRROR: rimuoverlo o usare --dir"

info "Fase 3 - git clone --mirror"
git clone --mirror "$SRC" "$MIRROR"

info "Verifica branch/tag/refs"
heads="$(count_refs "$MIRROR" refs/heads)"; tags="$(count_refs "$MIRROR" refs/tags)"
total="$(gr "$MIRROR" for-each-ref | wc -l | tr -d ' ')"
others="$(gr "$MIRROR" for-each-ref --format='%(refname)' | grep -Ev '^refs/(heads|tags)/' || true)"
gr "$MIRROR" fsck --no-progress >/dev/null 2>&1 && ok "fsck OK" || warn "fsck ha segnalato avvisi"
echo "  branch: $heads  tag: $tags  ref totali: $total"
if [ -n "$others" ]; then
  warn "Ref aggiuntivi nel mirror (non pubblicati sul backup: refs/pull, refs/merge-requests, ecc.): $(echo "$others" | wc -l | tr -d ' ')"
fi
state_set MIRROR_DIR "$MIRROR"; state_set BACKUP_URL "$BKP"; state_set SOURCE_URL "$SRC"
state_set BRANCH_COUNT "$heads"; state_set TAG_COUNT "$tags"

if [ "$CONFIRM" -ne 1 ]; then
  warn "Push sul backup NON eseguito (manca --confirm). Chiedi conferma all'utente e rilancia con --confirm."
  exit 0
fi

info "Push sul backup (solo heads e tags)"
gr "$MIRROR" push --force "$BKP" '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*'

info "Verifica backup remoto"
diff <(gr "$MIRROR" for-each-ref --format='%(objectname) %(refname)' refs/heads refs/tags | sort) \
     <(git ls-remote "$BKP" 'refs/heads/*' 'refs/tags/*' | grep -v '\^{}' | awk '{print $1" "$2}' | sort) \
  && ok "Backup completo: $heads branch, $tags tag identici al sorgente" \
  || die "Il backup non coincide con il mirror"
state_set BACKUP_DONE 1
