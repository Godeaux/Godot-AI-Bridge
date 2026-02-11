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
        "Editor tools (godot_*) control the Godot Editor — editing scenes, "
        "scripts, properties, signals, groups, input maps, and project files. "
        "Runtime tools (game_*) interact with the running game — taking snapshots, "
        "injecting input, reading and modifying state.\n\n"
        "Use godot_run_game to start the game, then game_snapshot as your primary "
        "observation tool. Always snapshot before and after interactions.\n\n"

        "## Snapshot Efficiency\n\n"
        "Full snapshots of large scenes are expensive. After your first full snapshot, "
        "use targeted follow-ups:\n"
        "- game_snapshot(root='Player', depth=3) — focus on a subtree\n"
        "- game_snapshot_diff() — see only what changed since last snapshot\n"
        "- game_state(ref='n5') — deep-inspect one specific node\n"
        "Save full snapshots (depth=12) for initial orientation or when the scene "
        "changes significantly (new level, menu transition).\n\n"
        "Key tools beyond basic scene/script editing:\n"
        "- godot_list_signals / godot_connect_signal / godot_disconnect_signal — "
        "wire up signal connections between nodes\n"
        "- godot_add_to_group / godot_remove_from_group — tag nodes for group lookup\n"
        "- godot_add_input_action / godot_add_input_binding — create and bind "
        "input actions (use godot_get_input_map to see existing ones)\n"
        "- game_set_property — modify node properties at runtime (speed, health, "
        "position) without stopping the game, like using the Inspector during play\n\n"

        "## Error Recovery — ALWAYS attempt to fix errors yourself\n\n"
        "When you encounter ANY error from these tools, your job is to diagnose "
        "and fix it — not to report it to the user and stop. You have full access "
        "to read and write scripts, inspect logs, and restart the game. Use that.\n\n"
        "If the fix is unambiguous (typo, missing node, wrong method name, etc.), "
        "just fix it and move on. If the fix is genuinely ambiguous — meaning there "
        "are multiple valid approaches and the developer's intent is unclear — "
        "briefly present the options to the user and ask which they prefer before "
        "proceeding. But do NOT ask the user about things you can figure out "
        "yourself from the code and error context.\n\n"

        "## Startup Gating (strict mode)\n\n"
        "Always launch the game with `godot_run_game(strict=true)`.  If the "
        "response has `ok=false`, enter a repair loop:\n"
        "  1. Read `startup_errors` from the response (file, line, message).\n"
        "  2. Call `godot_get_errors()` and `godot_get_debugger_output()` for "
        "full diagnostics.\n"
        "  3. Read the broken script with `godot_read_script()`.\n"
        "  4. Fix the code with `godot_write_script()`.\n"
        "  5. Call `godot_stop_game()`, then `godot_save_scene()`.\n"
        "  6. Re-run `godot_run_game(strict=true)`.\n"
        "  7. If `ok=true`, proceed normally.  If still `ok=false`, repeat "
        "from step 1 (up to 5 attempts).\n"
        "  8. After 5 failed attempts, report the errors to the user.\n\n"

        "## Mid-Game Crash Recovery\n\n"
        "If a runtime tool (game_snapshot, game_click, etc.) returns an error "
        "saying the game crashed or stopped unexpectedly, the error message will "
        "include log errors when available. Enter the same repair loop:\n"
        "  1. Read the error lines included in the response.\n"
        "  2. Call `godot_get_debugger_output()` if you need more context.\n"
        "  3. Read the broken script with `godot_read_script()`.\n"
        "  4. Fix the code with `godot_write_script()`.\n"
        "  5. Call `godot_stop_game()`, then `godot_save_scene()`.\n"
        "  6. Re-run `godot_run_game(strict=true)` and continue where you "
        "left off.\n"
        "Do NOT give up just because the game crashed. Crashes during gameplay "
        "are normal during development — read the error, fix it, relaunch.\n\n"

        "Fatal error patterns (always block on these): "
        "Node not found, Cannot call method, Invalid access, Invalid call, "
        "SCRIPT ERROR, Parse Error."
    ),
)

# Register all tools
register_editor_tools(mcp)
register_runtime_tools(mcp)

if __name__ == "__main__":
    mcp.run()
