"""Minimal client for the OpenCode v2 API."""

from __future__ import annotations

import asyncio
import time
from typing import Any

import aiohttp

from .const import SESSION_TTL


class OpenCodeError(Exception):
    """Base error for the OpenCode client."""


class OpenCodeAuthError(OpenCodeError):
    """The OpenCode server refused the credentials."""


class OpenCodeUnavailableError(OpenCodeError):
    """The OpenCode server is unreachable."""


class OpenCodeTimeoutError(OpenCodeError):
    """The agent did not answer in time."""


class OpenCodeSessionGone(OpenCodeError):
    """The OpenCode session no longer exists."""


class OpenCodeBusy(OpenCodeError):
    """The OpenCode session is still running another turn."""


class OpenCodeClient:
    """Talk to the OpenCode server with Basic auth."""

    def __init__(
        self,
        session: aiohttp.ClientSession,
        host: str,
        port: int,
        password: str,
    ) -> None:
        """Initialize the client."""
        self._session = session
        self._base = f"http://{host}:{port}".rstrip("/")
        self._auth = aiohttp.BasicAuth("opencode", password)
        self._sessions: dict[str, tuple[str, float]] = {}
        self._locks: dict[str, asyncio.Lock] = {}

    async def async_ask(
        self,
        conversation_id: str,
        text: str,
        *,
        agent: str,
        directory: str,
        timeout: float,
    ) -> str:
        """Send a prompt and return the final assistant text."""
        lock = self._locks.setdefault(conversation_id, asyncio.Lock())
        async with lock:
            session_id = await self._async_session(conversation_id, agent, directory)
            try:
                await self._async_prompt(session_id, text)
            except (OpenCodeSessionGone, OpenCodeBusy):
                session_id = await self._async_create(agent, directory)
                self._sessions[conversation_id] = (session_id, time.monotonic())
                await self._async_prompt(session_id, text)

            try:
                async with asyncio.timeout(timeout):
                    await self._async_wait(session_id, timeout)
            except TimeoutError as err:
                # The turn may still run server-side: drop the session so the
                # next question starts clean, and delete it best effort.
                self._sessions.pop(conversation_id, None)
                try:
                    await self._async_request("DELETE", f"/api/session/{session_id}")
                except OpenCodeError:
                    pass
                raise OpenCodeTimeoutError from err
            return await self._async_last_text(session_id)
    async def _async_session(self, conversation_id: str, agent: str, directory: str) -> str:
        await self._async_purge_expired()
        now = time.monotonic()
        cached = self._sessions.get(conversation_id)
        if cached is not None and now - cached[1] < SESSION_TTL:
            return cached[0]
        session_id = await self._async_create(agent, directory)
        self._sessions[conversation_id] = (session_id, now)
        return session_id

    async def _async_purge_expired(self) -> None:
        """Delete sessions that outlived their TTL, best effort."""
        now = time.monotonic()
        for conversation_id, (session_id, last_used) in list(self._sessions.items()):
            if now - last_used < SESSION_TTL:
                continue
            self._sessions.pop(conversation_id, None)
            try:
                await self._async_request("DELETE", f"/api/session/{session_id}")
            except OpenCodeError:
                pass

    async def async_close(self) -> None:
        """Forget the cached sessions (the server keeps their history)."""
        self._sessions.clear()

    async def _async_create(self, agent: str, directory: str) -> str:
        payload = {"agent": agent, "location": {"directory": directory}}
        data = await self._async_request("POST", "/api/session", json=payload)
        session_id = ((data or {}).get("data") or {}).get("id")
        if not session_id:
            raise OpenCodeError("The server did not return a session id")
        return str(session_id)

    async def _async_prompt(self, session_id: str, text: str) -> None:
        await self._async_request(
            "POST",
            f"/api/session/{session_id}/prompt",
            json={"text": text},
            session_gone=True,
        )

    async def _async_wait(self, session_id: str, timeout: float) -> None:
        await self._async_request(
            "POST",
            f"/api/experimental/session/{session_id}/wait",
            timeout=timeout + 5,
        )

    async def _async_last_text(self, session_id: str) -> str:
        data = await self._async_request(
            "GET",
            f"/api/session/{session_id}/message?order=desc&limit=20",
        )
        for message in (data or {}).get("data", []):
            if message.get("type") != "assistant":
                continue
            parts = [
                part.get("text", "")
                for part in message.get("content", [])
                if part.get("type") == "text"
            ]
            text = "\n".join(part for part in parts if part).strip()
            if text:
                return text
        return ""

    async def _async_request(
        self,
        method: str,
        path: str,
        *,
        json: dict[str, Any] | None = None,
        timeout: float = 15,
        session_gone: bool = False,
    ) -> Any:
        url = f"{self._base}{path}"
        try:
            async with self._session.request(
                method,
                url,
                auth=self._auth,
                json=json,
                timeout=aiohttp.ClientTimeout(total=timeout),
            ) as response:
                if response.status == 401:
                    raise OpenCodeAuthError
                if response.status == 404 and session_gone:
                    raise OpenCodeSessionGone
                if response.status == 409:
                    raise OpenCodeBusy
                if response.status >= 400:
                    raise OpenCodeError(f"HTTP {response.status}")
                if response.status == 204:
                    return None
                return await response.json(content_type=None)
        except TimeoutError as err:
            raise OpenCodeTimeoutError from err
        except aiohttp.ClientError as err:
            raise OpenCodeUnavailableError from err
