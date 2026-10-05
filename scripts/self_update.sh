#!/usr/bin/env bash
# Fetch, validate, and fast-forward this checkout when its upstream is newer.
# Exit 10 means the caller should restart itself to load the updated shell code.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    exit 0
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "NowPlaying update deferred: local source changes are present." >&2
    exit 0
fi

upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
if [[ -z "$upstream" ]]; then
    echo "NowPlaying update deferred: the current branch has no upstream." >&2
    exit 0
fi

remote=${upstream%%/*}
if ! GIT_TERMINAL_PROMPT=0 git \
    -c http.lowSpeedLimit=1 \
    -c http.lowSpeedTime=15 \
    fetch --quiet "$remote"; then
    echo "NowPlaying update check could not reach $remote; continuing with the current version." >&2
    exit 0
fi

head_commit=$(git rev-parse HEAD)
upstream_commit=$(git rev-parse "$upstream")
[[ "$head_commit" != "$upstream_commit" ]] || exit 0

if ! git merge-base --is-ancestor HEAD "$upstream"; then
    echo "NowPlaying update deferred: local and upstream history have diverged." >&2
    exit 0
fi

candidate=$(mktemp -d "${TMPDIR:-/tmp}/nowplaying-update.XXXXXX")
cleanup() { rm -rf "$candidate"; }
trap cleanup EXIT

if ! git archive "$upstream" | tar -x -C "$candidate"; then
    echo "NowPlaying update deferred: could not prepare the upstream candidate." >&2
    exit 0
fi

if ! (cd "$candidate" && ./scripts/check.sh); then
    echo "NowPlaying update deferred: upstream failed validation on this Mac." >&2
    exit 0
fi

if ! git merge --ff-only --quiet "$upstream"; then
    echo "NowPlaying update deferred: fast-forward failed." >&2
    exit 0
fi

echo "NowPlaying updated to $(git rev-parse --short HEAD); restarting."
exit 10
