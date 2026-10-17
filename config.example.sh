# Copy to config.local.sh, chmod 600, and set values separately on each Mac.

# Check the tracked upstream branch at startup and hourly while playback is idle.
# An update is installed only after it passes this Mac's full validation suite.
NOWPLAYING_AUTO_UPDATE_ENABLED=true
NOWPLAYING_AUTO_UPDATE_INTERVAL=3600
# NagBot Computer Agent: one-second local activity detection and a 30-second HA heartbeat.
NCA_ACTIVITY_INTERVAL_SEC=1
NCA_HEARTBEAT_SEC=30
# Report ordinary input idle as an attribute; lock/display sleep determine in-use state.
NCA_IDLE_THRESHOLD_SEC=300
HA_SERVER="root@homeassistant.local"
HA_BASE_URL="http://homeassistant.local:8123"
HA_API_URL="http://homeassistant.local:8123/api/webhook/REPLACE_ME"
HA_AUDIO_ENTITY="input_boolean.REPLACE_ME"
BEARER_TOKEN="REPLACE_ME"
# Stable name included in each webhook payload. Defaults to the Mac computer name.
# SOURCE_DEVICE="office-mac-mini"
# Optional: VLC movie metadata. Without a key, filename metadata is used.
OMDB_API_KEY=""
# Optional BetterTouchTool HTTP endpoint for this Mac. Leave blank to discover
# BTT on localhost and the Mac's active network interfaces. Set this only when
# BTT is deliberately bound to one address, for example:
# BTT_BASE_URL="http://192.0.2.20:51520"
BTT_BASE_URL=""
# Space-separated ports checked during automatic discovery.
BTT_PORTS="51520 51836"
# Optional: defaults to $NOWPLAYING_ROOT/ssh/id_ecdsa_ha
# SSH_KEY="$HOME/.ssh/your_home_assistant_key"
