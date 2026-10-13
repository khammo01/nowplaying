#!/usr/bin/env bash

# Report whether this Mac's interactive desktop is usable. This intentionally
# does not treat a running terminal, a background poller, or ordinary HID idle
# time as proof of use. It mirrors the useful Companion signals: session lock
# and display sleep. Failures stay active so a probe error cannot power down a
# monitor unexpectedly.

set -u

locked="false"
display_asleep="false"
idle_seconds=0

if command -v ioreg >/dev/null 2>&1; then
    root_state=$(ioreg -n Root -d1 2>/dev/null || true)
    if [[ "$root_state" =~ \"CGSSessionScreenIsLocked\"[[:space:]]*=[[:space:]]*Yes ]]; then
        locked="true"
    fi

    idle_ns=$(ioreg -c IOHIDSystem -r -d 1 2>/dev/null |
        awk -F'= ' '/HIDIdleTime/{gsub(/ /,"",$2); print $2; exit}')
    if [[ "${idle_ns:-}" =~ ^[0-9]+$ ]]; then
        idle_seconds=$(( idle_ns / 1000000000 ))
    fi
fi

if command -v osascript >/dev/null 2>&1; then
    asleep=$(osascript -l JavaScript \
        -e 'ObjC.import("CoreGraphics"); $.CGDisplayIsAsleep($.CGMainDisplayID())' \
        2>/dev/null || true)
    [[ "$asleep" == "1" ]] && display_asleep="true"
fi

active="true"
reason="active"
if [[ "$locked" == "true" ]]; then
    active="false"; reason="locked"
elif [[ "$display_asleep" == "true" ]]; then
    active="false"; reason="display asleep"
fi

jq -nc \
    --argjson active "$active" \
    --argjson locked "$locked" \
    --argjson display_asleep "$display_asleep" \
    --argjson idle_seconds "$idle_seconds" \
    --arg reason "$reason" \
    '{active:$active,locked:$locked,display_asleep:$display_asleep,idle_seconds:$idle_seconds,reason:$reason}'
