#!/bin/zsh
set -u

action="${1:-play}"
root="${0:A:h}"
click_sound="$root/assets/youtube-click.wav"
error_sound="/System/Library/Sounds/Basso.aiff"

case "$action" in
  next)     working="Switching to the next YouTube video" ;;
  home)     working="Opening YouTube Home" ;;
  open)     working="Opening YouTube" ;;
  play)     working="Finding the last YouTube video" ;;
  surprise) working="Choosing a YouTube surprise" ;;
  *) exit 2 ;;
esac

# BTT normally plays this before launching the worker so acknowledgement is
# instantaneous. Keep this fallback for direct command-line invocations.
if [[ "${NAGBOT_FEEDBACK_ALREADY_PLAYED:-0}" != "1" && -f "$click_sound" ]]; then
  /usr/bin/afplay "$click_sound" >/dev/null 2>&1 &
fi

if [[ "$action" == "next" ]]; then
  /usr/bin/osascript "$root/next_youtube_video.applescript" > /tmp/nagbot-youtube-action-result 2>&1 &
else
  /usr/bin/osascript "$root/youtube_control.applescript" "$action" > /tmp/nagbot-youtube-action-result 2>&1 &
fi
worker=$!
wait "$worker"
exit_code=$?
result="$(cat /tmp/nagbot-youtube-action-result 2>/dev/null)"

if (( exit_code != 0 )) || [[ "$result" == ERROR\|* ]] || [[ "$result" == *"did not start"* ]] || [[ "$result" == *"No current"* ]]; then
  detail="${result#ERROR|}"
  [[ -z "$detail" ]] && detail="YouTube could not complete the request"
  /usr/bin/afplay "$error_sound" >/dev/null 2>&1 &
  exit 1
fi

detail="${result#OK|}"
[[ -z "$detail" ]] && detail="Ready"

# Refresh only after the browser has accepted the command; the former HA-side
# 120/350 ms refreshes ran before slow tab changes had completed.
if [[ "$action" != "open" && "$action" != "home" ]]; then
  computer_name=$(/usr/sbin/scutil --get ComputerName 2>/dev/null || /bin/hostname -s)
  if [[ "${computer_name:l}" == *"mac mini"* || "${computer_name:l}" == *"mac-mini"* ]]; then
    btt_candidates=("http://192.168.1.26:51520")
  elif [[ "${computer_name:l}" == *"macbook"* || "${computer_name:l}" == *"work mac"* ]]; then
    btt_candidates=("http://192.168.1.179:51520")
  else
    local_ip="$(/usr/sbin/ipconfig getifaddr en0 2>/dev/null || true)"
    [[ -z "$local_ip" ]] && local_ip="$(/usr/sbin/ipconfig getifaddr en1 2>/dev/null || true)"
    btt_candidates=("http://${local_ip}:51520" "http://${local_ip}:51836")
  fi
  for base in "${btt_candidates[@]}"; do
    [[ "$base" == "http://:51520" || "$base" == "http://:51836" ]] && continue
    /usr/bin/curl -fsS --max-time 1 "$base/trigger_named_async_without_response/?trigger_name=nowplaying_refresh" >/dev/null 2>&1 && break
  done
fi

# The command has just changed selection/playback. Refresh the cheap inventory
# out of band; metadata refresh remains independently signal-driven above.
"$root/refresh_browser_cache.sh" >/dev/null 2>&1 &

exit 0
