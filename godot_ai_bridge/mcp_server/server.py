#!/usr/bin/env python3
"""Godot AI Bridge — Unified MCP Server.

A single MCP server that exposes both editor and runtime tools for controlling
the Godot editor and interacting with running games.

Run with: uv run server.py
Or configure as an MCP server:
{
    "mcpServers": {
        "godot": {
            "command": "uv",
            "args": ["run", "/path/to/godot_ai_bridge/mcp_server/server.py"]
        }
    }
}
"""

from __future__ import annotations

import sys
import os

# Ensure the mcp_server directory is on the path for local imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastmcp import FastMCP
from editor_tools import register_editor_tools
from runtime_tools import register_runtime_tools

# Create the MCP server
mcp = FastMCP(
    "godot-ai-bridge",
    instructions=(
        "You have access to tools for controlling the Godot game engine. "
        "Editor tools (godot_*) control the Godot Editor — editing scenes, scripts, "
        "and project files. Runtime tools (game_*) interact with the running game — "
        "taking snapshots, injecting input, and reading state. "
        "Use godot_run_game to start the game, then game_snapshot as your primary "
        "observation tool. Always snapshot before and after interactions."
    ),
)

# Register all tools
register_editor_tools(mcp)
register_runtime_tools(mcp)

if __name__ == "__main__":
    mcp.run()
