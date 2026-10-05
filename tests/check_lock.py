"""Verify the JSON process lock and legacy lock migration behavior."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def write_executable(path: Path, content: str) -> None:
    path.write_text(content)
    path.chmod(0o755)


with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    shutil.copy2(ROOT / "NowPlaying.sh", root / "NowPlaying.sh")
    (root / "config.local.sh").write_text("""HA_SERVER=unused.invalid
HA_API_URL=https://ha.invalid/webhook/test
HA_BASE_URL=https://ha.invalid
HA_AUDIO_ENTITY=input_boolean.test_mac
BEARER_TOKEN=test-only
OMDB_API_KEY=test-only
""")
    mock = root / "bin"
    mock.mkdir()
    commands = {
        "sleep": "#!/bin/bash\nexec /usr/bin/python3 -c 'import time; time.sleep(30)'\n",
        "osascript": "#!/bin/bash\necho '{\"playing\":false}'\n",
        "pmset": "#!/bin/bash\nexit 0\n",
        "ps": "#!/bin/bash\necho '2.5 coreaudiod'\n",
        "scp": "#!/bin/bash\nexit 0\n",
        "curl": "#!/bin/bash\nprintf 200\n",
    }
    for name, content in commands.items():
        write_executable(mock / name, content)
    env = dict(os.environ, PATH=str(mock) + ":" + os.environ["PATH"], TERM="dumb")
    env.pop("NOWPLAYING_CONFIG", None)

    process = subprocess.Popen(
        ["bash", str(root / "NowPlaying.sh")],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    lock_file = root / "cache" / "nowplaying.lock" / "lock.json"
    for _ in range(100):
        if lock_file.exists():
            break
        if process.poll() is not None:
            raise AssertionError(process.stderr.read())
        time.sleep(0.05)
    assert lock_file.exists(), "JSON lock file was not created"
    lock = json.loads(lock_file.read_text())
    assert lock["pid"] == process.pid, lock
    assert lock["script"] == str(root / "NowPlaying.sh"), lock
    assert lock["hostname"], lock
    assert lock["started_at"].endswith("+00:00"), lock

    duplicate = subprocess.run(
        ["bash", str(root / "NowPlaying.sh")],
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert duplicate.returncode == 1, duplicate
    assert f"already running as PID {process.pid}" in duplicate.stderr, duplicate.stderr

    process.terminate()
    process.wait(timeout=10)
    assert not lock_file.parent.exists(), "owner did not clean up its JSON lock"

    lock_file.parent.mkdir(parents=True)
    (lock_file.parent / "pid").write_text(f"{os.getpid()}\n")
    legacy_duplicate = subprocess.run(
        ["bash", str(root / "NowPlaying.sh")],
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert legacy_duplicate.returncode == 1, legacy_duplicate
    assert f"already running as PID {os.getpid()}" in legacy_duplicate.stderr

print("Passed JSON lock ownership, duplicate exclusion, cleanup, and legacy migration checks.")
