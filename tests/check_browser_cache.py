#!/usr/bin/env python3
import json
import pathlib
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]


with tempfile.TemporaryDirectory() as temp_dir:
    temp = pathlib.Path(temp_dir)
    cache = temp / "browser-inventory.json"
    legacy = temp / "legacy"
    legacy.write_text("Safari|2|3|https://www.youtube.com/watch?v=active")
    tabs = [
        {
            "browser": "Safari",
            "window_id": 42,
            "window_index": 2,
            "tab_index": 3,
            "url": "https://www.youtube.com/watch?v=active",
            "title": "Active",
            "selected": True,
            "is_youtube_page": True,
            "is_youtube_video": True,
            "is_media_page": True,
        },
        {
            "browser": "Safari",
            "window_id": 42,
            "window_index": 2,
            "tab_index": 4,
            "url": "https://www.youtube.com/watch?v=next",
            "title": "Next",
            "selected": False,
            "is_youtube_page": True,
            "is_youtube_video": True,
            "is_media_page": True,
        },
    ]
    subprocess.run(
        [str(ROOT / "update_browser_cache.py"), str(cache), str(legacy)],
        input=json.dumps(tabs),
        text=True,
        check=True,
    )
    first = json.loads(cache.read_text())
    assert first["generation"] == 1
    assert first["active"]["window_id"] == 42
    assert first["counts"] == {"media": 2, "youtube_pages": 2, "youtube_videos": 2}

    subprocess.run(
        [str(ROOT / "update_browser_cache.py"), str(cache), str(legacy)],
        input=json.dumps(tabs[:1]),
        text=True,
        check=True,
    )
    second = json.loads(cache.read_text())
    assert second["generation"] == 2
    assert second["active"]["url"].endswith("active")

print("Browser cache checks passed.")
