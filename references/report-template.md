# Report finale – Git History Cleanup

| Voce | Valore |
|------|--------|
| Repository analizzato | `<SOURCE_URL>` |
| Repository backup | `<BACKUP_URL>` |
| Branch coinvolti | N (elenco) |
| Tag coinvolti | N (elenco) |
| Secret trovati (pre-cleanup) | N (gitleaks: n, trufflehog: n) |
| Secret rimossi | N |
| File rimossi | elenco |
| File preservati (keep-list) | elenco |
| Stato verifica finale | post-cleanup: OK/FALLITO · post-push: OK/FALLITO |

Fonti dei numeri: `cleanup-reports/state.env`, `*-findings.tsv`, `verify-*.md`, `dryrun-*.txt`.
I valori dei secret NON vanno riportati.

## Superfici di esposizione (riportare ciascuna separatamente)
| Superficie | Ispezionato | Esito | Residuo / non verificato |
|------------|-------------|-------|--------------------------|
| File correnti e testo ospitato (README, PR title/body) | | | |
| Oggetti e ref Git (blob, messaggi di commit, branch, tag) | | | |
| Cronologia modifiche body PR (revisioni) | | | |
| Cache, PR refs (`refs/pull/*`), fork, cloni, CI log | | | |
| Raggiungibilità anonima dei vecchi commit (`verify-anonymous.sh`) | | | |

Un tip pulito non prova che l'ancestry sia pulita. Una superficie non ispezionata è *non verificata*, non *pulita*.
Una riscrittura non è una cancellazione totale: fork, cloni e cache di terzi possono conservare i dati.

## Azioni manuali richieste
- [ ] Riattivare le branch protection (stato originale annotato in Fase 4)
- [ ] **Rigenerare tutte le credenziali esposte** (considerarle compromesse)
- [ ] Eliminare il repository di backup quando non più necessario (contiene i secret originali)
- [ ] Informare il team: eseguire un nuovo clone (non fare pull/merge dei vecchi cloni)
- [ ] Chiudere e ricreare le Pull Request impattate
- [ ] Eliminare file temporanei con secret (`replacements.txt`, `cleanup-reports/`)
- [ ] (Se rilevante) chiedere al provider il gc dei commit orfani / cache
