#!/usr/bin/env python3
"""Serialize rapid media commands so AppleEvents never overlap or disappear."""

from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid


ROOT = Path(__file__).resolve().parent
QUEUE = ROOT / "cache" / "media-command-queue"
LOCK = ROOT / "cache" / "media-command-worker.lock"


def enqueue(arguments: list[str]) -> None:
    QUEUE.mkdir(parents=True, exist_ok=True)
    stamp = f"{time.time_ns():020d}-{uuid.uuid4().hex}.json"
    temporary = QUEUE / f".{stamp}.tmp"
    destination = QUEUE / stamp
    temporary.write_text(json.dumps(arguments), encoding="utf-8")
    os.replace(temporary, destination)


def drain() -> None:
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    with LOCK.open("a+") as lock_handle:
        try:
            fcntl.flock(lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return

        empty_checks = 0
        while empty_checks < 2:
            queued = sorted(QUEUE.glob("*.json"))
            if not queued:
                empty_checks += 1
                time.sleep(0.10)
                continue
            empty_checks = 0
            item = queued[0]
            try:
                arguments = json.loads(item.read_text(encoding="utf-8"))
                item.unlink(missing_ok=True)
                subprocess.run(
                    [str(ROOT / "media_command.sh"), *arguments],
                    check=False,
                    stdin=subprocess.DEVNULL,
                )
            except (OSError, ValueError, TypeError) as error:
                item.unlink(missing_ok=True)
                print(f"media command queue: {error}", file=sys.stderr)
            time.sleep(0.08)


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: media_command_queue.py COMMAND [SOURCE [VALUE]]", file=sys.stderr)
        return 2
    enqueue(sys.argv[1:])
    pid = os.fork()
    if pid == 0:
        os.setsid()
        second_pid = os.fork()
        if second_pid == 0:
            drain()
            os._exit(0)
        os._exit(0)
    os.waitpid(pid, 0)
    print("queued")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
