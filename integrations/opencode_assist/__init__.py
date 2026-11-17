"""OpenCode Assist integration."""

from __future__ import annotations

from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform
from homeassistant.core import HomeAssistant
from homeassistant.helpers.aiohttp_client import async_get_clientsession

from .api import OpenCodeClient
from .const import CONF_HOST, CONF_PASSWORD, CONF_PORT

PLATFORMS = [Platform.CONVERSATION]

type OpenCodeAssistConfigEntry = ConfigEntry[OpenCodeClient]


async def async_setup_entry(hass: HomeAssistant, entry: OpenCodeAssistConfigEntry) -> bool:
    """Set up OpenCode Assist from a config entry."""
    entry.runtime_data = OpenCodeClient(
        async_get_clientsession(hass),
        entry.data[CONF_HOST],
        entry.data[CONF_PORT],
        entry.data[CONF_PASSWORD],
    )
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: OpenCodeAssistConfigEntry) -> bool:
    """Unload a config entry."""
    unloaded = await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
    if unloaded:
        await entry.runtime_data.async_close()
    return unloaded
