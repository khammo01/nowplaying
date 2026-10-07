#!/bin/bash
# Apply one settled rotary gesture through BetterTouchTool's low-level Volume
# Up/Down actions. Those are the same actions used by the working desktop
# controls and are intercepted correctly by SoundSource. One rotary detent
# produces exactly one BTT volume notch.

set -u

CACHE_FILE="${HOME}/NowPlaying/cache/soundsource-volume-percent"
LOG_FILE="/tmp/nowplaying-volume-adjust.log"
LOCK_DIR="${HOME}/NowPlaying/cache/volume-action.lock"

delta="${1:-0}"

if ! [[ "$delta" =~ ^-?[0-9]+$ ]]; then
  printf 'invalid delta: <%s>\n' "$delta" > "$LOG_FILE"
  exit 2
fi

delta=$((delta))
(( delta < -16 )) && delta=-16
(( delta > 16 )) && delta=16

# BTT launches fast-path shell actions independently. Serialize them here so a
# second settled gesture waits behind the first instead of competing with it
# or disappearing while BTT is still emitting native volume-key events.
mkdir -p "${HOME}/NowPlaying/cache"
lock_acquired=false
for (( lock_attempt=0; lock_attempt<250; lock_attempt++ )); do
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    lock_acquired=true
    break
  fi
  sleep 0.02
done
if [[ "$lock_acquired" != true ]]; then
  printf 'delta=%s status=4 reason=volume-queue-timeout\n' "$delta" > "$LOG_FILE"
  exit 4
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

started_ms=$(( $(date +%s%N) / 1000000 ))

if (( delta > 0 )); then
  action_type=24
  action_name="Volume Up"
  count=$delta
elif (( delta < 0 )); then
  action_type=25
  action_name="Volume Down"
  count=$(( -delta ))
else
  action_type=0
  action_name="None"
  count=0
fi

# The Mini and Work Mac use different BTT webserver ports. BTT may listen only
# on one physical interface rather than localhost. Probe every active Mac
# address; the Mini commonly has Ethernet and Wi-Fi active at the same time.
btt_base=""
computer_name=$(/usr/sbin/scutil --get ComputerName 2>/dev/null || /bin/hostname -s)
computer_name_lower=$(printf '%s' "$computer_name" | /usr/bin/tr '[:upper:]' '[:lower:]')
if [[ "$computer_name_lower" == *"mac mini"* || "$computer_name_lower" == *"mac-mini"* ]]; then
  # BTT on the Mini is intentionally bound to Wi-Fi. Ignore Ethernet.
  local_ips=(192.168.1.26)
elif [[ "$computer_name_lower" == *"macbook"* || "$computer_name_lower" == *"work mac"* ]]; then
  local_ips=(192.168.1.179)
else
  local_ips=(127.0.0.1)
  for interface in en0 en1 en5 en6 en7 en8; do
    interface_ip=$(/usr/sbin/ipconfig getifaddr "$interface" 2>/dev/null || true)
    [[ -n "$interface_ip" ]] && local_ips+=("$interface_ip")
  done
fi
for local_ip in "${local_ips[@]}"; do
  for local_port in 51520 51836; do
    candidate_base="http://${local_ip}:${local_port}"
  [[ "$candidate_base" == "http://:51520" || "$candidate_base" == "http://:51836" ]] && continue
  if /usr/bin/curl -fsS --max-time 0.35 \
      "${candidate_base}/get_string_variable/?variableName=nowplaying_volume_notch" >/dev/null 2>&1; then
    btt_base="$candidate_base"
    break
  fi
  done
  [[ -n "$btt_base" ]] && break
done

# Snapshot the display-only notch before emitting any key events. The BTT
# triggers may update their own variables asynchronously; reading afterward
# and adding the delta again could make the controller feedback jump twice.
current_step=""
if [[ -n "$btt_base" ]]; then
  current_step=$(/usr/bin/curl -fsS --max-time 1 \
    "${btt_base}/get_string_variable/?variableName=nowplaying_volume_notch" 2>/dev/null || true)
fi
if ! [[ "$current_step" =~ ^[0-9]+$ ]]; then
  cached_percent=$(cat "$CACHE_FILE" 2>/dev/null || printf 0)
  [[ "$cached_percent" =~ ^[0-9]+$ ]] || cached_percent=0
  current_step=$(( (cached_percent * 16 + 50) / 100 ))
fi

status=0
if (( count > 0 )); then
  if [[ -z "$btt_base" ]]; then
    status=3
  else
    trigger_name=$([[ "$action_type" == 24 ]] && printf mac_mini_volume_up || printf mac_mini_volume_down)
    for (( i=0; i<count; i++ )); do
      # These established BTT triggers send the same low-level volume key used
      # by the keyboard. That preserves SoundSource routing and the native HUD.
      /usr/bin/curl -fsS --max-time 1 -o /dev/null \
        --get "${btt_base}/trigger_named/" \
        --data-urlencode "trigger_name=${trigger_name}" || {
          status=$?
          break
        }
      /bin/sleep 0.045
    done
  fi
else
  status=0
fi

if (( status == 0 )); then
  # Commands remain purely relative. Track the resulting notch only for UI
  # feedback; it is never used to set the Mac's audio level.
  target_step=$(( current_step + delta ))
  (( target_step < 0 )) && target_step=0
  (( target_step > 16 )) && target_step=16
  reported_percent=$(( (target_step * 100 + 8) / 16 ))
  printf '%s' "$reported_percent" > "$CACHE_FILE"
  if [[ -n "$btt_base" ]]; then
    /usr/bin/curl -fsS --max-time 1 -o /dev/null \
      "${btt_base}/set_string_variable/?variableName=nowplaying_volume_notch&to=${target_step}" \
      || true
  fi

  # Wake the running collector without starting a duplicate process. This is
  # best-effort because BTT also returns before a full metadata poll completes.
  pid_file="${HOME}/NowPlaying/cache/nowplaying.lock/pid"
  if [[ -r "$pid_file" ]]; then
    collector_pid=$(<"$pid_file")
    if [[ "$collector_pid" =~ ^[0-9]+$ ]]; then
      kill -USR1 "$collector_pid" 2>/dev/null || true
    fi
  fi
fi

ended_ms=$(( $(date +%s%N) / 1000000 ))
printf 'delta=%s resulting_notch=%s action=%s count=%s status=%s elapsed_ms=%s\n' \
  "$delta" "${target_step:-unknown}/16" "$action_name" "$count" "$status" \
  "$((ended_ms - started_ms))" > "$LOG_FILE"

exit "$status"
