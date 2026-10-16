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
- **Scoperta**: `scripts/scan-files.sh <repo> <label> --min-size <soglia> --ext <estensioni>` elenca i file
  storici che raggiungono o superano la soglia e/o corrispondono ai formati indicati (con dimensione, versioni e presenza
  nei tip). Produce solo *suggerimenti* (`<label>-paths-suggested.txt`, righe `#> ...` non attive).
  Chiedi all'utente la soglia e le estensioni da cercare; `--ext default` usa i formati/nomi sensibili comuni,
  La soglia predefinita è `50M` (50 MiB); chiedi se l'utente preferisce un valore diverso.
  `--ext none` disattiva la ricerca per estensione e `--min-size 0` quella per dimensione.
  Mostra l'elenco completo dei candidati e chiedi esplicitamente quali file **non** eliminare. Poi mostra
  l'elenco finale dei file selezionati per la rimozione e chiedi conferma prima di aggiungerli a
  `paths-to-remove.txt`; quelli da conservare vanno in `keep-list.txt`. Nessun candidato diventa una regola
  attiva automaticamente.
Un file eliminato sparisce da **tutta** la history, non solo dal tip. Mostra sempre all'utente l'elenco dei
file che verranno eliminati prima di chiedere conferma.
**Cartelle**: git non traccia cartelle vuote. Quando tutti i file di una cartella vengono eliminati, la cartella e
i genitori rimasti senza file spariscono da ogni commit (nessuna azione richiesta). Una cartella che contiene solo
file segnaposto (`.gitkeep`, `.keep`, ...) **non è vuota per git** e resta: il dry-run la segnala nel report
("Cartelle rimaste con soli file segnaposto"); se l'utente vuole eliminarla aggiungi la cartella
(es. `placeholder/`) a `paths-to-remove.txt` e rifai G3 e dry-run.

## Perimetro: scegli la modalità PRIMA di iniziare (obbligatorio)
Chiedi (o deduci dalla richiesta) il **perimetro** e dichiaralo; le regole e le fasi si applicano solo a ciò
che rientra nel perimetro. Non estendere mai il perimetro di tua iniziativa.

| Modalità | Quando | Fasi |
|----------|--------|------|
| **SOLO FILE** | l'utente vuole solo eliminare file/estensioni/file grandi (anche se i secret li ha già gestiti) | 0-4 (verifiche minime), **5c**, 7 (solo `paths-to-remove.txt` + `keep-list.txt`), 8-16 |
| **COMPLETA** | bonifica di secret/dati sensibili (con o senza file) | tutte |

**Modalità SOLO FILE** – regole:
- **Saltati**: Fase 5 (scansioni secret/pattern/config), 5b (revisione semantica), 6 (classificazione A/B/C/D dei
  secret), `replacements.txt`. Le regole 12, 13, 14 **non si applicano**: non bloccarti su blob mantenuti,
  candidate di configurazione o revisione semantica. Non sono "non verificati": sono fuori perimetro; dillo nel
  report finale ("secret: fuori perimetro").
- Se esistono già `replacements.txt` approvati dall'utente in una sessione precedente, riusali tali e quali
  (non rigenerarli né rivederli); altrimenti nessuna sostituzione.
- **G3 ridotto**: artefatti solo `paths-to-remove.txt`, `keep-list.txt`, `cleanup-reports/pre-files.tsv`,
  `cleanup-reports/pre-paths-suggested.txt` (+ `replacements.txt` se riusato). Non includere
  `pre-config-candidates.tsv`, `pre-semantic-review.md`, `pre-findings.tsv`.
- Riuso di mirror/backup/gate di sessioni precedenti: se il mirror non coincide più col sorgente, **non
  inseguire** report e gate vecchi: rifai solo backup (G1) e scoperta file (5c) sul mirror aggiornato, poi un
  unico G3 ridotto. Un gate è invalido solo se cambia un *suo* artefatto: non modificare artefatti dopo averli
  inseriti in un gate; se serve, ricrea il gate **una volta** e dillo.
- Verifica finale (13/15): file rimossi assenti, keep preservati, ref/tree attesi. Eventuali finding di secret
  preesistenti **non bloccano** il push (sono fuori perimetro): segnalali soltanto.
- **Anti-stallo** (vale anche in modalità COMPLETA): dopo ogni gate approvato procedi subito alla fase successiva; al massimo un blocco per
  gate. Quando serve un'approvazione, dai **un solo comando** `!...gate.sh approve ...` completo
  (con `CLEANUP_REPORTS=<cartella-di-lavoro>/cleanup-reports` se non sei nella cartella di lavoro) e fermati.
  Se l'utente scrive il comando senza `!` o fuori cartella, correggi in una frase, senza rigenerare il gate.

