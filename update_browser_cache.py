#!/usr/bin/env python3
"""Merge a lightweight browser inventory with NowPlaying's active target."""

from __future__ import annotations

import json
import os
import pathlib
import sys
import tempfile
import time


def read_json(path: pathlib.Path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError, TypeError):
        return default


def read_legacy_target(path: pathlib.Path):
    try:
        browser, window_index, tab_index, url = path.read_text().strip().split("|", 3)
        return {
            "browser": browser,
            "window_index": int(window_index),
            "tab_index": int(tab_index),
            "url": url,
        }
    except (OSError, ValueError):
        return None


def main() -> int:
    if len(sys.argv) != 3:
        return 2
    cache_path = pathlib.Path(sys.argv[1])
    legacy_path = pathlib.Path(sys.argv[2])
    try:
        tabs = json.load(sys.stdin)
    except (ValueError, TypeError):
        return 1
    if not isinstance(tabs, list):
        return 1

    previous = read_json(cache_path, {})
    active = read_legacy_target(legacy_path)
    if active:
        match = next(
            (
                tab
                for tab in tabs
                if tab.get("browser") == active["browser"]
                and tab.get("url") == active["url"]
            ),
            None,
        )
        if match:
            active = {**match, "last_confirmed_at": int(time.time())}
        else:
            # Retain the target for one recovery attempt. Each command validates
            # the URL before acting, so a stale entry cannot hit another tab.
            active["last_confirmed_at"] = previous.get("active", {}).get(
                "last_confirmed_at", 0
            )

    now = time.time()
    payload = {
        "schema": 1,
        "generation": int(previous.get("generation", 0)) + 1,
        "updated_at": now,
        "updated_at_iso": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
        "active": active,
        "tabs": tabs,
        "counts": {
            "media": sum(bool(tab.get("is_media_page")) for tab in tabs),
            "youtube_pages": sum(bool(tab.get("is_youtube_page")) for tab in tabs),
            "youtube_videos": sum(bool(tab.get("is_youtube_video")) for tab in tabs),
        },
    }

    cache_path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=cache_path.name + ".", dir=cache_path.parent)
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_name, cache_path)
    finally:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
