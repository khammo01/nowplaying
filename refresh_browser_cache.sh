#!/bin/zsh
set -u

root="${0:A:h}"
cache="$root/cache/browser-inventory.json"
lock="$root/cache/browser-inventory.lock"

mkdir -p "$root/cache"
if ! mkdir "$lock" 2>/dev/null; then
  # A terminated scan used to leave this empty directory behind forever,
  # silently disabling every future inventory refresh. Respect a live owner,
  # but reclaim an ownerless/dead lock after a short grace period.
  lock_pid="$(cat "$lock/pid" 2>/dev/null || true)"
  if [[ "$lock_pid" =~ ^[0-9]+$ ]] && kill -0 "$lock_pid" 2>/dev/null; then
    exit 0
  fi
  lock_mtime="$(/usr/bin/stat -f %m "$lock" 2>/dev/null || print 0)"
  now="$(/bin/date +%s)"
  if (( now - lock_mtime < 120 )); then
    exit 0
  fi
  /bin/unlink "$lock/pid" 2>/dev/null || true
  rmdir "$lock" 2>/dev/null || exit 0
  mkdir "$lock" 2>/dev/null || exit 0
fi
print -r -- "$$" > "$lock/pid"
trap '/bin/unlink "$lock/pid" 2>/dev/null || true; rmdir "$lock" 2>/dev/null || true' EXIT INT TERM

inventory="$(/usr/bin/python3 - "$root/browser_inventory.applescript" <<'PY'
import subprocess
import sys

try:
    result = subprocess.run(
        ["/usr/bin/osascript", sys.argv[1]],
        capture_output=True,
        text=True,
        timeout=20,
        check=False,
    )
except subprocess.TimeoutExpired:
    raise SystemExit(1)
if result.returncode:
    raise SystemExit(result.returncode)
print(result.stdout, end="")
PY
)" || exit 1
[[ -n "$inventory" ]] || inventory='[]'
print -r -- "$inventory" | /usr/bin/python3 "$root/update_browser_cache.py" "$cache" /tmp/nagmenu_nowplaying_tab_cache
