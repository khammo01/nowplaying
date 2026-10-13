#!/usr/bin/env bash
# NagBot Computer Agent: lightweight local computer-state service for HA.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_ROOT="$ROOT/cache"
CONFIG_FILE="${NOWPLAYING_CONFIG:-$ROOT/config.local.sh}"
STATE_FILE="$CACHE_ROOT/nagbot-computer-agent-state.json"
LOCK_DIR="$CACHE_ROOT/nagbot-computer-agent.lock"
INTERVAL="${NCA_ACTIVITY_INTERVAL_SEC:-1}"
HEARTBEAT="${NCA_HEARTBEAT_SEC:-30}"
IDLE_THRESHOLD="${NCA_IDLE_THRESHOLD_SEC:-300}"
mkdir -p "$CACHE_ROOT"
[[ -r "$CONFIG_FILE" ]] || exit 1
# shellcheck disable=SC1090
source "$CONFIG_FILE"
: "${HA_BASE_URL:?Set HA_BASE_URL in config.local.sh}"
: "${BEARER_TOKEN:?Set BEARER_TOKEN in config.local.sh}"
SOURCE_DEVICE="${SOURCE_DEVICE:-$(scutil --get ComputerName 2>/dev/null || hostname -s)}"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  old_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
  if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then exit 0; fi
  rm -rf "$LOCK_DIR"; mkdir "$LOCK_DIR" || exit 1
fi
printf '%s\n' "$$" > "$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR"' EXIT INT TERM

last_signature=""; last_emit=0
while true; do
  now=$(date +%s)
  session=$("$ROOT/scripts/nca_plugins/session_state.sh" 2>/dev/null || printf '{}')
  jq -e . >/dev/null 2>&1 <<<"$session" || session='{}'
  locked=$(jq -r '.locked // false' <<<"$session")
  screen_off=$(jq -r '.display_asleep // false' <<<"$session")
  idle_seconds=$(jq -r '.idle_seconds // 0' <<<"$session")
  [[ "$idle_seconds" =~ ^[0-9]+$ ]] || idle_seconds=0
  idle=false; (( idle_seconds >= IDLE_THRESHOLD )) && idle=true
  in_use=true; reason=active
  if [[ "$locked" == true ]]; then in_use=false; reason=locked
  elif [[ "$screen_off" == true ]]; then in_use=false; reason="screen off"
  fi
  nowplaying_running=false
  if pgrep -f "$ROOT/NowPlaying.sh" >/dev/null 2>&1; then nowplaying_running=true; fi
  nowplaying_version=$(git -C "$ROOT" describe --always --dirty 2>/dev/null || printf unknown)
  agent_version="$nowplaying_version"
  sent_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  payload=$(jq -nc \
    --arg source_device "$SOURCE_DEVICE" --arg sent_at "$sent_at" --arg reason "$reason" \
    --arg agent_version "$agent_version" --arg nowplaying_version "$nowplaying_version" \
    --argjson in_use "$in_use" --argjson locked "$locked" --argjson screen_off "$screen_off" \
    --argjson idle "$idle" --argjson idle_seconds "$idle_seconds" \
    --argjson nowplaying_running "$nowplaying_running" --argjson updated_epoch "$now" \
    '{schema_version:1,source_device:$source_device,sent_at:$sent_at,updated_epoch:$updated_epoch,
      in_use:$in_use,active:$in_use,idle:$idle,idle_seconds:$idle_seconds,locked:$locked,
      screen_off:$screen_off,screensaver:$locked,sleeping:$screen_off,fast_user_switched:false,
      terminating:false,reason:$reason,agent_version:$agent_version,
      detector_plugins:{session_state:{status:"ok",locked:$locked,screen_off:$screen_off,idle_seconds:$idle_seconds}},
      tools:{nowplaying:{running:$nowplaying_running,suspended:($in_use|not),version:$nowplaying_version}}}' )
  tmp="$STATE_FILE.tmp.$$"; printf '%s\n' "$payload" > "$tmp" && mv "$tmp" "$STATE_FILE"
  signature=$(jq -c 'del(.sent_at,.updated_epoch,.tools.nowplaying.version,.agent_version)' <<<"$payload")
  if [[ "$signature" != "$last_signature" || $((now-last_emit)) -ge "$HEARTBEAT" ]]; then
    curl -sS --connect-timeout 2 --max-time 4 -o /dev/null \
      -H "Authorization: Bearer $BEARER_TOKEN" -H 'Content-Type: application/json' \
      -d "$payload" "$HA_BASE_URL/api/events/nagbot_computer_agent_state" || true
    last_signature="$signature"; last_emit="$now"
  fi
  [[ "${1:-}" == "--once" ]] && break
  sleep "$INTERVAL"
done
