# Ricette git filter-repo

Regola generale: operare su un **clone fresco** (`git clone --mirror`), non sul backup, e provare con `--dry-run`.
Dopo `filter-repo` il remote `origin` viene rimosso.

## A. Eliminare file/pattern dalla history
`paths-to-remove.txt` (una regola per riga, `#` per commenti):
```
secrets/.env
config/prod.yml
glob:**/*.pem
regex:^deploy/keys/.*
```
```bash
git filter-repo --invert-paths --paths-from-file paths-to-remove.txt
```
Singolo path: `git filter-repo --invert-paths --path secrets/.env`
Glob: `git filter-repo --invert-paths --path-glob '*.pem'`

> Attenzione: l'esempio del prompt `--path-glob '*.md' --invert-paths` **rimuoverebbe tutti i Markdown**
> (README, CHANGELOG...). Usarlo solo se è davvero l'intento dell'utente e dopo aver compilato la keep-list.

## B. Sostituire valori sensibili
`replacements.txt`:
```
AKIAIOSFODNN7EXAMPLE==>***REMOVED***
regex:ghp_[A-Za-z0-9]{36}==>***REMOVED***
password123
```
(senza `==>` il valore diventa `***REMOVED***`)
```bash
git filter-repo --replace-text replacements.txt
```
I valori in `replacements.txt` sono secret in chiaro: tenere il file fuori dal repo e cancellarlo a fine lavoro
(`shred -u replacements.txt`).

## C/D. Esclusioni e invarianti
- C (escludi dalla bonifica) e D (mantieni): nessuna regola; inserire il file in `keep-list.txt`.
- `dry-run.sh --keep keep-list.txt` fallisce (exit 3) se una regola A rimuoverebbe un file della keep-list.
- Per limitare `--replace-text` ad alcuni file non esiste un filtro nativo: usare `--path` per
  restringere la riscrittura oppure un `--blob-callback` dedicato (richiede approvazione utente sul codice).

## Combinare A e B
```bash
git filter-repo --invert-paths --paths-from-file paths-to-remove.txt --replace-text replacements.txt
```

## Dry run
`--dry-run` non modifica i ref; produce `filter-repo/fast-export.original` e `fast-export.filtered`
(in un repo bare: `<repo>/filter-repo/`, altrimenti `.git/filter-repo/`).

## Dopo la riscrittura
```bash
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```
