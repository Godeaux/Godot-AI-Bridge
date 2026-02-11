"""Shared utilities for MCP tool modules."""

from __future__ import annotations


def b64_image(b64_data: str) -> dict[str, str]:
    """Return a base64 JPEG as an MCP image content block dict.

    FastMCP 2.14.5 can't serialize Image objects inside list[Any] returns,
    so we return the MCP-protocol image content block directly.
    """
    return {"type": "image", "data": b64_data, "mimeType": "image/jpeg"}


# Markers that indicate an error line in Godot console / log output.
ERROR_MARKERS = ("error", "exception", "traceback", "script error", "node not found")


def is_error_line(line: str) -> bool:
    """Return True if *line* looks like an error in Godot output."""
    stripped = line.strip()
    if not stripped:
        return False
    lowered = stripped.lower()
    return any(m in lowered for m in ERROR_MARKERS)
