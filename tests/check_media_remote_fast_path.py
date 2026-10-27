#!/usr/bin/env python3
"""Verify that provisional browser focus changes cannot fake a pause."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "media_remote_fast_path.sh"


def run_fast_path(info: dict) -> tuple[subprocess.CompletedProcess[str], Path]:
    temporary = tempfile.TemporaryDirectory()
    root = Path(temporary.name)
    payload = root / "payload.json"
    env = os.environ.copy()
    env.update(
        {
            "NOWPLAYING_ROOT": str(root),
            "NOWPLAYING_DISABLE_SIGNAL": "true",
            "NOWPLAYING_PAYLOAD_FILE": str(payload),
            "HA_API_URL": "http://127.0.0.1/unused",
            "SOURCE_DEVICE": "Test Mac",
            "BTT_NOWPLAYING_INFO_JSON": json.dumps(info),
        }
    )
    result = subprocess.run(
        ["/bin/zsh", str(SCRIPT)],
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    # Keep the temporary directory alive until callers finish reading payload.
    result._temporary_directory = temporary  # type: ignore[attr-defined]
    return result, payload


browser_paused, browser_paused_payload = run_fast_path(
    {
        "isPlaying": False,
        "title": "Never-started foreground tab",
        "appName": "Safari",
        "bundleIdentifier": "com.apple.Safari",
        "duration": 600,
    }
)
assert browser_paused.returncode == 0, browser_paused.stderr
assert not browser_paused_payload.exists(), (
    "A browser pause is ambiguous until the full tab scan completes"
)

browser_playing, browser_playing_payload = run_fast_path(
    {
        "isPlaying": True,
        "title": "Actually playing tab",
        "appName": "Safari",
        "bundleIdentifier": "com.apple.Safari",
        "duration": 600,
    }
)
assert browser_playing.returncode == 0, browser_playing.stderr
assert json.loads(browser_playing_payload.read_text())["media_status"] == "Playing"

music_paused, music_paused_payload = run_fast_path(
    {
        "isPlaying": False,
        "title": "Paused song",
        "appName": "Music",
        "bundleIdentifier": "com.apple.Music",
        "duration": 240,
    }
)
assert music_paused.returncode == 0, music_paused.stderr
assert json.loads(music_paused_payload.read_text())["media_status"] == "Paused"

print("Passed 3 MediaRemote focus-edge checks.")
