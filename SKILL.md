---
name: git-history-cleanup-assistant
description: >
  Guida la bonifica sicura della cronologia di un repository Git: rimozione di secret, password, token,
  API key, credenziali, dati sensibili e FILE (anche grandi o per estensione) con backup mirror, scansione
  (gitleaks + trufflehog + pattern custom), dry-run, riscrittura con git-filter-repo, force push con lease
  dopo approvazione dell'utente tramite gate su file Markdown, e verifica finale. Use this skill when asked to
  clean a Git history, remove secrets or files from all commits, purge leaked credentials or large files,
  run git filter-repo, or perform a post-leak repository remediation (anche in WSL2).
---

# Git History Cleanup Assistant

Agisci come **Git Repository Cleanup Engineer**. Obiettivo: ripulire in sicurezza la history di un
repository (secret, file/pattern indicati dall'utente), con backup completo, verifica e minimo rischio di
perdita dati. Ambiente tipico: WSL2 Linux. Comunica in italiano.

La bonifica si conclude con il force push sul **repository originale** (stesso URL, stessi branch e tag), solo
dopo l'approvazione dell'utente (gate G5). Il repo di backup è solo una copia di sicurezza.

## Cosa può essere eliminato dalla history (esplicito)
- **Valori sensibili dentro i file** → sostituzione (`replacements.txt`, azione B). Vale anche per i messaggi di commit.
- **File interi** (azione A) → `paths-to-remove.txt`, una regola per riga:
  path esatto o directory (`cfg/.env`, `secrets/`), `glob:*.pem`, `regex:^deploy/keys/.*`.
- **File per estensione o nome** (es. `*.pem`, `*.p12`, `.env`, `*.sqlite`): regole `glob:`/`regex:` come sopra.
- **File grandi**: per soglia con `--max-blob-size 5M` (dry-run e rewrite) oppure per path specifico.
- **Scoperta**: `scripts/scan-files.sh <repo> <label> --min-size 5M --ext default` elenca file grandi e con
  estensioni/nomi tipicamente sensibili (con dimensione, versioni, presenza nei tip). Produce solo
  *suggerimenti* (`<label>-paths-suggested.txt`, righe `#> ...` non attive): decide l'utente (Fase 6).
Un file eliminato sparisce da **tutta** la history, non solo dal tip. Mostra sempre all'utente l'elenco dei
file che verranno eliminati prima di chiedere conferma.

## Regole obbligatorie (non derogabili)

1. **Mai** riscrivere la history né fare force push senza il relativo **gate APPROVATO dall'utente** (vedi Gate).
2. **Mai** modificare i file in `cleanup-reports/gates/` né eseguire `gate.sh approve`: l'approvazione la dà
   solo l'utente, da un proprio terminale interattivo. Se un gate non è APPROVATO **fermati e attendi**.
3. **Prima** di qualsiasi modifica crea sempre un backup completo (mirror) e verificalo.
4. Dopo ogni bonifica **riesegui** la scansione dei secret.
5. Se trovi credenziali, ricorda sempre che vanno considerate **compromesse** e **rigenerate** (e ruotate per
   prime): la riscrittura non le rende di nuovo sicure (cache, fork, cloni, CI log).
6. Mai stampare valori dei secret in chiaro (gli script li mascherano). I report stanno in `./cleanup-reports/`
   e non vanno mai committati.
7. Lavora sempre su un mirror di lavoro, **mai sul backup**. Il backup resta intatto.
8. Se un gate o un prerequisito/permesso manca: **interrompi** e riferisci.
9. Mai dedurre visibilità/fork dal nome o dall'URL (`check-visibility.sh`). Non dichiarare "pulito" ciò che non
   hai verificato: distingui **verificato / residuo / non verificato** per ogni superficie.
10. Il push usa **lease per ref**, mai `--force` nudo né `--no-verify`. Lease rifiutato = il remoto è cambiato:
    **fermati**, rifai snapshot, analisi e approvazioni.
11. Non fidarti di un "falso positivo" senza averlo verificato: gli script mostrano il valore **mascherato**
    (prime 2 lettere + lunghezza) e `file:riga`; non scartare finding in base a un `REDACTED` generico.

## Gate di sicurezza (file Markdown con stato)

Ogni passo critico produce un file `cleanup-reports/gates/<ID>.md` con stato **DA_LEGGERE** → **APPROVATO**
(oppure RIFIUTATO) e l'hash degli artefatti da leggere. Gli script distruttivi controllano il gate con
`gate.sh require` e rifiutano di partire se non è APPROVATO **o se un artefatto è cambiato dopo l'approvazione**.

| Gate | Creato da | Frase da digitare | Sblocca |
|------|-----------|-------------------|---------|
| `G1-backup` | `backup-mirror.sh` | `Confermo il backup` | push sul repo di backup (`--confirm`) |
| `G2-protezioni` | `check-protections.sh` (se protezioni presenti/non verificabili) | `Confermo che le protezioni sono state rimosse o aggirate` | dry-run, rewrite, push |
| `G3-classificazione` | tu, con `gate.sh create` (Fasi 6-7) | `Confermo la classificazione` | dry-run |
| `G4-riscrittura` | `dry-run.sh` | `Confermo la riscrittura della history` | `rewrite.sh` |
| `G5-push` | `push-cleaned.sh --prepare` | `Confermo il force push` (se repo pubblico/con fork/non verificato: `Confermo il force push su repository pubblico o non verificato`) | `push-cleaned.sh` |

**Procedura per ogni gate**: (1) crea il gate con lo script; (2) di' all'utente il percorso del file `.md` e
chiedigli di **leggerlo** (e degli artefatti elencati); (3) l'utente approva **da un proprio terminale**:
`<dir-skill>/scripts/gate.sh approve <ID>` e digita la frase esatta (richiede TTY: l'agente non può farlo);
(4) attendi che l'utente confermi di aver approvato, poi verifica con `gate.sh status` e prosegui.
Se l'utente non vuole procedere: `gate.sh reject <ID>`. Se artefatti o regole cambiano dopo l'approvazione, il
gate va ricreato e riapprovato.

Gate G3 (classificazione), da creare dopo le Fasi 6-7:
```bash
gate.sh create G3-classificazione --title "Classificazione e regole" --phrase "Confermo la classificazione" \
  --artifact paths-to-remove.txt --artifact replacements.txt --artifact keep-list.txt --artifact pre-findings.tsv \
  --summary "<riepilogo: cosa verrà eliminato/sostituito/preservato>"
```

## Dove si lavora
Lancia gli script dalla **cartella di lavoro** (vuota, es. `~/cleanup-work`), non dal repo da bonificare e non
da dentro `cleanup-reports/` (se serve, gli script lo riconoscono). Gli script scrivono in `./cleanup-reports/`.
Script: `<dir-skill>/scripts`. Dettagli: `references/fasi.md`; ricette filter-repo: `references/filter-repo-recipes.md`;
protezioni: `references/branch-protection.md`; report finale: `references/report-template.md`.
Stato in `./cleanup-reports/state.env`. La sessione può essere ripresa: `backup-mirror.sh` riusa il mirror
esistente (se coincide ancora col sorgente) e i gate già approvati e invariati restano validi. Non cancellare
mirror o gate a mano per "ripartire": se il sorgente è cambiato lo script lo dice.

## Workflow

### FASE 0 – Repository Assessment
Chiedi (se non noti): URL repo sorgente (**URL, non path locale**), URL repo backup (vuoto e privato), branch
principale, provider. Esegui `assess-repo.sh [path]` se esiste un clone. Report: remote, branch, tag, default branch.

### FASE 1 – Prerequisiti
`check-prereqs.sh`. Tool: `git`, `gitleaks` (>= 8.19), `trufflehog` (binario Go ufficiale, **non** `pip install
trufflehog`), `git-filter-repo`, `jq`, `python3`, `curl`; `gh` opzionale. Se manca qualcosa **proponi** il comando
e **chiedi conferma** prima di installare.

### FASE 2 – Verifica accessi
Lettura sorgente, backup raggiungibile, permessi di push/force push (non fare force push di prova sul sorgente).
`check-visibility.sh <URL>`: exit 10 = pubblico/con fork → informa l'utente (fork e cloni conservano la vecchia
history). Verifica la **proprietà** di fork/account prima di scegliere la via di remediation.

### FASE 3 – Backup completo  (GATE G1)
`backup-mirror.sh <SOURCE> <BACKUP>`: mirror locale verificato, `backup-summary.md`, preimage dei ref remoti
(`remote-preimage.txt`, base del lease) e gate G1. Dopo l'approvazione dell'utente:
`backup-mirror.sh <SOURCE> <BACKUP> --confirm` pubblica heads+tags sul backup (i `refs/pull/*` non sono
pushabili) e verifica ref per ref. URL con credenziali incorporate sono rifiutati.

### FASE 4 – Analisi delle protezioni  (GATE G2 se presenti)
`check-protections.sh <URL>` (GitHub: branch protette e ruleset con regole e bypass). Exit 10/2 = protezioni
presenti o non verificabili → crea G2: **fermati** finché l'utente non le rimuove/aggira e approva G2.
Se la riscrittura tocca il branch di default (di solito sì: è antenato di tutti i branch) i ruleset sul default
branch impediranno il push.

### FASE 5 – Secret Discovery
`scan-secrets.sh <mirror> pre` (gitleaks + trufflehog, anche su mirror bare; valori mascherati) e
`summarize-findings.sh <mirror> pre` (tipo, file:riga, commit, autore, gravità, valore mascherato, branch).
`scan-patterns.sh <mirror> pre [--patterns-file F]`: contesto privato che gitleaks non vede (IP privati, PEM,
regole utente: `references/patterns.example`). Falsi positivi verificati: `GITLEAKS_CONFIG=<toml>`
(`references/gitleaks.example.toml`).

### FASE 5b – Revisione semantica (Layer 4)
`semantic-review-inventory.sh <mirror> pre` congela ref e file; applica
`references/ai_semantic_review_prompt.md` **anche al materiale senza hit** (nomi reali, codename, host interni,
PII in fixture, codici fiscali, trascrizioni). Ciò che non ispezioni è *non verificato*.

### FASE 5c – Scoperta file da eliminare
`scan-files.sh <mirror> pre --min-size 5M --ext default` (file grandi, estensioni/nomi sensibili). Presenta i
candidati all'utente: sono suggerimenti, non regole.

### FASE 6 – Classification
Mostra secret, file, branch. Per **ogni** elemento chiedi l'azione:
A. Eliminare completamente il file · B. Sostituire il valore sensibile · C. Escludere dalla bonifica · D. Mantenere invariato.
Ricorda: i secret vanno comunque rigenerati (anche per C/D).

### FASE 7 – Esclusioni e regole  (crea GATE G3)
Chiedi quali file preservare. Crea: `paths-to-remove.txt` (A), `replacements.txt` (B: `literal==>repl` o
`regex:...==>repl`), `keep-list.txt` (C/D). "Preservare" significa **non eliminare e non modificare**: una regola
che elimina o modifica un file in keep-list è un conflitto (exit 3); l'utente decide se togliere la regola, restringerla
o accettare la modifica (`--allow-keep-modified`). Un `paths-to-remove.txt` senza regole attive è tollerato.
Crea il gate G3 (vedi sopra) e attendi l'approvazione.

### FASE 8 – Impact Analysis
Il dry-run produce `dryrun-report.md`: file eliminati, file il cui contenuto cambia, commit, branch e tag
riscritti, avviso se il **branch di default** viene riscritto.

### FASE 9 – Dry Run  (richiede G3, crea G4)
`dry-run.sh <mirror> <work> --paths paths-to-remove.txt --replace replacements.txt --keep keep-list.txt
[--max-blob-size 5M] [--no-message-rewrite] [--allow-keep-modified]`. Nessuna modifica reale.

### FASE 10 – Approvazione  (GATE G4)
Di' all'utente di leggere `gates/G4-riscrittura.md` e `dryrun-report.md` e di approvare da terminale
(`Confermo la riscrittura della history`). Senza G4 APPROVATO **non procedere**.

### FASE 11 – Bonifica reale  (richiede G4)
`rewrite.sh <mirror> <work2> --paths ... --replace ... [--max-blob-size ...]` (stessi parametri del dry-run:
l'hash delle regole deve coincidere). Clona un mirror **fresco** di lavoro; il backup non viene mai modificato.
Riscrive anche i **messaggi di commit** (`--no-message-rewrite` per disattivare, identico al dry-run).

### FASE 12 – Pulizia
`reflog expire --expire=now --all` e `gc --prune=now --aggressive` (eseguiti da `rewrite.sh`).

### FASE 13 – Verifica post cleanup
`verify-final.sh <work2> post-cleanup --removed paths-to-remove.txt --replace replacements.txt --keep keep-list.txt
--baseline <mirror> [--patterns-file F]`: rescan, pattern custom, file rimossi assenti, valori sostituiti assenti
(file e messaggi), esclusioni preservate. Se restano finding: **non procedere al push**.

### FASE 13b – Revisione semantica sui ref riscritti
Ripeti la 5b sul risultato (pattern puliti non bastano).

### FASE 14 – Push sul repository ORIGINALE  (GATE G5)
`push-cleaned.sh <work2> <REMOTE_URL> --prepare` → `push-plan.md` (visibilità/fork, protezioni, ref da forzare /
nuovi / invariati, ref orfani) e gate G5. Dopo l'approvazione dell'utente: `push-cleaned.sh <work2> <REMOTE_URL>`.
Pubblica solo i ref cambiati, ciascuno con `--force-with-lease=<ref>:<sha-preimage>`; reimposta `origin`
(filter-repo lo rimuove). L'URL deve coincidere con quello dello snapshot. Branch eliminati dalla riscrittura NON
vengono rimossi dal remoto: elencali e cancellali solo con approvazione.

### FASE 15 – Verifica post push
Clone fresco del remoto → `verify-final.sh <clone> post-push ...`; poi `verify-anonymous.sh <REMOTE_URL>` (lettura
anonima e raggiungibilità dei vecchi commit). Riporta le superfici separatamente (file correnti/testo ospitato ·
oggetti e ref Git · cronologia modifiche delle PR · cache/PR refs/fork/cloni). Un 200 sui vecchi commit è
un'esposizione **residua** (richiesta al supporto del provider), non un errore di bonifica.

### FASE 16 – Checklist finale
- Riattivare le branch protection / ruleset.
- **Rigenerare tutte le credenziali esposte**.
- Eliminare il repo di backup e la cartella di lavoro (contengono i secret originali).
- Avvisare il team: nuovo clone obbligatorio. Chiudere/ricreare le PR impattate.

## Output finale atteso
`references/report-template.md`: repository analizzato, backup, n. branch/tag coinvolti, n. secret trovati/rimossi,
file rimossi, file preservati, stato verifica finale, stato dei gate, superfici di esposizione, azioni manuali.
