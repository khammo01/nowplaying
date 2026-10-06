#!/bin/zsh
set -u

root="${0:A:h}"
command_name="${1:-}"
media_source="${2:-}"
value="${3:-}"

signal_refresh() {
  local lock_dir="$root/cache/nowplaying.lock"
  local lock_file="$lock_dir/lock.json"
  local collector_pid=""
  if [[ -r "$lock_file" ]]; then
    collector_pid="$(/usr/bin/python3 - "$lock_file" <<'PY' 2>/dev/null || true
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    pid = json.load(handle).get("pid", "")
if isinstance(pid, int) and pid > 0:
    print(pid)
PY
)"
  elif [[ -r "$lock_dir/pid" ]]; then
    collector_pid="$(<"$lock_dir/pid")"
  fi
  [[ "$collector_pid" =~ ^[0-9]+$ ]] && kill -USR1 "$collector_pid" 2>/dev/null || true
}

if [[ -z "$media_source" || "$media_source" == "unknown" ]]; then
  media_source="$(/usr/bin/jq -r '.active.browser // empty' "$root/cache/browser-inventory.json" 2>/dev/null)"
  [[ -n "$media_source" ]] && media_source="youtube"
fi

case "$media_source:$command_name" in
  youtube:playpause|youtube:fullscreen|youtube:captions|youtube:slower|youtube:faster)
    /usr/bin/osascript "$root/youtube_target_command.applescript" "$command_name" "$value"
    ;;
  youtube:next_video)
    /usr/bin/osascript "$root/next_youtube_video.applescript"
    ;;
  youtube:seek_relative)
    "$root/media_seek_relative.sh" "$value" youtube
    ;;
  music:playpause)
    /usr/bin/osascript -e 'tell application "Music" to playpause'
    ;;
  music:next)
    /usr/bin/osascript -e 'tell application "Music" to next track'
    ;;
  music:previous)
    /usr/bin/osascript -e 'tell application "Music" to back track'
    ;;
  music:seek_relative)
    "$root/media_seek_relative.sh" "$value" music
    ;;
  vlc:playpause)
    /usr/bin/osascript -e 'tell application "VLC" to play'
    ;;
  vlc:next|vlc:next_video)
    /usr/bin/osascript -e 'tell application "VLC" to next'
    ;;
  vlc:previous)
    /usr/bin/osascript -e 'tell application "VLC" to previous'
    ;;
  vlc:seek_relative)
    "$root/media_seek_relative.sh" "$value" vlc
    ;;
  *)
    print -u2 -- "Unsupported media command: source=$media_source command=$command_name"
    exit 2
    ;;
esac
exit_status=$?
(( exit_status == 0 )) && signal_refresh
exit "$exit_status"
