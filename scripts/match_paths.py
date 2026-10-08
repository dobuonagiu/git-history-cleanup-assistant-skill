#!/usr/bin/env python3
"""Stampa i path (da stdin, uno per riga) che corrispondono alle regole di un paths-file.

Semantica allineata a git filter-repo --paths-from-file:
  riga semplice / literal:X  -> path esatto o prefisso di directory
  glob:X                     -> fnmatch (anche attraverso '/')
  regex:X                    -> re.match
Righe vuote e commenti '#' ignorati.
"""
import fnmatch
import re
import sys


def load(rules_file):
    rules = []
    with open(rules_file, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if line.startswith("glob:"):
                rules.append(("glob", line[5:]))
            elif line.startswith("regex:"):
                rules.append(("regex", re.compile(line[6:])))
            else:
                rules.append(("literal", line[8:] if line.startswith("literal:") else line))
    return rules


def match(rules, path):
    for kind, pat in rules:
        if kind == "literal":
            if path == pat or path.startswith(pat.rstrip("/") + "/"):
                return True
        elif kind == "glob":
            if fnmatch.fnmatchcase(path, pat):
                return True
        elif pat.match(path):
            return True
    return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Uso: match_paths.py <rules-file> < paths")
    rules = load(sys.argv[1])
    for raw in sys.stdin:
        p = raw.rstrip("\n")
        if p and match(rules, p):
            print(p)
