"""Actual Home Assistant media player for NowPlaying."""

import re
from typing import Any
from urllib.parse import parse_qs, urlparse

from homeassistant.components.media_player import (
    MediaPlayerEntity,
    MediaPlayerEntityFeature,
    MediaPlayerState,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from .const import METADATA_ENTITY, QUEUE_ENTITY, QUEUE_SOURCE_ENTITY
from .entity import NowPlayingEntity, parse_clock


FEATURES = (
    MediaPlayerEntityFeature.PAUSE
    | MediaPlayerEntityFeature.PLAY
    | MediaPlayerEntityFeature.PREVIOUS_TRACK
    | MediaPlayerEntityFeature.NEXT_TRACK
    | MediaPlayerEntityFeature.SEEK
    | MediaPlayerEntityFeature.VOLUME_SET
    | MediaPlayerEntityFeature.VOLUME_STEP
    | MediaPlayerEntityFeature.SHUFFLE_SET
    | MediaPlayerEntityFeature.SELECT_SOURCE
    | MediaPlayerEntityFeature.PLAY_MEDIA
)


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddConfigEntryEntitiesCallback,
) -> None:
    async_add_entities([NowPlayingMediaPlayer(entry.entry_id)])


class NowPlayingMediaPlayer(NowPlayingEntity, MediaPlayerEntity):
    """Expose canonical NowPlaying metadata and controls as a media player."""

    _attr_name = None
    _attr_icon = "mdi:multimedia"
    _attr_supported_features = FEATURES
    watched_entity_ids = (METADATA_ENTITY, QUEUE_ENTITY, QUEUE_SOURCE_ENTITY)

    def __init__(self, entry_id: str) -> None:
        self._attr_unique_id = f"{entry_id}_media_player"

    @property
    def available(self) -> bool:
        state = self._state(METADATA_ENTITY)
        return state is not None and state.state not in ("unknown", "unavailable")

    @property
    def state(self) -> MediaPlayerState:
        state = self._state(METADATA_ENTITY)
        raw = str(state.state if state else "idle").lower()
        if raw in ("youtube", "music", "video", "playing", "vlc"):
            return MediaPlayerState.PLAYING
        if raw in ("paused", "recently paused"):
            return MediaPlayerState.PAUSED
        if raw in ("startup", "starting", "connecting", "buffering"):
            return MediaPlayerState.BUFFERING
        return MediaPlayerState.IDLE

    def _attr(self, name: str, default: Any = None) -> Any:
        state = self._state(METADATA_ENTITY)
        return state.attributes.get(name, default) if state else default

    @property
    def media_title(self) -> str | None:
        return self._attr("track") or None

    @property
    def media_artist(self) -> str | None:
        return self._attr("artist") or None

    @property
    def media_album_name(self) -> str | None:
        return self._attr("album") or None

    @property
    def media_content_type(self) -> str | None:
        source = str(self._attr("media_source", "")).lower()
        return "music" if source == "music" else "video" if source in ("youtube", "video", "vlc") else None

    @property
    def media_duration(self) -> int | None:
        return parse_clock(self._attr("duration"))

    @property
    def media_position(self) -> int | None:
        return parse_clock(self._attr("current_position"))

    @property
    def media_position_updated_at(self):
        state = self._state(METADATA_ENTITY)
        return state.last_updated if state else None

    @property
    def entity_picture(self) -> str | None:
        return self._attr("controller_artwork_url") or self._attr("thumbnail_url") or None

    @property
    def volume_level(self) -> float | None:
        value = self._attr("volume_percent")
        try:
            return min(1.0, max(0.0, float(value) / 100.0))
        except (TypeError, ValueError):
            return None

    @property
    def shuffle(self) -> bool | None:
        if not self._attr("music_shuffle_available", False):
            return None
        return bool(self._attr("music_shuffle_enabled", False))

    @property
    def source(self) -> str | None:
        selected = self._state(QUEUE_SOURCE_ENTITY)
        return selected.state if selected and selected.state not in ("unknown", "unavailable") else "Auto"

    @property
    def source_list(self) -> list[str]:
        return ["Auto", "Mac Mini", "Work Mac"]

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        queue = self._state(QUEUE_ENTITY)
        attrs = queue.attributes if queue else {}
        return {
            "active_mac": self._attr("source_device", "Unknown Mac"),
            "media_source": self._attr("media_source", ""),
            "summary": self._attr("display_synopsis") or self._attr("summary", ""),
            "video_id": self._attr("video_id", ""),
            "published": self._attr("published_relative", ""),
            "views": self._attr("view_count", ""),
            "subscribers": self._attr("subscriber_count", ""),
            "queue_count": int(queue.state) if queue and queue.state.isdigit() else 0,
            "conflict_count": int(attrs.get("conflict_count", 0) or 0),
        }

    async def _script(self, service: str, data: dict[str, Any] | None = None) -> None:
        await self.hass.services.async_call("script", service, data or {}, blocking=False)

    async def async_media_play(self) -> None:
        if self.state == MediaPlayerState.PAUSED:
            await self._script("play_pause")
        elif self.state != MediaPlayerState.PLAYING:
            await self._script("resume_last_playback")

    async def async_media_pause(self) -> None:
        if self.state == MediaPlayerState.PLAYING:
            await self._script("play_pause")

    async def async_media_play_pause(self) -> None:
        await self._script("play_pause")

    async def async_media_next_track(self) -> None:
        await self._script("next_song")

    async def async_media_previous_track(self) -> None:
        await self._script("previous_song")

    async def async_media_seek(self, position: float) -> None:
        duration = self.media_duration or 0
        if duration > 0:
            await self._script("nowplaying_seek_percent", {"percent": min(100, max(0, position * 100 / duration))})

    async def async_volume_up(self) -> None:
        await self._script("volume_up")

    async def async_volume_down(self) -> None:
        await self._script("volume_down")

    async def async_set_volume_level(self, volume: float) -> None:
        current = (self.volume_level or 0.0) * 100
        # macOS volume-key steps are approximately 6.25 percentage points.
        steps = round((min(1.0, max(0.0, volume)) * 100 - current) / 6.25)
        if steps:
            await self._script("nowplaying_set_volume", {"delta_steps": max(-16, min(16, steps))})

    async def async_set_shuffle(self, shuffle: bool) -> None:
        current = self.shuffle
        if current is not None and current != shuffle:
            await self._script("music_shuffle_toggle")

    async def async_select_source(self, source: str) -> None:
        if source in self.source_list:
            await self.hass.services.async_call(
                "input_select",
                "select_option",
                {"entity_id": QUEUE_SOURCE_ENTITY, "option": source},
                blocking=False,
            )

    async def async_play_media(self, media_type: str, media_id: str, **kwargs: Any) -> None:
        video_id = self._youtube_id(media_id)
        if not video_id:
            return
        queue = self._state(QUEUE_ENTITY)
        source = queue.attributes.get("source_device", "Mac Mini") if queue else "Mac Mini"
        await self._script("play_youtube_queue_item", {"video_id": video_id, "source_device": source})

    @staticmethod
    def _youtube_id(value: str) -> str | None:
        if re.fullmatch(r"[A-Za-z0-9_-]{11}", value or ""):
            return value
        parsed = urlparse(value or "")
        host = parsed.netloc.lower()
        if host.endswith("youtu.be"):
            candidate = parsed.path.strip("/").split("/")[0]
        elif "youtube.com" in host:
            candidate = parse_qs(parsed.query).get("v", [""])[0]
            if not candidate and parsed.path.startswith("/shorts/"):
                candidate = parsed.path.split("/")[2]
        else:
            return None
        return candidate if re.fullmatch(r"[A-Za-z0-9_-]{11}", candidate) else None
