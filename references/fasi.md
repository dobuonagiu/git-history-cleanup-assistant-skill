# Comandi dettagliati per fase

Tutti gli script scrivono in `./cleanup-reports/` (override: `CLEANUP_REPORTS=/percorso`). Mai committare quella cartella.

| Fase | Comando |
|------|---------|
| 0 | `scripts/assess-repo.sh [path]` — equivale a `git remote -v`, `git branch -a`, `git tag` |
| 1 | `scripts/check-prereqs.sh` — `git --version`, `gitleaks version`, `trufflehog --version`, `git filter-repo --version` |
| 2-3 | `scripts/backup-mirror.sh <SRC> <BKP>` poi, dopo conferma, `... --confirm` |
| 5 | `scripts/scan-secrets.sh <mirror> pre-cleanup` + `scripts/summarize-findings.sh <mirror> pre-cleanup` |
| 9 | `scripts/dry-run.sh <mirror> <work> --paths P --replace R --keep K` |
| 11-12 | `scripts/rewrite.sh <mirror> <work> --approval "Confermo la riscrittura della history" --paths P --replace R` |
| 13 | `scripts/scan-secrets.sh` + `scripts/verify-final.sh <work> post-cleanup ...` |
| 14 | vedi sotto |
| 15 | `git clone <REPO> verify-clone` + `scripts/verify-final.sh verify-clone post-push ...` |

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

## Fase 14: push (dopo approvazione esplicita)
Script: `scripts/push-cleaned.sh <work> <URL> --approval "Confermo il force push"` (equivale a quanto segue).
`git filter-repo` rimuove il remote `origin`: va riaggiunto. Il work dir è un mirror bare
(con `safe.bareRepository=explicit` usare `git --git-dir=<work> ...`).
```bash
git --git-dir=<work> remote add origin <URL_SORGENTE>
git --git-dir=<work> push origin --force --all
git --git-dir=<work> push origin --force --tags
```
- Non usare `--mirror` verso GitHub/Azure DevOps (ref `refs/pull/*` rifiutati).
- Branch/tag eliminati dalla riscrittura restano sul remoto: elencarli e cancellarli solo con approvazione
  (`git push origin --delete <branch>`).
- Branch protetti: ricordare di averli disattivati in Fase 4.

## Limiti noti post-push
Su GitHub/GitLab i vecchi commit possono restare raggiungibili per SHA, cache, fork e PR chiuse:
contattare il supporto del provider per il garbage collection dei ref nascosti se i secret erano sensibili.
