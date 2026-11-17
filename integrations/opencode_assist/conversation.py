"""Conversation agent backed by the OpenCode server."""

from __future__ import annotations

from typing import Literal, override

from homeassistant.components import conversation
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers import intent
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from .api import (
    OpenCodeAuthError,
    OpenCodeClient,
    OpenCodeError,
    OpenCodeTimeoutError,
    OpenCodeUnavailableError,
)
from .const import (
    CONF_AGENT,
    CONF_ALLOWED_USERS,
    CONF_DIRECTORY,
    CONF_PROMPT_TIMEOUT,
    DEFAULT_AGENT,
    DEFAULT_DIRECTORY,
    DEFAULT_PROMPT_TIMEOUT,
)


async def async_setup_entry(
    hass: HomeAssistant,
    config_entry: ConfigEntry,
    async_add_entities: AddConfigEntryEntitiesCallback,
) -> None:
    """Set up the conversation entity."""
    async_add_entities([OpenCodeAssistEntity(config_entry, config_entry.runtime_data)])


class OpenCodeAssistEntity(conversation.ConversationEntity):
    """Read-only Home Assistant assistant delegated to OpenCode."""

    _attr_has_entity_name = True
    _attr_name = "OpenCode Assist"

    def __init__(self, entry: ConfigEntry, client: OpenCodeClient) -> None:
        """Initialize the agent."""
        self._entry = entry
        self._client = client
        self._attr_unique_id = entry.entry_id

    @property
    @override
    def supported_languages(self) -> list[str] | Literal["*"]:
        """Return supported languages."""
        return ["fr", "en"]

    def _option(self, key: str, default: str | int) -> str | int:
        if key in self._entry.options:
            return self._entry.options[key]
        return self._entry.data.get(key, default)

    @property
    def _allowed_users(self) -> set[str]:
        raw = str(self._option(CONF_ALLOWED_USERS, "") or "")
        return {item for item in raw.replace(",", " ").split() if item}

    async def _async_is_allowed(self, user_input: conversation.ConversationInput) -> bool:
        user_id = user_input.context.user_id
        allowed = self._allowed_users
        if allowed:
            return user_id in allowed
        if not user_id:
            return False
        user = await self.hass.auth.async_get_user(user_id)
        return user is not None and user.is_admin

    async def async_process(
        self, user_input: conversation.ConversationInput
    ) -> conversation.ConversationResult:
        """Process one Assist turn."""
        if not await self._async_is_allowed(user_input):
            return self._result(
                user_input,
                "Cet agent est réservé aux administrateurs.",
            )

        try:
            text = await self._client.async_ask(
                user_input.conversation_id or "assist",
                user_input.text,
                agent=str(self._option(CONF_AGENT, DEFAULT_AGENT)),
                directory=str(self._option(CONF_DIRECTORY, DEFAULT_DIRECTORY)),
                timeout=float(self._option(CONF_PROMPT_TIMEOUT, DEFAULT_PROMPT_TIMEOUT)),
            )
        except OpenCodeAuthError:
            text = "Le mot de passe OpenCode est refusé."
        except OpenCodeTimeoutError:
            text = "L'agent OpenCode n'a pas répondu à temps."
        except OpenCodeUnavailableError:
            text = "L'agent OpenCode est indisponible."
        except OpenCodeError:
            text = "L'agent OpenCode a renvoyé une erreur."

        return self._result(user_input, text.strip() or "Je n'ai pas de réponse.")

    def _result(
        self, user_input: conversation.ConversationInput, text: str
    ) -> conversation.ConversationResult:
        response = intent.IntentResponse(language=user_input.language)
        response.async_set_speech(text)
        return conversation.ConversationResult(
            response=response, conversation_id=user_input.conversation_id
        )
