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

### Dove lanciarla
**In una cartella nuova e vuota (es. `~/cleanup-work/`), non dentro il repository da bonificare.**

```bash
mkdir -p ~/cleanup-work && cd ~/cleanup-work
copilot
```

Perché:
- gli script non toccano il tuo checkout: clonano il sorgente come mirror (`git clone --mirror`) e riscrivono quella copia; `filter-repo` richiede comunque un clone fresco;
- creano `./cleanup-reports/` nella cartella corrente, con report e mirror di backup che contengono i secret originali: dentro il progetto rischieresti di committarli;
- il repo originale resta intatto, con eventuali modifiche non committate.

Ti servono:
- l'**URL** del repo sorgente (non un path locale: il lease al push è legato all'URL);
- un **repo di backup vuoto e privato**, da creare prima sul provider;
- i permessi di force push sul sorgente (e, se presenti, le branch protection da disattivare temporaneamente).

Dopo la bonifica:
- non fare `git pull` nel vecchio clone: rifai un clone fresco;
- salva prima eventuali commit locali non pushati (es. `git format-patch`), perché non sono nel mirror;
- a fine lavoro elimina `~/cleanup-work/` e il repo di backup (contengono i secret originali).

### Richiesta a Copilot

> Usa la skill git-history-cleanup-assistant per rimuovere i secret dalla history di `<URL repo>`; il backup va su `<URL repo backup vuoto e privato>`.

### Cosa succede al repo originale
La skill **non crea un nuovo repository**: la history bonificata viene pubblicata sul **repo originale**, allo stesso URL,
sugli stessi branch e tag, solo dopo la tua approvazione esplicita (`Confermo il force push`, Fase 14).

| Elemento | Ruolo |
|----------|-------|
| Repo originale (sorgente) | Destinazione finale: branch e tag vengono sovrascritti con la history riscritta |
| Repo di backup | Solo copia di sicurezza della history originale (contiene ancora i secret): non è mai la destinazione finale, eliminalo a fine lavoro |
| Cartella di lavoro (`cleanup-work`) | Mirror temporanei per riscrivere e verificare |

Cosa aspettarsi sul sorgente:
- **SHA cambiati**: chi ha un clone vecchio deve rifare il clone.
- **Lease**: se il sorgente è cambiato dopo il backup (qualcuno ha pushato), il push viene rifiutato; si riparte da snapshot e dry-run. L'URL di push deve coincidere con quello dello snapshot.
- **Branch/tag eliminati dalla riscrittura** restano sul remoto: la skill li elenca e li cancella solo con tua approvazione.
- **Repo pubblico o con fork**: il gate G5 richiede una frase più forte (`Confermo il force push su repository pubblico o non verificato`); fork, cache e PR esistenti possono conservare i vecchi commit.
- **Solo i ref cambiati** vengono pubblicati (gli invariati non si toccano).
- **`refs/pull/*` (GitHub)** non sono sovrascrivibili: le PR aperte vanno ricreate o riallineate.
- **Branch protection**: da disattivare prima (Fase 4) e riattivare dopo (Fase 16), altrimenti il push fallisce.

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

## Gate di sicurezza (approvi tu)
Ogni passo critico produce un file `cleanup-reports/gates/<ID>.md` con stato **DA_LEGGERE** → **APPROVATO**.
Gli script distruttivi non partono finché il gate non è APPROVATO, né se gli artefatti da leggere sono cambiati
dopo l'approvazione.

| Gate | Cosa sblocca | Frase da digitare |
|------|--------------|-------------------|
| G1-backup | push sul repo di backup | `Confermo il backup` |
| G2-protezioni | dry-run, rewrite, push (se ci sono branch protection/ruleset) | `Confermo che le protezioni sono state rimosse o aggirate` |
| G3-classificazione | dry-run | `Confermo la classificazione` |
| G4-riscrittura | riscrittura della history | `Confermo la riscrittura della history` |
| G5-push | force push sul repo originale | `Confermo il force push` |

Quando Copilot ti dice che un gate è pronto: **leggi il file `.md` indicato** e gli artefatti elencati, poi
approva lanciando tu il comando che Copilot ti suggerisce, **nel prompt di Copilot CLI con il `!` davanti**:
```
!~/.copilot/skills/git-history-cleanup-assistant/scripts/gate.sh approve G4-riscrittura --phrase "Confermo la riscrittura della history"
```
Lo stesso comando senza `--phrase`, da un terminale interattivo, ti chiede di digitare la frase. L'approvazione
viene registrata nel file (data, utente, modalità). `gate.sh status` mostra lo stato di tutti i gate;
`gate.sh reject <ID>` li blocca.

> I gate sono un controllo procedurale: l'agente ha l'istruzione di non approvare mai e di limitarsi a suggerirti
> il comando; un'approvazione non interattiva non è tecnicamente distinguibile da una fatta dall'agente.
> Controlla i comandi che Copilot ti chiede di approvare e non usare `/allow-all` durante una bonifica.

## Cosa può eliminare
- **Valori sensibili** dentro i file e nei messaggi di commit (sostituzione).
- **File interi** da tutta la history: per path, directory, `glob:` o `regex:` (es. `*.pem`, `.env`).
- **File grandi**: `--max-blob-size 5M` elimina ogni file oltre la soglia.
- `scan-files.sh` scopre file grandi e con estensioni/nomi sensibili e propone regole (mai attive senza la tua scelta).
- **Cartelle**: git non traccia cartelle vuote, quindi se si eliminano tutti i file di una cartella spariscono anche
  la cartella e i genitori rimasti vuoti. Cartelle con soli segnaposto (`.gitkeep`…) restano: il dry-run le segnala.
- File da **non toccare**: la keep-list; una regola che li elimina o li modifica è segnalata come conflitto.

## Funzionalità di sicurezza
- Scanner robusti: trufflehog su mirror bare, valori mascherati con `file:riga` (non `REDACTED` generico).
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
