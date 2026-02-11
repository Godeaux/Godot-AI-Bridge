"""MCP tool definitions for Godot editor operations.

These tools control the Godot Editor itself — scene editing, script management,
project structure, run control, and editor screenshots.
"""

from __future__ import annotations

import asyncio
import re
from typing import Any

from fastmcp import FastMCP
from client import editor, runtime
from utils import b64_image as _b64_image, is_error_line as _is_error_line


# ---------------------------------------------------------------------------
# Strict startup-gating: fatal error patterns and structured error parsing
# ---------------------------------------------------------------------------

# Patterns that are treated as fatal startup errors when strict=True.
# If any of these appear in console/debugger output after launch, the game
# is considered to have a startup error that must be fixed before proceeding.
_FATAL_PATTERNS: list[str] = [
    "node not found",
    "cannot call method",
    "invalid access",
    "invalid call",
    "script error",
    "parse error",
]

# Regex to extract file path and line number from Godot error output.
# Matches patterns like:
#   res://scripts/player.gd:11
#   At: res://scripts/player.gd:42
#   (res://scenes/main.gd:7)
_FILE_LINE_RE = re.compile(r"(res://[^\s:,)]+):(\d+)")

# Regex for "SCRIPT ERROR:" or "Parse Error:" prefixed lines.
_SCRIPT_ERROR_RE = re.compile(
    r"(?:SCRIPT ERROR|Parse Error|ERROR)\s*:\s*(.+)", re.IGNORECASE
)


def _is_fatal_error(line: str) -> bool:
    """Return True if *line* matches any fatal startup error pattern."""
    lowered = line.strip().lower()
    if not lowered:
        return False
    return any(p in lowered for p in _FATAL_PATTERNS)


def _parse_error_line(line: str) -> dict[str, Any]:
    """Parse a single Godot error line into a structured dict.

    Returns {"message": str, "file": str|None, "line": int|None}.
    """
    stripped = line.strip()
    result: dict[str, Any] = {"message": stripped, "file": None, "line": None}

    # Try to extract file:line
    m = _FILE_LINE_RE.search(stripped)
    if m:
        result["file"] = m.group(1)
        result["line"] = int(m.group(2))

    # Try to clean up the message (extract the core error after "SCRIPT ERROR:" etc.)
    m2 = _SCRIPT_ERROR_RE.search(stripped)
    if m2:
        result["message"] = m2.group(1).strip()

    return result


def _collect_startup_errors(output: str) -> list[dict[str, Any]]:
    """Scan console/debugger output for fatal startup errors.

    Returns a list of structured error dicts.  Only lines matching
    ``_FATAL_PATTERNS`` are included.
    """
    errors: list[dict[str, Any]] = []
    seen: set[str] = set()
    for line in output.split("\n"):
        if _is_fatal_error(line):
            key = line.strip()
            if key not in seen:
                seen.add(key)
                errors.append(_parse_error_line(line))
    return errors


