#!/bin/bash
# Print the reachable BetterTouchTool HTTP base URL for this Mac. A configured
# endpoint wins; otherwise probe localhost and active local interfaces. Keeping
# this discovery in one place avoids embedding private LAN addresses in source.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="${NOWPLAYING_CONFIG:-$ROOT/config.local.sh}"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

variable_name="${1:-nowplaying_volume_notch}"
ports="${BTT_PORTS:-51520 51836}"
candidates=()

if [[ -n "${BTT_BASE_URL:-}" ]]; then
  candidates+=("${BTT_BASE_URL%/}")
fi

candidates+=("http://127.0.0.1")
for interface in en0 en1 en2 en3 en4 en5 en6 en7 en8; do
  interface_ip=$(/usr/sbin/ipconfig getifaddr "$interface" 2>/dev/null || true)
  [[ -n "$interface_ip" ]] && candidates+=("http://${interface_ip}")
done

seen=""
for candidate in "${candidates[@]}"; do
  remainder="${candidate#*://}"
  if [[ "$remainder" == *:* ]]; then
    endpoints=("$candidate")
  else
    endpoints=()
    for port in $ports; do
      endpoints+=("${candidate}:${port}")
    done
  fi
  for endpoint in "${endpoints[@]}"; do
    case " $seen " in *" $endpoint "*) continue ;; esac
    seen="$seen $endpoint"
    if /usr/bin/curl -fsS --max-time 0.35 \
        "${endpoint}/get_string_variable/?variableName=${variable_name}" \
        >/dev/null 2>&1; then
      printf '%s\n' "$endpoint"
      exit 0
    fi
  done
done

exit 1