## Regole obbligatorie (non derogabili)
(Le regole 4, 5, 12, 13, 14 valgono in modalità COMPLETA; vedi sopra per SOLO FILE.)

1. **Mai** riscrivere la history né fare force push senza il relativo **gate APPROVATO dall'utente** (vedi Gate).
2. **Mai** modificare i file in `cleanup-reports/gates/` né eseguire `gate.sh approve`: l'approvazione la dà
   solo l'utente. Tu **suggerisci il comando** (da lanciare con `!` nel prompt di Copilot CLI) e attendi.
   Se un gate non è APPROVATO **fermati**.
3. **Prima** di qualsiasi modifica crea sempre un backup completo (mirror) e verificalo.
4. Dopo ogni bonifica **riesegui** la scansione dei secret.
5. Se trovi credenziali, ricorda sempre che vanno considerate **compromesse** e **rigenerate**: la
   riscrittura non le rende di nuovo sicure (cache, fork, cloni, CI log). Se l'utente sceglie di ruotarle a fine
   processo, procedi comunque e **ricordaglielo alla fine** (Fase 16 e risposta finale); non bloccare i gate.
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
12. Prima della classificazione, inventaria e rivedi **tutti i blob distinti raggiungibili nella history**, non
    solo i tip dei branch. Non dichiarare completa la scansione se esistono file grandi/binari non ispezionati o
    candidate di configurazione non classificati.
13. Considera credenziale ogni valore statico in un campo `password`, `username`, `secret`, `token` o URI con
    user-info, anche se ha bassa entropia, è in YAML/Properties/JSON, è codificato come escape o non è rilevato
    da Gitleaks/TruffleHog. Cerca esplicitamente Redis, Kafka/JAAS, MongoDB, SQL, AMQP, SMTP, LDAP, OAuth/JWT,
    cloud credentials, container registry, TLS e SSH.
14. Non arrivare a G3 con la revisione semantica descritta solo come "automatica" o con categorie non
    verificate: tutti i candidate del report e tutte le versioni di configurazione storiche devono essere
    esaminati e classificati; aggiungi i report di copertura e candidate agli artefatti del gate.
15. La scansione Git non include il contenuto esterno dei submodule o degli oggetti Git LFS, né garantisce
    accesso a PR refs, cache, log CI, artifact, wiki, release, package, issue, fork e cloni. Identifica queste
    superfici e dichiarale verificate, residue o NON VERIFICATE; non dichiarare pulito il repository nel suo
    complesso se restano fuori scope.

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
chiedigli di **leggerlo** (e degli artefatti elencati); (3) **suggerisci il comando di approvazione**, che l'utente
lancia lui stesso nel prompt di Copilot CLI con il `!` davanti, mostrandolo in un blocco di codice pronto da incollare:
```
!<dir-skill>/scripts/gate.sh approve <ID> --phrase "<frase esatta del gate>"
```
(lo stesso comando, senza `--phrase`, funziona da un terminale interattivo e chiede di digitare la frase;
lo script stampa già il comando giusto alla creazione del gate e quando un gate blocca); (4) attendi che l'utente
confermi di aver approvato, poi verifica con `gate.sh status` e prosegui. Non eseguire mai tu il comando `approve`.
Se l'utente non vuole procedere: `gate.sh reject <ID>`. Se artefatti o regole cambiano dopo l'approvazione, il
gate va ricreato e riapprovato.

Gate G3 SOLO FILE (dopo 5c):
```bash
gate.sh create G3-classificazione --title "Rimozione file" --phrase "Confermo la classificazione" \
  --artifact paths-to-remove.txt --artifact keep-list.txt \
  --artifact cleanup-reports/pre-files.tsv --artifact cleanup-reports/pre-paths-suggested.txt \
  --summary "<criteri, n. file da eliminare, file preservati>"
```

Gate G3 (classificazione) COMPLETA, da creare dopo le Fasi 6-7:
```bash
gate.sh create G3-classificazione --title "Classificazione e regole" --phrase "Confermo la classificazione" \
  --artifact paths-to-remove.txt --artifact replacements.txt --artifact keep-list.txt \
  --artifact cleanup-reports/pre-findings.tsv \
  --artifact cleanup-reports/pre-files.tsv --artifact cleanup-reports/pre-paths-suggested.txt \
  --artifact cleanup-reports/pre-config-candidates.tsv --artifact cleanup-reports/pre-semantic-scope.md \
  --artifact cleanup-reports/pre-semantic-review.md --artifact cleanup-reports/pre-rules-preflight.md \
  --summary "<riepilogo: criteri dimensione/formato, candidati esclusi, cosa verrà eliminato/sostituito/preservato>"
```

