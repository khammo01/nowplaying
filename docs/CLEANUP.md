# Cleanup review — 2026-09-28

The active process on the initial Mac ran `NowPlaying.sh`, which called the Safari and VLC compiled scripts. No references to the retired helpers were found in the active scripts, user LaunchAgents, shell startup files, or inspected configuration. No accessibility watcher process was running.

## Kept

The polling shell, both active AppleScripts (now text source), fallback artwork, local state/cache, and the SSH directory. The SSH directory is private and excluded in full: keys may be used outside this project, so no attempt was made to delete individual keys.

## Archived locally

`local-archive/2026-09-28/` is an ignored recovery directory, not part of the repository:

- The original `NowPlaying.sh` before credential extraction and cleanup.
- `NowPlaying_old.sh` and `NowPlaying_vlc_integrated.sh`: superseded runner copies.
- Safari `copy`, `old`, and `before-news-filter` compiled copies.
- `AXSafariWatcher.swift`, `ax_safari_watcher`, `build_ax_watcher.sh`, and `nowplaying_trigger.sh`: an unconnected prototype that only echoed triggers; the trigger wrapper also depended on `flock`.
- `yt_meta.js`: an old extractor not referenced by the active Safari script or runner.
- `image.png`, `youtube_artwork.jpg`, and `watch_and_sync.json`: unreferenced project artifacts. Current artwork is generated in `/tmp` or the cache; current state is `nowplaying_state.json`.
- Root `client_secret.json`, `fullchain.pem`, `id_ed25519`, and its public key: not referenced by the active setup. Kept privately for recovery rather than deleted.

The two active `.scpt` files remain ignored in the project root for compatibility with the already-running pre-cleanup loop. The new runner uses text source. They can be archived after the old loop has been stopped and any external callers have been checked.

## Code changes

- Home Assistant credentials and addresses moved into private `config.local.sh`; audio entity and base URL are machine-specific settings.
- OMDb key moved from VLC source to the `OMDB_API_KEY` environment variable exported by the runner.
- Removed four uncalled helpers: `compute_relative_time`, `jq_escape`, `json_string`, and `resolve_year_itunes`. The separately used iTunes artwork lookup remains.
- Removed a duplicate environment heading and empty spacing left by retired helpers.
- Fixed a missing newline that attached the CPU-reading assignment to a debug call, leaving CPU diagnostics stale.
- Added dependency/config checks, readable source, regression tests, and a conservative fast-forward update helper.

## Remaining limits

This was a dependency/credential cleanup, not a rewrite of playback arbitration. The legacy shell still labels generic Safari/VLC output as YouTube, and has overlapping idle/CoreAudio normalization. Concurrent Music and Safari playback can mix source labels/metadata; changing the arbitration needs a separate explicit behavior decision and regression cases. External requests also retain the original retry/timeout behavior. The Mac mini's different version must be compared before further refactoring or deployment there.
