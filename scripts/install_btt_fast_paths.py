#!/usr/bin/env python3
"""Install direct, source-aware media actions into existing BTT named triggers."""

from __future__ import annotations

import json
import subprocess


# BTT settings sync between Macs. Keep commands home-relative so the same
# trigger works with different macOS account names on each computer.
ROOT = "~/NowPlaying"
SHELL_ACTION_CONFIG = "/bin/zsh:::-c:::-:::"
READ_SOURCE = (
    "source=$(/usr/bin/osascript -e 'tell application \"BetterTouchTool\" "
    "to get_string_variable \"media_source\"' 2>/dev/null)\n"
)
READ_SEEK = (
    "delta=$(/usr/bin/osascript -e 'tell application \"BetterTouchTool\" "
    "to get_string_variable \"seek_delta_seconds\"' 2>/dev/null)\n"
    "source=$(/usr/bin/osascript -e 'tell application \"BetterTouchTool\" "
    "to get_string_variable \"media_source\"' 2>/dev/null)\n"
)
READ_VOLUME = (
    "delta=$(/usr/bin/osascript -e 'tell application \"BetterTouchTool\" "
    "to get_string_variable \"volume_delta_steps\"' 2>/dev/null)\n"
    "target=$(/usr/bin/osascript -e 'tell application \"BetterTouchTool\" "
    "to get_string_variable \"volume_percent\"' 2>/dev/null)\n"
)

COMMANDS = {
    "playpause_toggle": READ_SOURCE + f'exec {ROOT}/media_command.sh playpause "$source"',
    "mac_studio_next_song": READ_SOURCE + f'exec {ROOT}/media_command.sh next "$source"',
    "mac_mini_previous_song": READ_SOURCE + f'exec {ROOT}/media_command.sh previous "$source"',
    "mac_studio_open_youtube": f'exec {ROOT}/youtube_action_with_feedback.sh open',
    "mac_youtube_play": f'exec {ROOT}/youtube_action_with_feedback.sh play',
    "mac_youtube_surprise_me": f'exec {ROOT}/youtube_action_with_feedback.sh surprise',
    "mac_mini_play_apple_music_playlist": (
        "station=$(/usr/bin/osascript -e 'tell application \"BetterTouchTool\" "
        "to get_string_variable \"playlist_id\"' 2>/dev/null)\n"
        f'exec {ROOT}/play_music_station.sh "$station"'
    ),
    "mac_studio_skip_forward": (
        READ_SEEK + f'exec {ROOT}/media_seek_relative.sh "$delta" "$source"'
    ),
    "nowplaying_set_volume": (
        READ_VOLUME + f'exec {ROOT}/media_volume_adjust.sh "$delta" "$target"'
    ),
    "youtube_caption_toggle": f'exec /usr/bin/osascript {ROOT}/youtube_caption_toggle.applescript',
    "mac_studio_youtube_slower": (
        '/usr/bin/afplay "/System/Library/Sounds/Tink.aiff" >/dev/null 2>&1 &\n'
        f'exec /usr/bin/osascript {ROOT}/youtube_target_command.applescript slower'
    ),
    "mac_studio_youtube_faster": (
        '/usr/bin/afplay "/System/Library/Sounds/Tink.aiff" >/dev/null 2>&1 &\n'
        f'exec /usr/bin/osascript {ROOT}/youtube_target_command.applescript faster'
    ),
    "mac_mini_youtube_full_screen_toggle": (
        '/usr/bin/afplay "/System/Library/Sounds/Tink.aiff" >/dev/null 2>&1 &\n'
        f'exec /usr/bin/osascript {ROOT}/youtube_target_command.applescript fullscreen'
    ),
    "nowplaying_refresh": (
        'root="$HOME/NowPlaying"\n'
        'pid=$(/usr/bin/jq -r ".pid // empty" "$root/cache/nowplaying.lock/lock.json" 2>/dev/null)\n'
        'if [[ ! "$pid" =~ ^[0-9]+$ ]]; then pid=$(cat "$root/cache/nowplaying.lock/pid" 2>/dev/null); fi\n'
        'if [[ "$pid" =~ ^[0-9]+$ ]]; then kill -USR1 "$pid" 2>/dev/null; fi'
    ),
}

NEW_TRIGGERS = {
    "mac_youtube_home": f'exec {ROOT}/youtube_action_with_feedback.sh home',
    "media_controller_open_teams": "exec /usr/bin/open -a 'Microsoft Teams'",
    "mac_youtube_play_cached": (
        "video_id=$(/usr/bin/osascript -e 'tell application \"BetterTouchTool\" "
        "to get_string_variable \"youtube_video_id\"' 2>/dev/null)\n"
        f'exec /usr/bin/osascript {ROOT}/youtube_control.applescript play_id "$video_id"'
    ),
    "media_controller_set_input_volume": (
        "target=$(/usr/bin/osascript -e 'tell application \"BetterTouchTool\" "
        "to get_string_variable \"meeting_input_volume\"' 2>/dev/null)\n"
        "case \"$target\" in ''|*[!0-9]*) exit 2;; esac\n"
        "(( target < 0 )) && target=0\n"
        "(( target > 100 )) && target=100\n"
        "exec /usr/bin/osascript -e \"set volume input volume $target\""
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
    result = subprocess.run(
        ["/usr/bin/osascript", "-e", 'tell application "BetterTouchTool" to get_triggers'],
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(result.stdout)


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
                    "BTTShellTaskActionConfig": SHELL_ACTION_CONFIG,
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
                    "BTTShellTaskActionConfig": SHELL_ACTION_CONFIG,
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
                "BTTShellTaskActionConfig": SHELL_ACTION_CONFIG,
            },
        )
        print(f"Updated {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
