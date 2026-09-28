#!/usr/bin/env bash

# ============================================================
# NagMenu NowPlaying
# ============================================================

set -u

debug_mode="false"
# debug_mode="true"
# if debug true, replace debug with echo, otherwise nothing
debugecho() { [[ "${debug_mode:-false}" == "true" ]] && echo "$@"; }

#if debug false, do the command, otherwise nothing
nodebug() { [[ "${debug_mode:-false}" != "true" ]] && "$@"; }
DEBUG_DIR="/tmp/nowplaying-debug"
mkdir -p "$DEBUG_DIR"
export JQ_COLORS="0"


trap 'echo "Received termination signal, exiting..."; exit 0' SIGTERM SIGINT

echo "Starting*** NagMenu NowPlaying ***"
sleep 0.7
# ============================================================
# Paths & Environment
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NOWPLAYING_ROOT="$SCRIPT_DIR"

CACHE_ROOT="$NOWPLAYING_ROOT/cache"
SSH_ROOT="$NOWPLAYING_ROOT/ssh"

DEFAULT_ARTWORK="$NOWPLAYING_ROOT/default_music.jpg"
MUSIC_ART_CACHE="$CACHE_ROOT/music_artwork"


mkdir -p "$CACHE_ROOT" "$SSH_ROOT" "$MUSIC_ART_CACHE"


# ============================================================
# Home Assistant / Network
# ============================================================

# Local configuration is intentionally excluded from Git.
CONFIG_FILE="${NOWPLAYING_CONFIG:-$NOWPLAYING_ROOT/config.local.sh}"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Missing $CONFIG_FILE. Copy config.example.sh and fill in this Mac's settings." >&2
    exit 1
fi
source "$CONFIG_FILE"
SSH_KEY="${SSH_KEY:-$SSH_ROOT/id_ecdsa_ha}"
: "${HA_SERVER:?Set HA_SERVER in config.local.sh}"
: "${HA_API_URL:?Set HA_API_URL in config.local.sh}"
: "${HA_BASE_URL:?Set HA_BASE_URL in config.local.sh}"
: "${HA_AUDIO_ENTITY:?Set HA_AUDIO_ENTITY in config.local.sh}"
: "${BEARER_TOKEN:?Set BEARER_TOKEN in config.local.sh}"
export OMDB_API_KEY="${OMDB_API_KEY:-}"
for dependency in jq python3 curl osascript; do
    command -v "$dependency" >/dev/null || { echo "Missing dependency: $dependency" >&2; exit 1; }
done


# ============================================================
# Timing & Thresholds
# ============================================================

TRACK_CHECK_INTERVAL=3.8
PAUSED_WINDOW_SEC=10

# ============================================================
# Derived Media State (single source of truth)
# ============================================================

media_status="Idle"          # Music | YouTube | Paused | Idle
music_playing="false"         # "true" | "false"
youtube_playing="false"      # "true" | "false"
idle_start_epoch=""
idle_duration=0
last_active_timestamp=0
last_status="unknown"

# ============================================================
# Media Metadata (current frame)
# ============================================================

track="startup"
artist="startup"
album="startup"
genre="startup"
year="startup"
thumbnail_url="/local/default_music.jpg"
duration="00:00"
duration_sec=0
currentTime=0
currentTimehms="00:00"
video_duration=0
playback_speed="1.0"
playback_position_percent=0
progress_bar_full=""
description="startup"
playlist_name=""
video_id=""
url=""

# ============================================================
# Persistence / Counters
# ============================================================

youtube_video_count=0
high_score=0
last_sent_video_id=""
last_thumbnail_url=""
last_sent_current_time=0
last_known_track=""
last_known_artist=""
last_known_album=""
last_known_music_active="false"
last_known_youtube_active="false"
last_known_description=""

# ============================================================
# CoreAudio State
# ============================================================

core_audio_label="Idle"       # Active | Idle
last_core_audio_label=""
core_audio=""
cpu_usage=0.0

# ============================================================
# Artwork State
# ============================================================

last_music_artwork_hash=""

# ============================================================
# Clean up cache
# ============================================================
last_cache_cleanup=0
CACHE_CLEANUP_INTERVAL=3600 


# to print metacharacters properly in shell mode
cecho() {
    printf '%b\n' "$1"
}


cleanup_cache() {
    # Remove ALL cached files older than 24 hours (artwork included)
    find "$CACHE_ROOT" -type f -mtime +1 -delete 2>/dev/null
}