## Dove si lavora
Lancia gli script dalla **cartella di lavoro** (vuota, es. `~/cleanup-work`), non dal repo da bonificare e non
da dentro `cleanup-reports/` (se serve, gli script lo riconoscono). Gli script scrivono in `./cleanup-reports/`.
Script: `<dir-skill>/scripts`. Dettagli: `references/fasi.md`; ricette filter-repo: `references/filter-repo-recipes.md`;
protezioni: `references/branch-protection.md`; report finale: `references/report-template.md`.
Stato in `./cleanup-reports/state.env`. La sessione può essere ripresa: `backup-mirror.sh` riusa il mirror
esistente (se coincide ancora col sorgente) e i gate già approvati e invariati restano validi. Non cancellare
mirror o gate a mano per "ripartire": se il sorgente è cambiato lo script lo dice.

### Ripresa dopo un'interruzione
Prima di ripetere una fase, ricostruisci lo stato dalla cartella di lavoro esistente: leggi le chiavi pertinenti
di `cleanup-reports/state.env`, esegui `gate.sh status` e verifica mirror, report e relativi timestamp. Non
dedurre che una fase sia conclusa dal solo messaggio precedente dell'assistente, né che sia incompleta perché
manca una risposta finale. Riusa report validi e approvazioni i cui artefatti non sono cambiati; ripeti solo
passaggi mancanti o invalidati da uno snapshot del sorgente cambiato. Non cancellare mirror, report o gate e non
ricreare un gate approvato senza una ragione verificabile.

Le scansioni completate non equivalgono alla revisione/classificazione: in modalità COMPLETA, inventario
semantico e finding devono essere esaminati e classificati prima di G3. Dopo un gate approvato prosegui dalla
prima fase realmente incompleta, mantenendo gli stessi perimetro, criteri e decisioni già confermati.

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

### FASE 5 – Secret Discovery  (solo modalità COMPLETA; 5b e 5c idem tranne 5c, che vale anche per SOLO FILE)
`scan-secrets.sh <mirror> pre` (gitleaks + trufflehog, anche su mirror bare; valori mascherati) e
`summarize-findings.sh <mirror> pre` (tipo, file:riga, commit, autore, gravità, valore mascherato, branch).
`scan-patterns.sh <mirror> pre [--patterns-file F]`: contesto privato che gitleaks non vede (IP privati, PEM,
regole utente: `references/patterns.example`). Falsi positivi verificati: `GITLEAKS_CONFIG=<toml>`
(`references/gitleaks.example.toml`).
Esegui anche `scan-config-candidates.sh <mirror> pre`: cerca in tutte le modifiche storiche campi credenziale
generici, escaped JSON, URI con user-info e configurazioni Redis/Kafka. Il report mostra solo categoria,
commit e path, mai il valore. Ogni risultato è un candidato da ispezionare, non prova da solo che il valore
sia attivo; include anche le differenze dei merge commit e classifica tutti i risultati prima di G3.

### FASE 5b – Revisione semantica (Layer 4)
`semantic-review-inventory.sh <mirror> pre` congela ref e file; applica
`references/ai_semantic_review_prompt.md` **anche al materiale senza hit** (nomi reali, codename, host interni,
PII in fixture, codici fiscali, trascrizioni). Ciò che non ispezioni è *non verificato*.
L'inventario contiene ogni blob testuale distinto raggiungibile (incluse versioni storiche e ref non default)
e l'elenco dei commit da rivedere: non scegliere una sola versione per path. File esclusi per dimensione o
binarietà restano NON VERIFICATI e vanno esaminati con metodo/tool adeguato o rimossi se sensibili. Gli
oggetti LFS e il contenuto dei submodule richiedono scansione separata; le altre superfici remote sono
rendicontate come verificate, residue o non verificate.

### FASE 5c – Scoperta e selezione file grandi/per formato
Prima della scansione chiedi all'utente:
- la dimensione minima da considerare, proponendo `50M` come default (l'utente può scegliere un'altra soglia;
  `0` disattiva il criterio dimensionale);
- le estensioni/formati da cercare (es. `zip,mp4,psd`; `default` usa i formati e nomi sensibili comuni;
  `none` disattiva il criterio per estensione).

Esegui `scan-files.sh <mirror> pre --min-size <soglia> --ext <elenco|default|none>` e mostra
`cleanup-reports/pre-files.tsv` integralmente, senza limitarti ai file nei tip: i risultati coprono tutti i
blob/path nella history. Il report e `pre-paths-suggested.txt` sono solo candidati e non modificano la history.
Chiedi esplicitamente quali candidati devono essere preservati/non eliminati; per gli altri chiedi conferma
che vadano rimossi dalla history. Presenta infine la lista esatta da eliminare e attendi la conferma. Solo
dopo inserisci i path confermati in `paths-to-remove.txt` e quelli da preservare in `keep-list.txt`.
Un candidato non confermato per la rimozione resta fuori dalle regole; non usare mai `--max-blob-size` per
eliminare in blocco quando l'utente ha selezionato singoli candidati o esclusioni.

