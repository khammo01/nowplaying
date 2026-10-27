#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_CHECK="$(mktemp -d)"
trap 'rm -rf "$TMP_CHECK"' EXIT
bash -n "$ROOT/NowPlaying.sh" "$ROOT/config.example.sh" "$ROOT/scripts/check.sh" "$ROOT/scripts/update.sh" "$ROOT/scripts/self_update.sh" "$ROOT/media_command.sh" "$ROOT/scripts/nagbot_computer_agent.sh" "$ROOT/scripts/nca_plugins/session_state.sh"
for name in safari_youtube_nowplaying VLC_nowplaying open_youtube_window next_youtube_video browser_inventory youtube_control youtube_target_command; do
    osacompile -o "$TMP_CHECK/$name.scpt" "$ROOT/$name.applescript"
done
python3 "$ROOT/tests/check_playback.py"
python3 "$ROOT/tests/check_applescript_media_hosts.py"
python3 "$ROOT/tests/check_shell.py"
python3 "$ROOT/tests/check_volume_read.py"
python3 "$ROOT/tests/check_lock.py"
python3 "$ROOT/tests/check_next_youtube.py"
python3 "$ROOT/tests/check_browser_cache.py"
python3 "$ROOT/tests/check_media_remote_fast_path.py"
python3 "$ROOT/tests/check_self_update.py"
python3 -m py_compile "$ROOT/scripts/install_btt_fast_paths.py" "$ROOT/scripts/install_btt_exact_youtube.py" "$ROOT/scripts/install_btt_conflict_actions.py"
echo "All checks passed (no Home Assistant requests sent)."
