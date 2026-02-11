"""HTTP client helper for communicating with Godot editor and runtime bridges.

Every call has a hard 120-second cap. If Godot hasn't responded by then, the
request fails immediately so the MCP tool can report an error instead of
leaving the AI agent hanging.  Individual tools (game_wait, game_wait_for,
game_input_sequence) compute their own timeouts from the requested duration
and may exceed the default 30s, so the ceiling must accommodate them.
"""

from __future__ import annotations

import httpx
from typing import Any

# Hard ceiling — no single HTTP request to Godot should ever take longer than
# this.  Individual callers can pass a *shorter* timeout but never a longer one.
# Must be high enough to cover game_wait / game_wait_for / game_input_sequence
# which compute timeout = user_duration + 15s headroom.
MAX_TIMEOUT: float = 120.0


class GodotClient:
    """Async HTTP client for talking to one of the Godot bridge servers.

    Uses a persistent httpx.AsyncClient to avoid creating a new TCP connection
    for every single request. Falls back to a fresh client if the persistent
    one encounters connection issues.
    """

    def __init__(self, host: str, port: int, timeout: float = 30.0) -> None:
        self.base_url = f"http://{host}:{port}"
        self.timeout = min(timeout, MAX_TIMEOUT)
        self._client: httpx.AsyncClient | None = None

    def _effective_timeout(self, override: float | None) -> float:
        """Return the timeout to use, clamped to MAX_TIMEOUT."""
        if override is not None:
            return min(override, MAX_TIMEOUT)
        return self.timeout

    def _get_client(self) -> httpx.AsyncClient:
        """Get or create the persistent HTTP client."""
        if self._client is None or self._client.is_closed:
            self._client = httpx.AsyncClient(
                base_url=self.base_url,
                timeout=self.timeout,
            )
        return self._client

    async def get(
        self, path: str, params: dict[str, Any] | None = None, timeout: float | None = None,
    ) -> dict[str, Any]:
        """Send a GET request and return the JSON response."""
        t = self._effective_timeout(timeout)
        try:
            client = self._get_client()
            resp = await client.get(path, params=params, timeout=t)
            resp.raise_for_status()
            return resp.json()
        except (httpx.ConnectError, httpx.ReadError, httpx.WriteError):
            # Connection pool might be stale — retry once with a fresh client
            await self._reset_client()
            client = self._get_client()
            resp = await client.get(path, params=params, timeout=t)
            resp.raise_for_status()
            return resp.json()
        except httpx.TimeoutException:
            await self._reset_client()
            raise httpx.TimeoutException(
                f"Godot did not respond within {t}s on GET {path} — "
                f"the editor/game may have crashed or is unresponsive"
            )

    async def post(
        self, path: str, json: dict[str, Any] | None = None, timeout: float | None = None,
    ) -> dict[str, Any]:
        """Send a POST request with a JSON body and return the JSON response."""
        t = self._effective_timeout(timeout)
        try:
            client = self._get_client()
            resp = await client.post(path, json=json or {}, timeout=t)
            resp.raise_for_status()
            return resp.json()
        except (httpx.ConnectError, httpx.ReadError, httpx.WriteError):
            await self._reset_client()
            client = self._get_client()
            resp = await client.post(path, json=json or {}, timeout=t)
            resp.raise_for_status()
            return resp.json()
        except httpx.TimeoutException:
            await self._reset_client()
            raise httpx.TimeoutException(
                f"Godot did not respond within {t}s on POST {path} — "
                f"the editor/game may have crashed or is unresponsive"
            )

    async def is_available(self) -> bool:
        """Check if this bridge server is reachable."""
        try:
            async with httpx.AsyncClient(base_url=self.base_url, timeout=2.0) as client:
                resp = await client.get("/info")
                resp.raise_for_status()
            return True
        except Exception:
            return False

    async def _reset_client(self) -> None:
        """Close and discard the current client so a fresh one is created."""
        if self._client is not None and not self._client.is_closed:
            await self._client.aclose()
        self._client = None


# Pre-configured client instances
editor = GodotClient("127.0.0.1", 9899)
runtime = GodotClient("127.0.0.1", 9900)
