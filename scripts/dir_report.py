#!/usr/bin/env python3
"""Cartelle che spariscono / restano con soli segnaposto dopo l'eliminazione dei file.

Git non traccia le cartelle vuote: quando tutti i file di una cartella vengono eliminati dalla history,
la cartella (e i genitori rimasti senza file) non esiste più in nessun commit. Una cartella che contiene
solo file segnaposto (.gitkeep, .keep, ...) NON è vuota per git: resta, e va segnalata.

Uso: dir_report.py <paths-prima.txt> <paths-dopo.txt>
  Ogni file: un path per riga (tutti i path toccati nella history prima/dopo la riscrittura).
Output (stdout), sezioni parsabili:
  DIR_SPARISCONO: <dir>
  DIR_SOLO_SEGNAPOSTO: <dir>
"""
import posixpath
import sys

PLACEHOLDERS = {".gitkeep", ".keep", ".gitignore", ".gitattributes", ".placeholder", ".empty", "README.md.keep"}


def load(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return {line.rstrip("\n") for line in fh if line.strip()}


def ancestors(p):
    d = posixpath.dirname(p)
    while d:
        yield d
        d = posixpath.dirname(d)


def files_by_dir(paths):
    out = {}
    for p in paths:
        out.setdefault(posixpath.dirname(p), set()).add(posixpath.basename(p))
    return out


def main():
    before, after = load(sys.argv[1]), load(sys.argv[2])
    dirs_before = {d for p in before for d in ancestors(p)}
    dirs_after = {d for p in after for d in ancestors(p)}
    for d in sorted(dirs_before - dirs_after):
        print(f"DIR_SPARISCONO: {d}")

    removed = before - after
    removed_dirs = {d for p in removed for d in ancestors(p)}
    # una cartella è "solo segnaposto" se, dopo la riscrittura, ogni file al suo interno (sottocartelle incluse)
    # è un segnaposto, e prima conteneva altri file che sono stati eliminati
    for d in sorted(dirs_after & removed_dirs):
        inside = [p for p in after if p.startswith(d + "/")]
        if inside and all(posixpath.basename(p) in PLACEHOLDERS for p in inside):
            print(f"DIR_SOLO_SEGNAPOSTO: {d}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main()
