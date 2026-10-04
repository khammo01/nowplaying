#!/usr/bin/env bash
# ============================================================
# NagMenu NowPlaying
# ============================================================

set -u
debug_mode="false"
# debug_mode="true"
debugecho() { [[ "${debug_mode:-false}" == "true" ]] && echo "$@"; }
nodebug()   { [[ "${debug_mode:-false}" != "true" ]] && "$@"; }
export JQ_COLORS="0"
echo "Starting*** NagMenu NowPlaying ***"


# ============================================================
# Paths & Environment
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; NOWPLAYING_ROOT="$SCRIPT_DIR"; CACHE_ROOT="$NOWPLAYING_ROOT/cache"
SSH_ROOT="$NOWPLAYING_ROOT/ssh"; DEFAULT_ARTWORK="$NOWPLAYING_ROOT/default_music.jpg"
DEFAULT_VIDEO_ARTWORK="$NOWPLAYING_ROOT/default_video.jpg"
MUSIC_ART_CACHE="$CACHE_ROOT/music_artwork"
mkdir -p "$CACHE_ROOT" "$SSH_ROOT" "$MUSIC_ART_CACHE"
LOCK_DIR="$CACHE_ROOT/nowplaying.lock"
cleanup_lock() {
    if [[ -f "$LOCK_DIR/pid" ]] && [[ "$(cat "$LOCK_DIR/pid" 2>/dev/null)" == "$$" ]]; then
        rm -rf "$LOCK_DIR"
    fi
}
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    lock_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
    if [[ "$lock_pid" =~ ^[0-9]+$ ]] && kill -0 "$lock_pid" 2>/dev/null; then
        echo "NowPlaying is already running as PID $lock_pid; exiting." >&2
        exit 1
    fi
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" || exit 1
fi
printf '%s\n' "$$" > "$LOCK_DIR/pid"
trap 'cleanup_lock; echo "Received termination signal, exiting..."; exit 0' SIGTERM SIGINT
sleep_pid=""; browser_pid=""; immediate_poll_requested="false"
request_immediate_poll() {
    # BetterTouchTool calls this signal after a media command. Interrupt either
    # the adaptive sleep or a browser probe that has stopped responding, then
    # skip the next sleep so fresh metadata reaches Home Assistant immediately.
    immediate_poll_requested="true"
    [[ -n "${sleep_pid:-}" ]] && kill "$sleep_pid" 2>/dev/null || true
    [[ -n "${browser_pid:-}" ]] && kill "$browser_pid" 2>/dev/null || true
}
trap request_immediate_poll SIGUSR1
trap cleanup_lock EXIT
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
SOURCE_DEVICE="${SOURCE_DEVICE:-$(scutil --get ComputerName 2>/dev/null || hostname -s)}"
PAYLOAD_SCHEMA_VERSION=2
for dependency in jq python3 curl osascript perl; do
    command -v "$dependency" >/dev/null || { echo "Missing dependency: $dependency" >&2; exit 1; }
done
# Timing & Thresholds
# ============================================================

PAUSED_WINDOW_SEC=8; ACTIVE_CHECK_INTERVAL=3; PAUSED_CHECK_INTERVAL=3.5; IDLE_RECENT_CHECK_INTERVAL=5
IDLE_WARM_CHECK_INTERVAL=7; IDLE_LONG_CHECK_INTERVAL=10; IDLE_WARM_AFTER_SEC=60; IDLE_LONG_AFTER_SEC=300
CACHE_CLEANUP_INTERVAL=3600; next_check_interval="$ACTIVE_CHECK_INTERVAL"; last_polled_time="--:--:--.---"
last_cache_cleanup=0


# ============================================================
# Media State / Metadata
# ============================================================

media_status="Idle"; music_playing="false"; youtube_playing="false"; idle_start_epoch=""; idle_duration=0
track="startup"; artist="startup"; album="startup"; genre="startup"; year="startup"; summary=""; description="startup"
view_count=""; published_date=""; subscriber_count=""
thumbnail_url="/local/default_music.jpg"; duration_hms="00:00"; duration_sec=0; currentTime=0; currentTimehms="00:00"
playback_speed="1.0"; playback_position_percent=0; volume_percent=0; progress_bar_full=""; playlist_name=""; video_id=""; url=""; media_source=""


# ============================================================
# Persistence / Previous State
# ============================================================

youtube_video_count=0; high_score=0; last_video_id=""; last_video_timestamp=0; last_sent_video_id=""
last_thumbnail_url=""; last_generic_artwork_key=""; last_known_track=""; last_known_artist=""; last_known_description=""
last_known_youtube_active="false"; last_music_artwork_hash=""; last_music_artwork_key=""; last_ha_media_active_state=""
last_ha_update_time_utc=""; last_ha_update_time_local="--:--:--.---"; last_emitted_state=""; last_idle_bucket=""
current_idle_bucket=""
artwork_version=""


# ============================================================
# Profiling
# ============================================================

music_poll_ms=0; browser_poll_ms=0; vlc_poll_ms=0; ha_network_ms=0; loop_work_ms=0; sleep_ms=0; profile_music_ms=0
profile_browser_ms=0; profile_vlc_ms=0; profile_ha_network_ms=0; profile_sleep_ms=0


# ============================================================
# Generic Helpers
# ============================================================

