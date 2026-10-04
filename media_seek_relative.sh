#!/bin/zsh
set -u

delta="${1:-0}"
if ! [[ "$delta" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
  exit 2
fi

# Apple Music does not have a browser tab cache. Preserve its native seek
# behavior, then use the exact NowPlaying YouTube target for browser video.
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

if [[ "$music_result" == "music" ]]; then
  print -r -- "$music_result"
  exit 0
fi

/usr/bin/osascript /Users/kuhammon/NowPlaying/youtube_target_command.applescript seek_relative "$delta"
