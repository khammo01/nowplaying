#!/bin/zsh
set -u

root="${0:A:h}"
command_name="${1:-}"
media_source="${2:-}"
value="${3:-}"

signal_refresh() {
  local pid_file="$root/cache/nowplaying.lock/pid"
  if [[ -r "$pid_file" ]]; then
    local collector_pid
    collector_pid="$(<"$pid_file")"
    [[ "$collector_pid" =~ ^[0-9]+$ ]] && kill -USR1 "$collector_pid" 2>/dev/null || true
  fi
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
status=$?
(( status == 0 )) && signal_refresh
exit "$status"
