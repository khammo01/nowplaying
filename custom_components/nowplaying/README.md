# NowPlaying Home Assistant integration

This custom integration turns the canonical `sensor.now_playing_metadata` feed into a real Home Assistant media player and groups related controls and diagnostics as one device.

It creates:

- `media_player.nowplaying` with play, pause, play/pause, next, previous, seek, volume up/down/set, shuffle, source selection, and YouTube `play_media` support.
- Active Mac, connection, and YouTube queue sensors.
- A multiple-videos-playing problem sensor with the candidate inventory.
- A queue-source select and metadata-refresh button.

The integration intentionally uses the existing NowPlaying sensors and scripts as its transport. Install the repo's Home Assistant configuration first, copy `custom_components/nowplaying` into Home Assistant's `custom_components` directory, restart Home Assistant, then add **NowPlaying Media Remote** from **Settings → Devices & services → Add integration**.

Queue details, conflict candidates, summaries, descriptions, and source diagnostics are exposed as attributes and companion entities. Home Assistant's standard media-player schema carries the portable playback metadata and controls; the richer NowPlaying data remains visible on the same device without being forced into unrelated standard fields.
