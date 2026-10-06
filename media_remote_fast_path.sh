#!/bin/zsh

set -u

root="${NOWPLAYING_ROOT:-$HOME/NowPlaying}"
cache="$root/cache"
state_file="$cache/btt-media-state.json"
lock_dir="$cache/btt-media-state.lock"
mkdir -p "$cache"
mkdir "$lock_dir" 2>/dev/null || exit 0
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT

configured_url="${HA_API_URL:-}"
configured_source="${SOURCE_DEVICE:-}"
if [[ -f "$root/config.local.sh" ]]; then
    source "$root/config.local.sh"
fi
[[ -n "$configured_url" ]] && HA_API_URL="$configured_url"
[[ -n "$configured_source" ]] && SOURCE_DEVICE="$configured_source"

info="${BTT_NOWPLAYING_INFO_JSON:-}"
if [[ -z "$info" ]]; then
    info=$(/usr/bin/osascript -e \
        'tell application "BetterTouchTool" to get_string_variable "BTTNowPlayingInfoSequoia"' \
        2>/dev/null)
fi

row=$(print -r -- "$info" | /usr/bin/jq -r '
    if (.isPlaying | type) != "boolean" then empty else
    [
      (.isPlaying | tostring),
      (.title // ""),
      (.artist // ""),
      (.album // ""),
      (.appName // ""),
      (.bundleIdentifier // ""),
      (.parentBundleIdentifier // ""),
      ((.duration // 0) | tonumber? // 0 | floor | tostring)
    ]
    | map(tostring | gsub("[\r\n]"; " ") | gsub("\u001f"; " "))
    | join("\u001f") end
' 2>/dev/null)
[[ -n "$row" ]] || exit 0

IFS=$'\x1f' read -r playing title artist album app_name bundle_id parent_bundle_id duration_sec <<< "$row"
previous=$(/usr/bin/jq -r '.is_playing // empty' "$state_file" 2>/dev/null)
[[ "$playing" != "$previous" ]] || exit 0

observed_at=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')
temporary="${state_file}.$$"
/usr/bin/jq -n --argjson is_playing "$playing" --arg observed_at "$observed_at" \
    '{is_playing:$is_playing,observed_at:$observed_at}' > "$temporary" || exit 0
/bin/mv "$temporary" "$state_file"

# Wake the full scanner immediately. Its authoritative payload will replace the
# provisional MediaRemote payload below as soon as source discovery completes.
if [[ "${NOWPLAYING_DISABLE_SIGNAL:-false}" != "true" ]]; then
    pid=$(/usr/bin/jq -r '.pid // empty' "$root/cache/nowplaying.lock/lock.json" 2>/dev/null)
    if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
        pid=$(cat "$root/cache/nowplaying.lock/pid" 2>/dev/null)
    fi
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
        kill -USR1 "$pid" 2>/dev/null || true
    fi
fi

[[ -n "${HA_API_URL:-}" ]] || exit 0

effective_bundle_id="${parent_bundle_id:-$bundle_id}"
case "$effective_bundle_id" in
    com.apple.Music)
        media_source="music"
        music_playing=true
        video_playing=false
        ;;
    org.videolan.vlc|org.videolan.vlc*)
        media_source="vlc"
        music_playing=false
        video_playing=true
        ;;
    com.apple.Safari|com.google.Chrome|com.google.Chrome.*)
        media_source="browser"
        music_playing=false
        video_playing=true
        ;;
    *)
        media_source="mediaremote"
        music_playing=false
        video_playing=true
        ;;
esac

if [[ "$playing" == "true" ]]; then
    media_status="Playing"
    [[ -n "$title" ]] || title="Loading media…"
    [[ -n "$artist" ]] || artist="${app_name:-Detecting source…}"
else
    media_status="Paused"
    video_playing=false
fi
[[ -n "$album" ]] || album="$app_name"

if [[ ! "$duration_sec" =~ ^[0-9]+$ ]]; then
    duration_sec=0
fi
printf -v duration_hms '%02d:%02d' $(( duration_sec / 60 )) $(( duration_sec % 60 ))
source_device="${SOURCE_DEVICE:-$(/usr/sbin/scutil --get ComputerName 2>/dev/null || /bin/hostname -s)}"
event_id="${source_device}-mediaremote-$(/usr/bin/python3 -c 'import time; print(int(time.time() * 1000))')"
volume_percent=$(/usr/bin/osascript -e 'output volume of (get volume settings)' 2>/dev/null || printf '0')

payload=$(/usr/bin/jq -n \
    --argjson schema_version 2 \
    --arg event_id "$event_id" \
    --arg source_device "$source_device" \
    --arg sent_at "$observed_at" \
    --arg media_status "$media_status" \
    --arg media_source "$media_source" \
    --arg track "$title" \
    --arg artist "$artist" \
    --arg album "$album" \
    --arg duration "$duration_hms" \
    --argjson video_duration "$duration_sec" \
    --argjson volume_percent "${volume_percent:-0}" \
    --argjson video_playing "$video_playing" \
    --argjson music_app_playing "$music_playing" '
    {
      schema_version:$schema_version,
      event_id:$event_id,
      source_device:$source_device,
      sent_at:$sent_at,
      provisional:true,
      media_status:$media_status,
      media_source:$media_source,
      track:$track,
      artist:$artist,
      album:$album,
      summary:"",
      description:"",
      genre:"",
      year:"",
      currentTime:"00:00",
      duration:$duration,
      playback_position_percent:0,
      volume_percent:$volume_percent,
      playback_speed:"1.0",
      youtube_playing:false,
      video_playing:$video_playing,
      music_app_playing:$music_app_playing,
      idle_duration:0,
      video_duration:$video_duration,
      playlist:"",
      progress_bar_full:"",
      url:"",
      video_id:"",
      thumbnail:"",
      artwork_version:"",
      youtube_queue:[],
      youtube_queue_json:"{\"items\":[]}"
    }')

if [[ -n "${NOWPLAYING_PAYLOAD_FILE:-}" ]]; then
    print -r -- "$payload" > "$NOWPLAYING_PAYLOAD_FILE"
    exit 0
fi

/usr/bin/curl -sS --connect-timeout 1 --max-time 3 \
    -o /dev/null -X POST -H 'Content-Type: application/json' \
    -d "$payload" "$HA_API_URL" || true
