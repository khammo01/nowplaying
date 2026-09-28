# NowPlaying

macOS media detection for Music, Safari (YouTube and other sites), and VLC. Publishes playback state and artwork to Home Assistant and displays status in a terminal.

## Setup

Requires macOS, Bash, `jq`, Python 3, and the macOS `osascript`/`osacompile` tools. Install VLC if you want its sensor. AppleScript compilation may require VLC to be installed. Safari must allow JavaScript from Apple Events; grant the launching terminal the Automation permissions requested for the media apps/System Events.

1. Clone the repository to `~/NowPlaying` on a new computer. For an existing installation, follow [migration instructions](docs/MIGRATION.md) first.
2. Copy `config.example.sh` to `config.local.sh`, run `chmod 600 config.local.sh`, and fill in this computer's Home Assistant settings. Use the appropriate audio entity for each Mac. If both Macs share an entity/webhook, they can overwrite one another's state.
3. Set `SSH_KEY` to a local key authorized to copy artwork to the configured Home Assistant server. The default is `ssh/id_ecdsa_ha` beneath the checkout. Keys must be provisioned separately; they never sync through Git.
4. Run `./scripts/check.sh`, then `./NowPlaying.sh`.

`NOWPLAYING_CONFIG=/absolute/path/to/config.local.sh ./NowPlaying.sh` selects an alternate local configuration. `OMDB_API_KEY` is optional; VLC falls back to filename metadata without it.

## Files

- `NowPlaying.sh`: polling, Music sensor, state normalization, artwork, Home Assistant output, terminal display.
- `safari_youtube_nowplaying.applescript`: tab selection and Safari metadata. NYTimes/Washington Post video elements qualify only when duration is at least 10 seconds; unknown lengths wait, live streams qualify, and audio is unaffected. Media Session alone cannot activate those news sites. This is a duration filter, not a universal user-gesture detector.
- `VLC_nowplaying.applescript`: VLC metadata and optional OMDb lookup; reads the exported `OMDB_API_KEY`.
- `default_music.jpg`: fallback artwork used by the shell.
- `scripts/check.sh`: syntax, AppleScript compilation, 112 Safari playback checks, and isolated shell orchestration tests with mocked network calls.
- `scripts/update.sh`: refuses uncommitted changes, pulls using `--ff-only`, and validates the result. It never auto-merges or discards local changes.

The runner executes readable `.applescript` source directly. Edit and commit those files, not compiled `.scpt` files. No build is needed to run. Old compiled files on an existing Mac are ignored compatibility artifacts for an already-running older loop.

## Sync changes

Before editing, run `./scripts/update.sh`. After making changes:

```sh
./scripts/check.sh
git diff
git add NowPlaying.sh safari_youtube_nowplaying.applescript VLC_nowplaying.applescript
# Stage any other intended source/docs/test changes explicitly.
git commit -m "Describe the change"
git push
```

On the other Mac, run `./scripts/update.sh`, then stop and restart the existing `NowPlaying.sh` process in its terminal. Source changes to AppleScripts are read on subsequent polls; shell and config changes require a restart. Keep one polling process per Mac.

When both computers have commits, do not force-push or reset away either copy. Fetch, compare, and merge on a branch, resolve source conflicts, run checks, then push. The update helper intentionally stops if a fast-forward is impossible.

## Private local files

The root `.gitignore` uses an allowlist. Local settings, SSH keys, certificates, credentials, state JSON, caches, logs, compiled scripts, and `local-archive/` are excluded. New top-level source files must be added to the allowlist deliberately. Review `git diff --cached` before committing; never use `git add -f` on private files.

See [cleanup notes](docs/CLEANUP.md) for the migration archive and remaining implementation limitations.
