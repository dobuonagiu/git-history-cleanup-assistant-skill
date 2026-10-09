#!/usr/bin/env bash
# Fase 5c: scoperta di FILE da eliminare dalla history: file grandi e/o con estensioni/nomi sensibili.
# Uso: scan-files.sh <repo> <label> [--min-size 5M] [--ext zip,pem,...|default] [--name-regex REGEX]
#   --min-size   soglia dimensione blob (K/M/G). Default 5M. "0" disattiva la ricerca per dimensione.
#   --ext        estensioni da cercare; "default" = lista di estensioni/nomi tipicamente sensibili
#   --name-regex regex ERE sul path completo (es. '(^|/)\.env(\..*)?$')
# Output: $REPORT_DIR/<label>-files.tsv  e  $REPORT_DIR/<label>-paths-suggested.txt
# Il file *-paths-suggested.txt contiene SOLO suggerimenti commentati: l'utente decide (azione A, Fase 6)
# e copia le regole scelte in paths-to-remove.txt. Nulla viene eliminato da questo script.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
[ $# -ge 2 ] || die "Uso: $0 <repo> <label> [--min-size 5M] [--ext zip,pem|default] [--name-regex RE]"
repo="$1"; label="$2"; shift 2
MIN="5M"; EXT=""; NAMERE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --min-size) MIN="$2"; shift 2;;
    --ext) EXT="$2"; shift 2;;
    --name-regex) NAMERE="$2"; shift 2;;
    *) die "Opzione sconosciuta: $1";;
  esac
done

DEFAULT_EXT="pem,key,p12,pfx,jks,keystore,kdbx,ovpn,pcap,sqlite,sqlite3,db,dump,bak,tfstate,tfvars,gpg,asc,crt,cer,der,zip,tar,gz,tgz,7z,rar,iso,war,jar"
DEFAULT_NAMES='(^|/)(\.env(\..*)?|id_rsa|id_dsa|id_ecdsa|id_ed25519|\.htpasswd|\.npmrc|\.pypirc|credentials(\.json)?|secrets?\.(json|ya?ml|toml)|terraform\.tfstate(\.backup)?)$'
if [ "$EXT" = "default" ]; then EXT="$DEFAULT_EXT"; [ -n "$NAMERE" ] || NAMERE="$DEFAULT_NAMES"; fi

to_bytes() { # 5M -> 5242880
  local v="$1"; case "$v" in
    *[Kk]) echo $(( ${v%[Kk]} * 1024 ));; *[Mm]) echo $(( ${v%[Mm]} * 1048576 ));;
    *[Gg]) echo $(( ${v%[Gg]} * 1073741824 ));; *) echo "$v";; esac
}
MINB="$(to_bytes "$MIN")"
extre=""; [ -z "$EXT" ] || extre="\\.($(echo "$EXT" | sed 's/[[:space:]]//g; s/,/|/g'))$"

out="$REPORT_DIR/$label-files.tsv"; sug="$REPORT_DIR/$label-paths-suggested.txt"
printf 'MOTIVO\tPATH\tDIM_MAX\tVERSIONI\tNEI_TIP\n' > "$out"

# path -> (dimensione max, n. versioni distinte) per ogni blob nella history
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
gr "$repo" rev-list --objects --all \
  | gr "$repo" cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' \
  | awk '$1=="blob" && NF>=4 { sz=$3; $1=$2=$3=""; sub(/^ +/,""); print sz "\t" $0 }' > "$tmp"

tips="$(mktemp)"; trap 'rm -f "$tmp" "$tips"' EXIT
gr "$repo" for-each-ref --format='%(refname)' refs/heads refs/tags | while read -r r; do gr "$repo" ls-tree -r --name-only "$r"; done | sort -u > "$tips"

EXTRE="$extre" NAMERE="$NAMERE" awk -F'\t' -v min="$MINB" '
  BEGIN { extre=ENVIRON["EXTRE"]; namere=ENVIRON["NAMERE"] }
  { p=$2; s=$1+0; n[p]++; if (s>m[p]) m[p]=s }
  END { for (p in n) {
          why=""
          if (min>0 && m[p]>=min) why="grande"
          if (extre!="" && tolower(p) ~ extre) why=(why==""?"estensione":why"+estensione")
          if (namere!="" && p ~ namere) why=(why==""?"nome":why"+nome")
          if (why!="") printf "%s\t%s\t%d\t%d\n", why, p, m[p], n[p]
      } }' "$tmp" | sort -t$'\t' -k3,3nr | while IFS=$'\t' read -r why p sz n; do
  intip="no"; grep -qxF -- "$p" "$tips" && intip="sì"
  printf '%s\t%s\t%s\t%s\t%s\n' "$why" "$p" "$(numfmt --to=iec "$sz" 2>/dev/null || echo "$sz")" "$n" "$intip"
done >> "$out"

total=$(( $(wc -l < "$out") - 1 ))
{
  echo "# SUGGERIMENTI (generati da scan-files.sh, label=$label). NON ancora attivi."
  echo "# Per eliminarli dalla history (azione A) copia le righe volute (senza il prefisso '#> ') in paths-to-remove.txt."
  echo "# Per file grandi in blocco puoi invece usare --max-blob-size $MIN in dry-run/rewrite."
  tail -n +2 "$out" | awk -F'\t' '{ printf "# %s | %s | max %s | %s versioni | nel tip: %s\n#> %s\n", $1, $2, $3, $4, $5, $2 }'
} > "$sug"

echo "[$label] $total file candidati (soglia ${MIN}${EXT:+, estensioni: $EXT}${NAMERE:+, nome: regex}) -> $out"
[ "$total" -gt 0 ] && { column -t -s $'\t' "$out" | head -40; echo; echo "Suggerimenti (da approvare): $sug"; }
exit 0
