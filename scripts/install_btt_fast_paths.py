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


def detached(command: str, acknowledgement: str = "queued") -> str:
    """Launch a media command without holding BTT's HTTP request open."""
    return (
        'mkdir -p "$HOME/NowPlaying/cache"\n'
        f'({command}) </dev/null >>"$HOME/NowPlaying/cache/btt-media-actions.log" 2>&1 &!\n'
        f'print -r -- {json.dumps(acknowledgement)}'
    )


def youtube_detached(action: str) -> str:
    """Acknowledge the press before browser discovery begins."""
    return (
        'click="$HOME/NowPlaying/assets/youtube-click.wav"\n'
        'if [[ -f "$click" ]]; then /usr/bin/afplay "$click" >/dev/null 2>&1 &!; fi\n'
        + detached(
            f'NAGBOT_FEEDBACK_ALREADY_PLAYED=1 {ROOT}/youtube_action_with_feedback.sh {action}'
        )
    )

COMMANDS = {
    "playpause_toggle": READ_SOURCE + detached(f'{ROOT}/media_command.sh playpause "$source"'),
    "mac_studio_next_song": READ_SOURCE + detached(f'{ROOT}/media_command.sh next "$source"'),
    "mac_mini_previous_song": READ_SOURCE + detached(f'{ROOT}/media_command.sh previous "$source"'),
    "mac_studio_open_youtube": youtube_detached("open"),
    "mac_youtube_play": youtube_detached("play"),
    "mac_youtube_surprise_me": youtube_detached("surprise"),
    "mac_mini_play_apple_music_playlist": (
        "station=$(/usr/bin/osascript -e 'tell application \"BetterTouchTool\" "
        "to get_string_variable \"playlist_id\"' 2>/dev/null)\n"
        'mkdir -p "$HOME/NowPlaying/cache"\n'
        f'({ROOT}/play_music_station.sh "$station") </dev/null '
        '>>"$HOME/NowPlaying/cache/btt-media-actions.log" 2>&1 &!\n'
        'print -r -- "$station"'
    ),
    "mac_studio_skip_forward": (
        READ_SEEK + detached(f'{ROOT}/media_seek_relative.sh "$delta" "$source"')
    ),
    "nowplaying_set_volume": (
        READ_VOLUME + detached(f'{ROOT}/media_volume_adjust.sh "$delta" "$target"')
    ),
    "youtube_caption_toggle": detached(
        f'/usr/bin/osascript {ROOT}/youtube_caption_toggle.applescript'
    ),
    "mac_studio_youtube_slower": detached(
        '/usr/bin/afplay "/System/Library/Sounds/Tink.aiff" >/dev/null 2>&1 & '
        f'/usr/bin/osascript {ROOT}/youtube_target_command.applescript slower'
    ),
    "mac_studio_youtube_faster": detached(
        '/usr/bin/afplay "/System/Library/Sounds/Tink.aiff" >/dev/null 2>&1 & '
        f'/usr/bin/osascript {ROOT}/youtube_target_command.applescript faster'
    ),
    "mac_mini_youtube_full_screen_toggle": detached(
        '/usr/bin/afplay "/System/Library/Sounds/Tink.aiff" >/dev/null 2>&1 & '
        f'/usr/bin/osascript {ROOT}/youtube_target_command.applescript fullscreen'
    ),
    "nowplaying_refresh": (
        'root="$HOME/NowPlaying"\n'
        'pid=$(/usr/bin/jq -r ".pid // empty" "$root/cache/nowplaying.lock/lock.json" 2>/dev/null)\n'
        'if [[ ! "$pid" =~ ^[0-9]+$ ]]; then pid=$(cat "$root/cache/nowplaying.lock/pid" 2>/dev/null); fi\n'
        'if [[ "$pid" =~ ^[0-9]+$ ]]; then kill -USR1 "$pid" 2>/dev/null; fi'
    ),
}

NEW_TRIGGERS = {
    "mac_youtube_home": youtube_detached("home"),
    "music_shuffle_toggle": detached(
        f"/usr/bin/osascript {ROOT}/music_shuffle_toggle.applescript"
    ),
    "media_controller_open_teams": detached(
        "/usr/bin/osascript -e 'tell application \"Microsoft Teams\" to activate'"
    ),
    "media_controller_toggle_teams_mute": detached(
        f"/usr/bin/osascript {ROOT}/teams_toggle_mute.applescript"
    ),
    "mac_youtube_play_cached": (
        "video_id=$(/usr/bin/osascript -e 'tell application \"BetterTouchTool\" "
        "to get_string_variable \"youtube_video_id\"' 2>/dev/null)\n"
        + detached(f'/usr/bin/osascript {ROOT}/youtube_control.applescript play_id "$video_id"')
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
        if name == "mac_mini_play_apple_music_playlist" and len(actions) > 1:
            # The shell action returns immediately, so BTTLastTerminalCommandResult can
            # still contain an unrelated prior action. The playlist_id variable is set
            # by Home Assistant before this trigger is invoked and is deterministic.
            hud = actions[1]
            hud_config = json.loads(hud.get("BTTHUDActionConfiguration") or "{}")
            hud_config["BTTActionHUDTitle"] = "Now Playing: {playlist_id}"
            hud_config["BTTActionHUDAttributedTitle"] = ""
            hud_config["BTTActionHUDDetail"] = ""
            update_trigger(
                hud["BTTUUID"],
                {
                    "BTTHUDActionConfiguration": json.dumps(
                        hud_config, separators=(",", ":")
                    ),
                    "BTTAdditionalActionData": hud_config,
                },
            )
            update_trigger(
                trigger["BTTUUID"],
                {"BTTTriggerConfig": {"BTTHUDText": "", "BTTShowHUD": 0}},
            )
            print("Updated playlist HUD")
        if name == "mac_studio_skip_forward":
            # Progress-slider seeks include their destination as a BTT variable.
            # Showing that value avoids the old hard-coded "+10s" feedback.
            update_trigger(
                trigger["BTTUUID"],
                {
                    "BTTTriggerConfig": {
                        "BTTHUDText": "Seeking… {seek_target_percent}%",
                        "BTTShowHUD": 1,
                    }
                },
            )
            print("Updated seek HUD")
        print(f"Updated {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
