# NowPlaying media controllers

This directory publishes the two ESPHome hardware profiles used by the NowPlaying media remote:

| Profile | Hardware | Display | Input |
| --- | --- | --- | --- |
| `rectangle-controller.yaml` | Waveshare ESP32-S3 Touch AMOLED | 450×600 portrait panel, rotated for the enclosure | touch plus three hardware buttons |
| `rotary-controller.yaml` | Waveshare ESP32-S3 Knob | 360×360 round panel | touch, rotary encoder, and press |

Both profiles share the same media model and Home Assistant service contract. They include video and music transport, YouTube Up Next, quick actions, meeting microphone control, connection and power diagnostics, adaptive brightness and sleep, and the multiple-video conflict chooser. Their layouts remain hardware-specific so the round profile respects the usable circular area.

Install the repository's `custom_components/nowplaying` integration to expose the same feed as a native Home Assistant media player and collect its queue, source, connection, conflict, and refresh entities under one NowPlaying device.

These are reference firmware profiles from a working installation. They are intentionally published as ESPHome profiles plus a Home Assistant package, which are the native extension formats for this hardware and Home Assistant.

## Install

1. Install ESPHome 2026.10 or newer in Home Assistant.
2. Copy `esphome/` beneath your ESPHome configuration directory.
3. Copy `secrets.example.yaml` to `secrets.yaml` and add your Wi-Fi credentials.
4. Run `controllers/scripts/install-fonts.sh`. If ESPHome runs on another host, copy the resulting `fonts/` directory there.
5. Put `home-assistant/video-conflict.yaml` under your Home Assistant `packages/` directory and add `nowplaying_webhook_id` to Home Assistant's `secrets.yaml`.
6. Ensure your existing `script.nowplaying_send_to_source` accepts `source_device` and `trigger`, then install the BetterTouchTool actions with `python3 scripts/install_btt_fast_paths.py` on each Mac.
7. Set each Mac's `HA_API_URL` to the webhook URL and give each a distinct `SOURCE_DEVICE` in `config.local.sh`.
8. Adjust the profile substitutions at the top of the selected ESPHome YAML, validate it, then compile and install it through ESPHome.

The full profiles also refer to optional entities for announcements, meetings, ambient light, firmware status, and shortcuts. Rename those references to match your Home Assistant installation or remove the corresponding optional UI card. The core media contract is `sensor.now_playing_metadata`, `sensor.now_playing_youtube_queue`, and the scripts named in the ESPHome `homeassistant.action` calls.

## Privacy and credentials

The exported profiles contain no Wi-Fi password, webhook token, API token, SSH key, or private LAN address. The Work Mac BetterTouchTool host is a substitution and defaults to `work-mac.local`. The firmware uses ESPHome secrets for Wi-Fi credentials. Do not commit your populated secret files.

## Conflict chooser

Each Mac publishes every actively playing YouTube tab with a stable video ID, browser, window, tab, title, channel, duration, and thumbnail URL. Home Assistant combines the inventories. If more than one tab is playing, either controller displays the first two candidates. Choosing one pauses the others, revalidates the selected tab by video ID, starts it, and brings its browser window forward. Tabs remain open.

The two conflict thumbnails use ESPHome `online_image` objects and release their decoded buffers after the conflict clears. This keeps the idle memory cost out of the normal controller UI.

## Maintaining the profiles

The deployed firmware remains the source of truth. Before publishing an update, remove site-specific entity IDs and addresses, validate both YAML files, compile both targets, and confirm that no secret or private address is present:

```sh
rg -n 'password:|token|webhook|192\\.168\\.|10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.' controllers/
```

The rectangle profile includes the small local `qmi8658` component it needs. The rotary profile uses its upstream rotary encoder and haptic components directly.

### Meeting card volume

While the rotary meeting card is visible, the wheel changes the Work Mac’s HiDock H1 hardware output by two percentage points per detent. Dismissing the card restores the selected media control mode. Run `scripts/install_btt_fast_paths.py` on the Work Mac after updating. The Home Assistant scripts `script.work_mac_hidock_volume_up` and `script.work_mac_hidock_volume_down` must call the corresponding BTT named triggers on the Work Mac. The helper targets HiDock H1 directly and preserves the default audio output.
