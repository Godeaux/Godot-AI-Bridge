"""HTTP client helper for communicating with Godot editor and runtime bridges."""

from __future__ import annotations

import httpx
from typing import Any


class GodotClient:
    """Async HTTP client for talking to one of the Godot bridge servers.

    Uses a persistent httpx.AsyncClient to avoid creating a new TCP connection
    for every single request. Falls back to a fresh client if the persistent
    one encounters connection issues.
    """

    def __init__(self, host: str, port: int, timeout: float = 30.0) -> None:
        self.base_url = f"http://{host}:{port}"
        self.timeout = timeout
        self._client: httpx.AsyncClient | None = None

    def _get_client(self, timeout_override: float | None = None) -> httpx.AsyncClient:
        """Get or create the persistent HTTP client."""
        t = timeout_override or self.timeout
        if self._client is None or self._client.is_closed:
            self._client = httpx.AsyncClient(
                base_url=self.base_url,
                timeout=t,
            )
        return self._client

    async def get(
        self, path: str, params: dict[str, Any] | None = None, timeout: float | None = None,
    ) -> dict[str, Any]:
        """Send a GET request and return the JSON response."""
        try:
            client = self._get_client(timeout)
            resp = await client.get(path, params=params, timeout=timeout)
            resp.raise_for_status()
            return resp.json()
        except httpx.ConnectError:
            # Connection pool might be stale — retry with a fresh client
            await self._reset_client()
            client = self._get_client(timeout)
            resp = await client.get(path, params=params, timeout=timeout)
            resp.raise_for_status()
            return resp.json()

    async def post(
        self, path: str, json: dict[str, Any] | None = None, timeout: float | None = None,
    ) -> dict[str, Any]:
        """Send a POST request with a JSON body and return the JSON response."""
        try:
            client = self._get_client(timeout)
            resp = await client.post(path, json=json or {}, timeout=timeout)
            resp.raise_for_status()
            return resp.json()
        except httpx.ConnectError:
            await self._reset_client()
            client = self._get_client(timeout)
            resp = await client.post(path, json=json or {}, timeout=timeout)
            resp.raise_for_status()
            return resp.json()

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
