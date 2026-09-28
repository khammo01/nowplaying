#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Commit or stash local source changes before updating." >&2
    exit 1
fi
git pull --ff-only
./scripts/check.sh
echo "Updated. Stop and restart NowPlaying.sh in its existing terminal to load all changes."
