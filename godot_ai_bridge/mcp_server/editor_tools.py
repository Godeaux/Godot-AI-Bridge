"""MCP tool definitions for Godot editor operations.

These tools control the Godot Editor itself — scene editing, script management,
project structure, run control, and editor screenshots.
"""

from __future__ import annotations

import asyncio
import base64
from typing import Any

from fastmcp import FastMCP, Image
from client import editor, runtime


def _b64_image(b64_data: str) -> Image:
    """Decode a base64 PNG string from Godot into a FastMCP Image."""
    return Image(data=base64.b64decode(b64_data), format="png")


def register_editor_tools(mcp: FastMCP) -> None:
    """Register all editor tools with the MCP server."""

    # --- Scene & Node Tools ---

    @mcp.tool
    async def godot_get_scene_tree() -> dict[str, Any]:
        """Get the full scene tree of the currently open scene in the Godot editor.

        Returns a nested structure with each node's name, type, path, and children.
        Use this to understand the scene structure before making modifications.
        """
        try:
            return await editor.get("/scene/tree")
        except Exception as e:
            return {"error": f"Editor not reachable: {e}. Is the Godot editor open with the AI Bridge plugin enabled?"}

    @mcp.tool
    async def godot_create_scene(root_type: str, save_path: str) -> dict[str, Any]:
        """Create a new scene with the given root node type and save it.

        Args:
            root_type: The Godot node class for the root (e.g., 'Node2D', 'Control', 'Node3D').
            save_path: Where to save the scene (e.g., 'res://scenes/level_2.tscn').
        """
        return await editor.post("/scene/create", {"root_type": root_type, "save_path": save_path})

    @mcp.tool
    async def godot_add_node(
        parent_path: str,
        type: str,
        name: str,
        properties: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Add a new node to the currently edited scene.

        Args:
            parent_path: Path to the parent node ('.' for scene root, 'Player' for a child named Player).
            type: Godot node class name (e.g., 'Sprite2D', 'CollisionShape2D', 'Label').
            name: Name for the new node.
            properties: Optional dict of property name → value to set after creation.
                        Vectors use arrays: {"position": [100, 200]}.
                        Resource paths as strings: {"texture": "res://icon.svg"}.
        """
        body: dict[str, Any] = {"parent_path": parent_path, "type": type, "name": name}
        if properties:
            body["properties"] = properties
        return await editor.post("/node/add", body)

    @mcp.tool
    async def godot_remove_node(path: str) -> dict[str, Any]:
        """Remove a node from the currently edited scene.

        Args:
            path: Path to the node relative to scene root (e.g., 'Player/OldChild').
        """
        return await editor.post("/node/remove", {"path": path})

    @mcp.tool
    async def godot_set_property(path: str, property: str, value: Any) -> dict[str, Any]:
        """Set a property on a node in the currently edited scene.

        Args:
            path: Node path relative to scene root (e.g., 'Player', '.', 'UI/Score').
            property: Property name (e.g., 'position', 'modulate', 'text').
            value: Value to set. Use arrays for vectors: [100, 200] for Vector2.
                   Use dicts for colors: {"r": 1, "g": 0, "b": 0, "a": 1}.
                   Use strings for resource paths: "res://textures/sprite.png".
        """
        return await editor.post("/node/set_property", {"path": path, "property": property, "value": value})

    @mcp.tool
    async def godot_get_property(path: str, property: str) -> dict[str, Any]:
        """Get the value of a property on a node in the currently edited scene.

        Args:
            path: Node path relative to scene root.
            property: Property name to read.
        """
        return await editor.get("/node/get_property", {"path": path, "property": property})

    @mcp.tool
    async def godot_save_scene() -> dict[str, Any]:
        """Save the currently edited scene to disk."""
        return await editor.post("/scene/save")

    @mcp.tool
    async def godot_open_scene(path: str) -> dict[str, Any]:
        """Open a scene file in the editor.

        Args:
            path: Resource path to the scene (e.g., 'res://scenes/main.tscn').
        """
        return await editor.post("/scene/open", {"path": path})

    @mcp.tool
    async def godot_duplicate_node(path: str, new_name: str = "") -> dict[str, Any]:
        """Duplicate a node in the currently edited scene.

        Creates a copy of the node (and all its children) as a sibling.
        The duplicate gets all the same properties, children, and scripts.

        Args:
            path: Path to the node to duplicate (e.g., 'Player', 'Enemies/Goblin').
            new_name: Optional name for the duplicate. If empty, Godot auto-names it.
        """
        body: dict[str, Any] = {"path": path}
        if new_name:
            body["new_name"] = new_name
        return await editor.post("/node/duplicate", body)

    @mcp.tool
    async def godot_reparent_node(
        path: str,
        new_parent: str,
        keep_global_transform: bool = True,
    ) -> dict[str, Any]:
        """Move a node to a different parent in the currently edited scene.

        Args:
            path: Path to the node to move (e.g., 'OldParent/MyNode').
            new_parent: Path to the new parent ('.' for scene root, 'NewParent' for a child).
            keep_global_transform: If True, adjusts local transform to maintain global position.
        """
        return await editor.post("/node/reparent", {
            "path": path,
            "new_parent": new_parent,
            "keep_global_transform": keep_global_transform,
        })

    @mcp.tool
    async def godot_list_node_properties(path: str) -> dict[str, Any]:
        """List all editable properties of a node in the currently edited scene.

        Returns every editor-visible property with its name, type, current value,
        and type hints. Useful for discovering what properties exist before
        setting them with godot_set_property.

        Args:
            path: Node path ('.' for root, 'Player', 'UI/Score', etc.).
        """
        return await editor.get("/node/properties", {"path": path})

    # --- Script Tools ---

    @mcp.tool
    async def godot_read_script(path: str) -> dict[str, Any]:
        """Read the full contents of a GDScript file.

        Args:
            path: Resource path to the script (e.g., 'res://scripts/player.gd').
        """
        return await editor.get("/script/read", {"path": path})

    @mcp.tool
    async def godot_write_script(path: str, content: str) -> dict[str, Any]:
        """Write content to a GDScript file. Creates the file if it doesn't exist.

        After writing, you must stop and restart the game for changes to take effect.

        Args:
            path: Resource path for the script (e.g., 'res://scripts/player.gd').
            content: Full script content to write.
        """
        return await editor.post("/script/write", {"path": path, "content": content})

    @mcp.tool
    async def godot_create_script(
        path: str,
        extends: str = "Node",
        template: str = "basic",
    ) -> dict[str, Any]:
        """Create a new script file with boilerplate.

        Args:
            path: Resource path for the new script (e.g., 'res://scripts/enemy.gd').
            extends: Base class (e.g., 'CharacterBody2D', 'Node2D', 'Control').
            template: Template type — 'basic' (ready+process), 'empty' (just extends), or 'full' (type-specific).
        """
        return await editor.post("/script/create", {"path": path, "extends": extends, "template": template})

    @mcp.tool
    async def godot_get_errors() -> dict[str, Any]:
        """Get current script compilation errors from the editor.

        Returns a list of errors with file paths and messages.
        """
        return await editor.get("/script/errors")

    @mcp.tool
    async def godot_get_debugger_output() -> dict[str, Any]:
        """Get recent output from the editor's Output/debugger panel."""
        return await editor.get("/debugger/output")

    # --- Project Tools ---

    @mcp.tool
    async def godot_project_structure() -> dict[str, Any]:
        """Get the project directory tree (res://).

        Returns file names, types, paths, and sizes. Excludes .godot/ and the bridge addon.
        Use this to understand what files exist before reading or modifying them.
        """
        return await editor.get("/project/structure")

    @mcp.tool
    async def godot_search_files(pattern: str = "", query: str = "") -> dict[str, Any]:
        """Search project files by glob pattern or filename substring.

        Args:
            pattern: Glob pattern like '*.gd', '*.tscn', 'player*'. Leave empty to use query instead.
            query: Substring to search for in filenames (case-insensitive). Leave empty to use pattern.
        """
        params: dict[str, str] = {}
        if pattern:
            params["pattern"] = pattern
        if query:
            params["query"] = query
        return await editor.get("/project/search", params)

    @mcp.tool
    async def godot_get_input_map() -> dict[str, Any]:
        """Get all InputMap actions and their key/button bindings.

        Returns action names mapped to their input events (keys, mouse buttons, joypad).
        Use this to understand what input actions are available for game_trigger_action.
        """
        return await editor.get("/project/input_map")

    @mcp.tool
    async def godot_get_project_settings() -> dict[str, Any]:
        """Get key project settings: name, main scene, window size, physics FPS, etc."""
        return await editor.get("/project/settings")

    @mcp.tool
    async def godot_get_autoloads() -> dict[str, Any]:
        """Get all registered autoload singletons and their script paths."""
        return await editor.get("/project/autoloads")

    # --- Run Control ---

    @mcp.tool
    async def godot_run_game(scene: str = "") -> dict[str, Any]:
        """Start running the game from the editor.

        After starting, runtime tools become available. This tool will wait for
        the runtime bridge to become reachable before returning.

        Args:
            scene: Optional scene path to run (e.g., 'res://scenes/level_1.tscn').
                   If empty, runs the project's main scene.
        """
        body: dict[str, Any] = {}
        if scene:
            body["scene"] = scene

        result = await editor.post("/game/run", body)

        # Poll until runtime bridge is available
        for i in range(50):  # 5 second timeout
            await asyncio.sleep(0.1)
            if await runtime.is_available():
                info = await runtime.get("/info")
                return {
                    "ok": True,
                    "running": True,
                    "game_info": info,
                }

        return {
            "ok": True,
            "running": True,
            "warning": "Game started but runtime bridge not yet reachable. Try game_snapshot in a moment.",
        }

    @mcp.tool
    async def godot_stop_game() -> dict[str, Any]:
        """Stop the currently running game.

        After stopping, runtime tools will no longer be available.
        Use this before editing code — changes require a restart to take effect.
        """
        return await editor.post("/game/stop")

    @mcp.tool
    async def godot_is_game_running() -> dict[str, Any]:
        """Check if the game is currently running."""
        return await editor.get("/game/is_running")

    # --- Editor Screenshot ---

    @mcp.tool
    async def godot_editor_screenshot(width: int = 960, height: int = 540) -> list[Any]:
        """Capture a screenshot of the Godot editor viewport.

        Use this to see the current state of the editor, verify scene changes,
        check node placement, and evaluate the visual state of your edits.

        Args:
            width: Screenshot width in pixels (default 960).
            height: Screenshot height in pixels (default 540).
        """
        data = await editor.get("/screenshot", {"width": str(width), "height": str(height)})
        if "error" in data:
            return [data["error"]]

        return [
            f"Editor screenshot ({data['size'][0]}x{data['size'][1]})",
            _b64_image(data["image"]),
        ]