#  Function: Download YouTube thumbnail (input the video_id, not full URL)
download_youtube_thumbnail() {
    video_id="$1"
    temp_file="/tmp/youtube_artwork.jpg"
    fallback="$NOWPLAYING_ROOT/default_music.jpg"

    declare -a urls=(
        "https://img.youtube.com/vi/${video_id}/maxresdefault.jpg"
        "https://img.youtube.com/vi/${video_id}/sddefault.jpg"
        "https://img.youtube.com/vi/${video_id}/hqdefault.jpg"
    )

    for u in "${urls[@]}"; do
        curl -s "$u" -o "$temp_file"

        # file must exist and be larger than placeholder
        if [[ -s "$temp_file" ]]; then
            size=$(stat -f%z "$temp_file")

            # real thumbnails are > 15 KB
            if (( size > 15000 )); then
                scp -q -i "$SSH_KEY" -o IdentitiesOnly=yes \
                    "$temp_file" "$HA_SERVER:/config/www/nowplaying/artwork.jpg"
                return 0
            fi
        fi

        sleep 0.15
    done

    # fallback artwork
    cp "$fallback" "$temp_file"
    scp -q -i "$SSH_KEY" -o IdentitiesOnly=yes \
        "$temp_file" "$HA_SERVER:/config/www/nowplaying/artwork.jpg"
}
download_generic_artwork() {
    local image_url="$1"
    local temp_file="/tmp/nowplaying_generic_artwork.jpg"

    [[ -z "$image_url" ]] && return 1

    curl -L -s --fail "$image_url" -o "$temp_file" || return 1
    [[ -s "$temp_file" ]] || return 1

    scp -q -i "$SSH_KEY" -o IdentitiesOnly=yes \
        "$temp_file" "$HA_SERVER:/config/www/nowplaying/artwork.jpg"
}
get_music_artwork() {
	local temp_file="/tmp/music_artwork.jpg"   # keep /tmp (fast + local)
	local default_art="$DEFAULT_ARTWORK"
	local cache_dir="$MUSIC_ART_CACHE"
    mkdir -p "$cache_dir"

    local metadata
    metadata=$(osascript <<'EOF'
tell application "Music"
    if player state is not stopped then
        return (artist of current track) & " -|- " & (name of current track)
    else
        return ""
    end if
end tell
EOF
    )

    local artist="" track=""
    if [[ -n "$metadata" ]]; then
        artist="${metadata%% -|- *}"
        track="${metadata##* -|- }"
    fi

    # ------------------------------------------------------------
    # 2) Cache lookup
    local cache_file=""
    if [[ -n "$artist" && -n "$track" ]]; then
        local cache_key
        cache_key=$(printf "%s|%s" "$artist" "$track" | shasum | awk '{print $1}')
        cache_file="$cache_dir/$cache_key.jpg"

        if [[ -s "$cache_file" ]]; then
            cp "$cache_file" "$temp_file"
            echo "$temp_file"
            return 0
        fi
    fi

    # ------------------------------------------------------------
    # 3) AppleScript embedded artwork (best effort)
    local result
    result=$(osascript <<'EOF'
tell application "Music"
    try
        if player state is not stopped and (count of artworks of current track) > 0 then
            set outFilePOSIX to "/tmp/music_artwork.jpg"
            set artData to data of artwork 1 of current track
            set f to open for access (POSIX file outFilePOSIX) with write permission
            set eof f to 0
            write artData to f
            close access f
            return outFilePOSIX
        end if
    end try
    return ""
end tell
EOF
    )

    if [[ -n "$result" && -s "$result" ]]; then
        [[ -n "$cache_file" ]] && cp "$result" "$cache_file"
        echo "$temp_file"
        return 0
    fi

    # ------------------------------------------------------------
    # 4) Sanitize track for API search
    local clean_track="$track"
    clean_track="$(printf "%s" "$clean_track" | sed -E '
        s/[[:space:]]*\[[^]]*\]//g;
        s/[[:space:]]*\([^)]*\)//g;
        s/[[:space:]]+/ /g;
        s/^ //; s/ $//
    ')"

    # ------------------------------------------------------------
    # 5) iTunes Search API (jq-based, reliable)
    if [[ -n "$artist" && -n "$clean_track" ]]; then
        local itunes_json itunes_url
        itunes_json=$(curl -s --get \
            --data-urlencode "term=${artist} ${clean_track}" \
            --data "media=music&entity=song&limit=1" \
            https://itunes.apple.com/search)

        itunes_url=$(printf "%s" "$itunes_json" | jq -r '
            if .resultCount > 0 and .results[0].artworkUrl100 then
                .results[0].artworkUrl100
                | sub("100x100bb"; "600x600bb")
            else
                empty
            end
        ')

        if [[ -n "$itunes_url" ]]; then
            curl -s "$itunes_url" -o "$temp_file"
            if [[ -s "$temp_file" ]]; then
                [[ -n "$cache_file" ]] && cp "$temp_file" "$cache_file"
                echo "$temp_file"
                return 0
            fi
        fi
    fi

    # ------------------------------------------------------------
    # 6) MusicBrainz + Cover Art Archive (last resort)
    if [[ -n "$artist" && -n "$clean_track" ]]; then
        local mb_json release_id
        mb_json=$(curl -s \
          "https://musicbrainz.org/ws/2/recording/?query=artist:${artist// /%20}%20${clean_track// /%20}&fmt=json&limit=1")

        release_id=$(printf "%s" "$mb_json" | jq -r '
            .recordings[0].releases[0].id // empty
        ')

        if [[ -n "$release_id" ]]; then
            curl -s \
              "https://coverartarchive.org/release/$release_id/front-500" \
              -o "$temp_file"

            if [[ -s "$temp_file" ]]; then
                [[ -n "$cache_file" ]] && cp "$temp_file" "$cache_file"
                echo "$temp_file"
                return 0
            fi
        fi
    fi

    # ------------------------------------------------------------
    # 7) Fallback
    cp "$default_art" "$temp_file"
    echo "$temp_file"
    return 0
}


# ============================================================
# SENSOR LAYER — Music.app
# ============================================================
read_music_sensor() {
osascript <<'EOF'
on escape_text(t)
	if t is missing value then return ""
	set s to t as string
	set Q to quote
	set s to my replace_chars(s, Q, "'")
	set s to my replace_chars(s, return, "")
	set s to my replace_chars(s, linefeed, "")
	return s
end escape_text

on replace_chars(this_text, search_string, replacement_string)
	set AppleScript's text item delimiters to search_string
	set the item_list to every text item of this_text
	set AppleScript's text item delimiters to replacement_string
	set this_text to the item_list as string
	set AppleScript's text item delimiters to ""
	return this_text
end replace_chars

with timeout of 5 seconds
	set Q to quote
	
	tell application "System Events"
		if not (exists process "Music") then
			return "{" & Q & "playing" & Q & ": false}"
		end if
	end tell
	
	tell application "Music"
		if player state is not playing then
			return "{" & Q & "playing" & Q & ": false}"
		end if
		
		set trackName to name of current track
		set trackArtist to artist of current track
		set trackAlbum to album of current track
		set trackGenre to genre of current track
		try
			set trackYear to year of current track
		on error
			set trackYear to 0
		end try
		
		set trackDuration to duration of current track
		set trackPosition to player position
	end tell
	
	set trackName to escape_text(trackName)
	set trackArtist to escape_text(trackArtist)
	set trackAlbum to escape_text(trackAlbum)
	set trackGenre to escape_text(trackGenre)
	
	set json to "{"
	set json to json & Q & "playing" & Q & ": true,"
	set json to json & Q & "track" & Q & ": " & Q & trackName & Q & ","
	set json to json & Q & "artist" & Q & ": " & Q & trackArtist & Q & ","
	set json to json & Q & "album" & Q & ": " & Q & trackAlbum & Q & ","
	set json to json & Q & "genre" & Q & ": " & Q & trackGenre & Q & ","
	set json to json & Q & "year" & Q & ": " & trackYear & ","
	set json to json & Q & "duration" & Q & ": " & trackDuration & ","
	set json to json & Q & "position" & Q & ": " & trackPosition
	set json to json & "}"
	return json
end timeout
EOF
}

# ============================================================
# SENSOR LAYER — CoreAudio
# ============================================================

read_coreaudio_sensor() {
    local pmset_active cpu

    if pmset -g assertions | grep -q "coreaudiod"; then
        pmset_active=1
    else
        pmset_active=0
    fi

    cpu=$(ps -A -o %cpu,comm 2>/dev/null | awk '/coreaudiod/ {print $1; exit}')
    cpu="${cpu:-0}"

    echo "${pmset_active}|${cpu}"
}

# ============================================================
# SECTION C Normalization and derived state
# ============================================================

STATE_FILE="$NOWPLAYING_ROOT/nowplaying_state.json"
read_json() {
    local key="$1"
    [[ -f "$STATE_FILE" ]] || echo "{}" > "$STATE_FILE"

    jq -r --arg k "$key" '.[$k] // empty' "$STATE_FILE" 2>/dev/null || echo ""
}

update_json() {
    local key="$1"
    local value="$2"
    [[ -f "$STATE_FILE" ]] || echo "{}" > "$STATE_FILE"

    tmp=$(mktemp)
    jq --arg k "$key" --arg v "$value" '.[$k]=$v' "$STATE_FILE" 2>/dev/null > "$tmp" \
        && mv "$tmp" "$STATE_FILE" || rm -f "$tmp"
}
binge_watch_tracker() {
    # --- Load persisted values once ---
    last_video_id=$(read_json "last_video_id")
    youtube_video_count=$(read_json "youtube_video_count")
    high_score=$(read_json "high_score")
    last_video_timestamp=$(read_json "last_video_timestamp")

    current_timestamp=$(date +%s)


    # --- Default fallback if corrupted/empty timestamp ---
    [[ "$last_video_timestamp" =~ ^[0-9]+$ ]] || last_video_timestamp=0

    # --- Reset streak if idle for 1hr (in secs) ---
    if (( current_timestamp - last_video_timestamp > 3600 )); then
        youtube_video_count=0
        update_json "youtube_video_count" "$youtube_video_count"
    fi

    # --- Only count if: new video + 20% watched + at least 30 seconds ---
    if [[ -n "$video_id" &&
          "$video_id" != "$last_video_id" &&
		  "$playback_position_percent" -gt 20 &&
          "$currentTime" -ge 30 ]]; then

        youtube_video_count=$((youtube_video_count + 1))

        update_json "youtube_video_count" "$youtube_video_count"
        update_json "last_video_timestamp" "$current_timestamp"
        update_json "last_video_id" "$video_id"

        if (( youtube_video_count > high_score )); then
            high_score="$youtube_video_count"
            update_json "high_score" "$high_score"
        fi
    fi
}

build_progress_bar() {
    local percent="$1"
    local bar_len=54

    percent=$(safe_int "$percent")
    (( percent < 0 )) && percent=0
    (( percent > 100 )) && percent=100

    local filled=$(( bar_len * percent / 100 ))
    local empty=$(( bar_len - filled ))

    local filled_bar empty_bar
    filled_bar=$(printf "%-${filled}s" "" | tr ' ' '*')
    empty_bar=$(printf "%-${empty}s" "")

    if (( filled > 0 )); then
        progress_bar_full="  [\033[31m${filled_bar}\033[0m ${percent}% ${empty_bar}]"
    else
        progress_bar_full="  [${filled_bar} ${percent}% ${empty_bar}]"
    fi
}
epoch_now() {
    date +%s
}

safe_int() {
    [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo 0
}

safe_bool() {
    case "$1" in
        true|TRUE|1) echo "true" ;;
        *)           echo "false" ;;
    esac
}
# ============================================================
# jq helpers (prevents fatal parse errors on bad frames)
# ============================================================

jq_try() {
    # Usage: jq_try '<filter>' '<json>' '<fallback>'
    # Returns fallback if jq fails for any reason.
    local filter="$1"
    local json="$2"
    local fallback="${3:-}"

    # quick sanity gate: must look like JSON object
    if [[ -z "$json" || "$json" != \{* ]]; then
        printf '%s' "$fallback"
        return 0
    fi

    local out
    out=$(jq -r "$filter" <<<"$json" 2>/dev/null) || {
        printf '%s' "$fallback"
        return 0
    }
    printf '%s' "$out"
}

jq_bool() {
    # Normalizes to "true"/"false"
    local v="$1"
    case "$v" in
        true|TRUE|1) echo "true" ;;
        *)           echo "false" ;;
    esac
}
update_idle_timer() {
    local now
    now=$(epoch_now)

    # Treat Paused as idle for timing purposes
    if [[ "$media_status" == "Idle" || "$media_status" == "Paused" ]]; then
        if [[ -z "$idle_start_epoch" ]]; then
            idle_start_epoch="$now"
        fi
        idle_duration=$(( now - idle_start_epoch ))
    else
        # Only reset when actively playing
        idle_start_epoch=""
        idle_duration=0
        last_active_timestamp="$now"
    fi
}

