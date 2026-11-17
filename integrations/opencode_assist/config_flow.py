"""Config flow for OpenCode Assist."""

from __future__ import annotations

from typing import Any

import aiohttp
import voluptuous as vol

from homeassistant.config_entries import ConfigEntry, ConfigFlow, ConfigFlowResult, OptionsFlow
from homeassistant.core import HomeAssistant
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.selector import (
    TextSelector,
    TextSelectorConfig,
    TextSelectorType,
)

from .api import OpenCodeAuthError, OpenCodeUnavailableError
from .const import (
    CONF_AGENT,
    CONF_ALLOWED_USERS,
    CONF_DIRECTORY,
    CONF_HOST,
    CONF_PASSWORD,
    CONF_PORT,
    CONF_PROMPT_TIMEOUT,
    DEFAULT_AGENT,
    DEFAULT_DIRECTORY,
    DEFAULT_HOST,
    DEFAULT_PORT,
    DEFAULT_PROMPT_TIMEOUT,
    DOMAIN,
    MAX_PROMPT_TIMEOUT,
    MIN_PROMPT_TIMEOUT,
    TITLE,
)

INVALID_AUTH = "invalid_auth"
CANNOT_CONNECT = "cannot_connect"


async def _async_validate(hass: HomeAssistant, host: str, port: int, password: str) -> None:
    """Check the server answers with these credentials."""
    session = async_get_clientsession(hass)
    url = f"http://{host}:{port}/api/info"
    try:
        async with session.get(
            url,
            auth=aiohttp.BasicAuth("opencode", password),
            timeout=aiohttp.ClientTimeout(total=10),
        ) as response:
            if response.status == 401:
                raise OpenCodeAuthError
            if response.status != 200:
                raise OpenCodeUnavailableError
    except TimeoutError as err:
        raise OpenCodeUnavailableError from err
    except aiohttp.ClientError as err:
        raise OpenCodeUnavailableError from err


def _user_schema(defaults: dict[str, Any] | None = None) -> vol.Schema:
    values = defaults or {}
    return vol.Schema(
        {
            vol.Required(CONF_HOST, default=values.get(CONF_HOST, DEFAULT_HOST)): str,
            vol.Required(CONF_PORT, default=values.get(CONF_PORT, DEFAULT_PORT)): vol.All(
                vol.Coerce(int), vol.Range(min=1, max=65535)
            ),
            vol.Required(
                CONF_PASSWORD,
                default=values.get(CONF_PASSWORD, ""),
            ): TextSelector(TextSelectorConfig(type=TextSelectorType.PASSWORD)),
            vol.Required(CONF_AGENT, default=values.get(CONF_AGENT, DEFAULT_AGENT)): str,
            vol.Required(
                CONF_DIRECTORY, default=values.get(CONF_DIRECTORY, DEFAULT_DIRECTORY)
            ): str,
            vol.Optional(
                CONF_ALLOWED_USERS, default=values.get(CONF_ALLOWED_USERS, "")
            ): str,
            vol.Required(
                CONF_PROMPT_TIMEOUT,
                default=values.get(CONF_PROMPT_TIMEOUT, DEFAULT_PROMPT_TIMEOUT),
            ): vol.All(
                vol.Coerce(int),
                vol.Range(min=MIN_PROMPT_TIMEOUT, max=MAX_PROMPT_TIMEOUT),
            ),
        }
    )


def _options_schema(defaults: dict[str, Any]) -> vol.Schema:
    return vol.Schema(
        {
            vol.Required(CONF_AGENT, default=defaults.get(CONF_AGENT, DEFAULT_AGENT)): str,
            vol.Required(
                CONF_DIRECTORY, default=defaults.get(CONF_DIRECTORY, DEFAULT_DIRECTORY)
            ): str,
            vol.Optional(
                CONF_ALLOWED_USERS, default=defaults.get(CONF_ALLOWED_USERS, "")
            ): str,
            vol.Required(
                CONF_PROMPT_TIMEOUT,
                default=defaults.get(CONF_PROMPT_TIMEOUT, DEFAULT_PROMPT_TIMEOUT),
            ): vol.All(
                vol.Coerce(int),
                vol.Range(min=MIN_PROMPT_TIMEOUT, max=MAX_PROMPT_TIMEOUT),
            ),
        }
    )


class OpenCodeAssistConfigFlow(ConfigFlow, domain=DOMAIN):
    """Handle the configuration flow."""

    VERSION = 1

    async def async_step_user(
        self, user_input: dict[str, Any] | None = None
    ) -> ConfigFlowResult:
        """Ask for the server details."""
        errors: dict[str, str] = {}

        if user_input is not None:
            await self.async_set_unique_id(
                f"{user_input[CONF_HOST]}:{user_input[CONF_PORT]}"
            )
            self._abort_if_unique_id_configured()

            try:
                await _async_validate(
                    self.hass,
                    str(user_input[CONF_HOST]),
                    int(user_input[CONF_PORT]),
                    str(user_input[CONF_PASSWORD]),
                )
            except OpenCodeAuthError:
                errors["base"] = INVALID_AUTH
            except OpenCodeUnavailableError:
                errors["base"] = CANNOT_CONNECT
            else:
                return self.async_create_entry(title=TITLE, data=user_input)

        return self.async_show_form(
            step_id="user",
            data_schema=_user_schema(user_input),
            errors=errors,
        )

    @staticmethod
    def async_get_options_flow(config_entry: ConfigEntry) -> OptionsFlow:
        """Return the options flow."""
        return OpenCodeAssistOptionsFlow()


class OpenCodeAssistOptionsFlow(OptionsFlow):
    """Adjust the agent settings."""

    async def async_step_init(
        self, user_input: dict[str, Any] | None = None
    ) -> ConfigFlowResult:
        """Show the options form."""
        if user_input is not None:
            return self.async_create_entry(title="", data=user_input)

        current = {**self.config_entry.data, **self.config_entry.options}
        return self.async_show_form(
            step_id="init",
            data_schema=_options_schema(current),
        )