timestamp_ms() {
    perl -MTime::HiRes=time -e 'printf "%.0f\n", time() * 1000'
}
clock_now_ms() {
    perl -MPOSIX=strftime -MTime::HiRes=time -e '
        $t = time();
        $whole = int($t);
        $ms = int(($t - $whole) * 1000);
        printf "%s.%03d\n",
            strftime("%H:%M:%S", localtime($whole)),
            $ms;
    '
}
epoch_now() { date +%s; }
cecho()     { printf '%b\n' "$1"; }
normalize_ints() {
    local v
    for v; do
        [[ "${!v:-}" =~ ^[0-9]+$ ]] || printf -v "$v" '%s' "0"
    done
}
normalize_bools() {
    local v
    for v; do
        case "${!v:-}" in
            true|TRUE|1) printf -v "$v" '%s' "true" ;;
            *)           printf -v "$v" '%s' "false" ;;
        esac
    done
}
strip_newlines() {
    local s="${1:-}"
    s="${s//$'\r'/}"; s="${s//$'\n'/}"
    printf '%s' "$s"
}
sanitize_vars() {
    local v
    for v; do
        printf -v "$v" '%s' "$(strip_newlines "${!v:-}")"
    done
}
clean_track_name() {
    sed -E '
        s/[[:space:]]*\[[^]]*\]//g;
        s/[[:space:]]*\([^)]*\)//g;
        s/[[:space:]]+/ /g;
        s/^ //;
        s/ $//
    '
}
send_artwork() {
    local source_file="$1" hash remote_temp controller_remote_temp
    local publish_file="/tmp/nowplaying_artwork_publish.jpg"
    local controller_file="/tmp/nowplaying_artwork_controller.jpg"
    # Music.app frequently returns PNG artwork even though the shared HA path
    # has a .jpg suffix. Normalize every source to a compact, genuine JPEG so
    # small clients (including the rotary controller) can decode it quickly.
    if ! sips -s format jpeg -s formatOptions 86 -Z 600 "$source_file" --out "$publish_file" >/dev/null 2>&1; then
        cp "$source_file" "$publish_file" || return 1
    fi
    if ! sips -s format jpeg -s formatOptions 82 -Z 192 "$source_file" --out "$controller_file" >/dev/null 2>&1; then
        cp "$publish_file" "$controller_file" || return 1
    fi
    hash=$(shasum -a 256 "$publish_file" 2>/dev/null | awk '{print $1}')
    [[ -n "$hash" ]] || return 1
    remote_temp="/config/www/nowplaying/.artwork.${hash}.$$.tmp"
    controller_remote_temp="/config/www/nowplaying/.controller-artwork.${hash}.$$.tmp"
    scp -q -i "$SSH_KEY" -o IdentitiesOnly=yes "$publish_file" "$HA_SERVER:$remote_temp" || return 1
    scp -q -i "$SSH_KEY" -o IdentitiesOnly=yes "$controller_file" "$HA_SERVER:$controller_remote_temp" || return 1
    ssh -q -i "$SSH_KEY" -o IdentitiesOnly=yes "$HA_SERVER" \
        "mv '$remote_temp' /config/www/nowplaying/artwork.jpg && mv '$controller_remote_temp' /config/www/nowplaying/controller-artwork.jpg" || return 1
    artwork_version="$hash"
}


# ============================================================
# Startup Screen
# ============================================================

draw_startup_screen() {
    nodebug printf '\e[8;27;76t'
    nodebug printf '\033[H\033[J'
    printf '\n\n\n\n\n\n'
    echo "                         Checking media..."
    echo "  -------------------------------------------------------------------"
    printf '\n\n\n\n\n\n'
    echo "                 Polling Music, browsers and VLC"
    printf '\n\n\n\n\n\n\n'
    echo "  -------------------------------------------------------------------"
    echo "     Last Polled Time: --:--:--.--- | Check Interval: --"; echo "     Last HA Update Time: --:--:--.---"
    echo "     Timing: Music 0ms | Browser 0ms | VLC 0ms | HA 0ms | Sleep 0ms"; echo ""
}


# ============================================================
# Cache Cleanup
# ============================================================

cleanup_cache() {
    find "$CACHE_ROOT" -type f -mtime +1 -delete 2>/dev/null
}


# ============================================================
# YouTube Artwork
# ============================================================

download_youtube_thumbnail() {
    local requested_video_id="$1"
    local temp_file="/tmp/youtube_artwork.jpg"; local size u; local -a urls=(
        "https://img.youtube.com/vi/${requested_video_id}/maxresdefault.jpg"
        "https://img.youtube.com/vi/${requested_video_id}/sddefault.jpg"
        "https://img.youtube.com/vi/${requested_video_id}/hqdefault.jpg"
    )
    for u in "${urls[@]}"; do
        curl -s "$u" -o "$temp_file"
        if [[ -s "$temp_file" ]]; then
            size=$(stat -f%z "$temp_file")
            if (( size > 15000 )); then
                send_artwork "$temp_file"
                return 0
            fi
        fi
        sleep 0.15
    done
    cp "$DEFAULT_ARTWORK" "$temp_file"
    send_artwork "$temp_file"
}


# ============================================================
# Generic Browser / VLC Artwork
# ============================================================

download_generic_artwork() {
    local image_url="$1"
    local temp_file="/tmp/nowplaying_generic_artwork.jpg"
    [[ -n "$image_url" ]] || return 1
    curl -L -s --fail "$image_url" -o "$temp_file" || return 1
    [[ -s "$temp_file" ]] || return 1
    send_artwork "$temp_file"
}

