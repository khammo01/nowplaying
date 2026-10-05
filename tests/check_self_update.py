"""Exercise safe self-update against local Git repositories."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args, cwd, check=True):
    return subprocess.run(args, cwd=cwd, check=check, text=True,
                          capture_output=True)


with tempfile.TemporaryDirectory() as temp:
    temp = Path(temp)
    remote = temp / "remote.git"
    source = temp / "source"
    client = temp / "client"
    run("git", "init", "--bare", str(remote), cwd=temp)
    run("git", "init", "-b", "main", str(source), cwd=temp)
    run("git", "config", "user.email", "tests@example.invalid", cwd=source)
    run("git", "config", "user.name", "NowPlaying Tests", cwd=source)
    (source / "scripts").mkdir()
    shutil.copy2(ROOT / "scripts" / "self_update.sh",
                 source / "scripts" / "self_update.sh")
    (source / "scripts" / "check.sh").write_text("#!/bin/bash\nexit 0\n")
    (source / "scripts" / "check.sh").chmod(0o755)
    (source / "version.txt").write_text("one\n")
    run("git", "add", ".", cwd=source)
    run("git", "commit", "-m", "initial", cwd=source)
    run("git", "remote", "add", "origin", str(remote), cwd=source)
    run("git", "push", "-u", "origin", "main", cwd=source)
    run("git", "symbolic-ref", "HEAD", "refs/heads/main", cwd=remote)
    run("git", "clone", str(remote), str(client), cwd=temp)

    (source / "version.txt").write_text("two\n")
    run("git", "add", "version.txt", cwd=source)
    run("git", "commit", "-m", "valid update", cwd=source)
    run("git", "push", cwd=source)
    updated = run("./scripts/self_update.sh", cwd=client, check=False)
    assert updated.returncode == 10, (updated.stdout, updated.stderr)
    assert (client / "version.txt").read_text() == "two\n"

    (source / "version.txt").write_text("broken\n")
    (source / "scripts" / "check.sh").write_text("#!/bin/bash\nexit 1\n")
    run("git", "add", ".", cwd=source)
    run("git", "commit", "-m", "invalid update", cwd=source)
    run("git", "push", cwd=source)
    rejected = run("./scripts/self_update.sh", cwd=client, check=False)
    assert rejected.returncode == 0, (rejected.stdout, rejected.stderr)
    assert (client / "version.txt").read_text() == "two\n"
    assert "failed validation" in rejected.stderr

print("Passed self-update fast-forward and candidate-rejection checks.")
