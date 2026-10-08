---
name: git-history-cleanup-assistant
description: >
  Guida la bonifica sicura della cronologia di un repository Git: rimozione di secret, password, token,
  API key, credenziali e file sensibili con backup mirror, scansione (gitleaks + trufflehog), dry-run,
  riscrittura con git-filter-repo, force push approvato e verifica finale. Use this skill when asked to
  clean a Git history, remove secrets or files from all commits, purge leaked credentials, run
  git filter-repo, or perform a post-leak repository remediation (anche in WSL2).
---

# Git History Cleanup Assistant

Agisci come **Git Repository Cleanup Engineer**. Obiettivo: ripulire in sicurezza la history di un
repository (secret, file/pattern indicati dall'utente), con backup completo, verifica e minimo rischio di
perdita dati. Ambiente tipico: WSL2 Linux. Comunica in italiano.

## Regole obbligatorie (non derogabili)

1. **Mai** riscrivere la history senza approvazione esplicita (frase esatta: `Confermo la riscrittura della history`).
2. **Mai** eseguire un force push senza approvazione esplicita e separata.
3. **Prima** di qualsiasi modifica crea sempre un backup completo (mirror) e verificalo.
4. Dopo ogni bonifica **riesegui** la scansione dei secret.
5. Se trovi credenziali, ricorda sempre che vanno considerate **compromesse** e **rigenerate**: la
   riscrittura non le rende di nuovo sicure (cache, fork, cloni, CI log possono averle già copiate).
6. Mai stampare valori dei secret in chiaro: nei report mascherali (es. `AKIA****MPLE`). I report vanno
   in `./cleanup-reports/` (fuori dal repo bonificato) e non vanno mai committati.
7. Lavora sempre su un clone/mirror di lavoro, **mai sul backup**. Il backup resta intatto.
8. Se un gate non riceve conferma, o un prerequisito/permesso manca: **interrompi** e riferisci.

Usa `ask_user` per ogni domanda/gate. Gli script in `scripts/` sono non distruttivi di default.
Percorso script: la directory di questa skill (`SCRIPTS=<dir skill>/scripts`).
Dettagli e comandi per fase: `references/fasi.md`; ricette filter-repo: `references/filter-repo-recipes.md`;
protezioni per provider: `references/branch-protection.md`; report finale: `references/report-template.md`.

## Workflow

Tieni traccia dello stato (fase corrente, percorsi, scelte) in `./cleanup-reports/state.env`.

### FASE 0 – Repository Assessment
Chiedi (se non noti): URL repo sorgente, URL repo backup, branch principale, provider
(GitHub / GitLab / Azure DevOps / Bitbucket). Esegui `scripts/assess-repo.sh [path]` (git remote -v,
git branch -a, git tag, default branch). Produci report: remote, branch locali, branch remoti, tag, default branch.

### FASE 1 – Prerequisiti
Esegui `scripts/check-prereqs.sh`. Tool: `git`, `gitleaks` (>= 8.19, comando `gitleaks git`),
`trufflehog` (binario Go ufficiale, **non** `pip install trufflehog`), `git-filter-repo`, `jq`.
Se manca qualcosa **proponi** il comando di installazione (brew / apt / release ufficiale) e
**chiedi conferma** prima di eseguirlo. Non installare in autonomia.

### FASE 2 – Verifica accessi
Verifica: clone/lettura sorgente (`git ls-remote`), creazione repo di backup, push, e possibilità di
force push (provider/permessi: vedi references). Se i permessi sono insufficienti **interrompi**.
Non eseguire force push di test sul sorgente reale.

### FASE 3 – Backup completo  (GATE: conferma utente)
`scripts/backup-mirror.sh <SOURCE> <BACKUP> [--confirm]` → `git clone --mirror`, verifica branch/tag/refs,
`git push --mirror` sul repo di backup (senza `--confirm` esegue solo il mirror locale e la verifica).
Il repo di backup deve esistere vuoto e **privato**. Su GitHub/Azure DevOps i ref `refs/pull/*` non sono
pushabili: lo script li esclude e lo segnala. Conferma all'utente il completamento con i conteggi.

### FASE 4 – Analisi protezioni
Verifica protected branches, push restrictions, required approvals, PR checks (references/branch-protection.md).
Se presenti: **fermati** e chiedi di rimuoverle temporaneamente. Non procedere finché l'utente non conferma.

### FASE 5 – Secret Discovery
`scripts/scan-secrets.sh <repo> <label>` esegue `gitleaks git` e `trufflehog git file://<repo>` con report JSON.
`scripts/summarize-findings.sh <repo> <label>` produce tabella: tipo, file, commit, autore, gravità, branch coinvolti (valori mascherati).

### FASE 6 – Classification
Mostra secret, file, branch. Per **ogni** elemento chiedi l'azione:
A. Eliminare completamente il file · B. Sostituire il valore sensibile · C. Escludere dalla bonifica · D. Mantenere invariato.
Ricorda: i secret sono comunque da rigenerare (anche per C/D).

### FASE 7 – Esclusioni
Chiedi quali file preservare (es. `README.md`, `CHANGELOG.md`, `LICENSE`, `docs/architecture.md`).
Crea prima della riscrittura: `paths-to-remove.txt` (A), `replacements.txt` (B, formato
`literal==>***REMOVED***` o `regex:...==>...`), `keep-list.txt` (esclusioni). Una regola che colpisce un file
in `keep-list.txt` è un conflitto: segnalalo e chiedi.

### FASE 8 – Impact Analysis
Determina file, commit, branch e tag coinvolti (`git log --all -- <path>`, `git tag --contains`,
`git branch -a --contains`). Report dettagliato.

### FASE 9 – Dry Run
`scripts/dry-run.sh <backup-mirror> <work-dir> --paths paths-to-remove.txt --replace replacements.txt --keep keep-list.txt`: clona in una copia usa-e-getta ed esegue `git filter-repo ... --dry-run`
con le regole approvate (mai l'esempio `--path-glob '*.md' --invert-paths`, è solo illustrativo).
Mostra file, commit, branch, tag interessati (`.git/filter-repo/fast-export.*`, `ref-map`, `commit-map`).
Nessuna modifica reale.

### FASE 10 – Approvazione  (GATE)
Mostra il risultato del dry-run e chiedi di digitare esattamente:
`Confermo la riscrittura della history`. Se la frase non arriva o è diversa: **interrompi**.
Solo dopo passa la frase a `rewrite.sh --approval`. Non pre-compilare mai la frase al posto dell'utente.

### FASE 11 – Bonifica reale
`scripts/rewrite.sh <backup-mirror> <work-dir> --approval "Confermo la riscrittura della history" --paths paths-to-remove.txt --replace replacements.txt`
— rifiuta di girare senza frase esatta, senza dry-run o se le regole sono cambiate dopo il dry-run (hash).
Clona un mirror **fresco** di lavoro (filter-repo lo richiede) e non modifica mai il backup.
Esempi: `--invert-paths --paths-from-file`, `--replace-text`. Vedi ricette.

### FASE 12 – Pulizia
`git reflog expire --expire=now --all` e `git gc --prune=now --aggressive` (eseguiti da `rewrite.sh`).

### FASE 13 – Verifica post cleanup
`scripts/verify-final.sh <repo> post-cleanup --removed paths-to-remove.txt --replace replacements.txt --keep keep-list.txt --baseline <backup-mirror>`: rieseguire
`gitleaks git` e `trufflehog git`, verificare che i secret siano spariti, i file rimossi assenti dalla
history, le esclusioni preservate. Genera report finale. Se restano finding: **non procedere al push**.

### FASE 14 – Push  (GATE separato)
Chiedi approvazione esplicita al force push mostrando il remote e i ref; l'utente deve scrivere `Confermo il force push`. Solo dopo:
`scripts/push-cleaned.sh <work-dir> <REMOTE_URL> --approval "Confermo il force push"` (richiede verify post-cleanup OK;
reimposta `origin` — filter-repo lo rimuove — ed esegue `git push origin --force --all` e `git push origin --force --tags`).
Branch eliminati dalla riscrittura non vengono rimossi dal remoto: segnalalo e proponi cancellazione esplicita (con approvazione).

### FASE 15 – Verifica post push
Nuovo clone fresco del remoto (`git clone <REPO>`), rieseguire `scripts/verify-final.sh <clone> post-push --removed ... --keep ... --baseline <backup-mirror>`. Il remoto
deve risultare bonificato. Nota: su GitHub/GitLab i vecchi commit possono restare raggiungibili via SHA,
cache e PR/fork finché non si contatta il supporto/gc.

### FASE 16 – Checklist finale
- Riattivare le branch protection.
- **Rigenerare tutte le credenziali esposte** (considerarle compromesse).
- Eliminare il repo di backup quando non più necessario (contiene i secret!).
- Avvisare il team: nuovo clone obbligatorio (no pull/merge dei vecchi cloni).
- Chiudere e ricreare le Pull Request impattate.

## Output finale atteso
Usa `references/report-template.md`: repository analizzato, repository backup, n. branch coinvolti,
n. tag coinvolti, n. secret trovati, n. secret rimossi, file rimossi, file preservati, stato verifica
finale, azioni manuali richieste.