resolve_media_status() {

    if [[ "$music_playing" == "true" ]]; then
        media_status="Music"
        return
    fi

    if [[ "$youtube_playing" == "true" ]]; then
        media_status="YouTube"
        return
    fi

    if [[ -n "$last_known_track" && "$idle_duration" -lt "$PAUSED_WINDOW_SEC" ]]; then
        media_status="Paused"
        return
    fi

    media_status="Idle"
}

snapshot_last_known_media() {
    last_known_track="$track"
    last_known_artist="$artist"
    last_known_album="$album"
    last_known_description="$description"
    last_known_music_active="$music_playing"
    last_known_youtube_active="$youtube_playing"
}

update_coreaudio_label() {
    local sensor pmset cpu

    sensor=$(read_coreaudio_sensor)
    pmset="${sensor%%|*}"
    cpu="${sensor##*|}"

    if [[ "$music_playing" == "true" || "$youtube_playing" == "true" ]]; then
        core_audio_label="Active"
    else
        core_audio_label="Idle"
    fi

    cpu_usage=$(printf "%.1f" "$cpu")
    core_audio="${core_audio_label} (pmset=${pmset} | CPU=${cpu_usage}%)"
}
refresh_ha_core_audio_state() {
    local now_epoch
    now_epoch=$(date +%s)

    core_audio_service=""

    # --------------------------------------------------
    # Media is the ONLY source of truth
    # --------------------------------------------------
    if [[ "$music_playing" == "true" || "$youtube_playing" == "true" ]]; then
		debugecho "DEBUG Something is playing. Music: $music_playing Youtube: $youtube_playing"
        core_audio_label="Active"
    else
		debugecho "DEBUG Nothing is playing. Music: $music_playing Youtube: $youtube_playing"
	    core_audio_label="Idle"
    fi

    # --------------------------------------------------
    # Idle tracking (debug / display only)
    # --------------------------------------------------
    if [[ "$core_audio_label" == "Idle" ]]; then
        if [[ -z "$idle_start_epoch" ]]; then
            idle_start_epoch="$now_epoch"
        fi
        idle_duration=$(( now_epoch - idle_start_epoch ))
    else
        idle_start_epoch=""
        idle_duration=0
    fi

    # --------------------------------------------------
    # Decide HA action (EDGE TRIGGERED)
    # --------------------------------------------------
    if [[ "$core_audio_label" != "$last_core_audio_label" ]]; then
        last_core_audio_label="$core_audio_label"

        if [[ "$core_audio_label" == "Active" ]]; then
            core_audio_service="turn_on"
        else
            core_audio_service="turn_off"
        fi
    fi
	debugecho "DEBUG Decided what to tell HA. $core_audio_service "
    # --------------------------------------------------
    # Debug string
    # --------------------------------------------------
    debugecho "DEBUG Getting coreaudiod"
	if pmset -g assertions | grep -q "coreaudiod"; then
        pmset_active=1
    else
        pmset_active=0
    fi

    debugecho "DEBUG Getting CPU Usage"
    cpu_usage=$(ps -A -o %cpu,comm 2>/dev/null | awk '/coreaudiod/ {print $1; exit}')
    cpu_str=$(printf "%.1f" "${cpu_usage:-0}")

    core_audio="${core_audio_label} (pmset=${pmset_active} | CPU=${cpu_str}%)"

    # --------------------------------------------------
    # Fire HA service immediately if needed
    # --------------------------------------------------
    [[ -z "$core_audio_service" ]] && return
	debugecho "DEBUG Updating HA core audio state"
    curl -s -o /dev/null --fail \
      -H "Authorization: Bearer $BEARER_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$(jq -nc --arg entity "$HA_AUDIO_ENTITY" '{entity_id: $entity}')" \
      "${HA_BASE_URL%/}/api/services/input_boolean/${core_audio_service}"
}


