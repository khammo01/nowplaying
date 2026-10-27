"""Conflict status for the NowPlaying device."""

from homeassistant.components.binary_sensor import BinarySensorDeviceClass, BinarySensorEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from .const import QUEUE_ENTITY
from .entity import NowPlayingEntity


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddConfigEntryEntitiesCallback) -> None:
    async_add_entities([PlaybackConflictSensor(entry.entry_id)])


class PlaybackConflictSensor(NowPlayingEntity, BinarySensorEntity):
    _attr_name = "Multiple Videos Playing"
    _attr_device_class = BinarySensorDeviceClass.PROBLEM
    watched_entity_ids = (QUEUE_ENTITY,)

    def __init__(self, entry_id: str) -> None:
        self._attr_unique_id = f"{entry_id}_playback_conflict"

    @property
    def is_on(self) -> bool:
        state = self._state(QUEUE_ENTITY)
        return bool(state and int(state.attributes.get("conflict_count", 0) or 0) > 1)

    @property
    def extra_state_attributes(self):
        state = self._state(QUEUE_ENTITY)
        return {"items": state.attributes.get("conflict_items", [])} if state else {}
