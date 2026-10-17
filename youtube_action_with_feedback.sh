#!/bin/zsh
set -u

action="${1:-play}"
root="${0:A:h}"
click_sound="$root/assets/youtube-click.wav"
error_sound="/System/Library/Sounds/Basso.aiff"

# BTT launches this action asynchronously, so repeated button presses can
# otherwise overlap and advance two tabs at once. Keep Next single-flight.
if [[ "$action" == "next" ]]; then
  lock_dir="$root/cache/next-youtube.lock"
  /bin/mkdir -p "$root/cache"
  if ! /bin/mkdir "$lock_dir" 2>/dev/null; then
    lock_pid="$(cat "$lock_dir/pid" 2>/dev/null || true)"
    if [[ "$lock_pid" == <-> ]] && /bin/kill -0 "$lock_pid" 2>/dev/null; then
      print -r -- "OK|Next YouTube is already in progress"
      exit 0
    fi
    /bin/rmdir "$lock_dir" 2>/dev/null || {
      print -r -- "OK|Next YouTube is already in progress"
      exit 0
    }
    /bin/mkdir "$lock_dir" 2>/dev/null || exit 0
  fi
  print -r -- "$$" > "$lock_dir/pid"
  trap '/bin/rm -f "$lock_dir/pid" 2>/dev/null; /bin/rmdir "$lock_dir" 2>/dev/null' EXIT INT TERM
fi

show_rejection() {
  local detail="$1"
  local btt_base hud_config hud_action
  btt_base=$("$root/scripts/find_btt_base.sh" nowplaying_volume_notch 2>/dev/null || true)
  hud_config=$(/usr/bin/jq -nc --arg detail "$detail" '{
    BTTActionHUDTitle:"Next YouTube canceled",
    BTTActionHUDDetail:$detail,
    BTTActionHUDDuration:3,
    BTTActionHUDWidth:420,
    BTTActionHUDHeight:170,
    BTTActionHUDPosition:0,
    BTTActionHUDBlur:true,
    BTTActionHUDBackground:"rgba(0.08,0.08,0.09,0.92)",
    BTTActionHUDBorderWidth:1,
    BTTActionHUDCloseOnClick:1,
    BTTActionHUDHideWhenOtherHUDAppears:true
  } | tojson')
  hud_action=$(/usr/bin/jq -nc --arg config "$hud_config" '{
    BTTPredefinedActionType:254,
    BTTPredefinedActionName:"Show HUD Overlay",
    BTTHUDActionConfiguration:$config
  }')
  if [[ -z "$btt_base" ]] || ! /usr/bin/curl -fsS --max-time 2 -G --data-urlencode "json=$hud_action" "$btt_base/trigger_action/" >/dev/null 2>&1; then
    /usr/bin/osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "Next YouTube canceled"' -e 'end run' "$detail" >/dev/null 2>&1 || true
  fi
}

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

if (( exit_code != 0 )) || [[ "$result" == ERROR\|* ]] || [[ "$result" == REJECT\|* ]] || [[ "$result" == *"did not start"* ]] || [[ "$result" == *"No current"* ]]; then
  detail="${result#ERROR|}"
  detail="${detail#REJECT|}"
  [[ -z "$detail" ]] && detail="YouTube could not complete the request"
  show_rejection "$detail"
  /usr/bin/afplay "$error_sound" >/dev/null 2>&1 &
  exit 1
fi

detail="${result#OK|}"
[[ -z "$detail" ]] && detail="Ready"

# Refresh only after the browser has accepted the command; the former HA-side
# 120/350 ms refreshes ran before slow tab changes had completed.
if [[ "$action" != "open" && "$action" != "home" ]]; then
  base=$("$root/scripts/find_btt_base.sh" nowplaying_volume_notch 2>/dev/null || true)
  if [[ -n "$base" ]]; then
    /usr/bin/curl -fsS --max-time 1 "$base/trigger_named_async_without_response/?trigger_name=nowplaying_refresh" >/dev/null 2>&1 || true
  fi
fi

# The command has just changed selection/playback. Refresh the cheap inventory
# out of band; metadata refresh remains independently signal-driven above.
"$root/refresh_browser_cache.sh" >/dev/null 2>&1 &

exit 0
