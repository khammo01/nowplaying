#!/usr/bin/env python3
"""Install direct, source-aware media actions into existing BTT named triggers."""

from __future__ import annotations

import json
import os
import subprocess
import urllib.request


ROOT = "/Users/kuhammon/NowPlaying"
READ_SOURCE = (
    "source=$(/usr/bin/osascript -e 'tell application \"BetterTouchTool\" "
    "to get_string_variable \"media_source\"' 2>/dev/null)\n"
)

COMMANDS = {
    "playpause_toggle": READ_SOURCE + f'exec {ROOT}/media_command.sh playpause "$source"',
    "mac_studio_next_song": READ_SOURCE + f'exec {ROOT}/media_command.sh next "$source"',
    "mac_mini_previous_song": READ_SOURCE + f'exec {ROOT}/media_command.sh previous "$source"',
}

NEW_TRIGGERS = {
    "mac_youtube_play_cached": (
        "video_id=$(/usr/bin/osascript -e 'tell application \"BetterTouchTool\" "
        "to get_string_variable \"youtube_video_id\"' 2>/dev/null)\n"
        f'exec /usr/bin/osascript {ROOT}/youtube_control.applescript play_id "$video_id"'
    ),
}


def update_trigger(uuid: str, patch: dict) -> None:
    applescript = """
on run argv
  tell application "BetterTouchTool" to update_trigger (item 1 of argv) json (item 2 of argv)
end run
"""
    subprocess.run(
        ["/usr/bin/osascript", "-", uuid, json.dumps(patch, separators=(",", ":"))],
        input=applescript,
        text=True,
        check=True,
        stdout=subprocess.DEVNULL,
    )


def load_local_triggers() -> list[dict]:
    """Read the BTT instance on this Mac, never another Mac's trigger UUIDs."""
    configured = os.environ.get("BTT_URL", "").rstrip("/")
    candidates = ([configured] if configured else []) + [
        "http://127.0.0.1:51520/get_triggers",
        "http://127.0.0.1:51836/get_triggers",
    ]
    errors = []
    for url in candidates:
        if not url:
            continue
        try:
            with urllib.request.urlopen(url + "/", timeout=2) as response:
                return json.load(response)
        except Exception as exc:  # report all attempted local endpoints together
            errors.append(f"{url}: {exc}")
    raise SystemExit("Could not read local BTT triggers:\n" + "\n".join(errors))


def main() -> int:
    triggers = load_local_triggers()
    by_name = {item.get("BTTTriggerName"): item for item in triggers}
    for name, command in NEW_TRIGGERS.items():
        if name in by_name:
            actions = by_name[name].get("BTTActionsToExecute") or []
            if not actions:
                raise SystemExit(f"Named trigger has no action: {name}")
            update_trigger(
                actions[0]["BTTUUID"],
                {
                    "BTTPredefinedActionType": 206,
                    "BTTPredefinedActionName": "Execute Shell Script  or  Task",
                    "BTTShellTaskActionScript": command,
                },
            )
            print(f"Updated {name}")
            continue
        trigger_json = {
            "BTTTriggerType": 643,
            "BTTTriggerClass": "BTTTriggerTypeOtherTriggers",
            "BTTTriggerName": name,
            "BTTEnabled2": 1,
            "BTTActionsToExecute": [
                {
                    "BTTPredefinedActionType": 206,
                    "BTTPredefinedActionName": "Execute Shell Script  or  Task",
                    "BTTShellTaskActionScript": command,
                }
            ],
        }
        applescript = """
on run argv
  tell application "BetterTouchTool" to add_new_trigger (item 1 of argv)
end run
"""
        subprocess.run(
            ["/usr/bin/osascript", "-", json.dumps(trigger_json, separators=(",", ":"))],
            input=applescript,
            text=True,
            check=True,
            stdout=subprocess.DEVNULL,
        )
        print(f"Created {name}")
    for name, command in COMMANDS.items():
        trigger = by_name.get(name)
        if not trigger:
            raise SystemExit(f"Missing BTT named trigger: {name}")
        actions = trigger.get("BTTActionsToExecute") or []
        if not actions:
            raise SystemExit(f"Named trigger has no action: {name}")
        action = actions[0]
        update_trigger(
            action["BTTUUID"],
            {
                "BTTPredefinedActionType": 206,
                "BTTPredefinedActionName": "Execute Shell Script  or  Task",
                "BTTShellTaskActionScript": command,
            },
        )
        print(f"Updated {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
