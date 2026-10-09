#!/usr/bin/env bash
# Test end-to-end degli script (repo locali in una dir temporanea, scanner e gh finti, nessuna rete).
# Uso: tests/run-tests.sh      Richiede: git, git-filter-repo, jq, python3, curl
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/scripts"
T="$(mktemp -d)"; trap 'kill "${HTTP_PID:-0}" 2>/dev/null; rm -rf "$T"' EXIT
export PATH="$ROOT/tests/stubs:$PATH" CLEANUP_REPORTS="$T/rep" STUB_SECRET="SECRETVALUE123"
export GIT_AUTHOR_NAME=T GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=T GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0
chmod +x "$ROOT"/tests/stubs/* "$S"/*.sh
pass=0; failn=0

ok_()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad_()  { failn=$((failn + 1)); printf '  FAIL %s\n' "$1"; }
t_ok()   { local d="$1"; shift; if "$@" >"$T/out.log" 2>&1; then ok_ "$d"; else bad_ "$d"; sed 's/^/       | /' "$T/out.log" | tail -8; fi; cp "$T/out.log" "$T/last.log"; }
t_fail() { local d="$1"; shift; if "$@" >"$T/out.log" 2>&1; then bad_ "$d"; sed 's/^/       | /' "$T/out.log" | tail -5; else ok_ "$d"; fi; cp "$T/out.log" "$T/last.log"; }
t_rc()   { local d="$1" want="$2"; shift 2; "$@" >"$T/out.log" 2>&1; local rc=$?; if [ "$rc" -eq "$want" ]; then ok_ "$d"; else bad_ "$d (rc=$rc, atteso $want)"; sed 's/^/       | /' "$T/out.log" | tail -6; fi; cp "$T/out.log" "$T/last.log"; }
contains() { grep -q -- "$2" "$1"; }
absent()   { ! grep -q -- "$2" "$1"; }
# L'utente approva da terminale (pty): solo così gate.sh approve funziona
approve() { python3 "$ROOT/tests/approve.py" "$S/gate.sh" "$1" "$2"; }
gstatus() { sed -n 's/^status: //p' "$CLEANUP_REPORTS/gates/$1.md"; }

echo "== setup =="
cd "$T"
git init -q --bare -b main src.git; git init -q --bare -b main bkp.git
git clone -q src.git w 2>/dev/null; cd w
echo "hi README-TOKEN-XYZ" > README.md; mkdir cfg; echo 'AWS_KEY=AKIAIOSFODNN7EXAMPLE' > cfg/.env
echo 'token = SECRETVALUE123' > app.py; echo 'host=10.1.2.3' > net.conf
head -c 1500000 /dev/urandom > big.bin; echo k > server.pem
git add .; git commit -qm one
git rm -q cfg/.env; echo x >> README.md; git commit -qam "fix: remove SECRETVALUE123 from config"
git tag v1; git checkout -qb feat; echo y >> app.py; git commit -qam three
git push -q origin main feat v1; cd "$T"
printf '# regole\ncfg/.env\nnet.conf\n' > paths.txt; printf 'SECRETVALUE123==>***REMOVED***\n' > repl.txt
printf 'README.md\n' > keep.txt; printf 'README.md\ncfg/.env\n' > keep_bad.txt
printf 'README-TOKEN-XYZ==>X\n' > repl_keep.txt; : > empty_paths.txt

echo "== matcher =="
printf 'glob:*.pem\nregex:^deploy/.*\nsecrets/.env\n' > "$T/rules"
printf 'a/b.pem\ndeploy/x\nsecrets/.env\nsecrets/.env.bak\nREADME.md\n' | python3 "$S/match_paths.py" "$T/rules" > "$T/m.out"
t_ok "match_paths: glob/regex/literal" test "$(wc -l < "$T/m.out")" = 3
t_ok "match_paths: non confonde prefissi" absent "$T/m.out" '.env.bak'

echo "== gate.sh =="
t_fail "approve senza TTY rifiutato (l'agente non può approvare)" "$S/gate.sh" approve nonexist
"$S/gate.sh" create GT --title test --phrase "Frase di prova" --artifact "$T/paths.txt" >/dev/null 2>&1
t_ok "gate creato DA_LEGGERE" test "$(gstatus GT)" = DA_LEGGERE
t_fail "approve senza TTY rifiutato anche su gate esistente" "$S/gate.sh" approve GT
t_rc "require bloccato se DA_LEGGERE (exit 4)" 4 "$S/gate.sh" require GT
t_fail "approve con frase errata" approve GT "sbagliata"
t_ok "...stato invariato" test "$(gstatus GT)" = DA_LEGGERE
t_ok "approve con frase esatta via pty" approve GT "Frase di prova"
t_ok "gate APPROVATO" test "$(gstatus GT)" = APPROVATO
t_ok "require ok" "$S/gate.sh" require GT
echo '# extra' >> paths.txt
t_rc "require fallisce se un artefatto cambia (exit 4)" 4 "$S/gate.sh" require GT
sed -i '$d' paths.txt
t_ok "require torna ok se artefatto ripristinato" "$S/gate.sh" require GT
t_ok "create idempotente non resetta un gate approvato" "$S/gate.sh" create GT --title test --phrase "Frase di prova" --artifact "$T/paths.txt"
t_ok "...ancora APPROVATO" test "$(gstatus GT)" = APPROVATO
"$S/gate.sh" reject GT --reason test >/dev/null 2>&1
t_rc "gate RIFIUTATO blocca (exit 4)" 4 "$S/gate.sh" require GT
t_ok "require --optional su gate inesistente" "$S/gate.sh" require NONE --optional

echo "== backup / preimage / G1 =="
t_ok "backup senza --confirm non pubblica" "$S/backup-mirror.sh" "$T/src.git" "$T/bkp.git"
t_ok "backup vuoto dopo mirror locale" test -z "$(git ls-remote "$T/bkp.git")"
t_ok "preimage creato" test -s "$T/rep/remote-preimage.txt"
t_ok "gate G1-backup creato" test "$(gstatus G1-backup)" = DA_LEGGERE
t_ok "rilancio: riusa il mirror esistente" "$S/backup-mirror.sh" "$T/src.git" "$T/bkp.git"
t_ok "...e lo dichiara" contains "$T/last.log" 'Riuso il mirror'
t_fail "--confirm bloccato senza approvazione G1" "$S/backup-mirror.sh" "$T/src.git" "$T/bkp.git" --confirm
t_ok "backup ancora vuoto" test -z "$(git ls-remote "$T/bkp.git")"
t_ok "utente approva G1" approve G1-backup "Confermo il backup"
t_ok "backup con --confirm (riusa il mirror)" "$S/backup-mirror.sh" "$T/src.git" "$T/bkp.git" --confirm
t_ok "backup identico al sorgente" test "$(git ls-remote "$T/bkp.git" refs/heads/main | cut -f1)" = "$(git --git-dir="$T/src.git" rev-parse main)"
t_fail "snapshot rifiuta URL con credenziali" "$S/snapshot-remote.sh" "https://user:pw@example.com/x.git"
MIRROR="$T/rep/backup-mirror.git"

echo "== scansioni =="
t_rc "scan-secrets su mirror bare (trufflehog via copia) exit 1" 1 "$S/scan-secrets.sh" "$MIRROR" pre
t_ok "report gitleaks senza valore in chiaro" absent "$T/rep/pre-gitleaks.json" 'SECRETVALUE123'
t_ok "report gitleaks con valore mascherato" contains "$T/rep/pre-gitleaks.json" 'len 14'
t_ok "nessun file raw residuo" test -z "$(ls -A "$T"/rep/.pre-gitleaks.raw "$T"/rep/.scan-* 2>/dev/null)"
t_ok "summarize-findings" "$S/summarize-findings.sh" "$MIRROR" pre
t_ok "summarize mostra file:riga e valore mascherato" contains "$T/last.log" 'cfg/.env:2'
t_rc "scan-patterns trova IP privato (exit 1)" 1 "$S/scan-patterns.sh" "$MIRROR" pre
t_ok "scan-patterns non stampa i valori" absent "$T/rep/pre-patterns.tsv" '10\.1\.2\.3'
printf 'my-host::host=10\\.1\n' > "$T/custom.pat"
t_rc "scan-patterns con patterns-file" 1 "$S/scan-patterns.sh" "$MIRROR" pre2 --patterns-file "$T/custom.pat"
t_ok "pattern custom rilevato" contains "$T/rep/pre2-patterns.tsv" 'my-host'
t_ok "inventario revisione semantica" "$S/semantic-review-inventory.sh" "$MIRROR" pre
t_ok "scope include README.md" contains "$T/rep/pre-semantic-scope.md" 'README.md'

echo "== scoperta file (grandi / estensioni) =="
t_ok "scan-files trova file grande" "$S/scan-files.sh" "$MIRROR" f --min-size 1M --ext default
t_ok "...big.bin per dimensione" contains "$T/rep/f-files.tsv" 'big.bin'
t_ok "...server.pem per estensione" contains "$T/rep/f-files.tsv" 'server.pem'
t_ok "...app.py non è candidato" absent "$T/rep/f-files.tsv" 'app.py'
t_ok "suggerimenti NON attivi (commentati)" test -z "$(grep -Ev '^#' "$T/rep/f-paths-suggested.txt")"
t_ok "scan-files con sola estensione" "$S/scan-files.sh" "$MIRROR" f2 --min-size 0 --ext pem
t_ok "...solo .pem" test "$(tail -n +2 "$T/rep/f2-files.tsv" | wc -l)" = 1

echo "== dry-run (gate G3) =="
t_fail "dry-run bloccato senza gate G3" "$S/dry-run.sh" "$MIRROR" "$T/d0" --paths paths.txt --replace repl.txt --keep keep.txt
"$S/gate.sh" create G3-classificazione --title "Classificazione" --phrase "Confermo la classificazione" \
  --artifact "$T/paths.txt" --artifact "$T/repl.txt" --artifact "$T/keep.txt" >/dev/null 2>&1
t_fail "dry-run bloccato: G3 non approvato" "$S/dry-run.sh" "$MIRROR" "$T/d0" --paths paths.txt --replace repl.txt --keep keep.txt
t_ok "utente approva G3" approve G3-classificazione "Confermo la classificazione"
t_rc "dry-run: conflitto keep (file eliminato) exit 3" 3 "$S/dry-run.sh" "$MIRROR" "$T/d1" --paths paths.txt --replace repl.txt --keep keep_bad.txt
t_rc "dry-run: keep modificato da sostituzione exit 3" 3 "$S/dry-run.sh" "$MIRROR" "$T/d2" --paths paths.txt --replace repl_keep.txt --keep keep.txt
t_ok "...e lo spiega" contains "$T/last.log" 'modificherebbero file in keep-list'
t_ok "dry-run: --allow-keep-modified accetta" "$S/dry-run.sh" "$MIRROR" "$T/d3" --paths paths.txt --replace repl_keep.txt --keep keep.txt --allow-keep-modified
t_ok "dry-run: file vuoto di path tollerato" "$S/dry-run.sh" "$MIRROR" "$T/d4" --paths empty_paths.txt --replace repl.txt --keep keep.txt
t_ok "dry-run: --max-blob-size elimina file grandi" "$S/dry-run.sh" "$MIRROR" "$T/d5" --max-blob-size 1M --keep keep.txt
t_ok "...big.bin tra i file eliminati" contains "$T/rep/dryrun-removed-files.txt" 'big.bin'
t_ok "dry-run ok (regole approvate)" "$S/dry-run.sh" "$MIRROR" "$T/dry" --paths paths.txt --replace repl.txt --keep keep.txt
t_ok "dry-run conta il commit con secret nel messaggio" test "$(wc -l < "$T/rep/dryrun-affected-commits.txt")" -ge 2
t_ok "gate G4-riscrittura creato DA_LEGGERE" test "$(gstatus G4-riscrittura)" = DA_LEGGERE
t_ok "report segnala il branch di default" contains "$T/rep/dryrun-report.md" 'branch di default'

echo "== rewrite (gate G4) =="
t_fail "rewrite bloccato: G4 non approvato" "$S/rewrite.sh" "$MIRROR" "$T/clean" --paths paths.txt --replace repl.txt
t_fail "G4: frase sbagliata" approve G4-riscrittura "ok"
t_fail "rewrite ancora bloccato" "$S/rewrite.sh" "$MIRROR" "$T/clean" --paths paths.txt --replace repl.txt
t_ok "utente approva G4" approve G4-riscrittura "Confermo la riscrittura della history"
cp repl.txt repl.bak; echo 'EXTRA==>X' >> repl.txt
t_fail "rewrite rifiutato se le regole cambiano dopo l'approvazione" "$S/rewrite.sh" "$MIRROR" "$T/clean" --paths paths.txt --replace repl.txt
cp repl.bak repl.txt
t_fail "rewrite rifiutato con --no-message-rewrite (hash diverso)" "$S/rewrite.sh" "$MIRROR" "$T/clean" --paths paths.txt --replace repl.txt --no-message-rewrite
t_ok "rewrite approvato" "$S/rewrite.sh" "$MIRROR" "$T/clean" --paths paths.txt --replace repl.txt
t_ok "messaggi di commit riscritti" test -z "$(git --git-dir="$T/clean" log --all --format=%B | grep SECRETVALUE123)"
t_ok "backup intatto" test -n "$(git --git-dir="$MIRROR" log --all --format=%B | grep SECRETVALUE123)"
t_fail "push-prepare rifiutato prima della verifica" "$S/push-cleaned.sh" "$T/clean" "$T/src.git" --prepare
t_ok "verify-final OK" "$S/verify-final.sh" "$T/clean" post-cleanup --removed paths.txt --replace repl.txt --keep keep.txt --baseline "$MIRROR"
t_rc "verify-final sul backup = FAIL (exit 1)" 1 "$S/verify-final.sh" "$MIRROR" neg --removed paths.txt --replace repl.txt

echo "== protezioni (G2) =="
t_rc "check-protections: provider non GitHub = exit 2" 2 "$S/check-protections.sh" "$T/src.git"
t_ok "G2-protezioni creato" test "$(gstatus G2-protezioni)" = DA_LEGGERE
t_fail "dry-run/rewrite bloccati da G2 non approvato" "$S/rewrite.sh" "$MIRROR" "$T/clean2" --paths paths.txt --replace repl.txt
t_fail "push-prepare bloccato da G2" "$S/push-cleaned.sh" "$T/clean" "$T/src.git" --prepare
t_ok "utente approva G2" approve G2-protezioni "Confermo che le protezioni sono state rimosse o aggirate"
REP1="$CLEANUP_REPORTS"; export CLEANUP_REPORTS="$T/rep2"
t_rc "check-protections GitHub: ruleset attivo = exit 10" 10 "$S/check-protections.sh" "https://github.com/x/y.git"
t_ok "...elenca il ruleset e i bypass" contains "$T/rep2/protections.md" 'non_fast_forward'
t_ok "...e crea il gate G2" test "$(gstatus G2-protezioni)" = DA_LEGGERE
export CLEANUP_REPORTS="$REP1"

echo "== push con lease (G5) =="
t_ok "push --prepare crea G5" "$S/push-cleaned.sh" "$T/clean" "$T/src.git" --prepare
t_ok "G5 DA_LEGGERE" test "$(gstatus G5-push)" = DA_LEGGERE
t_ok "piano elenca i ref da forzare" contains "$T/rep/push-plan.md" 'FORCE'
t_fail "push bloccato senza approvazione G5" "$S/push-cleaned.sh" "$T/clean" "$T/src.git"
t_fail "G5: frase sbagliata" approve G5-push "si"
t_ok "utente approva G5" approve G5-push "Confermo il force push"
# il remoto cambia dopo lo snapshot -> il lease deve bloccare
( cd "$T/w" && git checkout -q main && echo late >> README.md && git commit -qam late && git push -q origin main )
before="$(git --git-dir="$T/src.git" rev-parse main)"
t_fail "lease: push rifiutato se il remoto è cambiato" "$S/push-cleaned.sh" "$T/clean" "$T/src.git"
t_ok "lease: rifiuto per stale info" contains "$T/last.log" 'stale info'
t_ok "lease: remoto invariato" test "$(git --git-dir="$T/src.git" rev-parse main)" = "$before"
t_ok "nuovo snapshot" "$S/snapshot-remote.sh" "$T/src.git"
t_fail "dopo nuovo snapshot il G5 non è più valido" "$S/push-cleaned.sh" "$T/clean" "$T/src.git"
t_ok "...nuovo prepare + approvazione" "$S/push-cleaned.sh" "$T/clean" "$T/src.git" --prepare
t_ok "utente riapprova G5" approve G5-push "Confermo il force push"
t_ok "push con lease riuscito" "$S/push-cleaned.sh" "$T/clean" "$T/src.git"
t_ok "remoto aggiornato" test "$(git --git-dir="$T/src.git" rev-parse main)" = "$(git --git-dir="$T/clean" rev-parse main)"
t_ok "tag aggiornato" test "$(git --git-dir="$T/src.git" rev-parse 'v1^{commit}')" = "$(git --git-dir="$T/clean" rev-parse 'v1^{commit}')"
git clone -q "$T/src.git" "$T/vc"
t_ok "verify post-push" "$S/verify-final.sh" "$T/vc" post-push --removed paths.txt --replace repl.txt --keep keep.txt

echo "== visibilità =="
t_rc "check-visibility: pubblico/fork = exit 10" 10 "$S/check-visibility.sh" "https://github.com/x/y.git"
t_rc "check-visibility: provider non GitHub = exit 0" 0 "$S/check-visibility.sh" "$T/src.git"

echo "== verifica anonima =="
mkdir -p "$T/www/commit"; old="$(head -1 "$T/rep/dryrun-affected-commits.txt")"; : > "$T/www/commit/$old"
PORT=$((20000 + RANDOM % 20000))
( cd "$T/www" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 ) & HTTP_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.5; done
export COMMIT_URL_TEMPLATE="http://127.0.0.1:$PORT/commit/<sha>"
t_rc "verify-anonymous: commit ancora raggiungibile = exit 1" 1 "$S/verify-anonymous.sh" "$T/src.git" --sha "$old"
t_rc "verify-anonymous: commit non raggiungibile = exit 0" 0 "$S/verify-anonymous.sh" "$T/src.git" --sha 0000000000000000000000000000000000000000
unset COMMIT_URL_TEMPLATE

echo
echo "Passati: $pass  Falliti: $failn"
[ "$failn" -eq 0 ]
