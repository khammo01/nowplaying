#!/usr/bin/env bash
# Merge the multi-video conflict feature into a divergent NowPlaying checkout.
# The live checkout is changed only after every merge and focused check passes.
set -euo pipefail

ROOT="${1:-$HOME/NowPlaying}"
BASE_COMMIT="ba3e085"
FEATURE_COMMIT="cc2dc1d"
FILES=(
  NowPlaying.sh
  youtube_control.applescript
  scripts/install_btt_fast_paths.py
  scripts/check.sh
  tests/check_next_youtube.py
)
NEW_FILES=(scripts/install_btt_conflict_actions.py)

cd "$ROOT"
git fetch --quiet origin main
git cat-file -e "$BASE_COMMIT^{commit}"
git cat-file -e "$FEATURE_COMMIT^{commit}"

candidate=$(mktemp -d "${TMPDIR:-/tmp}/nowplaying-conflict.XXXXXX")
cleanup() { rm -rf "$candidate"; }
trap cleanup EXIT

# Recreate the current working source without caches, private credentials, or Git
# metadata. This makes validation representative while keeping private material
# out of the temporary candidate.
tar \
  --exclude=.git --exclude=cache --exclude=config.local.sh \
  --exclude='config.local.sh.*' --exclude=ssh \
  -cf - . | tar -xf - -C "$candidate"

for file in "${FILES[@]}"; do
  mkdir -p "$candidate/$(dirname "$file")"
  base_file="$candidate/.base-${file//\//_}"
  feature_file="$candidate/.feature-${file//\//_}"
  merged_file="$candidate/.merged-${file//\//_}"
  git show "$BASE_COMMIT:$file" >"$base_file"
  git show "$FEATURE_COMMIT:$file" >"$feature_file"
  if ! git merge-file -p "$ROOT/$file" "$base_file" "$feature_file" >"$merged_file"; then
    echo "Conflict feature was not installed: $file needs a manual merge." >&2
    exit 2
  fi
  cp "$merged_file" "$candidate/$file"
done

for file in "${NEW_FILES[@]}"; do
  mkdir -p "$candidate/$(dirname "$file")"
  git show "$FEATURE_COMMIT:$file" >"$candidate/$file"
done

chmod +x "$candidate/NowPlaying.sh" "$candidate/scripts/"*.py
(cd "$candidate" && \
  bash -n NowPlaying.sh scripts/check.sh && \
  python3 -m py_compile scripts/install_btt_fast_paths.py scripts/install_btt_conflict_actions.py && \
  python3 tests/check_next_youtube.py && \
  osacompile -o "$candidate/youtube-control-check.scpt" youtube_control.applescript)

stamp=$(date +%Y%m%d-%H%M%S)
for file in "${FILES[@]}"; do
  cp "$ROOT/$file" "$ROOT/$file.before-video-conflict-$stamp"
  cp "$candidate/$file" "$ROOT/$file"
done
for file in "${NEW_FILES[@]}"; do
  cp "$candidate/$file" "$ROOT/$file"
done

python3 "$ROOT/scripts/install_btt_conflict_actions.py"
pid=$(jq -r '.pid // empty' "$ROOT/cache/nowplaying.lock/lock.json" 2>/dev/null || true)
if [[ "$pid" =~ ^[0-9]+$ ]]; then kill -USR1 "$pid" 2>/dev/null || true; fi
echo "Installed multi-video conflict support without replacing local checkout changes."
