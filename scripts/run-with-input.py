#!/usr/bin/env python3
"""Runs a Deno program in a pseudo-terminal and feeds it answers for prompt().

Deno's prompt() returns null when stdin is not a terminal, so piping input does
not work. This script allocates a pty, writes one answer per prompt and prints
the complete terminal transcript.

The program may read and write files in its own folder, nothing else (no
environment variables, no network, no other programs), and it is stopped after
60 seconds.

Usage: run-with-input.py <file.ts> [answer ...]
"""
import os
import pty
import select
import sys
import time


def run(path, answers):
    # run inside the program's folder, like "Open in Integrated Terminal" does,
    # so that relative paths such as "scores.json" resolve next to main.ts
    folder = os.path.dirname(os.path.abspath(path))
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(folder)
        os.execvp("deno", ["deno", "run", "--allow-read=.", "--allow-write=.", os.path.basename(path)])
    pending = list(answers)
    out = b""
    quiet_since = time.time()
    started = time.time()
    while True:
        if time.time() - started > 60:
            os.kill(pid, 9)
            out += b"\n[timeout: program stopped after 60 seconds]\n"
            break
        ready, _, _ = select.select([fd], [], [], 0.1)
        if ready:
            try:
                data = os.read(fd, 4096)
            except OSError:
                break
            if not data:
                break
            out += data
            quiet_since = time.time()
        elif pending and time.time() - quiet_since > 0.3:
            # the program is waiting: answer the prompt
            os.write(fd, (pending.pop(0) + "\n").encode())
            quiet_since = time.time()
        elif not pending and time.time() - quiet_since > 5:
            os.kill(pid, 9)
            out += b"\n[timeout: program did not finish]\n"
            break
    os.waitpid(pid, 0)
    sys.stdout.write(out.decode(errors="replace").replace("\r\n", "\n"))


if __name__ == "__main__":
    run(sys.argv[1], sys.argv[2:])