normalize_state() {
    # Sanitize booleans
    music_playing=$(safe_bool "$music_playing")
    youtube_playing=$(safe_bool "$youtube_playing")

    # Update idle tracking
    update_idle_timer

    # Resolve media status
    resolve_media_status

    # Update CoreAudio label
    update_coreaudio_label
}

# ============================================================
# SECTION D — Transition & Emission Logic
# ============================================================

# Tracks last emitted semantic state (not raw media_status)
last_emitted_state=""

# Tracks last emitted idle bucket
last_idle_bucket=""

# ------------------------------------------------------------
# Helper: classify idle into buckets
# ------------------------------------------------------------
idle_bucket() {
    local d
    d=$(safe_int "$idle_duration")

    if (( d < PAUSED_WINDOW_SEC )); then
        echo "early"
    elif (( d < 60 )); then
        echo "paused"
    else
        echo "long"
    fi
}

# ------------------------------------------------------------
# Decide whether to emit an update this cycle
# ------------------------------------------------------------
should_emit() {

    local current_bucket
    current_bucket=$(idle_bucket)

    # --------------------------------------------------------
    # 1. ACTIVE MEDIA — always emit
    # --------------------------------------------------------
    if [[ "$media_status" == "Music" || "$media_status" == "YouTube" ]]; then
        last_emitted_state="$media_status"
        last_idle_bucket=""
        return 0
    fi

    # --------------------------------------------------------
    # 2. TRANSITION: Active → Paused
    # --------------------------------------------------------
	# 2. Paused — never emit to HA
	if [[ "$media_status" == "Paused" ]]; then
	    last_emitted_state="Paused"
	    return 1
	fi
    # --------------------------------------------------------
    # 3. TRANSITION: Paused → Idle (first frame)
    # --------------------------------------------------------
    if [[ "$media_status" == "Idle" && "$last_emitted_state" != "Idle" ]]; then
        last_emitted_state="Idle"
        last_idle_bucket="$current_bucket"
        return 0
    fi

    # --------------------------------------------------------
    # 4. Idle escalation (Paused → Long Idle)
    # --------------------------------------------------------
    if [[ "$media_status" == "Idle" && "$current_bucket" != "$last_idle_bucket" ]]; then
        last_idle_bucket="$current_bucket"

        # Only emit when entering long idle
        if [[ "$current_bucket" == "long" ]]; then
            return 0
        fi
    fi

    # --------------------------------------------------------
    # 5. Otherwise suppress
    # --------------------------------------------------------
    return 1
}

