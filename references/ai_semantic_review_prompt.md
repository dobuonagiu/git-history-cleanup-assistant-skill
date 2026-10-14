# Prompt: revisione semantica (Layer 4)

Gli scanner a regex (gitleaks, trufflehog, pattern custom) non vedono il **contesto privato novel**.
Questa revisione serve a trovare ciò che nessuna regola conosceva. Va eseguita sullo scope congelato da
`scripts/semantic-review-inventory.sh` (Fase 5b, e di nuovo sui ref riscritti in Fase 13b prima del push).

## Regole
- Rivedi **anche** il materiale senza hit degli scanner: gli hit prioritizzano, non definiscono la copertura.
- Lo scope include ogni blob testuale distinto della history raggiungibile, non soltanto una versione per path
  o i file presenti sul tip dei branch. Se un file di configurazione ha più versioni, rivedile tutte.
- Non copiare mai valori sensibili nei report o nella chat: usa descrizioni e path (`config/prod.yml:12, hostname interno`).
- Registra risultati e copertura **fuori dal repository** (es. `cleanup-reports/`).
- Ciò che non hai ispezionato è **non verificato**, non "pulito".
- Nessun finding semantico = nessuna azione automatica: proponi, l'utente decide (classificazione A/B/C/D).

## Cosa cercare
1. Nomi reali di persone, clienti, fornitori, collaboratori; email personali; telefoni; indirizzi.
2. Codename di progetto, nomi di ambienti/cluster/tenant interni, ticket e URL di sistemi interni.
3. Domini, hostname, IP, VPN, share di rete, percorsi di filesystem che rivelano infrastruttura privata.
4. Frammenti di trascrizioni, chat, meeting, note interne, email incollate in commenti/doc/test/fixture.
5. Descrizioni di architettura, topologia, regole di firewall, procedure di accesso, runbook interni.
6. Dati personali (PII) o dati cliente in fixture, dump, CSV, snapshot di test.
7. Credenziali "non standard": password in chiaro in commenti, token in URL, connection string, chiavi in file di config/notebook, valori codificati base64.
8. Contesto sensibile nei **messaggi di commit**, nomi di branch e tag.
9. Campi configurazione e credenziali statiche a bassa entropia, anche senza finding automatici: `user`,
   `username`, `password`, `passwd`, `pwd`, `secret`, `token`, URI `user:password@host` e proprietà di
   Redis, Kafka/JAAS (`sasl.jaas.config`), MongoDB, SQL, AMQP, SMTP, LDAP, OAuth/JWT, cloud, registry,
   TLS/SSH. Controlla YAML, `.properties`, JSON, XML, `.env`, Docker/Compose, Helm/Kubernetes, Terraform,
   CI, script, notebook, fixture, documenti e file di esempio.
10. Forme equivalenti o offuscate: virgolette/escape JSON (`\u0022`), escape delle virgolette, URL encoding,
    base64/hex e stringhe concatenate. La codifica non rende una credenziale sicura.
11. Elementi non contenuti nei blob Git ordinari: payload Git LFS, repository dei submodule, ref non
    scaricati dal provider, PR/issue/wiki/release, log e artifact CI, package, fork e cloni. Verifica queste
    superfici separatamente o contrassegnale come NON VERIFICATE.

## Procedura
1. Leggi `<label>-semantic-scope.md` (ref congelati, file inclusi, file esclusi).
2. Per **ogni versione distinta** nello scope e per ogni messaggio di commit applica la lista sopra. Usa il
   report di `scan-config-candidates.sh` come checklist obbligatoria, non come unica fonte di finding.
3. Per ogni finding annota: `path | commit/ref | categoria | gravità (alta/media/bassa) | azione suggerita (A/B/C/D) | note` — senza il valore.
4. Chiudi con il riepilogo di copertura: blob/versioni ispezionati, commit e ref ispezionati; file grandi,
   binari, ref non raggiungibili o altri elementi esclusi sono NON VERIFICATI. Non descrivere la revisione
   come completa finché tutti i candidate di configurazione non sono classificati.
5. Presenta la tabella all'utente e usa `ask_user` per decidere; i nuovi valori da sostituire vanno in `replacements.txt`, i path in `paths-to-remove.txt`, **poi** ripetere il dry-run.

## Output atteso
```
Copertura: N file testuali, M commit, K ref | Non verificati: <elenco>
| # | Path | Ref/commit | Categoria | Gravità | Azione suggerita |
```
