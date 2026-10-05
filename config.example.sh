# Copy to config.local.sh, chmod 600, and set values separately on each Mac.

# Check the tracked upstream branch at startup and hourly while playback is idle.
# An update is installed only after it passes this Mac's full validation suite.
NOWPLAYING_AUTO_UPDATE_ENABLED=true
NOWPLAYING_AUTO_UPDATE_INTERVAL=3600
HA_SERVER="root@homeassistant.local"
HA_BASE_URL="http://homeassistant.local:8123"
HA_API_URL="http://homeassistant.local:8123/api/webhook/REPLACE_ME"
HA_AUDIO_ENTITY="input_boolean.REPLACE_ME"
BEARER_TOKEN="REPLACE_ME"
# Stable name included in each webhook payload. Defaults to the Mac computer name.
# SOURCE_DEVICE="office-mac-mini"
# Optional: VLC movie metadata. Without a key, filename metadata is used.
OMDB_API_KEY=""
# Optional: defaults to $NOWPLAYING_ROOT/ssh/id_ecdsa_ha
# SSH_KEY="$HOME/.ssh/your_home_assistant_key"