enrich_vlc_episode_json() {
    local json="$1" parsed raw series season episode episode_title cache_key cache_file
    local show_json show_id episode_json seasons_json season_json poster summary show_name episode_name genres year metadata
    raw=$(jq -r '.raw_name // .filename_guess // ""' <<< "$json" 2>/dev/null)
    parsed=$(python3 - "$raw" <<'PY'
import os, re, sys
raw = os.path.splitext(os.path.basename(sys.argv[1]))[0]
m = re.search(r'(?i)^(.*?)[\s._-]+s(\d{1,2})e(\d{1,2})(?:[\s._-]+(.*))?$', raw)
if m:
    clean = lambda s: re.sub(r'\s+', ' ', re.sub(r'[._-]+', ' ', s or '')).strip()
    series = re.sub(r'\s*\((?:19|20)\d{2}\)\s*$', '', clean(m.group(1))).strip()
    print('\x1f'.join((series, str(int(m.group(2))), str(int(m.group(3))), clean(m.group(4)))))
PY
    )
    [[ -n "$parsed" ]] || { printf '%s' "$json"; return; }
    IFS=$'\x1f' read -r series season episode episode_title <<< "$parsed"
    [[ -n "$series" && -n "$season" && -n "$episode" ]] || { printf '%s' "$json"; return; }

    mkdir -p "$CACHE_ROOT/vlc_metadata"
    cache_key=$(printf '%s' "${series}|${season}|${episode}" | shasum -a 256 | awk '{print $1}')
    cache_file="$CACHE_ROOT/vlc_metadata/${cache_key}.json"
    if [[ -s "$cache_file" ]]; then
        metadata=$(cat "$cache_file")
    else
        show_json=$(curl -L -sS --fail --max-time 4 --get \
            --data-urlencode "q=$series" "https://api.tvmaze.com/singlesearch/shows" 2>/dev/null || printf '{}')
        show_id=$(jq -r '.id // empty' <<< "$show_json" 2>/dev/null)
        if [[ -n "$show_id" ]]; then
            episode_json=$(curl -L -sS --fail --max-time 4 \
                "https://api.tvmaze.com/shows/${show_id}/episodebynumber?season=${season}&number=${episode}" 2>/dev/null || printf '{}')
            seasons_json=$(curl -L -sS --fail --max-time 4 \
                "https://api.tvmaze.com/shows/${show_id}/seasons" 2>/dev/null || printf '[]')
            season_json=$(jq -c --argjson n "$season" '[.[] | select(.number == $n)][0] // {}' <<< "$seasons_json" 2>/dev/null || printf '{}')
            # TVMaze exposes episode landscape art, season art, and show art.
            # Use them in that order so a missing episode still gets relevant art.
            poster=$(jq -rn --argjson e "$episode_json" --argjson s "$season_json" --argjson h "$show_json" \
                '$e.image.original // $e.image.medium // $s.image.original // $s.image.medium // $h.image.original // $h.image.medium // ""')
            summary=$(jq -r '.summary // "" | gsub("<[^>]+>"; " ") | gsub("&amp;"; "&") | gsub("&quot;"; "\"") | gsub("[[:space:]]+"; " ") | sub("^ "; "") | sub(" $"; "")' <<< "$episode_json" 2>/dev/null)
            show_name=$(jq -r '.name // empty' <<< "$show_json" 2>/dev/null)
            episode_name=$(jq -r '.name // empty' <<< "$episode_json" 2>/dev/null)
            genres=$(jq -r '(.genres // []) | join(", ")' <<< "$show_json" 2>/dev/null)
            year=$(jq -r '(.premiered // "") | split("-")[0]' <<< "$show_json" 2>/dev/null)
            metadata=$(jq -nc \
                --arg poster "$poster" --arg show "$show_name" --arg episode_name "$episode_name" \
                --arg summary "$summary" --arg genres "$genres" --arg year "$year" \
                --arg season "$season" --arg episode "$episode" --arg fallback_title "$episode_title" '
                {
                  poster: $poster,
                  thumbnail: $poster,
                  channel: ($show // "VLC"),
                  title: (if $episode_name != "" then $episode_name
                          elif $fallback_title != "" then $fallback_title
                          else $show end),
                  album: ("Season " + $season + " · Episode " + $episode),
                  genre: $genres,
                  year: $year,
                  summary: $summary,
                  description: $summary
                } | with_entries(select(.value != ""))')
            if [[ -n "$poster" ]]; then
                printf '%s\n' "$metadata" > "${cache_file}.tmp"
                mv "${cache_file}.tmp" "$cache_file"
            fi
        fi
    fi
    if [[ -n "${metadata:-}" ]]; then
        jq -c --argjson metadata "$metadata" '. * $metadata' <<< "$json" 2>/dev/null || printf '%s' "$json"
    else
        printf '%s' "$json"
    fi
}


# ============================================================
# Music Artwork
# ============================================================

get_music_artwork() {
    local requested_artist="${1:-}"
    local requested_track="${2:-}"
    local temp_file="/tmp/music_artwork.jpg"; local cache_file="" cache_key="" result="" clean_track=""
    local itunes_json="" itunes_url="" mb_json="" release_id=""
    if [[ -n "$requested_artist" && -n "$requested_track" ]]; then
        cache_key=$(
            printf '%s|%s' "$requested_artist" "$requested_track" |
                shasum | awk '{print $1}'
        )
        cache_file="$MUSIC_ART_CACHE/$cache_key.jpg"
        if [[ -s "$cache_file" ]]; then
            cp "$cache_file" "$temp_file"
            printf '%s\n' "$temp_file"
            return 0
        fi
    fi
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
        printf '%s\n' "$temp_file"
        return 0
    fi
    clean_track=$(printf '%s' "$requested_track" | clean_track_name)
    if [[ -n "$requested_artist" && -n "$clean_track" ]]; then
        itunes_json=$(
            curl -s --get --data-urlencode "term=${requested_artist} ${clean_track}" --data "media=music&entity=song&limit=1" https://itunes.apple.com/search
        )
        itunes_url=$(
            printf '%s' "$itunes_json" |
                jq -r '
                    if .resultCount > 0 and .results[0].artworkUrl100 then
                        .results[0].artworkUrl100
                        | sub("100x100bb"; "600x600bb")
                    else
                        empty
                    end
                '
        )
        if [[ -n "$itunes_url" ]]; then
            curl -s "$itunes_url" -o "$temp_file"
            if [[ -s "$temp_file" ]]; then
                [[ -n "$cache_file" ]] && cp "$temp_file" "$cache_file"
                printf '%s\n' "$temp_file"
                return 0
            fi
        fi
        mb_json=$(
            curl -s "https://musicbrainz.org/ws/2/recording/?query=artist:${requested_artist// /%20}%20${clean_track// /%20}&fmt=json&limit=1"
        )
        release_id=$(
            printf '%s' "$mb_json" |
                jq -r '.recordings[0].releases[0].id // empty'
        )
        if [[ -n "$release_id" ]]; then
            curl -s "https://coverartarchive.org/release/$release_id/front-500" -o "$temp_file"
            if [[ -s "$temp_file" ]]; then
                [[ -n "$cache_file" ]] && cp "$temp_file" "$cache_file"
                printf '%s\n' "$temp_file"
                return 0
            fi
        fi
    fi
    cp "$DEFAULT_ARTWORK" "$temp_file"
    printf '%s\n' "$temp_file"
}


# ============================================================
# Sensor Layer — Music.app
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
    set oldTID to AppleScript's text item delimiters
    set AppleScript's text item delimiters to search_string
    set the item_list to every text item of this_text
    set AppleScript's text item delimiters to replacement_string
    set this_text to item_list as string
    set AppleScript's text item delimiters to oldTID
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
# JSON Parsers
# ============================================================

parse_music_json() {
    local json="$1" row
    local parsed_playing parsed_track parsed_artist parsed_album
    local parsed_genre parsed_year parsed_duration parsed_position
    row=$(
        jq -r '
            [
                (.playing // false),
                (.track // ""),
                (.artist // ""),
                (.album // ""),
                (.genre // ""),
                (.year // ""),
                ((.duration // 0) | tonumber? // 0 | floor),
                ((.position // 0) | tonumber? // 0 | floor)
            ]
            | map(tostring | gsub("[\r\n]"; " ") | gsub("\u001f"; " "))
            | join("\u001f")
        ' <<< "$json" 2>/dev/null
    ) || row=$'false\x1f\x1f\x1f\x1f\x1f\x1f0\x1f0'
    IFS=$'\x1f' read -r parsed_playing parsed_track parsed_artist parsed_album parsed_genre parsed_year parsed_duration parsed_position <<< "$row"
    music_playing="$parsed_playing"; normalize_bools music_playing
    if [[ "$music_playing" == "true" ]]; then
        track="$parsed_track"; artist="$parsed_artist"; album="$parsed_album"; genre="$parsed_genre"
        year="$parsed_year"; duration_sec="$parsed_duration"; currentTime="$parsed_position"
        normalize_ints duration_sec currentTime
    fi
}
parse_video_json() {
    local json="$1" row
    local source_kind="${2:-youtube}"
    local parsed_playing parsed_track parsed_artist parsed_album
    local parsed_genre parsed_year parsed_summary parsed_description parsed_speed
    local parsed_duration parsed_position parsed_url parsed_video_id; local parsed_thumbnail parsed_playlist
    local parsed_view_count parsed_published_date parsed_subscriber_count
    row=$(
        jq -r '
            [
                (.playing // false),
                (.title // .track // .parsed_title // .raw_name // ""),
                (.channel // .artist // .director // "VLC"),
                (.album // .writer // ""),
                (.genre // ""),
                (.year // .parsed_year // ""),
                (.summary // ""),
                (.description // .plot // ""),
                (.playbackRate // .playback_speed // 1.0),
                (
                    (.video_duration // .duration_sec // .duration // 0)
                    | tonumber? // 0 | floor
                ),
                (
                    (.currentTime // .current_time // .position // 0)
                    | tonumber? // 0 | floor
                ),
                (.url // .media_path // ""),
                (.video_id // .videoId // .id // .imdbID // ""),
                (.thumbnail // .thumbnail_url // .poster // ""),
                (.playlist // .playlist_name // ""),
                (.view_count // ""),
                (.published_date // ""),
                (.subscriber_count // "")
            ]
            | map(tostring | gsub("[\r\n]"; " ") | gsub("\u001f"; " "))
            | join("\u001f")
        ' <<< "$json" 2>/dev/null
    ) || row=$'false\x1f\x1f\x1f\x1f\x1f\x1f\x1f\x1f1.0\x1f0\x1f0\x1f\x1f\x1f\x1f\x1f\x1f\x1f'
    IFS=$'\x1f' read -r parsed_playing parsed_track parsed_artist parsed_album parsed_genre parsed_year parsed_summary parsed_description parsed_speed \
        parsed_duration parsed_position parsed_url parsed_video_id parsed_thumbnail parsed_playlist parsed_view_count parsed_published_date parsed_subscriber_count <<< "$row"
    youtube_playing="$parsed_playing"; normalize_bools youtube_playing
    if [[ "$youtube_playing" == "true" ]]; then
        media_source="$source_kind"
        track="$parsed_track"; artist="$parsed_artist"; album="$parsed_album"; genre="$parsed_genre"
        year="$parsed_year"; summary="$parsed_summary"; description="$parsed_description"; playback_speed="${parsed_speed:-1.0}"
        duration_sec="$parsed_duration"; currentTime="$parsed_position"; url="$parsed_url"; video_id="$parsed_video_id"
        thumbnail_url="$parsed_thumbnail"; playlist_name="$parsed_playlist"; view_count="$parsed_view_count"
        published_date="$parsed_published_date"; subscriber_count="$parsed_subscriber_count"; normalize_ints duration_sec currentTime
    fi
}


# ============================================================
# Persistence
# ============================================================

STATE_FILE="$NOWPLAYING_ROOT/nowplaying_state.json"
load_persistent_state() {
    [[ -f "$STATE_FILE" ]] || printf '{}\n' > "$STATE_FILE"
    local state_row
    state_row=$(
        jq -r '
            [
                (.last_video_id // ""),
                (.youtube_video_count // 0),
                (.high_score // 0),
                (.last_video_timestamp // 0)
            ]
            | map(tostring | gsub("[\r\n]"; " ") | gsub("\u001f"; " "))
            | join("\u001f")
        ' "$STATE_FILE" 2>/dev/null
    ) || state_row=$'\x1f0\x1f0\x1f0'
    IFS=$'\x1f' read -r last_video_id youtube_video_count high_score last_video_timestamp <<< "$state_row"
    normalize_ints youtube_video_count high_score last_video_timestamp
}
persist_binge_state() {
    local tmp
    tmp=$(mktemp) || return
    normalize_ints youtube_video_count high_score last_video_timestamp
    jq --arg last_video_id "$last_video_id" --argjson youtube_video_count "$youtube_video_count" --argjson high_score "$high_score" \
        --argjson last_video_timestamp "$last_video_timestamp" '
        .last_video_id = $last_video_id
        | .youtube_video_count = $youtube_video_count
        | .high_score = $high_score
        | .last_video_timestamp = $last_video_timestamp
        ' "$STATE_FILE" 2>/dev/null > "$tmp" && mv "$tmp" "$STATE_FILE" || rm -f "$tmp"
}


# ============================================================
# Binge Watch Tracking
# ============================================================

binge_watch_tracker() {
    local current_timestamp="${1:-0}"
    local state_changed="false"
    [[ "$current_timestamp" =~ ^[0-9]+$ ]] || current_timestamp=0
    normalize_ints youtube_video_count high_score last_video_timestamp playback_position_percent currentTime
    if (( current_timestamp - last_video_timestamp > 3600 )) &&
       (( youtube_video_count != 0 )); then
        youtube_video_count=0; state_changed="true"
    fi
    if [[ -n "$video_id" &&
          "$video_id" != "$last_video_id" &&
          "$playback_position_percent" -gt 20 &&
          "$currentTime" -ge 30 ]]; then
        youtube_video_count=$((youtube_video_count + 1))
        last_video_timestamp="$current_timestamp"; last_video_id="$video_id"; state_changed="true"
        (( youtube_video_count > high_score )) &&
            high_score="$youtube_video_count"
    fi
    [[ "$state_changed" == "true" ]] && persist_binge_state
}


# ============================================================
# Progress Bar
# ============================================================

build_progress_bar() {
    local percent="$1"
    local bar_len=54 filled empty filled_bar="" empty_bar=""
    [[ "$percent" =~ ^[0-9]+$ ]] || percent=0
    (( percent < 0 )) && percent=0
    (( percent > 100 )) && percent=100
    filled=$(( bar_len * percent / 100 ))
    empty=$(( bar_len - filled ))
    printf -v filled_bar '%*s' "$filled" ''
    filled_bar="${filled_bar// /*}"
    printf -v empty_bar '%*s' "$empty" ''
    if (( filled > 0 )); then
        progress_bar_full="  [\033[31m${filled_bar}\033[0m ${percent}% ${empty_bar}]"
    else
        progress_bar_full="  [${filled_bar} ${percent}% ${empty_bar}]"
    fi
}


# ============================================================
# Media Status Resolution
# ============================================================

resolve_media_status() {
    if [[ "$music_playing" == "true" ]]; then
        media_status="Music"
    elif [[ "$youtube_playing" == "true" ]]; then
        media_status="YouTube"
    elif [[ -n "$last_known_track" &&
            "$idle_duration" -lt "$PAUSED_WINDOW_SEC" ]]; then
        media_status="Paused"
    else
        media_status="Idle"
    fi
}
update_idle_timer() {
    local now="$1"
    [[ "$now" =~ ^[0-9]+$ ]] || now=0
    if [[ "$media_status" == "Idle" ||
          "$media_status" == "Paused" ]]; then
        [[ -n "$idle_start_epoch" ]] || idle_start_epoch="$now"
        idle_duration=$(( now - idle_start_epoch ))
    else
        idle_start_epoch=""; idle_duration=0
    fi
}


# ============================================================
# Normalize State
# ============================================================

normalize_state() {
    local now="$1"
    normalize_bools music_playing youtube_playing
    resolve_media_status
    update_idle_timer "$now"
    resolve_media_status
}


# ============================================================
# Snapshot Last Known Media
# ============================================================

snapshot_last_known_media() {
    last_known_track="$track"; last_known_artist="$artist"; last_known_description="$description"
    last_known_youtube_active="$youtube_playing"
}


# ============================================================
# Transition & Emission Logic
# ============================================================

idle_bucket() {
    local d="$idle_duration"
    [[ "$d" =~ ^[0-9]+$ ]] || d=0
    if (( d < PAUSED_WINDOW_SEC )); then
        current_idle_bucket="early"
    elif (( d < 60 )); then
        current_idle_bucket="paused"
    else
        current_idle_bucket="long"
    fi
}
should_emit() {
    idle_bucket
    if [[ "$media_status" == "Music" ||
          "$media_status" == "YouTube" ]]; then
        last_emitted_state="$media_status"; last_idle_bucket=""; return 0
    fi
    if [[ "$media_status" == "Paused" ]]; then
        if [[ "$last_emitted_state" != "Paused" ]]; then
            last_emitted_state="Paused"; last_idle_bucket="$current_idle_bucket"; return 0
        fi
        return 1
    fi
    if [[ "$media_status" == "Idle" &&
          "$last_emitted_state" != "Idle" ]]; then
        last_emitted_state="Idle"; last_idle_bucket="$current_idle_bucket"; return 0
    fi
    if [[ "$media_status" == "Idle" &&
          "$current_idle_bucket" != "$last_idle_bucket" ]]; then
        last_idle_bucket="$current_idle_bucket"
        [[ "$current_idle_bucket" == "long" ]] && return 0
    fi
    return 1
}


# ============================================================
# Adaptive Polling
# ============================================================

choose_check_interval() {
    local d="$idle_duration"
    [[ "$d" =~ ^[0-9]+$ ]] || d=0
    case "$media_status" in
        Music|YouTube)
            next_check_interval="$ACTIVE_CHECK_INTERVAL"
            ;;
        Paused)
            next_check_interval="$PAUSED_CHECK_INTERVAL"
            ;;
        Idle)
            if (( d < IDLE_WARM_AFTER_SEC )); then
                next_check_interval="$IDLE_RECENT_CHECK_INTERVAL"
            elif (( d < IDLE_LONG_AFTER_SEC )); then
                next_check_interval="$IDLE_WARM_CHECK_INTERVAL"
            else
                next_check_interval="$IDLE_LONG_CHECK_INTERVAL"
            fi
            ;;
        *)
            next_check_interval="$IDLE_RECENT_CHECK_INTERVAL"
            ;;
    esac
}


# ============================================================
# HA Media Active Boolean
# ============================================================

refresh_ha_media_active_state() {
    local desired_state service payload
    if [[ "$music_playing" == "true" ||
          "$youtube_playing" == "true" ]]; then
        desired_state="Active"; service="turn_on"
    else
        desired_state="Idle"; service="turn_off"
    fi
    [[ "$desired_state" == "$last_ha_media_active_state" ]] && return
    last_ha_media_active_state="$desired_state"; debugecho "DEBUG HA media-active edge -> $desired_state"
    payload=$(jq -nc --arg entity_id "$HA_AUDIO_ENTITY" '{entity_id: $entity_id}')
    curl -s -o /dev/null --fail \
        -H "Authorization: Bearer $BEARER_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$HA_BASE_URL/api/services/input_boolean/$service" || true
}

# ============================================================
# Artwork Emission
# ============================================================

emit_artwork() {
    if [[ "$youtube_playing" == "true" ]]; then
        if [[ -n "$thumbnail_url" &&
              "$thumbnail_url" != "$last_thumbnail_url" ]]; then
            if [[ "$thumbnail_url" == https://img.youtube.com/* &&
                  -n "$video_id" ]]; then
                debugecho "DEBUG Emitting YouTube artwork"
                download_youtube_thumbnail "$video_id" || return 1
            else
                debugecho "DEBUG Emitting generic artwork"
                download_generic_artwork "$thumbnail_url" || return 1
            fi
            last_sent_video_id="$video_id"; last_thumbnail_url="$thumbnail_url"; last_music_artwork_key=""
        elif [[ -z "$thumbnail_url" &&
                -n "$video_id" &&
                "$video_id" != "$last_sent_video_id" ]]; then
            debugecho "DEBUG Emitting YouTube artwork by video_id"
            download_youtube_thumbnail "$video_id" || return 1
            last_sent_video_id="$video_id"; last_music_artwork_key=""
        elif [[ "$media_source" == "vlc" && -z "$thumbnail_url" ]]; then
            # VLC frequently has no poster metadata. Publishing a real placeholder
            # for each newly loaded item prevents dashboards from retaining the
            # previous browser/video artwork indefinitely.
            local generic_key="vlc|${track}|${duration_sec}"
            if [[ "$generic_key" != "$last_generic_artwork_key" ]]; then
                debugecho "DEBUG Emitting VLC placeholder artwork"
                send_artwork "$DEFAULT_VIDEO_ARTWORK" || return 1
                last_generic_artwork_key="$generic_key"
                last_thumbnail_url=""; last_sent_video_id=""; last_music_artwork_key=""
            fi
        fi
        return
    fi
    if [[ "$music_playing" == "true" ]]; then
        local artwork_key="${artist}|${album}|${track}"
        local art hash
        [[ "$artwork_key" == "$last_music_artwork_key" ]] && return
        debugecho "DEBUG Music track/source changed. Resolving artwork."
        art=$(get_music_artwork "$artist" "$track")
        hash=$(md5 -q "$art" 2>/dev/null)
        if [[ "$hash" != "$last_music_artwork_hash" ||
              -n "$last_thumbnail_url" ]]; then
            debugecho "DEBUG Emitting music artwork"
            send_artwork "$art" || return 1
            last_music_artwork_hash="$hash"
        fi
        last_music_artwork_key="$artwork_key"; last_thumbnail_url=""; last_sent_video_id=""; return
    fi
    debugecho "DEBUG Nothing playing. Not sending artwork."
}


# ============================================================
# Home Assistant Payload
# ============================================================

emit_home_assistant() {
    debugecho "DEBUG Updating HA"
    # SoundSource can maintain a routed-device volume that differs from the
    # macOS master value. Controller commands persist the confirmed target here.
    local routed_volume_file="$CACHE_ROOT/soundsource-volume-percent"
    if [[ -s "$routed_volume_file" ]]; then
        volume_percent=$(<"$routed_volume_file")
    else
        volume_percent=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null || printf '0')
    fi
    normalize_ints idle_duration playback_position_percent volume_percent duration_sec currentTime youtube_video_count high_score
    normalize_bools youtube_playing music_playing
    sanitize_vars track artist album genre year summary description view_count published_date subscriber_count media_status media_source currentTimehms duration_hms playback_speed playlist_name progress_bar_full url video_id thumbnail_url artwork_version
    local payload; local resp_file="/tmp/nowplaying_ha_resp.txt"; local http_code
    local sent_at event_id
    sent_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    event_id="${SOURCE_DEVICE}-$(timestamp_ms)"
    payload=$(
        jq -n --arg source_device "$SOURCE_DEVICE" --arg sent_at "$sent_at" --arg event_id "$event_id" --arg media_source "$media_source" \
            --arg track "$track" --arg artist "$artist" --arg album "$album" --arg genre "$genre" --arg year "$year" --arg summary "$summary" --arg description "$description" \
            --arg view_count "$view_count" --arg published_date "$published_date" --arg subscriber_count "$subscriber_count" \
            --arg media_status "$media_status" --arg currentTime "$currentTimehms" --arg duration "$duration_hms" --arg playback_speed "$playback_speed" \
            --arg playlist "$playlist_name" --arg progress_bar_full "$progress_bar_full" --arg url "$url" --arg video_id "$video_id" --arg thumbnail "$thumbnail_url" --arg artwork_version "$artwork_version" \
            --argjson schema_version "$PAYLOAD_SCHEMA_VERSION" \
            --argjson idle_duration "$idle_duration" --argjson playback_position_percent "$playback_position_percent" --argjson youtube_playing "$youtube_playing" \
            --argjson volume_percent "$volume_percent" \
            --argjson music_app_playing "$music_playing" --argjson total_videos_watched "$youtube_video_count" --argjson high_score "$high_score" \
            --argjson video_duration "$duration_sec" '
            {
                schema_version: $schema_version,
                event_id: $event_id,
                source_device: $source_device,
                sent_at: $sent_at,
                track: $track,
                artist: $artist,
                album: $album,
                genre: $genre,
                year: $year,
                summary: $summary,
                description: $description,
                view_count: $view_count,
                published_date: $published_date,
                subscriber_count: $subscriber_count,
                media_status: $media_status,
                media_source: $media_source,
                idle_duration: $idle_duration,
                currentTime: $currentTime,
                duration: $duration,
                playback_position_percent: $playback_position_percent,
                volume_percent: $volume_percent,
                playback_speed: $playback_speed,
                youtube_playing: $youtube_playing,
                music_app_playing: $music_app_playing,
                total_videos_watched: $total_videos_watched,
                high_score: $high_score,
                video_duration: $video_duration,
                playlist:
                    (
                        $playlist |
                        if . == "" then "(None)" else . end
                    ),
                progress_bar_full: $progress_bar_full,
                url: $url,
                video_id: $video_id,
                thumbnail: $thumbnail,
                artwork_version: $artwork_version
            }
            '
    )
    http_code=$(
        curl -sS --connect-timeout 3 --max-time 8 --retry 2 --retry-delay 1 \
            -o "$resp_file" -w "%{http_code}" -X POST \
            -H "Content-Type: application/json" -d "$payload" "$HA_API_URL"
    )
    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        debugecho "DEBUG HA Result: Success"
    else
        debugecho "DEBUG HA Result: Error - $http_code"
    fi
    last_ha_update_time_utc=$(date -u '+%Y-%m-%dT%H:%M:%S')
    last_ha_update_time_local=$(clock_now_ms)
}


# ============================================================
# CLI Helpers
# ============================================================

declare -a WRAPPED_LINES
wrap_words() {
    local text="$1"
    local max_len="$2"
    local max_lines="$3"
    local word line_index=0 i; WRAPPED_LINES=()
    for ((i=0; i<max_lines; i++)); do
        WRAPPED_LINES[i]=""
    done
    for word in $text; do
        if (( line_index < max_lines - 1 )) &&
           (( ${#WRAPPED_LINES[$line_index]} >= max_len )); then
            ((line_index++))
        fi
        WRAPPED_LINES[$line_index]="${WRAPPED_LINES[$line_index]} $word"
    done
}
print_title_lines() {
    local text="$1"
    local header="$2"
    local max_lines="${3:-4}"
    local max_len=$((59 - ${#header}))
    local i line
    wrap_words "$text" "$max_len" "$max_lines"
    if (( max_lines == 4 )) &&
       (( ${#WRAPPED_LINES[3]} > max_len )); then
        WRAPPED_LINES[3]="${WRAPPED_LINES[3]:1:$((max_len - 3))}..."
    fi
    for ((i=0; i<max_lines; i++)); do
        line="${WRAPPED_LINES[$i]# }"
        [[ -n "$line" ]] || continue
        if (( i == 0 )); then
            cecho "${header}\033[1m\033[33m${line}\033[0m"
        else
            cecho "                      \033[1m\033[33m${line}\033[0m"
        fi
    done
}
print_description_lines() {
    local text="$1"
    local header="     Description:   "
    local max_len=$((59 - ${#header}))
    local i line
    wrap_words "$text" "$max_len" 4
    if (( ${#WRAPPED_LINES[3]} > max_len )); then
        WRAPPED_LINES[3]="${WRAPPED_LINES[3]:0:$((max_len - 3))}..."
    fi
    for ((i=0; i<4; i++)); do
        line="${WRAPPED_LINES[$i]# }"
        [[ -n "$line" ]] || continue
        if (( i == 0 )); then
            cecho "\033[36m${header}  ${line}\033[0m"
        else
            cecho "\033[36m                      ${line}\033[0m"
        fi
    done
}


# ============================================================
# CLI Output
# ============================================================

emit_cli() {
    nodebug printf '\e[8;28;82t'
    nodebug printf '\033[H\033[J'
    printf '\n\n\n'
    if [[ "$music_playing" == "true" ]]; then
        printf '\n\n\n'
        echo "                         Now Playing - Music"
        echo "  -------------------------------------------------------------------"
        printf '\n\n\n\n\n'
        print_title_lines "$track" "     Track:           " 2
        echo "     Artist:          $artist"; echo "     Album:           $album"; echo "     Genre:           $genre"
        [[ -n "$year" ]] && echo "     Year:            $year"
        echo "     Duration:        $currentTimehms / $duration_hms"; echo ""
        cecho "   $progress_bar_full"
        printf '\n\n\n\n'
    elif [[ "$youtube_playing" == "true" ]]; then
        echo "                         Now Playing - Video"
        echo "  -------------------------------------------------------------------"; echo ""
        local title="${track%" - YouTube"}"
        local desc="${description:-$last_known_description}"
        print_title_lines "$title" "     Title:           " 4
        echo "     Channel:         $artist"; echo "     Playlist:        $playlist_name"
        echo "     Speed:           ${playback_speed}"
        print_description_lines "$desc"
        echo "     Video Binge:     Current score: $youtube_video_count"
        echo "                      High Score: $high_score"
        printf '\n\n\n\n'
        echo "                            $currentTimehms / $duration_hms"
        cecho "   $progress_bar_full"
    elif [[ "$media_status" == "Paused" ]]; then
        printf '\n\n'
        echo "                     Most Recent Media - Paused"
        echo "  -------------------------------------------------------------------"
        printf '\n\n\n\n\n'
        echo "     Status:          PAUSED for $idle_duration sec"
        local title="${last_known_track%" - YouTube"}"
        print_title_lines "$title" "     Title:           " 4
        echo "     Artist:          $last_known_artist"
        if [[ "$last_known_youtube_active" == "true" ]]; then
            echo "     Source:          Video"
        else
            echo "     Source:          Music"
        fi
        printf '\n\n\n\n\n\n'
    else
        local idle_hhmm="--:--"
        [[ -z "$idle_start_epoch" ]] ||
            idle_hhmm=$(date -r "$idle_start_epoch" "+%H:%M")
        printf '\n\n'
        echo "                            Media: Idle"
        echo "  -------------------------------------------------------------------"
        printf '\n\n\n\n\n\n\n'
        echo "                       Idle - since $idle_hhmm"
        printf '\n\n\n\n\n\n\n'
    fi
    echo "  -------------------------------------------------------------------"
    printf "     Last Polled Time: %-12s | Check Interval: %ss\n" "$last_polled_time" "$next_check_interval"
    echo "     Last HA Update Time: $last_ha_update_time_local"
    printf "     Timing: Music %dms | Browser %dms | VLC %dms | HA %dms | Sleep %dms\n" "$profile_music_ms" "$profile_browser_ms" "$profile_vlc_ms" "$profile_ha_network_ms" \
        "$profile_sleep_ms"
    echo ""
}


# ============================================================
# Initialization
# ============================================================

load_persistent_state
draw_startup_screen


# ============================================================
# Main Loop
# ============================================================

while true; do
    immediate_poll_requested="false"
    loop_start_ms=$(timestamp_ms)
    loop_now_epoch=$(epoch_now)
    # ========================================================
    # SENSOR READ — Music.app
    # ========================================================
    debugecho "DEBUG Checking Music..."
    timing_start_ms=$(timestamp_ms)
    music_json=$(read_music_sensor)
    parse_music_json "$music_json"
    timing_end_ms=$(timestamp_ms)
    music_poll_ms=$(( timing_end_ms - timing_start_ms ))
    debugecho "DEBUG Done checking Music."
    if [[ "$music_playing" == "true" ]]; then
        summary=""; description=""; view_count=""; published_date=""; subscriber_count=""; url=""; video_id=""; thumbnail_url=""; playlist_name=""
        debugecho "DEBUG Music playing track=$track"; debugecho "DEBUG Music playing artist=$artist"
    else
        debugecho "DEBUG Music not playing."
    fi
    # ========================================================
    # SENSOR READ — Safari / Chrome
    # ========================================================
    debugecho "DEBUG Checking browser video..."
    timing_start_ms=$(timestamp_ms)
    if [[ "$music_playing" == "true" ]]; then
        # Music.app is the authoritative active source. Avoid delaying its
        # controller response on unrelated browser/PWA inspection.
        youtube_playing="false"
    else
        browser_output="$CACHE_ROOT/browser-probe.$$.json"
        : > "$browser_output"
        osascript "$NOWPLAYING_ROOT/safari_youtube_nowplaying.applescript" \
            > "$browser_output" 2>/dev/null &
        browser_pid=$!
        wait "$browser_pid" 2>/dev/null || true
        browser_pid=""
        browser_json=$(cat "$browser_output" 2>/dev/null)
        rm -f "$browser_output"
        # A controller refresh may interrupt this probe. Keep the last known
        # browser state for this partial cycle; the signal also suppresses the
        # sleep, so the next complete probe replaces it immediately.
        if [[ -n "$browser_json" ]]; then
            parse_video_json "$browser_json" "youtube"
        fi
    fi
    timing_end_ms=$(timestamp_ms)
    browser_poll_ms=$(( timing_end_ms - timing_start_ms ))
    # ========================================================
    # SENSOR READ — VLC fallback
    # ========================================================
    vlc_poll_ms=0
    if [[ "$music_playing" != "true" && "$youtube_playing" != "true" ]]; then
        if pgrep -x "VLC" >/dev/null 2>&1; then
            debugecho "DEBUG VLC running. Checking VLC..."
            timing_start_ms=$(timestamp_ms)
            vlc_json=$(
                OMDB_API_KEY="${OMDB_API_KEY:-}" \
                    osascript "$NOWPLAYING_ROOT/VLC_nowplaying.applescript" 2>/dev/null
            )
            vlc_json=$(enrich_vlc_episode_json "$vlc_json")
            # A VLC win replaces browser-specific fields rather than inheriting
            # metadata from the last YouTube item.
            track=""; artist=""; album=""; genre=""; year=""; summary=""; description=""
            view_count=""; published_date=""; subscriber_count=""; playlist_name=""
            video_id=""; thumbnail_url=""; url=""
            parse_video_json "$vlc_json" "vlc"
            if [[ -s "$CACHE_ROOT/vlc-playback-speed" ]]; then
                playback_speed=$(cat "$CACHE_ROOT/vlc-playback-speed")
            fi
            [[ -n "$artist" ]] || artist="VLC"
            timing_end_ms=$(timestamp_ms)
            vlc_poll_ms=$(( timing_end_ms - timing_start_ms ))
        else
            debugecho "DEBUG VLC not running. Skipping VLC AppleScript."
        fi
    fi
    # ========================================================
    # Poll completed
    # ========================================================
    last_polled_time=$(clock_now_ms)
    debugecho "DEBUG Done checking video source. youtube_playing=$youtube_playing"
    if [[ "$youtube_playing" == "true" ]]; then
        debugecho "DEBUG Video source url=$url"; debugecho "DEBUG Video source id=$video_id"
        debugecho "DEBUG Video source thumbnail=$thumbnail_url"
    else
        url=""; video_id=""; thumbnail_url=""; playlist_name=""; debugecho "DEBUG Video source not playing."
    fi
    # ========================================================
    # Derived Time / Playback Values
    # ========================================================
    normalize_ints currentTime duration_sec
    if (( duration_sec > 0 )); then
        playback_position_percent=$(( currentTime * 100 / duration_sec ))
    else
        playback_position_percent=0
    fi
    if [[ "$youtube_playing" == "true" && "$media_source" == "youtube" ]]; then
        debugecho "DEBUG Video playing. Running binge tracker."
        binge_watch_tracker "$loop_now_epoch"
    fi
    debugecho "DEBUG Binge info: vid='${video_id:-}' pct=${playback_position_percent:-0} t=${currentTime:-0} dur=${duration_sec:-0}"
    printf -v currentTimehms '%02d:%02d' $(( currentTime / 60 )) $(( currentTime % 60 ))
    printf -v duration_hms '%02d:%02d' $(( duration_sec / 60 )) $(( duration_sec % 60 ))
    build_progress_bar "$playback_position_percent"
    normalize_state "$loop_now_epoch"
    choose_check_interval
    current_calendar_year=$(date '+%Y')
    if [[ ! "$year" =~ ^[0-9]{4}$ ]] || (( 10#$year < 1900 || 10#$year > current_calendar_year + 1 )); then
        year=""
    fi
    debugecho "DEBUG Polling status=$media_status idle=${idle_duration}s next=${next_check_interval}s"
    if [[ "$media_status" == "Music" ||
          "$media_status" == "YouTube" ]]; then
        debugecho "DEBUG Snapshotting last known media"
        snapshot_last_known_media
    fi
    # ========================================================
    # DRAW UI FIRST
    # ========================================================
    emit_cli
    # ========================================================
    # HA / Network effects AFTER local UI draw
    # ========================================================
    ha_start_ms=$(timestamp_ms)
    refresh_ha_media_active_state
    debugecho "DEBUG NowPlaying: $track | $artist"
    if should_emit; then
        emit_artwork
        emit_home_assistant
    fi
    ha_end_ms=$(timestamp_ms)
    ha_network_ms=$(( ha_end_ms - ha_start_ms ))
    # ========================================================
    # Cache Cleanup
    # ========================================================
    if (( loop_now_epoch - last_cache_cleanup > CACHE_CLEANUP_INTERVAL )); then
        cleanup_cache
        last_cache_cleanup="$loop_now_epoch"
    fi
    # ========================================================
    # Finish Profiling This Loop
    # ========================================================
    loop_end_ms=$(timestamp_ms)
    loop_work_ms=$(( loop_end_ms - loop_start_ms ))
    profile_music_ms="$music_poll_ms"; profile_browser_ms="$browser_poll_ms"; profile_vlc_ms="$vlc_poll_ms"
    profile_ha_network_ms="$ha_network_ms"
    # The selected interval is the target start-to-start cadence. Previously
    # it was added after all poll work, turning a 3-second interval into 30+
    # seconds whenever a browser scan was slow.
    sleep_ms=$(python3 - "$next_check_interval" "$loop_work_ms" <<'PY'
import sys
target_ms = float(sys.argv[1]) * 1000
work_ms = int(sys.argv[2])
print(max(0, round(target_ms - work_ms)))
PY
)
    [[ "$immediate_poll_requested" == "true" ]] && sleep_ms=0
    profile_sleep_ms="$sleep_ms"
    if (( sleep_ms > 0 )); then
        sleep "$(python3 - "$sleep_ms" <<'PY'
import sys
print(int(sys.argv[1]) / 1000)
PY
)" &
        sleep_pid=$!
        wait "$sleep_pid" 2>/dev/null || true
        sleep_pid=""
    fi
done
