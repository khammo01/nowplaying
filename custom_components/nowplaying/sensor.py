"""Companion sensors for the NowPlaying device."""

from datetime import datetime, timezone

from homeassistant.components.sensor import SensorEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from .const import METADATA_ENTITY, QUEUE_ENTITY
from .entity import NowPlayingEntity


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddConfigEntryEntitiesCallback) -> None:
    async_add_entities([ActiveMacSensor(entry.entry_id), QueueSensor(entry.entry_id), ConnectionSensor(entry.entry_id)])


class ActiveMacSensor(NowPlayingEntity, SensorEntity):
    _attr_name = "Active Mac"
    _attr_icon = "mdi:desktop-classic"
    watched_entity_ids = (METADATA_ENTITY,)

    def __init__(self, entry_id: str) -> None:
        self._attr_unique_id = f"{entry_id}_active_mac"

    @property
    def native_value(self):
        state = self._state(METADATA_ENTITY)
        return state.attributes.get("source_device", "Unknown Mac") if state else "Unknown Mac"


class QueueSensor(NowPlayingEntity, SensorEntity):
    _attr_name = "YouTube Queue"
    _attr_icon = "mdi:playlist-play"
    _attr_native_unit_of_measurement = "videos"
    watched_entity_ids = (QUEUE_ENTITY,)

    def __init__(self, entry_id: str) -> None:
        self._attr_unique_id = f"{entry_id}_queue"

    @property
    def native_value(self):
        state = self._state(QUEUE_ENTITY)
        try:
            return int(state.state) if state else 0
        except ValueError:
            return 0

    @property
    def extra_state_attributes(self):
        state = self._state(QUEUE_ENTITY)
        return {"source_device": state.attributes.get("source_device", ""), "items": state.attributes.get("queue_items", [])} if state else {}


class ConnectionSensor(NowPlayingEntity, SensorEntity):
    _attr_name = "Connection"
    _attr_icon = "mdi:home-assistant"
    watched_entity_ids = (METADATA_ENTITY,)

    def __init__(self, entry_id: str) -> None:
        self._attr_unique_id = f"{entry_id}_connection"

    @property
    def native_value(self):
        state = self._state(METADATA_ENTITY)
        if not state or state.state in ("unknown", "unavailable"):
            return "Disconnected"
        age = (datetime.now(timezone.utc) - state.last_updated).total_seconds()
        return "Connected" if age < 180 else "Stale"

    @property
    def extra_state_attributes(self):
        state = self._state(METADATA_ENTITY)
        return {"last_update": state.last_updated.isoformat(), "source_device": state.attributes.get("source_device", "")} if state else {}