def _truncate_log_tail(output: str, max_lines: int = 60) -> str:
    """Return the last *max_lines* lines of *output*."""
    lines = output.strip().split("\n")
    if len(lines) > max_lines:
        return "\n".join(lines[-max_lines:])
    return output.strip()


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
            data = await editor.get("/scene/tree")
        except Exception as e:
            return {"error": f"Editor not reachable: {e}. Is the Godot editor open with the AI Bridge plugin enabled?"}
        if "error" in data:
            return data
        if "_description" not in data:
            root = data.get("root", {})
            data["_description"] = f"🌳 Scene tree of '{root.get('name', '?')}' ({root.get('type', '?')})"
        return data

    @mcp.tool
    async def godot_create_scene(root_type: str, save_path: str) -> dict[str, Any]:
        """Create a new scene with the given root node type and save it.

        Args:
            root_type: The Godot node class for the root (e.g., 'Node2D', 'Control', 'Node3D').
            save_path: Where to save the scene (e.g., 'res://scenes/level_2.tscn').
        """
        result = await editor.post("/scene/create", {"root_type": root_type, "save_path": save_path})
        if "ok" in result and "_description" not in result:
            result["_description"] = f"🆕 Created scene '{save_path}' (root: {root_type})"
        return result

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
        result = await editor.post("/node/add", body)
        if "ok" in result and "_description" not in result:
            result["_description"] = f"➕ Added {type} '{name}' under '{parent_path}'"
        return result

    @mcp.tool
    async def godot_remove_node(path: str) -> dict[str, Any]:
        """Remove a node from the currently edited scene.

        Args:
            path: Path to the node relative to scene root (e.g., 'Player/OldChild').
        """
        result = await editor.post("/node/remove", {"path": path})
        if "ok" in result and "_description" not in result:
            result["_description"] = f"🗑️ Removed node '{path}'"
        return result

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
        result = await editor.post("/node/set_property", {"path": path, "property": property, "value": value})
        if "ok" in result and "_description" not in result:
            result["_description"] = f"✏️ Set '{path}'.{property}"
        return result

    @mcp.tool
    async def godot_get_property(path: str, property: str) -> dict[str, Any]:
        """Get the value of a property on a node in the currently edited scene.

        Args:
            path: Node path relative to scene root.
            property: Property name to read.
        """
        result = await editor.get("/node/get_property", {"path": path, "property": property})
        if "error" not in result and "_description" not in result:
            result["_description"] = f"🔍 '{path}'.{property} = {result.get('value', '?')}"
        return result

    @mcp.tool
    async def godot_save_scene() -> dict[str, Any]:
        """Save the currently edited scene to disk."""
        result = await editor.post("/scene/save")
        if "ok" in result and "_description" not in result:
            result["_description"] = "💾 Scene saved"
        return result

    @mcp.tool
    async def godot_open_scene(path: str) -> dict[str, Any]:
        """Open a scene file in the editor.

        Args:
            path: Resource path to the scene (e.g., 'res://scenes/main.tscn').
        """
        result = await editor.post("/scene/open", {"path": path})
        if "ok" in result and "_description" not in result:
            result["_description"] = f"📂 Opened scene '{path}'"
        return result

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
        result = await editor.post("/node/duplicate", body)
        if "ok" in result and "_description" not in result:
            result["_description"] = f"📋 Duplicated '{path}' → '{result.get('name', '?')}'"
        return result

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
        result = await editor.post("/node/reparent", {
            "path": path,
            "new_parent": new_parent,
            "keep_global_transform": keep_global_transform,
        })
        if "ok" in result and "_description" not in result:
            result["_description"] = f"📦 Reparented '{path}' → under '{new_parent}'"
        return result

    @mcp.tool
    async def godot_reorder_node(
        path: str,
        position: int | str,
    ) -> dict[str, Any]:
        """Move a node up/down among its siblings (changes draw order in 2D, UI layout order).

        In Godot, child order determines draw order (later = on top) and
        UI layout order. Use this to control z-ordering without z_index.

        Args:
            path: Node path (e.g., 'Player', 'UI/Panel').
            position: Target position — an integer index (0 = first child),
                      or one of: 'up' (one step earlier), 'down' (one step later),
                      'first' (move to front), 'last' (move to back).
        """
        result = await editor.post("/node/reorder", {
            "path": path,
            "position": position,
        })
        if "ok" in result and "_description" not in result:
            result["_description"] = f"↕️ Reordered '{path}' → index {result.get('new_index', '?')}"
        return result

    @mcp.tool
    async def godot_list_node_properties(path: str) -> dict[str, Any]:
        """List all editable properties of a node in the currently edited scene.

        Returns every editor-visible property with its name, type, current value,
        and type hints. Useful for discovering what properties exist before
        setting them with godot_set_property.

        Args:
            path: Node path ('.' for root, 'Player', 'UI/Score', etc.).
        """
        result = await editor.get("/node/properties", {"path": path})
        if "error" not in result and "_description" not in result:
            result["_description"] = f"📜 {result.get('count', '?')} properties on '{result.get('node', path)}' ({result.get('type', '?')})"
        return result

    @mcp.tool
    async def godot_rename_node(path: str, new_name: str) -> dict[str, Any]:
        """Rename a node in the currently edited scene.

        Args:
            path: Path to the node to rename (e.g., 'Player', 'UI/OldLabel').
            new_name: The new name for the node.
        """
        result = await editor.post("/node/rename", {"path": path, "new_name": new_name})
        if "ok" in result and "_description" not in result:
            result["_description"] = f"✏️ Renamed '{result.get('old_name', path)}' → '{new_name}'"
        return result

    @mcp.tool
    async def godot_instance_scene(
        scene_path: str,
        parent_path: str = ".",
        name: str = "",
    ) -> dict[str, Any]:
        """Add an instance of a PackedScene (.tscn) as a child node.

        This is how you compose scenes — instantiate a player.tscn inside a level,
        add enemy.tscn instances, place UI components, etc. The instanced scene
        retains its connection to the source .tscn file.

        Args:
            scene_path: Resource path to the scene file (e.g., 'res://scenes/player.tscn').
            parent_path: Where to add it ('.' for scene root, 'Enemies' for a child).
            name: Optional custom name. If empty, uses the scene's root node name.
        """
        body: dict[str, Any] = {"scene_path": scene_path, "parent_path": parent_path}
        if name:
            body["name"] = name
        result = await editor.post("/node/instance_scene", body)
        if "ok" in result and "_description" not in result:
            result["_description"] = f"🔗 Instanced '{scene_path}' as '{result.get('name', '?')}' under '{parent_path}'"
        return result

    @mcp.tool
    async def godot_find_nodes(
        name: str = "",
        type: str = "",
        group: str = "",
        in_path: str = "",
    ) -> dict[str, Any]:
        """Search for nodes in the currently edited scene by name, type, or group.

        At least one search criterion must be provided. Results include each
        matching node's name, type, and path.

        Args:
            name: Name pattern to match. Supports '*' wildcards (e.g., 'Enemy*', '*Label').
                  Without wildcards, matches as a case-insensitive substring.
            type: Godot class name to filter by (e.g., 'Label', 'CharacterBody2D').
                  Also matches subclasses.
            group: Group name the node must belong to (e.g., 'enemies', 'interactable').
            in_path: Optional subtree to search within (e.g., 'UI' to only search under UI).
        """
        params: dict[str, str] = {}
        if name:
            params["name"] = name
        if type:
            params["type"] = type
        if group:
            params["group"] = group
        if in_path:
            params["in"] = in_path
        result = await editor.get("/node/find", params)
        if "error" not in result and "_description" not in result:
            count = result.get("count", 0)
            criteria = " + ".join(filter(None, [
                f"name='{name}'" if name else "",
                f"type='{type}'" if type else "",
                f"group='{group}'" if group else "",
            ]))
            result["_description"] = f"🔍 Found {count} node(s) matching {criteria}"
        return result

    # --- Signal Tools ---

    @mcp.tool
    async def godot_list_signals(path: str) -> dict[str, Any]:
        """List all signals on a node and their current connections.

        Returns every signal defined on the node (both built-in and custom),
        along with argument info and any existing connections. Useful for
        understanding what signals are available before connecting them.

        Args:
            path: Node path ('.' for root, 'Player', 'UI/Button', etc.).
        """
        result = await editor.get("/node/signals", {"path": path})
        if "error" not in result and "_description" not in result:
            connected = sum(len(s.get("connections", [])) for s in result.get("signals", []))
            result["_description"] = f"📡 {result.get('count', '?')} signal(s) on '{result.get('node', path)}', {connected} connection(s)"
        return result

    @mcp.tool
    async def godot_connect_signal(
        source: str,
        signal_name: str,
        target: str,
        method: str,
    ) -> dict[str, Any]:
        """Connect a signal from one node to a method on another node.

        This creates a signal connection in the editor scene. The connection
        will be saved with the scene and persist across runs.

        Args:
            source: Node path of the signal emitter (e.g., 'UI/StartButton').
            signal_name: Name of the signal to connect (e.g., 'pressed', 'body_entered').
            target: Node path of the receiver (e.g., '.', 'GameManager').
            method: Method name on the target to call (e.g., '_on_start_pressed').
        """
        result = await editor.post("/node/connect_signal", {
            "source": source,
            "signal": signal_name,
            "target": target,
            "method": method,
        })
        if "ok" in result and "_description" not in result:
            result["_description"] = f"🔗 Connected '{source}'.{signal_name} → '{target}'.{method}()"
        return result

    @mcp.tool
    async def godot_disconnect_signal(
        source: str,
        signal_name: str,
        target: str,
        method: str,
    ) -> dict[str, Any]:
        """Disconnect a signal connection between two nodes.

        Args:
            source: Node path of the signal emitter.
            signal_name: Name of the signal to disconnect.
            target: Node path of the receiver.
            method: Method name on the target that was connected.
        """
        result = await editor.post("/node/disconnect_signal", {
            "source": source,
            "signal": signal_name,
            "target": target,
            "method": method,
        })
        if "ok" in result and "_description" not in result:
            result["_description"] = f"🔌 Disconnected '{source}'.{signal_name} → '{target}'.{method}()"
        return result

    # --- Group Tools ---

    @mcp.tool
    async def godot_add_to_group(path: str, group: str) -> dict[str, Any]:
        """Add a node to a group.

        Groups are used to organize nodes (e.g., 'enemies', 'collectibles',
        'interactable'). Nodes in a group can be found with godot_find_nodes(group=...).

        Args:
            path: Node path (e.g., 'Player', 'Enemies/Goblin').
            group: Group name to add the node to (e.g., 'enemies', 'persistent').
        """
        result = await editor.post("/node/add_to_group", {"path": path, "group": group})
        if "ok" in result and "_description" not in result:
            result["_description"] = f"🏷️ Added '{path}' to group '{group}'"
        return result

    @mcp.tool
    async def godot_remove_from_group(path: str, group: str) -> dict[str, Any]:
        """Remove a node from a group.

        Args:
            path: Node path (e.g., 'Player', 'Enemies/Goblin').
            group: Group name to remove the node from.
        """
        result = await editor.post("/node/remove_from_group", {"path": path, "group": group})
        if "ok" in result and "_description" not in result:
            result["_description"] = f"🏷️ Removed '{path}' from group '{group}'"
        return result

    # --- Input Map Tools ---

    @mcp.tool
    async def godot_add_input_action(
        action: str,
        deadzone: float = 0.5,
    ) -> dict[str, Any]:
        """Add a new input action to the project's InputMap.

        Creates an action with no bindings. Use godot_add_input_binding to
        add key/button bindings after creation.

        Args:
            action: Action name (e.g., 'jump', 'attack', 'move_left').
            deadzone: Analog deadzone threshold (0.0–1.0, default 0.5).
        """
        result = await editor.post("/project/input_map/add_action", {
            "action": action,
            "deadzone": deadzone,
        })
        if "ok" in result and "_description" not in result:
            result["_description"] = f"🎮 Added input action '{action}'"
        return result

    @mcp.tool
    async def godot_remove_input_action(action: str) -> dict[str, Any]:
        """Remove an input action and all its bindings from the project.

        Args:
            action: Action name to remove (e.g., 'jump', 'attack').
        """
        result = await editor.post("/project/input_map/remove_action", {"action": action})
        if "ok" in result and "_description" not in result:
            result["_description"] = f"🎮 Removed input action '{action}'"
        return result

    @mcp.tool
    async def godot_add_input_binding(
        action: str,
        event_type: str,
        value: str,
    ) -> dict[str, Any]:
        """Add a key/button binding to an existing input action.

        The action must already exist (use godot_add_input_action first, or
        check godot_get_input_map to see existing actions).

        Args:
            action: Action name to bind to (e.g., 'jump').
            event_type: One of 'key', 'mouse_button', 'joypad_button', 'joypad_motion'.
            value: The binding value, depends on event_type:
                   - key: Key name like 'Space', 'W', 'A', 'D', 'Escape', 'Shift', 'Up', 'Down'.
                   - mouse_button: Button index as string ('1' = left, '2' = right, '3' = middle).
                   - joypad_button: Button index as string ('0', '1', '2', etc.).
                   - joypad_motion: 'axis:direction' like '0:1' (left stick right) or '1:-1' (left stick up).
        """
        result = await editor.post("/project/input_map/add_binding", {
            "action": action,
            "event_type": event_type,
            "value": value,
        })
        if "ok" in result and "_description" not in result:
            result["_description"] = f"🎮 Added {event_type} binding '{value}' to '{action}'"
        return result

    @mcp.tool
    async def godot_remove_input_binding(action: str, index: int) -> dict[str, Any]:
        """Remove a specific binding from an input action by index.

        Use godot_get_input_map to see current bindings and their indices.

        Args:
            action: Action name (e.g., 'jump').
            index: 0-based index of the binding to remove.
        """
        result = await editor.post("/project/input_map/remove_binding", {
            "action": action,
            "index": index,
        })
        if "ok" in result and "_description" not in result:
            result["_description"] = f"🎮 Removed binding #{index} from '{action}'"
        return result

    # --- Script Tools ---

    @mcp.tool
    async def godot_read_script(path: str) -> dict[str, Any]:
        """Read the full contents of a GDScript file.

        Args:
            path: Resource path to the script (e.g., 'res://scripts/player.gd').
        """
        result = await editor.get("/script/read", {"path": path})
        if "error" not in result and "_description" not in result:
            lines = result.get("content", "").count("\n") + 1
            result["_description"] = f"📄 Read '{path}' ({lines} lines)"
        return result

    @mcp.tool
    async def godot_write_script(path: str, content: str) -> dict[str, Any]:
        """Write content to a GDScript file. Creates the file if it doesn't exist.

        After writing, you must stop and restart the game for changes to take effect.

        Args:
            path: Resource path for the script (e.g., 'res://scripts/player.gd').
            content: Full script content to write.
        """
        result = await editor.post("/script/write", {"path": path, "content": content})
        if "ok" in result and "_description" not in result:
            lines = content.count("\n") + 1
            result["_description"] = f"✍️ Wrote '{path}' ({lines} lines)"
        return result

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
        result = await editor.post("/script/create", {"path": path, "extends": extends, "template": template})
        if "ok" in result and "_description" not in result:
            result["_description"] = f"🆕 Created script '{path}' (extends {extends})"
        return result

    @mcp.tool
    async def godot_get_errors() -> dict[str, Any]:
        """Get current script compilation errors from the editor.

        Returns a list of errors with file paths and messages.
        """
        result = await editor.get("/script/errors")
        if "_description" not in result:
            errors = result.get("errors", [])
            if errors:
                result["_description"] = f"❌ {len(errors)} script error(s)"
            else:
                result["_description"] = "✅ No script errors"
        return result

    @mcp.tool
    async def godot_get_debugger_output() -> dict[str, Any]:
        """Get recent output from the editor's Output/debugger panel."""
        result = await editor.get("/debugger/output")
        if "_description" not in result:
            result["_description"] = "📟 Debugger output"
        return result

    # --- Project Tools ---

    def _count_files_in_tree(entries: list) -> int:
        """Recursively count files in a project structure tree."""
        count = 0
        for entry in entries:
            if entry.get("type") == "file":
                count += 1
            elif entry.get("type") == "directory":
                count += _count_files_in_tree(entry.get("children", []))
        return count

    @mcp.tool
    async def godot_project_structure() -> dict[str, Any]:
        """Get the project directory tree (res://).

        Returns file names, types, paths, and sizes. Excludes .godot/ and the bridge addon.
        Use this to understand what files exist before reading or modifying them.
        """
        result = await editor.get("/project/structure")
        if "error" not in result and "_description" not in result:
            file_count = _count_files_in_tree(result.get("tree", []))
            result["_description"] = f"📁 Project structure — {file_count} files"
        return result

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
        result = await editor.get("/project/search", params)
        if "error" not in result and "_description" not in result:
            matches = len(result.get("matches", []))
            term = pattern or query
            result["_description"] = f"🔎 Search '{term}' — {matches} match(es)"
        return result

    @mcp.tool
    async def godot_get_input_map() -> dict[str, Any]:
        """Get all InputMap actions and their key/button bindings.

        Returns action names mapped to their input events (keys, mouse buttons, joypad).
        Use this to understand what input actions are available for game_trigger_action.
        """
        result = await editor.get("/project/input_map")
        if "error" not in result and "_description" not in result:
            count = len(result.get("actions", {}))
            result["_description"] = f"🎮 Input map — {count} action(s)"
        return result

    @mcp.tool
    async def godot_get_project_settings() -> dict[str, Any]:
        """Get key project settings: name, main scene, window size, physics FPS, etc."""
        result = await editor.get("/project/settings")
        if "_description" not in result:
            name = result.get("name", "?")
            result["_description"] = f"⚙️ Project settings for '{name}'"
        return result

    @mcp.tool
    async def godot_get_autoloads() -> dict[str, Any]:
        """Get all registered autoload singletons and their script paths."""
        result = await editor.get("/project/autoloads")
        if "error" not in result and "_description" not in result:
            count = len(result.get("autoloads", {}))
            result["_description"] = f"🔌 {count} autoload(s)"
        return result

    # --- Run Control ---

    @mcp.tool
    async def godot_run_game(scene: str = "", strict: bool = False) -> dict[str, Any]:
        """Start running the game from the editor.

        After starting, runtime tools become available. This tool will wait for
        the runtime bridge to become reachable before returning.

        When **strict=True** (startup gating mode), any fatal runtime error
        detected during startup causes the tool to return ``ok=false`` with
        machine-readable ``startup_errors``.  Fatal patterns include:
        Node not found, Cannot call method, Invalid access/call, SCRIPT ERROR,
        and Parse Error.

        If you receive ``ok=false``, you MUST enter repair mode:
        1. Stop normal actions (no snapshot/click).
        2. Call ``godot_get_errors()`` and ``godot_get_debugger_output()`` for
           full diagnostics.
        3. Patch the files referenced by ``startup_errors`` / debug output.
        4. Save the scene (``godot_save_scene()``), then re-run
           ``godot_run_game(strict=True)``.
        5. Repeat up to 5 attempts. Only proceed when ``ok=true``.

        Args:
            scene: Optional scene path to run (e.g., 'res://scenes/level_1.tscn').
                   If empty, runs the project's main scene.
            strict: If True, treat any fatal error pattern as a startup failure
                    that must be repaired before the agent may proceed.
        """
        body: dict[str, Any] = {}
        if scene:
            body["scene"] = scene

        result = await editor.post("/game/run", body)

        # Give the editor a moment to process the deferred play call and
        # compile/launch the game before we start polling the runtime bridge.
        await asyncio.sleep(1.5)

        # Poll until runtime bridge is available (~15 more seconds of polling).
        # Large projects can take a while to boot, so we give plenty of time
        # before declaring "game failed to start".
        for i in range(60):  # ~15 more seconds of polling (60 × 0.25s)
            await asyncio.sleep(0.25)
            if await runtime.is_available():
                info = await runtime.get("/info")
                scene_name = info.get("current_scene", scene or "main scene")

                # Gather console output for error detection
                console_output = ""
                try:
                    console = await runtime.get("/console")
                    console_output = console.get("output", "")
                except Exception:
                    pass  # Console fetch is best-effort

                # Gather debugger output as well (captures errors the console may miss)
                debugger_output = ""
                try:
                    debugger = await editor.get("/debugger/output")
                    debugger_output = debugger.get("output", "")
                except Exception:
                    pass

                combined_output = (console_output + "\n" + debugger_output).strip()

                # --- Strict mode: check for fatal startup errors ---
                if strict:
                    startup_errors = _collect_startup_errors(combined_output)
                    if startup_errors:
                        return {
                            "ok": False,
                            "running": True,
                            "error_type": "startup_runtime_error",
                            "startup_errors": startup_errors,
                            "log_tail": _truncate_log_tail(combined_output),
                            "_description": (
                                f"❌ Game started but has {len(startup_errors)} fatal "
                                f"startup error(s) — read the errors below, fix the "
                                f"code, stop, save, and relaunch"
                            ),
                        }

                # --- Build success response ---
                response: dict[str, Any] = {
                    "ok": True,
                    "running": True,
                    "_description": f"▶️ Game started — '{scene_name}'",
                    "game_info": info,
                }
                # Surface any non-fatal error lines in non-strict mode
                if console_output:
                    error_lines = [
                        line.strip() for line in console_output.split("\n")
                        if _is_error_line(line)
                    ]
                    if error_lines:
                        response["runtime_errors"] = error_lines
                return response

        # Runtime bridge never connected — the game likely crashed on startup.
        # Gather whatever diagnostics we can from the editor side.
        debugger_output = ""
        try:
            debugger = await editor.get("/debugger/output")
            debugger_output = debugger.get("output", "")
        except Exception:
            pass  # Editor may also be unreachable

        if strict:
            startup_errors = _collect_startup_errors(debugger_output)
            # If no structured errors were found, synthesize one from any
            # available error lines so the caller always gets something useful.
            if not startup_errors:
                error_lines = [
                    line.strip() for line in debugger_output.split("\n")
                    if _is_error_line(line)
                ]
                startup_errors = [_parse_error_line(l) for l in error_lines]
            return {
                "ok": False,
                "running": False,
                "error_type": "startup_runtime_error",
                "startup_errors": startup_errors,
                "log_tail": _truncate_log_tail(debugger_output) if debugger_output else "",
                "_description": (
                    f"❌ Game failed to start — {len(startup_errors)} error(s) found. "
                    "Read the errors, fix the code, save, and relaunch."
                ),
            }

        # Non-strict fallback (original behaviour)
        response: dict[str, Any] = {
            "ok": False,
            "running": False,
            "_description": "❌ Game failed to start — call godot_get_debugger_output() to see errors, fix, and relaunch",
        }
        if debugger_output:
            error_lines = [
                line.strip() for line in debugger_output.split("\n")
                if _is_error_line(line)
            ]
            if error_lines:
                response["debugger_errors"] = error_lines
        return response

    @mcp.tool
    async def godot_stop_game() -> dict[str, Any]:
        """Stop the currently running game.

        After stopping, runtime tools will no longer be available.
        Use this before editing code — changes require a restart to take effect.
        """
        result = await editor.post("/game/stop")
        if "_description" not in result:
            result["_description"] = "⏹️ Game stopped"
        return result

    @mcp.tool
    async def godot_is_game_running() -> dict[str, Any]:
        """Check if the game is currently running."""
        result = await editor.get("/game/is_running")
        if "_description" not in result:
            running = result.get("running", False)
            result["_description"] = "🟢 Game is running" if running else "⚫ Game is not running"
        return result

    # --- Editor Screenshot ---

    @mcp.tool
    async def godot_editor_screenshot(
        mode: str = "viewport",
        width: int = 640,
        height: int = 360,
        quality: float = 0.75,
    ) -> list[Any]:
        """Capture a screenshot of the Godot editor.

        Two modes are available:
        - "viewport": Just the 2D/3D main canvas — what you'd look at to check node
          placement, visual layout, and scene composition. Use this most of the time.
        - "full": The entire editor window including all docks (Scene tree, Inspector,
          FileSystem, bottom panel). Use this when you need to see the inspector values,
          the scene hierarchy, or the overall editor layout.

        Args:
            mode: "viewport" for the 2D/3D canvas only, "full" for the entire editor window.
            width: Screenshot width in pixels (default 640).
            height: Screenshot height in pixels (default 360).
            quality: JPEG quality 0.0–1.0 (default 0.75). Lower = smaller response.
        """
        data = await editor.get("/screenshot", {
            "width": str(width),
            "height": str(height),
            "quality": str(quality),
            "mode": mode,
        })
        if "error" in data:
            return [data["error"]]

        actual_mode = data.get("mode", mode)
        mode_label = "viewport" if actual_mode == "viewport" else "full editor"
        return [
            f"📸 Editor screenshot — {mode_label} ({data['size'][0]}x{data['size'][1]})",
            _b64_image(data["image"]),
        ]
