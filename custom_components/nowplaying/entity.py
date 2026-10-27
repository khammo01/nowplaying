"""Shared entity support for NowPlaying."""

from collections.abc import Iterable

from homeassistant.core import callback
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.entity import Entity
from homeassistant.helpers.event import async_track_state_change_event

from .const import DEVICE_ID, DOMAIN, NAME


class NowPlayingEntity(Entity):
    """Base entity backed by existing NowPlaying state entities."""

    _attr_has_entity_name = True
    _attr_should_poll = False
    _attr_device_info = DeviceInfo(
        identifiers={(DOMAIN, DEVICE_ID)},
        manufacturer="NowPlaying",
        model="Mac Media Bridge",
        name=NAME,
        configuration_url="https://github.com/khammo01/nowplaying",
    )
    watched_entity_ids: tuple[str, ...] = ()

    async def async_added_to_hass(self) -> None:
        """Refresh immediately whenever a backing entity changes."""
        await super().async_added_to_hass()
        if self.watched_entity_ids:
            self.async_on_remove(
                async_track_state_change_event(
                    self.hass,
                    self.watched_entity_ids,
                    self._handle_source_update,
                )
            )

    @callback
    def _handle_source_update(self, _event) -> None:
        self.async_write_ha_state()

    def _state(self, entity_id: str):
        return self.hass.states.get(entity_id)


def parse_clock(value: object) -> int | None:
    """Convert HH:MM:SS or MM:SS metadata to seconds."""
    try:
        parts = [int(part) for part in str(value or "").split(":")]
    except ValueError:
        return None
    if not parts or len(parts) > 3:
        return None
    total = 0
    for part in parts:
        total = total * 60 + part
    return max(0, total)