### FASE 6 – Classification
Mostra secret, file (inclusi i candidati della Fase 5c) e branch. Per **ogni** elemento chiedi l'azione:
A. Eliminare completamente il file · B. Sostituire il valore sensibile · C. Escludere dalla bonifica · D. Mantenere invariato.
Per i candidati della Fase 5c, chiarisci quali non eliminare e richiedi conferma separata per la lista finale
di rimozione. Ricorda: i secret vanno comunque rigenerati (anche per C/D).

### FASE 7 – Esclusioni e regole  (crea GATE G3)
Chiedi quali file preservare. Crea: `paths-to-remove.txt` (A), `replacements.txt` (B: `literal==>repl` o
`regex:...==>repl`), `keep-list.txt` (C/D e candidati da non eliminare). "Preservare" significa **non eliminare e non modificare**: una regola
che elimina o modifica un file in keep-list è un conflitto (exit 3); l'utente decide se togliere la regola, restringerla
o accettare la modifica (`--allow-keep-modified`). Un `paths-to-remove.txt` senza regole attive è tollerato.
Crea il gate G3 includendo anche `pre-files.tsv` e `pre-paths-suggested.txt` come artefatti di classificazione
(vedi sopra) e attendi l'approvazione.

**Preflight delle regole (obbligatorio prima di G3, evita cicli G3→dry-run→G3)**: nelle sessioni reali G3 è stato
ricreato più volte per regole scoperte difettose o decisioni mancanti *dopo* l'approvazione. Prima di creare G3:
1. **Decisioni in un'unica domanda** (`ask_user`): per ogni categoria ambigua (endpoint/host interni, identificatori
   JWT/tenant/client-id, URL di workflow/CI, nomi reali, file di esempio/test) chiedi in blocco azione (A/B/C/D) e
   sostituto, indicando l'impatto operativo (build, CI, riconfigurazione). Non emergere una categoria alla volta.
2. **Verifica a secco delle sostituzioni** sull'intero inventario dei blob distinti (Fase 5b): ogni regola deve
   (a) corrispondere ad almeno un blob, (b) essere idempotente (il sostituto non è riabbinato da nessuna regola),
   (c) non produrre sintassi rotta (virgolette/apici duplicati, JSON/YAML/XML/properties non più validi: riparsa i
   file strutturati modificati), (d) non toccare file in keep-list se non voluto. Allega al gate il report
   (es. `cleanup-reports/pre-rules-preflight.md`: regola → n. blob/file, esempio prima/dopo mascherato).
3. **Raggruppa le correzioni**: se dopo dry-run o rewrite locale serve cambiare le regole, raccogli *tutte* le
   correzioni in un solo ciclo e ricrea G3 **una volta**, dichiarando cosa è cambiato e perché; poi dry-run e G4.
4. **Credenziali**: la rotazione può essere fatta dall'utente a fine processo; non bloccare gate, riscrittura
   o push per questo. Tieni traccia delle credenziali compromesse trovate e ricordale alla fine (Fase 16).

### FASE 8 – Impact Analysis
Il dry-run produce `dryrun-report.md`: file eliminati, file il cui contenuto cambia, commit, branch e tag
riscritti, avviso se il **branch di default** viene riscritto.

### FASE 9 – Dry Run  (richiede G3, crea G4)
`dry-run.sh <mirror> <work> --paths paths-to-remove.txt --replace replacements.txt --keep keep-list.txt
[--max-blob-size 5M] [--no-message-rewrite] [--allow-keep-modified]`. Nessuna modifica reale.

### FASE 10 – Approvazione  (GATE G4)
Di' all'utente di leggere `gates/G4-riscrittura.md` e `dryrun-report.md` e suggerisci il comando `!...gate.sh approve G4-riscrittura --phrase ...`
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
- **Promemoria esplicito all'utente: rigenerare/ruotare tutte le credenziali esposte** (elenco per tipo/sistema,
  senza valori). Se la rotazione è stata rimandata a fine processo, è questo il momento: ripetilo anche nella
  risposta finale e nel report.
- Eliminare il repo di backup e la cartella di lavoro (contengono i secret originali).
- Avvisare il team: nuovo clone obbligatorio. Chiudere/ricreare le PR impattate.

## Output finale atteso
`references/report-template.md`: repository analizzato, backup, n. branch/tag coinvolti, n. secret trovati/rimossi,
file rimossi, file preservati, stato verifica finale, stato dei gate, superfici di esposizione, azioni manuali.
