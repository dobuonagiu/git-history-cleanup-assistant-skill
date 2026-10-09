#!/usr/bin/env python3
"""Approva un gate come farebbe l'utente da terminale: apre una pty e digita la frase richiesta.
Uso: approve.py <gate.sh> <gate-id> <frase>   (exit code = quello di gate.sh)"""
import os
import pty
import select
import sys

script, gate_id, phrase = sys.argv[1:4]
pid, fd = pty.fork()
if pid == 0:
    os.execv("/bin/bash", ["bash", script, "approve", gate_id])

out, sent = b"", False
while True:
    ready, _, _ = select.select([fd], [], [], 10)
    if not ready:
        break
    try:
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    out += data
    if not sent and out.rstrip().endswith(b">"):
        os.write(fd, (phrase + "\n").encode())
        sent = True
_, status = os.waitpid(pid, 0)
sys.stdout.write(out.decode(errors="replace")[-300:])
sys.exit(os.WEXITSTATUS(status))
