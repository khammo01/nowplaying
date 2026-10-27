"""Refresh control for the NowPlaying device."""

from homeassistant.components.button import ButtonEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from .entity import NowPlayingEntity


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddConfigEntryEntitiesCallback) -> None:
    async_add_entities([RefreshButton(entry.entry_id)])


class RefreshButton(NowPlayingEntity, ButtonEntity):
    _attr_name = "Refresh Metadata"
    _attr_icon = "mdi:refresh"

    def __init__(self, entry_id: str) -> None:
        self._attr_unique_id = f"{entry_id}_refresh"

    async def async_press(self) -> None:
        await self.hass.services.async_call("script", "nowplaying_request_refresh", {}, blocking=False)
