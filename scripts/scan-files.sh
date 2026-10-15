#!/usr/bin/env bash
# Fase 5c: scoperta di FILE da eliminare dalla history: file grandi e/o con estensioni/nomi sensibili.
# Uso: scan-files.sh <repo> <label> [--min-size 50M] [--ext zip,pem,...|default|none] [--name-regex REGEX]
#   --min-size   soglia dimensione blob (K/M/G). Default 50M. "0" disattiva la ricerca per dimensione.
#   --ext        estensioni da cercare; "default" = lista di estensioni/nomi tipicamente sensibili;
#                "none" disattiva la ricerca per estensione
#   --name-regex regex ERE sul path completo (es. '(^|/)\.env(\..*)?$')
# Output: $REPORT_DIR/<label>-files.tsv  e  $REPORT_DIR/<label>-paths-suggested.txt
# Il file *-paths-suggested.txt contiene SOLO suggerimenti commentati: l'utente decide (azione A, Fase 6)
# e copia le regole scelte in paths-to-remove.txt. Nulla viene eliminato da questo script.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
[ $# -ge 2 ] || die "Uso: $0 <repo> <label> [--min-size 50M] [--ext zip,pem|default|none] [--name-regex RE]"
repo="$1"; label="$2"; shift 2
MIN="50M"; EXT=""; NAMERE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --min-size) [ $# -ge 2 ] || die "Valore mancante per --min-size"; MIN="$2"; shift 2;;
    --ext) [ $# -ge 2 ] || die "Valore mancante per --ext"; EXT="$2"; shift 2;;
    --name-regex) [ $# -ge 2 ] || die "Valore mancante per --name-regex"; NAMERE="$2"; shift 2;;
    *) die "Opzione sconosciuta: $1";;
  esac
done

DEFAULT_EXT="pem,key,p12,pfx,jks,keystore,kdbx,ovpn,pcap,sqlite,sqlite3,db,dump,bak,tfstate,tfvars,gpg,asc,crt,cer,der,zip,tar,gz,tgz,7z,rar,iso,war,jar"
DEFAULT_NAMES='(^|/)(\.env(\..*)?|id_rsa|id_dsa|id_ecdsa|id_ed25519|\.htpasswd|\.npmrc|\.pypirc|credentials(\.json)?|secrets?\.(json|ya?ml|toml)|terraform\.tfstate(\.backup)?)$'
if [ "$EXT" = "default" ]; then EXT="$DEFAULT_EXT"; [ -n "$NAMERE" ] || NAMERE="$DEFAULT_NAMES"; fi
if [ "$EXT" = "none" ]; then EXT=""; fi

[[ "$MIN" =~ ^[0-9]+[KkMmGg]?$ ]] || die "Soglia non valida: $MIN (usa byte o un numero seguito da K, M o G; 0 disattiva)"
MINB="$(python3 - "$MIN" <<'PY'
import re
import sys

value = sys.argv[1]
match = re.fullmatch(r"([0-9]+)([KkMmGg]?)", value)
number = int(match.group(1))
factor = {"": 1, "k": 1024, "m": 1024**2, "g": 1024**3}[match.group(2).lower()]
print(number * factor)
PY
)" || die "Impossibile convertire la soglia: $MIN"
[[ -z "$EXT" || "$EXT" == "default" ]] || {
  [[ ! "$EXT" =~ (^,|,,|,$) ]] || die "Elenco estensioni non valido: contiene un elemento vuoto"
  IFS=',' read -r -a ext_parts <<< "$EXT"
  normalized_ext=()
  for ext in "${ext_parts[@]}"; do
    ext="${ext//[[:space:]]/}"
    ext="${ext#.}"
    [[ "$ext" =~ ^[[:alnum:]_.+-]+$ ]] || die "Estensione non valida: $ext"
    [ -n "$ext" ] || die "Elenco estensioni non valido: contiene un elemento vuoto"
    normalized_ext+=("${ext,,}")
  done
  EXT="$(IFS=,; echo "${normalized_ext[*]}")"
}

out="$REPORT_DIR/$label-files.tsv"; sug="$REPORT_DIR/$label-paths-suggested.txt"
printf 'MOTIVO\tPATH\tDIM_MAX\tVERSIONI\tNEI_TIP\n' > "$out"

# path -> blob distinti in ogni albero storico. `rev-list --objects` deduplica per object ID e
# quindi può nascondere un secondo path che condivide lo stesso contenuto.
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
gr "$repo" log --all --format=%T | sort -u | while IFS= read -r tree; do
  [ -z "$tree" ] || gr "$repo" ls-tree -r -l "$tree"
done | awk -F'\t' '$1 ~ / blob / { split($1, meta, " "); print $2 "\t" meta[3] "\t" meta[4] }' | sort -u > "$tmp"

tips="$(mktemp)"; trap 'rm -f "$tmp" "$tips"' EXIT
gr "$repo" for-each-ref --format='%(refname)' refs/heads refs/tags | while read -r r; do gr "$repo" ls-tree -r --name-only "$r"; done | sort -u > "$tips"

EXTENSIONS="$EXT" NAMERE="$NAMERE" awk -F'\t' -v min="$MINB" '
  BEGIN {
    n_ext=split(ENVIRON["EXTENSIONS"], ext, ",")
    namere=ENVIRON["NAMERE"]
  }
  { p=$1; oid=$2; s=$3+0; n[p]++; if (s>m[p]) m[p]=s }
  END { for (p in n) {
          why=""
          if (min>0 && m[p]>=min) why="grande"
          for (i=1; i<=n_ext && ext[i]!=""; i++) {
            suffix="." tolower(ext[i]); path=tolower(p)
            if (length(path)>=length(suffix) && substr(path, length(path)-length(suffix)+1)==suffix) {
              why=(why==""?"estensione":why"+estensione")
              break
            }
          }
          if (namere!="" && p ~ namere) why=(why==""?"nome":why"+nome")
          if (why!="") printf "%s\t%s\t%d\t%d\n", why, p, m[p], n[p]
      } }' "$tmp" | sort -t$'\t' -k3,3nr | while IFS=$'\t' read -r why p sz n; do
  intip="no"; grep -qxF -- "$p" "$tips" && intip="sì"
  printf '%s\t%s\t%s\t%s\t%s\n' "$why" "$p" "$(numfmt --to=iec "$sz" 2>/dev/null || echo "$sz")" "$n" "$intip"
done >> "$out"

total=$(( $(wc -l < "$out") - 1 ))
{
  echo "# SUGGERIMENTI (generati da scan-files.sh, label=$label). NON ancora attivi."
  echo "# Criterio dimensione minima: $MIN"
  echo "# Estensioni: ${EXT:-nessuna}"
  [ -z "$NAMERE" ] || echo "# Regex nome: $NAMERE"
  echo "# Per eliminarli dalla history (azione A) copia le righe volute (senza il prefisso '#> ') in paths-to-remove.txt."
  echo "# La soglia serve alla scoperta; non equivale a una regola di rimozione in blocco."
  tail -n +2 "$out" | awk -F'\t' '{ printf "# %s | %s | max %s | %s versioni | nel tip: %s\n#> %s\n", $1, $2, $3, $4, $5, $2 }'
} > "$sug"

echo "[$label] $total file candidati (soglia ${MIN}${EXT:+, estensioni: $EXT}${NAMERE:+, nome: regex}) -> $out"
[ "$total" -gt 0 ] && { column -t -s $'\t' "$out" | head -40; echo; echo "Suggerimenti (da approvare): $sug"; }
exit 0
