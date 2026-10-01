# NowPlaying

macOS media detection for Music, Safari, Google Chrome, and VLC. Publishes playback state and artwork to Home Assistant and displays status in a terminal.

## Setup

Requires macOS, Bash, `jq`, Python 3, and the macOS `osascript`/`osacompile` tools. Install VLC if you want its sensor. AppleScript compilation may require VLC to be installed. Safari must allow JavaScript from Apple Events; Chrome users must enable **View → Developer → Allow JavaScript from Apple Events**. Grant the launching terminal the Automation permissions requested for browsers, media apps, and System Events.

1. Clone [khammo01/nowplaying](https://github.com/khammo01/nowplaying) to `~/NowPlaying` on a new computer (`git clone https://github.com/khammo01/nowplaying.git ~/NowPlaying`). For an existing installation, follow [migration instructions](docs/MIGRATION.md) first.
2. Copy `config.example.sh` to `config.local.sh`, run `chmod 600 config.local.sh`, and fill in this computer's Home Assistant settings. Use the appropriate audio entity for each Mac. If both Macs share an entity/webhook, they can overwrite one another's state.
3. Set `SSH_KEY` to a local key authorized to copy artwork to the configured Home Assistant server. The default is `ssh/id_ecdsa_ha` beneath the checkout. Keys must be provisioned separately; they never sync through Git.
4. Run `./scripts/check.sh`, then `./NowPlaying.sh`.

`NOWPLAYING_CONFIG=/absolute/path/to/config.local.sh ./NowPlaying.sh` selects an alternate local configuration. `OMDB_API_KEY` is optional; VLC falls back to filename metadata without it.

## Files

- `NowPlaying.sh`: polling, Music sensor, state normalization, artwork, Home Assistant output, terminal display.
- `safari_youtube_nowplaying.applescript`: cached fast-path and full-tab discovery across Safari and Chrome, iframe-aware media detection, YouTube/Shorts metadata, and generic-site metadata. Browser playback is restricted to dedicated media hosts; shopping, news, and other unlisted sites are ignored regardless of video length, embedded players, or Media Session state. Both discovery and metadata paths enforce the same policy.
- `open_youtube_window.applescript`: brings forward the Safari window containing the most YouTube tabs and selects its first YouTube tab. If none are open, it opens the YouTube home page.
- `VLC_nowplaying.applescript`: VLC metadata and optional OMDb lookup; reads the exported `OMDB_API_KEY`.
- `default_music.jpg`: fallback artwork used by the shell.
- `scripts/check.sh`: syntax, AppleScript compilation, browser playback regression checks, and isolated shell orchestration tests with mocked network calls.
- `scripts/update.sh`: refuses uncommitted changes, pulls using `--ff-only`, and validates the result. It never auto-merges or discards local changes.

Home Assistant receives one versioned JSON document per meaningful media update. Payloads include a schema version, event ID, source-device name, and send timestamp so Home Assistant can keep one canonical metadata sensor without reconstructing media state from many helpers. Webhook delivery uses bounded connection/response timeouts and limited retries; a slow Home Assistant instance cannot stall the polling loop indefinitely.

The runner executes readable `.applescript` source directly. Edit and commit those files, not compiled `.scpt` files. No build is needed to run. Old compiled files on an existing Mac are ignored compatibility artifacts for an already-running older loop.

## Sync changes

For pushing, authenticate Git on each Mac separately (for example, install GitHub CLI and run `gh auth login`). Browser sign-in alone does not authenticate command-line Git.

Before editing, run `./scripts/update.sh`. After making changes:

```sh
./scripts/check.sh
git diff
git add NowPlaying.sh safari_youtube_nowplaying.applescript VLC_nowplaying.applescript
# Stage any other intended source/docs/test changes explicitly.
git commit -m "Describe the change"
git push
```

On the other Mac, run `./scripts/update.sh`, then stop and restart the existing `NowPlaying.sh` process in its terminal. Source changes to AppleScripts are read on subsequent polls; shell and config changes require a restart. Keep one polling process per Mac. YouTube descriptions and summaries are emitted only when their page metadata belongs to the current video, so cached metadata from a previous Safari page cannot be published as the current description.

When both computers have commits, do not force-push or reset away either copy. Fetch, compare, and merge on a branch, resolve source conflicts, run checks, then push. The update helper intentionally stops if a fast-forward is impossible.

## Private local files

The root `.gitignore` uses an allowlist. Local settings, SSH keys, certificates, credentials, state JSON, caches, logs, compiled scripts, and `local-archive/` are excluded. New top-level source files must be added to the allowlist deliberately. Review `git diff --cached` before committing; never use `git add -f` on private files.

See [cleanup notes](docs/CLEANUP.md) for the migration archive and remaining implementation limitations.

## Browser media allowlist

Allowed services: YouTube (including Music), Netflix, Hulu, Disney+, Max/HBO Max,
Prime Video, Apple TV, Peacock, Paramount+, Twitch, Vimeo, Dailymotion,
Crunchyroll, Tubi, Pluto TV, Spotify, Apple Music, Amazon Music, SoundCloud,
Pandora, Tidal, Deezer, Bandcamp, and Plex Web (`app.plex.tv`). Exact hosts and
their subdomains match; lookalike suffixes do not. Amazon shopping pages are
excluded; use `primevideo.com` or `music.amazon.com` for Amazon media.
Intentional playback on any other site is also ignored. To add a service,
update `mediaHosts` in both JavaScript paths and the playback regression cases.
Native Music and VLC detection is unchanged.