# ============================================================
# SECTION E — Effects Layer
# ============================================================

# ------------------------------------------------------------
# Home Assistant timing
# ------------------------------------------------------------
last_ha_update_time_utc=""
last_ha_update_time_local=""


# ------------------------------------------------------------
# Artwork handling
# ------------------------------------------------------------
emit_artwork() {
    # YouTube / VLC artwork (video/poster change only)
    if [[ "$youtube_playing" == "true" ]]; then
        if [[ -n "$thumbnail_url" ]]; then
            if [[ "$thumbnail_url" != "$last_thumbnail_url" ]]; then
                if [[ "$thumbnail_url" == https://img.youtube.com/* && -n "$video_id" ]]; then
                    debugecho "DEBUG Emitting Youtube Artwork"
                    download_youtube_thumbnail "$video_id"
                else
                    debugecho "DEBUG Emitting generic artwork"
                    download_generic_artwork "$thumbnail_url" || true
                fi
                last_sent_video_id="$video_id"
                last_thumbnail_url="$thumbnail_url"
            fi
        elif [[ -n "$video_id" && "$video_id" != "$last_sent_video_id" ]]; then
            debugecho "DEBUG Emitting Youtube Artwork by video_id"
            download_youtube_thumbnail "$video_id"
            last_sent_video_id="$video_id"
        fi
        return
    fi

    # Music artwork (hash-based) track change only
    if [[ "$music_playing" == "true" ]]; then

        local art hash
        art=$(get_music_artwork)
        debugecho "DEBUG Emitting music artwork"
        hash=$(md5 -q "$art" 2>/dev/null)

        if [[ "$hash" != "$last_music_artwork_hash" ]]; then
            scp -i "$SSH_KEY" -o IdentitiesOnly=yes                 "$art" "$HA_SERVER:/config/www/nowplaying/artwork.jpg"
            last_music_artwork_hash="$hash"
        fi
        debugecho "DEBUG Nothing Playing. Not sending Artwork"

    fi
}
# --------------------------------------------------------
# Final sanitation before HA (CRITICAL)
# --------------------------------------------------------
strip_newlines() {
    printf '%s' "$1" | tr -d '\r\n'
}
track=$(strip_newlines "$track")
artist=$(strip_newlines "$artist")
description=$(strip_newlines "$description")
media_status=$(strip_newlines "$media_status")
currentTimehms=$(strip_newlines "$currentTimehms")

# ------------------------------------------------------------
# Home Assistant payload sender
# ------------------------------------------------------------
emit_home_assistant() {
	debugecho "DEBUG Updating HA"
	
  # Make sure numeric-ish values are safe
  idle_duration=$(safe_int "${idle_duration:-0}")
  playback_position_percent=$(safe_int "${playback_position_percent:-0}")
  duration_sec=$(safe_int "${duration_sec:-0}")
  currentTime=$(safe_int "${currentTime:-0}")
  youtube_video_count=$(safe_int "${youtube_video_count:-0}")
  high_score=$(safe_int "${high_score:-0}")

  # Strings (strip newlines so HA templates don’t get weird)
  track=$(strip_newlines "${track:-}")
  artist=$(strip_newlines "${artist:-}")
  album=$(strip_newlines "${album:-}")
  genre=$(strip_newlines "${genre:-}")
  year=$(strip_newlines "${year:-}")
  description=$(strip_newlines "${description:-}")
  media_status=$(strip_newlines "${media_status:-}")
  currentTimehms=$(strip_newlines "${currentTimehms:-00:00}")
  duration_hms=$(strip_newlines "${duration_hms:-00:00}")
  playback_speed=$(strip_newlines "${playback_speed:-1.0}")
  playlist_name=$(strip_newlines "${playlist_name:-}")
  progress_bar_full=$(strip_newlines "${progress_bar_full:-}")
  url=$(strip_newlines "${url:-}")
  video_id=$(strip_newlines "${video_id:-}")
  thumbnail_url=$(strip_newlines "${thumbnail_url:-}")

  # Booleans must be actual JSON booleans
  youtube_playing=$(safe_bool "${youtube_playing:-false}")
  music_playing=$(safe_bool "${music_playing:-false}")

  # Build JSON safely
  payload=$(
    jq -n \
      --arg track "$track" \
      --arg artist "$artist" \
      --arg album "$album" \
      --arg genre "$genre" \
      --arg year "$year" \
      --arg description "$description" \
      --arg media_status "$media_status" \
      --arg currentTime "$currentTimehms" \
      --arg duration "$duration_hms" \
      --arg playback_speed "$playback_speed" \
      --arg playlist "$playlist_name" \
      --arg progress_bar_full "$progress_bar_full" \
      --arg url "$url" \
      --arg video_id "$video_id" \
      --arg thumbnail "$thumbnail_url" \
      --argjson idle_duration "$idle_duration" \
      --argjson playback_position_percent "$playback_position_percent" \
      --argjson youtube_playing "$youtube_playing" \
      --argjson music_app_playing "$music_playing" \
      --argjson total_videos_watched "$youtube_video_count" \
      --argjson high_score "$high_score" \
      --argjson video_duration "$duration_sec" \
      '
      {
        track: $track,
        artist: $artist,
        album: $album,
        genre: $genre,
        year: $year,
        description: $description,
        media_status: $media_status,
        idle_duration: $idle_duration,
        currentTime: $currentTime,
        duration: $duration,
        playback_position_percent: $playback_position_percent,
        playback_speed: $playback_speed,
        youtube_playing: $youtube_playing,
        music_app_playing: $music_app_playing,

        total_videos_watched: $total_videos_watched,
        high_score: $high_score,
        video_duration: $video_duration,

        playlist: ($playlist | if .=="" then "(None)" else . end),
        progress_bar_full: $progress_bar_full,
        url: $url,
        video_id: $video_id,
        thumbnail: $thumbnail
      }'
  )

  # DEBUG prove what you’re sending + what HA returns
  #debugecho "DEBUG HA payload: $payload"

  resp_file="/tmp/nowplaying_ha_resp.txt"
  http_code=$(
    curl -sS -o "$resp_file" -w "%{http_code}" \
      -X POST \
      -H "Content-Type: application/json" \
      -d "$payload" \
      "$HA_API_URL"
  )
 
	  if [[ "$http_code" == "200" ]]; then
	    debugecho "DEBUG HA Result: Success"
	  else
	    debugecho "DEBUG HA Result: Error - $http_code"
	  fi

  last_ha_update_time_utc=$(date -u '+%Y-%m-%dT%H:%M:%S')
  last_ha_update_time_local=$(date '+%H:%M:%S')
}


wrap_two_lines() {
    local text="$1"
    local header="$2"
    local max_len=$((59 - ${#header}))
    local line1=""
    local line2=""

    for word in $text; do
        if [[ ${#line1} -lt $max_len ]]; then
            line1="$line1 $word"
        else
            line2="$line2 $word"
        fi
    done

    # Trim leading spaces
    line1="${line1# }"
    line2="${line2# }"

    printf "%s\n%s" "$line1" "$line2"
}

emit_cli() {

    # Timestamp header: HH:MM:SS.ms (0.1s resolution)
    ts=$(python3 <<'PY'
import datetime, sys
now = datetime.datetime.now()
ms = int(now.microsecond / 100000)
sys.stdout.write(now.strftime('%H:%M:%S.') + str(ms))
PY
)

    # === GUI RENDER (with restored fancy formatting) ===============
	nodebug printf '\e[8;27;76t'
	nodebug printf "\033[H\033[J"

    echo ""
    echo ""
    echo ""

    if [[ "$music_playing" == "true" ]]; then
        echo ""
        echo ""
        echo ""

        echo "  $ts               Now Playing - Music"
        echo "  -------------------------------------------------------------------"
        echo ""
        echo ""
        echo ""
        echo ""
        echo ""
        header="     Track:           "
        wrapped=$(wrap_two_lines "$track" "$header")
        t1=$(echo "$wrapped" | sed -n '1p')
        t2=$(echo "$wrapped" | sed -n '2p')

        cecho "$header\033[1m\033[33m${t1# }\033[0m"
        if [[ -n "$t2" ]]; then
            cecho "                     \033[1m\033[33m${t2# }\033[0m"
        fi

        echo "     Artist:          $artist"
        echo "     Album:           $album"
        echo "     Genre:           $genre"
        echo "     Year:            $year"
        echo "     Duration:        $currentTimehms / $duration_hms"
        echo ""
        cecho "   $progress_bar_full"
        echo ""
        echo ""
        echo ""
        echo ""

    elif [[ "$youtube_playing" == "true" ]]; then
        echo "  $ts               Now Playing - YouTube"
        echo "  -------------------------------------------------------------------"
        echo ""
        title="${track%" - YouTube"}"
        header="     Title:           "
        max_len=$((59 - ${#header}))
        t1=""; t2=""; t3=""; t4=""

        for word in $title; do
            if [[ ${#t1} -lt $max_len ]]; then t1="$t1 $word"; continue; fi
            if [[ ${#t2} -lt $max_len ]]; then t2="$t2 $word"; continue; fi
            if [[ ${#t3} -lt $max_len ]]; then t3="$t3 $word"; continue; fi
            t4="$t4 $word"
        done

        [[ ${#t4} -gt $max_len ]] && t4="${t4:1:$((max_len-3))}..."

		[[ -n "$t1" ]] && printf '%b\n' "${header}\033[1m\033[33m${t1# }\033[0m"
		[[ -n "$t2" ]] && cecho "                      \033[1m\033[33m${t2# }\033[0m"
		[[ -n "$t3" ]] && cecho "                      \033[1m\033[33m${t3# }\033[0m"
		[[ -n "$t4" ]] && cecho "                      \033[1m\033[33m${t4# }\033[0m"

        echo "     Channel:         $artist"
        echo "     Playlist:        $playlist_name"
        echo "     Speed:           ${playback_speed}"
        desc="${description:-$last_known_description}"
        header="     Description:   "
        max_len=$((59 - ${#header}))
        d1=""; d2=""; d3=""; d4=""

        for word in $desc; do
            if [[ ${#d1} -lt $max_len ]]; then d1="$d1 $word"; continue; fi
            if [[ ${#d2} -lt $max_len ]]; then d2="$d2 $word"; continue; fi
            if [[ ${#d3} -lt $max_len ]]; then d3="$d3 $word"; continue; fi
            d4="$d4 $word"
        done

        [[ ${#d4} -gt $max_len ]] && d4="${d4:0:$((max_len-3))}..."
		[[ -n "$d1" ]] && printf '%b\n' "\033[36m$header  ${d1# }\033[0m"
		[[ -n "$d2" ]] && printf '%b\n' "\033[36m                      ${d2# }\033[0m"
		[[ -n "$d3" ]] && printf '%b\n' "\033[36m                      ${d3# }\033[0m"
		[[ -n "$d4" ]] && printf '%b\n' "\033[36m                      ${d4# }\033[0m"

        echo "     Video Binge:     Current score: $youtube_video_count"
        echo "                      High Score: $high_score"
        echo ""
        echo ""
		echo ""
		echo ""
        echo "                            $currentTimehms / $duration_hms"
        cecho "   $progress_bar_full"

    elif [[ "$media_status" == "Paused" ]]; then
        echo ""
        echo ""
        echo "  $ts             Most Recent Media (Paused)"
        echo "  -------------------------------------------------------------------"
        echo ""
        echo ""
        echo ""
        echo ""
        echo ""
        echo "     Status:          PAUSED for $idle_duration sec"
        title="${last_known_track%" - YouTube"}"
        header="     Title:           "
        max_len=$((59 - ${#header}))
        t1=""; t2=""; t3=""; t4=""

        for word in $title; do
            if [[ ${#t1} -lt $max_len ]]; then t1="$t1 $word"; continue; fi
            if [[ ${#t2} -lt $max_len ]]; then t2="$t2 $word"; continue; fi
            if [[ ${#t3} -lt $max_len ]]; then t3="$t3 $word"; continue; fi
            t4="$t4 $word"
        done

        [[ ${#t4} -gt $max_len ]] && t4="${t4:1:$((max_len-3))}..."

		[[ -n "$t1" ]] && printf '%b\n' "${header}\033[1m\033[33m${t1# }\033[0m"
		[[ -n "$t2" ]] && printf '%b\n' "                      \033[1m\033[33m${t2# }\033[0m"
		[[ -n "$t3" ]] && printf '%b\n' "                      \033[1m\033[33m${t3# }\033[0m"
		[[ -n "$t4" ]] && printf '%b\n' "                      \033[1m\033[33m${t4# }\033[0m"
		
        echo "     Artist:          $last_known_artist"
        echo "     Source:          $( [[ "$last_known_youtube_active" == "true" ]] && echo "YouTube" || echo "Music" )"
        echo ""
        echo ""
        echo ""
        echo ""
        echo ""
        echo ""

    else
        idle_hhmm="--:--"
        [[ -n "$idle_start_epoch" ]] && idle_hhmm=$(date -r "$idle_start_epoch" "+%H:%M")

        echo ""
        echo ""
        echo "  $ts          Media: Idle"
        echo "  -------------------------------------------------------------------"
        echo ""
        echo ""
        echo ""
        echo ""
        echo ""
        echo ""
        echo ""
        echo "                 Idle - since $idle_hhmm "
        echo ""
        echo ""
        echo ""
        echo ""
        echo ""
        echo ""
        echo ""
    fi

    echo "  -------------------------------------------------------------------"
    echo "         Audio Status:  $core_audio"
    echo "         Last HA Update Time: $last_ha_update_time_local"
    echo ""
}

# ------------------------------------------------------------
# Unified effect entrypoint
# ------------------------------------------------------------
emit_outputs() {
	debugecho "DEBUG Sending outputs."

	# Restore description if paused or idle
	if [[ -z "$description" && -n "$last_known_description" ]]; then
	    description="$last_known_description"
	fi
    if should_emit; then
        emit_artwork
        emit_home_assistant
    fi
debugecho "DEBUG Updating CLI"
    emit_cli
}

# ============================================================
# SECTION F — Main Loop / Orchestrator
# ============================================================

# ------------------------------------------------------------
# Initialization
# ------------------------------------------------------------


echo "NowPlaying loop started."
echo ""

# ------------------------------------------------------------
# Main loop
# ------------------------------------------------------------
while true; do

    # --------------------------------------------------------
    # SENSOR READ — Music.app
    # --------------------------------------------------------
	debugecho "DEBUG Checking music.. "
	music_json=$(read_music_sensor)
	music_playing=$(jq_try '.playing // false' "$music_json" "false")
	music_playing=$(jq_bool "$music_playing")
	debugecho "DEBUG Done checking music."
	
	if [[ "$music_playing" == "true" ]]; then
	    track=$(strip_newlines "$(jq_try '.track // ""' "$music_json" "")")
	    artist=$(strip_newlines "$(jq_try '.artist // ""' "$music_json" "")")
	    album=$(strip_newlines "$(jq_try '.album // ""' "$music_json" "")")
	    genre=$(strip_newlines "$(jq_try '.genre // ""' "$music_json" "")")
	    year=$(strip_newlines "$(jq_try '.year // ""' "$music_json" "")")

	    duration_sec=$(jq_try '(.duration // 0) | tonumber? // 0 | floor' "$music_json" "0")
	    currentTime=$(jq_try '(.position // 0) | tonumber? // 0 | floor' "$music_json" "0")

	    description=""
	    url=""
	    video_id=""
	    thumbnail_url=""

	    debugecho "DEBUG Music playing track=$track"
	    debugecho "DEBUG Music playing artist=$artist"
	else
	    debugecho "DEBUG Music not playing."
	fi

    # --------------------------------------------------------
    # SENSOR READ — Safari / YouTube / VLC
    # --------------------------------------------------------
    debugecho "DEBUG Checking Youtube..."
    safari_json=$(osascript "$NOWPLAYING_ROOT/safari_youtube_nowplaying.applescript" 2>/dev/null)
    safari_playing=$(jq_bool "$(jq_try '.playing // false' "$safari_json" "false")")

    youtube_json="$safari_json"
    youtube_playing="$safari_playing"

    if [[ "$youtube_playing" != "true" ]]; then
        debugecho "DEBUG Checking VLC..."
        vlc_json=$(osascript "$NOWPLAYING_ROOT/VLC_nowplaying.applescript" 2>/dev/null)
        vlc_playing=$(jq_bool "$(jq_try '.playing // false' "$vlc_json" "false")")
        if [[ "$vlc_playing" == "true" ]]; then
            youtube_json="$vlc_json"
            youtube_playing="true"
        fi
    fi

    debugecho "DEBUG Done checking video source. youtube_playing=$youtube_playing"

    if [[ "$youtube_playing" == "true" ]]; then
      track=$(strip_newlines "$(jq_try '.title // .track // .parsed_title // .raw_name // ""' "$youtube_json" "")")
      artist=$(strip_newlines "$(jq_try '.channel // .artist // .director // "VLC"' "$youtube_json" "")")
      album=$(strip_newlines "$(jq_try '.album // .writer // ""' "$youtube_json" "")")
      genre=$(strip_newlines "$(jq_try '.genre // ""' "$youtube_json" "")")
      year=$(strip_newlines "$(jq_try '.year // .parsed_year // ""' "$youtube_json" "")")
      description=$(strip_newlines "$(jq_try '.description // .plot // ""' "$youtube_json" "")")

      playback_speed=$(jq_try '.playbackRate // .playback_speed // 1.0' "$youtube_json" "1.0")

      duration_sec=$(jq_try '(
          .video_duration // .duration_sec // .duration // 0
        ) | tonumber? // 0 | floor' "$youtube_json" "0")

      currentTime=$(jq_try '(
          .currentTime // .current_time // .position // 0
        ) | tonumber? // 0 | floor' "$youtube_json" "0")

      url=$(jq_try '.url // .media_path // ""' "$youtube_json" "")
      video_id=$(jq_try '.video_id // .videoId // .id // .imdbID // ""' "$youtube_json" "")
      thumbnail_url=$(jq_try '.thumbnail // .thumbnail_url // .poster // ""' "$youtube_json" "")
      playlist_name=$(jq_try '.playlist // .playlist_name // ""' "$youtube_json" "")
      debugecho "DEBUG Video source url = $url"
      debugecho "DEBUG Video source id = $video_id"
      debugecho "DEBUG Video source thumbnail = $thumbnail_url"
    else
      url=""
      video_id=""
      thumbnail_url=""
      playlist_name=""
      debugecho "DEBUG Video source not playing."
    fi

    debugecho "DEBUG Done getting Music, Youtube info."
	# --------------------------------------------------------
	# DERIVED TIME FORMATS
	# --------------------------------------------------------
	currentTime=$(safe_int "$currentTime")
	duration_sec=$(safe_int "$duration_sec")

	if (( duration_sec > 0 )); then
		debugecho "DEBUG Binge info: vid='${video_id:-}' last='${last_video_id:-}' pct=${playback_position_percent:-0} t=${currentTime:-0} dur=${duration_sec:-0}"
	    playback_position_percent=$(( currentTime * 100 / duration_sec ))
	else
	    playback_position_percent=0
	fi
	
	# BINGE WATCH TRACKING (YouTube only)


	if [[ "$youtube_playing" == "true" ]]; then
		debugecho "DEBUG Youtube playing. Running binge. "
	    binge_watch_tracker
	fi
	debugecho "DEBUG Binge info: vid='${video_id:-}' last='${last_video_id:-}' pct=${playback_position_percent:-0} t=${currentTime:-0} dur=${duration_sec:-0}"

	debugecho "DEBUG Done initializing."

	currentTimehms=$(printf "%02d:%02d" $((currentTime / 60)) $((currentTime % 60)))
	duration_hms=$(printf "%02d:%02d" $((duration_sec / 60)) $((duration_sec % 60)))
	debugecho "DEBUG Build progress bar"
	build_progress_bar "$playback_position_percent"
	debugecho "DEBUG Refresh core audio state"	
	refresh_ha_core_audio_state
    # --------------------------------------------------------
    # NORMALIZATION + DERIVED STATE
    # --------------------------------------------------------
    normalize_state
	
    # --------------------------------------------------------
    # SNAPSHOT LAST KNOWN MEDIA
    # --------------------------------------------------------
    if [[ "$media_status" == "Music" || "$media_status" == "YouTube" ]]; then
        debugecho "DEBUG Snapshotting last known media" 
		snapshot_last_known_media
    fi

    # --------------------------------------------------------
    # EFFECTS (HA + CLI)
    # --------------------------------------------------------
	debugecho "DEBUG NowPlaying: $track | $artist"
	    emit_outputs

	
    # --------------------------------------------------------
    # Clean Cache
    # --------------------------------------------------------
	
	now_epoch=$(date +%s)

	if (( now_epoch - last_cache_cleanup > CACHE_CLEANUP_INTERVAL )); then
	    cleanup_cache
	    last_cache_cleanup="$now_epoch"
	fi
    # --------------------------------------------------------
    # LOOP TIMING
    # --------------------------------------------------------
    sleep "$TRACK_CHECK_INTERVAL"

done