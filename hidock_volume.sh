#!/bin/bash
# Adjust only the HiDock H1 hardware output, preserving all audio routing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
case "${1:---read}" in --read|+5|-5) ;; *) echo 'Expected --read, +5, or -5' >&2; exit 2;; esac
mkdir -p "$ROOT/cache"
helper="$ROOT/cache/hidock-volume"
if [[ ! -x "$helper" || "$ROOT/hidock_volume.swift" -nt "$helper" ]]; then
    candidate="$helper.build.$$"
    trap 'rm -f "$candidate"' EXIT
    /usr/bin/xcrun swiftc -O "$ROOT/hidock_volume.swift" -o "$candidate"
    mv "$candidate" "$helper"
    trap - EXIT
fi
exec "$helper" "${1:---read}"
