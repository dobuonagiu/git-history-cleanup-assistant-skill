# Git History Cleanup Assistant (Copilot CLI skill)

Skill per GitHub Copilot CLI che guida la bonifica della cronologia di un repository Git
(secret, token, password, file sensibili) in modo sicuro: backup mirror, scansione con
**gitleaks** e **trufflehog**, dry-run, riscrittura con **git-filter-repo**, force push approvato e verifica finale.
Pensata per WSL2/Linux/macOS.

> Nessuna riscrittura della history né force push avvengono senza approvazione esplicita dell'utente.
> Le credenziali trovate vanno sempre considerate compromesse e rigenerate.

## Installazione

Prerequisiti: [GitHub Copilot CLI](https://docs.github.com/en/copilot/concepts/agents/about-copilot-cli) e `git`.

```bash
git clone https://github.com/dobuonagiu/git-history-cleanup-assistant-skill.git
cd git-history-cleanup-assistant-skill
./install.sh
```

Questo crea un symlink in `~/.copilot/skills/git-history-cleanup-assistant` (aggiorni la skill con `git pull`).

Opzioni:
- `./install.sh --copy` copia i file invece del symlink (puoi poi eliminare il clone)
- `./install.sh --project` installa nel repo corrente in `.github/skills/`
- `./install.sh --uninstall` rimuove la skill

Installazione manuale equivalente:
```bash
git clone https://github.com/dobuonagiu/git-history-cleanup-assistant-skill.git ~/.copilot/skills/git-history-cleanup-assistant
```

Riavvia Copilot CLI (verifica con `/skills`).

## Uso

In Copilot CLI, dentro o fuori dal repo da bonificare:

> Usa la skill git-history-cleanup-assistant per rimuovere i secret dalla history di `<URL repo>`; il backup va su `<URL repo backup vuoto e privato>`.

La skill ti chiederà URL sorgente/backup, branch principale e provider, poi seguirà le fasi 0–16.

### Tool richiesti
La skill verifica la presenza di questi tool e, se mancano, **propone** l'installazione chiedendo conferma:

| Tool | Installazione |
|------|---------------|
| git | `sudo apt install git` |
| git-filter-repo | `sudo apt install git-filter-repo` oppure `pip install git-filter-repo` |
| gitleaks (>= 8.19) | `brew install gitleaks` oppure release ufficiale |
| trufflehog | `brew install trufflehog` oppure [installer ufficiale](https://github.com/trufflesecurity/trufflehog) |
| jq, python3, curl | `sudo apt install jq python3 curl` |
| gh (opzionale) | [GitHub CLI](https://cli.github.com): controllo visibilità/fork prima del push |

## Funzionalità di sicurezza
- Backup mirror verificato + **preimage** dei ref remoti; il push usa `--force-with-lease` per ref (mai `--force` nudo).
- Controllo **visibilità e fork** (`gh`); repo pubblico/con fork richiede consenso esplicito.
- Riscrittura anche dei **messaggi di commit**; verifica su file e messaggi.
- Doppio scanner (gitleaks + trufflehog) + **pattern custom** (`references/patterns.example`) + allowlist gitleaks.
- **Revisione semantica AI** (`references/ai_semantic_review_prompt.md`) prima e dopo la riscrittura.
- **Verifica anonima** post-push e report per **superfici di esposizione** (verificato / residuo / non verificato).

## Test
```bash
tests/run-tests.sh   # richiede git, git-filter-repo, jq, python3, curl; nessuna rete
```
Eseguiti anche da GitHub Actions (`.github/workflows/test.yml`).

## Contenuto
- `SKILL.md` — istruzioni e workflow (fasi 0–16, gate di approvazione)
- `scripts/` — script helper (non distruttivi di default; rewrite e push richiedono la frase di approvazione)
- `references/` — comandi, ricette `filter-repo`, protezioni per provider, prompt di revisione semantica, esempi di pattern/allowlist, template di report
- `tests/` — test end-to-end con scanner finti
- `install.sh` — installer

## Sicurezza
I report generati finiscono in `./cleanup-reports/` (mascherati, ma da non committare). Il repo di backup contiene
i secret originali: tienilo privato ed eliminalo a fine attività.
