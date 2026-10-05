#!/bin/zsh
set -u

root="${0:A:h}"
cache="$root/cache/browser-inventory.json"
lock="$root/cache/browser-inventory.lock"

mkdir -p "$root/cache"
if ! mkdir "$lock" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$lock" 2>/dev/null || true' EXIT INT TERM

inventory="$(/usr/bin/osascript "$root/browser_inventory.applescript" 2>/dev/null)" || exit 1
[[ -n "$inventory" ]] || inventory='[]'
print -r -- "$inventory" | /usr/bin/python3 "$root/update_browser_cache.py" "$cache" /tmp/nagmenu_nowplaying_tab_cache
