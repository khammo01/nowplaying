"""Constants for the NowPlaying Media Remote integration."""

DOMAIN = "nowplaying"
NAME = "NowPlaying"
DEVICE_ID = "mac-media-bridge"

METADATA_ENTITY = "sensor.now_playing_metadata"
QUEUE_ENTITY = "sensor.now_playing_youtube_queue"
QUEUE_SOURCE_ENTITY = "input_select.youtube_queue_source"

PLATFORMS = ["media_player", "sensor", "binary_sensor", "select", "button"]
