# Comandi dettagliati per fase

Tutti gli script scrivono in `./cleanup-reports/` (override: `CLEANUP_REPORTS=/percorso`). Mai committare quella cartella.

| Fase | Comando |
|------|---------|
| 0 | `scripts/assess-repo.sh [path]` — equivale a `git remote -v`, `git branch -a`, `git tag` |
| 1 | `scripts/check-prereqs.sh` |
| 2 | `scripts/check-visibility.sh <URL>` |
| 3 | `scripts/backup-mirror.sh <SRC> <BKP>` → gate G1 → `... --confirm` |
| 4 | `scripts/check-protections.sh <URL>` → gate G2 se presenti |
| 5 | `scripts/scan-secrets.sh <mirror> pre` · `summarize-findings.sh` · `scan-patterns.sh` · `semantic-review-inventory.sh` |
| 5c | `scripts/scan-files.sh <mirror> pre --min-size 5M --ext default` |
| 7 | `gate.sh create G3-classificazione ...` |
| 9 | `scripts/dry-run.sh <mirror> <work> --paths P --replace R --keep K [--max-blob-size 5M]` → gate G4 |
| 11-12 | `scripts/rewrite.sh <mirror> <work2> --paths P --replace R` (richiede G4 approvato) |
| 13 | `scripts/verify-final.sh <work2> post-cleanup ...` |
| 14 | `scripts/push-cleaned.sh <work2> <URL> --prepare` → gate G5 → `scripts/push-cleaned.sh <work2> <URL>` |
| 15 | `git clone <URL> verify-clone` + `verify-final.sh` + `scripts/verify-anonymous.sh <URL>` |

## Gate (file Markdown con stato)
`scripts/gate.sh create|status|require|approve|reject`. File in `cleanup-reports/gates/<ID>.md`, stati
`DA_LEGGERE` → `APPROVATO` (o `RIFIUTATO`). `approve` funziona solo da terminale interattivo (TTY) e richiede
di digitare la frase esatta: l'agente non può approvare. `require` fallisce (exit 4) se il gate non è APPROVATO
o se un artefatto è cambiato dopo l'approvazione. Un `create` con stessi artefatti e frase su un gate già
APPROVATO lo lascia invariato (utile per riprendere una sessione).

## Installazione tool (solo dopo conferma utente)
- gitleaks: `brew install gitleaks` · `sudo apt install gitleaks` · release ufficiale (>= 8.19)
- trufflehog: `brew install trufflehog` · `curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b ~/.local/bin`
  (`pip install trufflehog` NON è il tool ufficiale)
- git-filter-repo: `sudo apt install git-filter-repo` · `pip install git-filter-repo`

## Fase 2: test accessi
- Lettura: `git ls-remote <SRC>`
- Backup: `git ls-remote <BKP>` (repo vuoto, privato)
- Push/force push: verificare ruolo (admin/maintain) e che le protezioni non blocchino il force push (Fase 4).
  Non fare force push di prova sul sorgente. Si può testare su un branch temporaneo del **backup**:
  `git push <BKP> HEAD:refs/heads/_probe && git push -f <BKP> HEAD:refs/heads/_probe && git push <BKP> :refs/heads/_probe`
  (solo con l'ok dell'utente).

## Fase 5: comandi sottostanti
```bash
gitleaks git --no-banner --redact --report-format json --report-path out.json <repo>
trufflehog git file://<repo> --json --no-update
```
Gravità: trufflehog `Verified=true` → CRITICAL (credenziale ancora attiva); altri finding → HIGH.

## Fase 8: impact analysis manuale
```bash
git log --all --oneline -- <path>
git branch -a --contains <sha>
git tag --contains <sha>
git log --all -S'<valore>' --oneline        # occorrenze di un valore
```

## Fase 14: push con lease (dopo approvazione esplicita)
Script: `scripts/push-cleaned.sh <work> <URL> --prepare` (piano + gate G5), poi `scripts/push-cleaned.sh <work> <URL>` dopo l'approvazione dell'utente. Pubblica solo i ref cambiati o nuovi.
Prima della riscrittura (Fase 3) `snapshot-remote.sh <URL>` salva `remote-preimage.txt` (`<sha> <ref>`).
Il push equivale a (un lease per ogni ref; sha vuoto = il ref non deve esistere sul remoto):
```bash
git --git-dir=<work> remote add origin <URL>
git --git-dir=<work> push origin \
  --force-with-lease=refs/heads/main:<sha-preimage> --force-with-lease=refs/tags/v1:<sha-preimage> ... \
  refs/heads/main:refs/heads/main refs/tags/v1:refs/tags/v1 ...
```
Se il remoto è cambiato dopo lo snapshot → `stale info`, push rifiutato per quel ref: ripartire da snapshot/analisi.
Mai fallback a `--force`, mai `--no-verify`. `filter-repo` rimuove `origin` e un mirror lascia `remote.origin.mirror=true`
(incompatibile con refspec espliciti): lo script reimposta il remote.
Con `safe.bareRepository=explicit` usare `git --git-dir=<work> ...`.
- Non usare `--mirror` verso GitHub/Azure DevOps (ref `refs/pull/*` rifiutati).
- Branch/tag eliminati dalla riscrittura restano sul remoto: elencarli e cancellarli solo con approvazione
  (`git push origin --delete <branch>`).
- Branch protetti: ricordare di averli disattivati in Fase 4.

## Visibilità e fork (Fase 2/14)
`scripts/check-visibility.sh <URL>`: `gh repo view <owner>/<repo> --json visibility,forkCount,isFork,isArchived`.
Exit 0 = privato senza fork (o provider non GitHub: da verificare a mano), 10 = pubblico/con fork, 2 = verifica impossibile.
Se exit ≠ 0 la frase del gate G5 diventa `Confermo il force push su repository pubblico o non verificato`.

## Verifica anonima (Fase 15)
`scripts/verify-anonymous.sh <URL> [--commits F | --sha SHA]`: senza credenziali prova `git ls-remote` e
`https://github.com/<owner>/<repo>/commit/<sha>` per i vecchi commit (da `dryrun-affected-commits.txt`).
HTTP 200 = ancora raggiungibile (residuo); 404 = non raggiungibile (su repo privato non prova la rimozione).
Altri provider: `COMMIT_URL_TEMPLATE='https://host/.../<sha>'`.

## Pattern custom, allowlist, revisione semantica
- `scripts/scan-patterns.sh <repo> <label> [--patterns-file F]` — formato `nome::regex`, esempi in `references/patterns.example`.
- `GITLEAKS_CONFIG=<toml>` — allowlist per falsi positivi, esempio in `references/gitleaks.example.toml`.
- `scripts/semantic-review-inventory.sh <repo> <label>` + `references/ai_semantic_review_prompt.md`.

## Test degli script
`tests/run-tests.sh` (repo locali temporanei, scanner e `gh` finti, nessuna rete). Eseguito anche da GitHub Actions.

## Limiti noti post-push
Su GitHub/GitLab i vecchi commit possono restare raggiungibili per SHA, cache, fork e PR chiuse:
contattare il supporto del provider per il garbage collection dei ref nascosti se i secret erano sensibili.
