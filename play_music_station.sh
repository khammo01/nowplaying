#!/bin/bash
# Open one of the controller's named Apple Music catalog stations. Music's
# AppleScript API can control normal tracks but cannot reliably start these
# catalog-radio URLs, so this intentionally keeps the one small Shortcut bridge
# that accepts a URL. All latency-sensitive rotary controls bypass Shortcuts.

set -u

# A station choice is an intentional source switch. Explicitly pause any
# competing video first so starting Music can never leave YouTube or VLC
# playing underneath it. This checks actual player state on the Mac instead of
# trusting Home Assistant's last poll, and it never toggles an already-paused
# player back on.
/usr/bin/osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
set pausePlayingVideo to "(() => { const videos=[...document.querySelectorAll('video')]; let count=0; for (const video of videos) { if (!video.paused && !video.ended) { video.pause(); count++; } } return String(count); })()"

if application "Safari" is running then
  tell application "Safari"
    repeat with candidateWindow in windows
      repeat with candidateTab in tabs of candidateWindow
        try
          set tabURL to URL of candidateTab as text
          if tabURL contains "youtube.com/watch" or tabURL contains "youtube.com/shorts/" or tabURL contains "youtu.be/" then
            do JavaScript pausePlayingVideo in candidateTab
          end if
        end try
      end repeat
    end repeat
  end tell
end if

if application "Google Chrome" is running then
  tell application "Google Chrome"
    repeat with candidateWindow in windows
      repeat with candidateTab in tabs of candidateWindow
        try
          set tabURL to URL of candidateTab as text
          if tabURL contains "youtube.com/watch" or tabURL contains "youtube.com/shorts/" or tabURL contains "youtu.be/" then
            execute candidateTab javascript pausePlayingVideo
          end if
        end try
      end repeat
    end repeat
  end tell
end if

if application "VLC" is running then
  tell application "VLC"
    try
      if playing then pause
    end try
  end tell
end if
APPLESCRIPT

station="${1:-}"
case "$station" in
  dosem)
    url='https://music.apple.com/us/station/dosem-similar-artists-station/ra.256573197'
    ;;
  above_and_beyond)
    url='https://music.apple.com/us/station/above-beyond-similar-artists-station/ra.20318188'
    ;;
  *)
    printf 'unknown station: %s\n' "$station" >&2
    exit 2
    ;;
esac

input_file="${HOME}/NowPlaying/cache/playlist-input.$$.txt"
printf '%s' "$url" > "$input_file"
/usr/bin/shortcuts run 'Play Music from Provided Playlist' --input-path "$input_file"
command_exit_status=$?
unlink "$input_file" 2>/dev/null || true

if (( command_exit_status == 0 )); then
  pid_file="${HOME}/NowPlaying/cache/nowplaying.lock/pid"
  if [[ -r "$pid_file" ]]; then
    collector_pid=$(<"$pid_file")
    if [[ "$collector_pid" =~ ^[0-9]+$ ]]; then
      kill -USR1 "$collector_pid" 2>/dev/null || true
    fi
  fi
  case "$station" in
    dosem) printf 'Dosem\n' ;;
    above_and_beyond) printf 'Above & Beyond\n' ;;
  esac
fi

exit "$command_exit_status"
