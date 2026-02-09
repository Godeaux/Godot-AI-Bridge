"""HTTP client helper for communicating with Godot editor and runtime bridges."""

from __future__ import annotations

import httpx
from typing import Any


class GodotClient:
    """Async HTTP client for talking to one of the Godot bridge servers."""

    def __init__(self, host: str, port: int, timeout: float = 30.0) -> None:
        self.base_url = f"http://{host}:{port}"
        self.timeout = timeout

    async def get(self, path: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Send a GET request and return the JSON response."""
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            resp = await client.get(f"{self.base_url}{path}", params=params)
            resp.raise_for_status()
            return resp.json()

    async def post(self, path: str, json: dict[str, Any] | None = None) -> dict[str, Any]:
        """Send a POST request with a JSON body and return the JSON response."""
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            resp = await client.post(f"{self.base_url}{path}", json=json or {})
            resp.raise_for_status()
            return resp.json()

    async def is_available(self) -> bool:
        """Check if this bridge server is reachable."""
        try:
            await self.get("/info")
            return True
        except Exception:
            return False


# Pre-configured client instances
editor = GodotClient("127.0.0.1", 9899)
runtime = GodotClient("127.0.0.1", 9900)
