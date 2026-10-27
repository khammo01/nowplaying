"""Queue source selection for the NowPlaying device."""

from homeassistant.components.select import SelectEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from .const import QUEUE_SOURCE_ENTITY
from .entity import NowPlayingEntity


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddConfigEntryEntitiesCallback) -> None:
    async_add_entities([QueueSourceSelect(entry.entry_id)])


class QueueSourceSelect(NowPlayingEntity, SelectEntity):
    _attr_name = "Queue Source"
    _attr_icon = "mdi:devices"
    _attr_options = ["Auto", "Mac Mini", "Work Mac"]
    watched_entity_ids = (QUEUE_SOURCE_ENTITY,)

    def __init__(self, entry_id: str) -> None:
        self._attr_unique_id = f"{entry_id}_queue_source"

    @property
    def current_option(self):
        state = self._state(QUEUE_SOURCE_ENTITY)
        return state.state if state and state.state in self.options else "Auto"

    async def async_select_option(self, option: str) -> None:
        await self.hass.services.async_call("input_select", "select_option", {"entity_id": QUEUE_SOURCE_ENTITY, "option": option}, blocking=False)
