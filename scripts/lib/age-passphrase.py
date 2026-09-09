#!/usr/bin/env python3
"""Run age -p / age -d with a passphrase supplied non-interactively (pty)."""
from __future__ import annotations

import os
import pty
import select
import subprocess
import sys


def _feed_passphrase(master_fd: int, passphrase: str, prompts: int) -> None:
    buf = ""
    sent = 0
    while sent < prompts:
        if not select.select([master_fd], [], [], 30)[0]:
            raise RuntimeError("timed out waiting for age passphrase prompt")
        chunk = os.read(master_fd, 4096)
        if not chunk:
            break
        buf += chunk.decode("utf-8", "replace")
        if "passphrase" in buf.lower():
            os.write(master_fd, (passphrase + "\n").encode())
            sent += 1
            buf = ""


def main() -> int:
    if len(sys.argv) != 5:
        print("usage: age-passphrase.py <-p|-d> <passphrase> <output> <input>", file=sys.stderr)
        return 2
    subcmd, passphrase, out_path, in_path = sys.argv[1:5]
    if subcmd not in ("-p", "-d"):
        print("subcmd must be -p or -d", file=sys.stderr)
        return 2
    if not passphrase:
        print("empty passphrase", file=sys.stderr)
        return 2

    cmd = ["age", subcmd, "-o", out_path, in_path]
    master_fd, slave_fd = pty.openpty()
    proc = subprocess.Popen(cmd, stdin=slave_fd, stdout=slave_fd, stderr=slave_fd)
    os.close(slave_fd)
    try:
        _feed_passphrase(master_fd, passphrase, 2 if subcmd == "-p" else 1)
    finally:
        os.close(master_fd)
    return proc.wait()


if __name__ == "__main__":
    raise SystemExit(main())
