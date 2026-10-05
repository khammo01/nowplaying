#!/bin/zsh
set -u

delta="${1:-0}"
source="${2:-}"
if ! [[ "$delta" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
  exit 2
fi

# Route explicitly from NowPlaying metadata. This prevents an idle Music app or
# paused browser tab from stealing a command meant for VLC/the active YouTube
# tab. A blank source keeps a conservative Music-then-browser fallback.
if [[ "$source" == "vlc" ]]; then
  /usr/bin/osascript - "$delta" <<'APPLESCRIPT'
on run argv
  set jumpSeconds to (item 1 of argv) as real
  tell application "VLC"
    if it is running then
      set currentPosition to current time
      set newPosition to currentPosition + jumpSeconds
      if newPosition < 0 then set newPosition to 0
      try
        set totalDuration to duration of current item
        if totalDuration > 0 and newPosition > totalDuration then set newPosition to totalDuration
      end try
      set current time to newPosition
      return "vlc"
    end if
  end tell
  return "vlc-not-running"
end run
APPLESCRIPT
  exit $?
fi

music_result="not-music"
if [[ "$source" == "music" || -z "$source" ]]; then
  music_result=$(/usr/bin/osascript - "$delta" <<'APPLESCRIPT'
on run argv
  set jumpSeconds to (item 1 of argv) as real
  tell application "Music"
    if player state is playing then
      set currentPosition to player position
      set trackDuration to duration of current track
      set newPosition to currentPosition + jumpSeconds
      if newPosition < 0 then set newPosition to 0
      if newPosition > trackDuration then set newPosition to trackDuration
      set player position to newPosition
      return "music"
    end if
  end tell
  return "not-music"
end run
APPLESCRIPT
  )
fi

if [[ "$source" == "music" || ( -z "$source" && "$music_result" == "music" ) ]]; then
  print -r -- "$music_result"
  [[ "$music_result" == "music" ]]
  exit $?
fi

/usr/bin/osascript /Users/kuhammon/NowPlaying/youtube_target_command.applescript seek_relative "$delta"
