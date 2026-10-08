#!/usr/bin/env bash
# Test end-to-end degli script (repo locali in una dir temporanea, scanner finti, nessuna rete).
# Uso: tests/run-tests.sh      Richiede: git, git-filter-repo, jq, python3, curl
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/scripts"
T="$(mktemp -d)"; trap 'kill "${HTTP_PID:-0}" 2>/dev/null; rm -rf "$T"' EXIT
export PATH="$ROOT/tests/stubs:$PATH" CLEANUP_REPORTS="$T/rep" STUB_SECRET="SECRETVALUE123"
export GIT_AUTHOR_NAME=T GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=T GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0
chmod +x "$ROOT"/tests/stubs/*
pass=0; failn=0

ok_()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad_()  { failn=$((failn + 1)); printf '  FAIL %s\n' "$1"; }
# t_ok "descr" cmd...   -> il comando deve riuscire ;  t_fail -> deve fallire
t_ok()   { local d="$1"; shift; if "$@" >"$T/out.log" 2>&1; then ok_ "$d"; else bad_ "$d"; sed 's/^/       | /' "$T/out.log" | tail -8; fi; }
t_fail() { local d="$1"; shift; if "$@" >"$T/out.log" 2>&1; then bad_ "$d"; else ok_ "$d"; fi; cp "$T/out.log" "$T/last.log"; }
t_rc()   { local d="$1" want="$2"; shift 2; "$@" >"$T/out.log" 2>&1; local rc=$?; if [ "$rc" -eq "$want" ]; then ok_ "$d"; else bad_ "$d (rc=$rc, atteso $want)"; sed 's/^/       | /' "$T/out.log" | tail -6; fi; }
contains() { grep -q -- "$2" "$1"; }
absent()   { ! grep -q -- "$2" "$1"; }

echo "== setup =="
mkdir -p "$T/w" && cd "$T"
git init -q --bare -b main src.git; git init -q --bare -b main bkp.git
git clone -q src.git w 2>/dev/null; cd w
echo hi > README.md; mkdir cfg; echo 'AWS_KEY=AKIAIOSFODNN7EXAMPLE' > cfg/.env
echo 'token = SECRETVALUE123' > app.py; echo 'host=10.1.2.3' > net.conf
git add .; git commit -qm one
git rm -q cfg/.env; echo x >> README.md; git commit -qam "fix: remove SECRETVALUE123 from config"
git tag v1; git checkout -qb feat; echo y >> app.py; git commit -qam three
git push -q origin main feat v1; cd "$T"
printf '# regole\ncfg/.env\n' > paths.txt; printf 'SECRETVALUE123==>***REMOVED***\n' > repl.txt
printf 'README.md\napp.py\n' > keep.txt; printf 'README.md\ncfg/.env\n' > keep_bad.txt

echo "== matcher =="
printf 'glob:*.pem\nregex:^deploy/.*\nsecrets/.env\n' > "$T/rules"
printf 'a/b.pem\ndeploy/x\nsecrets/.env\nsecrets/.env.bak\nREADME.md\n' | python3 "$S/match_paths.py" "$T/rules" > "$T/m.out"
t_ok "match_paths: glob/regex/literal" test "$(wc -l < "$T/m.out")" = 3
t_ok "match_paths: non confonde prefissi" absent "$T/m.out" '.env.bak'

echo "== backup / preimage =="
t_ok "backup senza --confirm non pubblica" "$S/backup-mirror.sh" "$T/src.git" "$T/bkp.git"
t_ok "backup vuoto dopo dry-mirror" test -z "$(git ls-remote "$T/bkp.git")"
t_ok "preimage creato" test -s "$T/rep/remote-preimage.txt"
rm -rf "$T/rep/backup-mirror.git"
t_ok "backup con --confirm" "$S/backup-mirror.sh" "$T/src.git" "$T/bkp.git" --confirm
t_fail "backup rifiuta repo non vuoto" "$S/backup-mirror.sh" "$T/src.git" "$T/bkp.git" --dir "$T/m2"
t_fail "snapshot rifiuta URL con credenziali" "$S/snapshot-remote.sh" "https://user:pw@example.com/x.git"
MIRROR="$T/rep/backup-mirror.git"

echo "== scansioni =="
t_rc "scan-secrets trova il secret (exit 1)" 1 "$S/scan-secrets.sh" "$MIRROR" pre
t_ok "summarize-findings" "$S/summarize-findings.sh" "$MIRROR" pre
t_rc "scan-patterns trova IP privato (exit 1)" 1 "$S/scan-patterns.sh" "$MIRROR" pre
t_ok "scan-patterns non stampa i valori" absent "$T/rep/pre-patterns.tsv" '10\.1\.2\.3'
printf 'my-host::host=10\\.1\n' > "$T/custom.pat"
t_rc "scan-patterns con patterns-file" 1 "$S/scan-patterns.sh" "$MIRROR" pre2 --patterns-file "$T/custom.pat"
t_ok "pattern custom rilevato" contains "$T/rep/pre2-patterns.tsv" 'my-host'
t_ok "inventario revisione semantica" "$S/semantic-review-inventory.sh" "$MIRROR" pre
t_ok "scope include README.md" contains "$T/rep/pre-semantic-scope.md" 'README.md'

echo "== dry-run =="
t_rc "dry-run: conflitto con keep-list (exit 3)" 3 "$S/dry-run.sh" "$MIRROR" "$T/dry1" --paths paths.txt --replace repl.txt --keep keep_bad.txt
t_ok "dry-run ok" "$S/dry-run.sh" "$MIRROR" "$T/dry2" --paths paths.txt --replace repl.txt --keep keep.txt
t_ok "dry-run conta il commit con secret nel messaggio" test "$(wc -l < "$T/rep/dryrun-affected-commits.txt")" -ge 2

echo "== rewrite (gate) =="
t_fail "rewrite rifiuta senza approvazione" "$S/rewrite.sh" "$MIRROR" "$T/c0" --paths paths.txt --replace repl.txt
t_fail "rewrite rifiuta frase sbagliata" "$S/rewrite.sh" "$MIRROR" "$T/c0" --paths paths.txt --replace repl.txt --approval "ok"
echo 'EXTRA==>X' >> repl.txt
t_fail "rewrite rifiuta se le regole cambiano dopo dry-run" "$S/rewrite.sh" "$MIRROR" "$T/c0" --paths paths.txt --replace repl.txt --approval "Confermo la riscrittura della history"
printf 'SECRETVALUE123==>***REMOVED***\n' > repl.txt
t_fail "rewrite rifiuta se --no-message-rewrite cambia hash" "$S/rewrite.sh" "$MIRROR" "$T/c0" --paths paths.txt --replace repl.txt --no-message-rewrite --approval "Confermo la riscrittura della history"

echo "== rewrite (reale) =="
t_ok "rewrite approvato" "$S/rewrite.sh" "$MIRROR" "$T/clean" --paths paths.txt --replace repl.txt --approval "Confermo la riscrittura della history"
t_ok "messaggi di commit riscritti" test -z "$(git --git-dir="$T/clean" log --all --format=%B | grep SECRETVALUE123)"
t_ok "backup intatto" test -n "$(git --git-dir="$MIRROR" log --all --format=%B | grep SECRETVALUE123)"
t_fail "push rifiutato prima della verifica" "$S/push-cleaned.sh" "$T/clean" "$T/src.git" --approval "Confermo il force push"
t_rc "verify-final: IP privato residuo = FAIL (exit 1)" 1 "$S/verify-final.sh" "$T/clean" post-cleanup --removed paths.txt --replace repl.txt --keep keep.txt --baseline "$MIRROR"
# l'IP 10.x è un finding legittimo dei pattern: lo trattiamo come falso positivo rimuovendo net.conf dalla history
printf 'cfg/.env\nnet.conf\n' > paths.txt
rm -rf "$T/dry3" "$T/clean"; "$S/dry-run.sh" "$MIRROR" "$T/dry3" --paths paths.txt --replace repl.txt --keep keep.txt >/dev/null 2>&1
t_ok "rewrite 2 (con net.conf)" "$S/rewrite.sh" "$MIRROR" "$T/clean" --paths paths.txt --replace repl.txt --approval "Confermo la riscrittura della history"
t_ok "verify-final OK" "$S/verify-final.sh" "$T/clean" post-cleanup --removed paths.txt --replace repl.txt --keep keep.txt --baseline "$MIRROR"
t_rc "verify-final sul backup = FAIL (exit 1)" 1 "$S/verify-final.sh" "$MIRROR" neg --removed paths.txt --replace repl.txt

echo "== push con lease =="
t_fail "push rifiuta senza approvazione" "$S/push-cleaned.sh" "$T/clean" "$T/src.git"
t_fail "push rifiuta frase sbagliata" "$S/push-cleaned.sh" "$T/clean" "$T/src.git" --approval "si"
# il remoto cambia dopo lo snapshot -> lease deve bloccare
( cd "$T/w" && git checkout -q main && echo late >> README.md && git commit -qam late && git push -q origin main )
before="$(git --git-dir="$T/src.git" rev-parse main)"
t_fail "lease: push rifiutato se il remoto è cambiato" "$S/push-cleaned.sh" "$T/clean" "$T/src.git" --approval "Confermo il force push"
t_ok "lease: rifiuto per stale info" contains "$T/last.log" 'stale info'
t_ok "lease: remoto invariato" test "$(git --git-dir="$T/src.git" rev-parse main)" = "$before"
t_ok "nuovo snapshot" "$S/snapshot-remote.sh" "$T/src.git"
t_ok "push con lease riuscito" "$S/push-cleaned.sh" "$T/clean" "$T/src.git" --approval "Confermo il force push"
t_ok "remoto aggiornato" test "$(git --git-dir="$T/src.git" rev-parse main)" = "$(git --git-dir="$T/clean" rev-parse main)"
t_ok "tag aggiornato" test "$(git --git-dir="$T/src.git" rev-parse 'v1^{commit}')" = "$(git --git-dir="$T/clean" rev-parse 'v1^{commit}')"
git clone -q "$T/src.git" "$T/vc"
t_ok "verify post-push" "$S/verify-final.sh" "$T/vc" post-push --removed paths.txt --replace repl.txt --keep keep.txt

echo "== visibilità =="
t_rc "check-visibility: pubblico/fork = exit 10" 10 "$S/check-visibility.sh" "https://github.com/x/y.git"
t_rc "check-visibility: provider non GitHub = exit 0" 0 "$S/check-visibility.sh" "$T/src.git"
printf 'PREIMAGE_URL=https://github.com/x/y.git\n' >> "$T/rep/state.env"
printf 'VERIFY_post_cleanup=OK\n' >> "$T/rep/state.env"
t_fail "push GitHub pubblico richiede --ack-exposure" "$S/push-cleaned.sh" "$T/clean" "https://github.com/x/y.git" --approval "Confermo il force push"
t_ok "...e il motivo è l'ack" contains "$T/last.log" 'ack-exposure'

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
