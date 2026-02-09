"""MCP tool definitions for Godot runtime (running game) operations.

These tools interact with the actual running game — taking snapshots,
injecting input, reading state, waiting for conditions, and capturing screenshots.
Only available when the game is running.
"""

from __future__ import annotations

from typing import Any

from fastmcp import FastMCP, Image
from client import runtime


GAME_NOT_RUNNING_MSG = "Game is not running. Use godot_run_game() to start it first."


async def _check_runtime() -> str | None:
    """Return an error message if runtime is not available, None if OK."""
    if not await runtime.is_available():
        return GAME_NOT_RUNNING_MSG
    return None


def register_runtime_tools(mcp: FastMCP) -> None:
    """Register all runtime tools with the MCP server."""

    # --- Primary Observation ---

    @mcp.tool
    async def game_snapshot(
        root: str = "",
        depth: int = 12,
        include_screenshot: bool = True,
    ) -> list[Any]:
        """Get a structured scene tree snapshot from the running game with stable refs.

        This is your PRIMARY way to understand game state. Always call this before and
        after interactions. Returns both structured data (node tree with refs, positions,
        properties) and a screenshot by default.

        Each node gets a short ref like "n1", "n5" — use these with game_click_node,
        game_state, etc. Refs are only valid until the next snapshot call.

        Args:
            root: Optional node path to start from instead of scene root (e.g., 'HUD').
            depth: Max tree depth to walk (default 12).
            include_screenshot: Whether to include a screenshot (default True).
        """
        err = await _check_runtime()
        if err:
            return [err]

        params: dict[str, str] = {
            "depth": str(depth),
            "include_screenshot": "true" if include_screenshot else "false",
        }
        if root:
            params["root"] = root

        data = await runtime.get("/snapshot", params)
        if "error" in data:
            return [str(data["error"])]

        # Build text summary
        screenshot_data = data.pop("screenshot", None)
        result: list[Any] = [data]

        if screenshot_data:
            result.append(Image(data=screenshot_data, media_type="image/png"))

        return result

    # --- Screenshots ---

    @mcp.tool
    async def game_screenshot(width: int = 960, height: int = 540) -> list[Any]:
        """Capture the running game viewport as a screenshot.

        Every snapshot already includes a screenshot by default, so only call this
        separately when you need a different resolution or just the image without
        the full structured data.

        Args:
            width: Screenshot width in pixels (default 960).
            height: Screenshot height in pixels (default 540).
        """
        err = await _check_runtime()
        if err:
            return [err]

        data = await runtime.get("/screenshot", {"width": str(width), "height": str(height)})
        if "error" in data:
            return [str(data["error"])]

        return [
            f"Game screenshot ({data['size'][0]}x{data['size'][1]}, frame {data.get('frame', '?')})",
            Image(data=data["image"], media_type=data["mime"]),
        ]

    @mcp.tool
    async def game_screenshot_node(ref: str = "", path: str = "") -> list[Any]:
        """Capture a cropped screenshot of a specific node's region.

        Useful for inspecting UI elements up close — zoom into a button, panel,
        or sprite to evaluate alignment, text readability, and visual quality.

        Args:
            ref: Node ref from latest snapshot (e.g., 'n5'). Preferred over path.
            path: Node path as alternative to ref (e.g., 'HUD/ScoreLabel').
        """
        err = await _check_runtime()
        if err:
            return [err]

        params: dict[str, str] = {}
        if ref:
            params["ref"] = ref
        if path:
            params["path"] = path

        data = await runtime.get("/screenshot/node", params)
        if "error" in data:
            return [str(data["error"])]

        return [
            f"Node screenshot (region: {data.get('node_rect', 'unknown')})",
            Image(data=data["image"], media_type=data["mime"]),
        ]

    # --- Input ---

    @mcp.tool
    async def game_click(x: float, y: float, button: str = "left") -> dict[str, Any]:
        """Click at specific screen coordinates in the running game.

        Prefer game_click_node when targeting a specific node — it handles coordinate
        lookup automatically and is more reliable.

        Args:
            x: X coordinate in screen space.
            y: Y coordinate in screen space.
            button: Mouse button — 'left', 'right', or 'middle'.
        """
        err = await _check_runtime()
        if err:
            return {"error": err}

        return await runtime.post("/click", {"x": x, "y": y, "button": button})

    @mcp.tool
    async def game_click_node(ref: str = "", path: str = "") -> dict[str, Any]:
        """Click a node by its ref from the latest snapshot.

        This is the preferred way to click UI elements. For Controls, clicks at
        the center of the node's rect. For Node2D, clicks at global_position.

        Args:
            ref: Node ref from latest snapshot (e.g., 'n5'). Preferred.
            path: Node path as alternative (e.g., 'HUD/StartButton').
        """
        err = await _check_runtime()
        if err:
            return {"error": err}

        body: dict[str, Any] = {}
        if ref:
            body["ref"] = ref
        if path:
            body["path"] = path
        return await runtime.post("/click_node", body)

    @mcp.tool
    async def game_press_key(
        key: str,
        action: str = "tap",
        duration: float = 0.0,
    ) -> dict[str, Any]:
        """Press a key in the running game.

        Args:
            key: Key name — letters ('a'-'z'), digits ('0'-'9'), or special keys
                 ('space', 'enter', 'escape', 'tab', 'shift', 'ctrl', 'alt',
                  'up', 'down', 'left', 'right', 'backspace', 'delete', 'f1'-'f12').
            action: How to press — 'tap' (press+release), 'press' (hold down),
                    'release' (let go), 'hold' (press for duration then release).
            duration: Seconds to hold the key (only used with action='hold').
        """
        err = await _check_runtime()
        if err:
            return {"error": err}

        return await runtime.post("/key", {"key": key, "action": action, "duration": duration})

    @mcp.tool
    async def game_trigger_action(
        action: str,
        pressed: bool = True,
        strength: float = 1.0,
    ) -> dict[str, Any]:
        """Trigger an InputMap action in the running game.

        Prefer this over raw key presses when possible — it maps directly to the
        project's input configuration. Use game_list_actions() to see available actions.

        Args:
            action: Action name from the InputMap (e.g., 'jump', 'move_left', 'ui_accept').
            pressed: True to press, False to release.
            strength: Action strength from 0.0 to 1.0 (for analog input).
        """
        err = await _check_runtime()
        if err:
            return {"error": err}

        return await runtime.post("/action", {"action": action, "pressed": pressed, "strength": strength})

    @mcp.tool
    async def game_mouse_move(x: float, y: float) -> dict[str, Any]:
        """Move the mouse to a position in the running game.

        Args:
            x: Target X coordinate.
            y: Target Y coordinate.
        """
        err = await _check_runtime()
        if err:
            return {"error": err}

        return await runtime.post("/mouse_move", {"x": x, "y": y})

    @mcp.tool
    async def game_input_sequence(
        steps: list[dict[str, Any]],
        snapshot_after: bool = True,
        screenshot_after: bool = True,
    ) -> list[Any]:
        """Execute a sequence of input steps with proper timing.

        Each step is a dict with one key determining the action:
        - {"key": "d", "duration": 2.0} — hold D for 2 seconds
        - {"wait": 0.5} — wait 0.5 seconds
        - {"action": "jump"} — trigger the jump action
        - {"click": [400, 300]} — click at coordinates
        - {"click_node": "n7"} — click a node by ref
        - {"mouse_move": [500, 300]} — move mouse

        Args:
            steps: List of input step dicts to execute in order.
            snapshot_after: Take a snapshot after the sequence (default True).
            screenshot_after: Include screenshot in the post-sequence snapshot (default True).
        """
        err = await _check_runtime()
        if err:
            return [err]

        data = await runtime.post("/sequence", {
            "steps": steps,
            "snapshot_after": snapshot_after,
            "screenshot_after": screenshot_after,
        })

        if "error" in data:
            return [str(data["error"])]

        screenshot_data = data.pop("screenshot", None)
        result: list[Any] = [data]
        if screenshot_data:
            result.append(Image(data=screenshot_data, media_type="image/png"))
        return result

    # --- State ---

    @mcp.tool
    async def game_state(ref: str = "", path: str = "") -> dict[str, Any]:
        """Get detailed state for a specific node in the running game.

        Returns more information than snapshot for specific node types:
        - CharacterBody: velocity, is_on_floor, is_on_wall, is_on_ceiling
        - RigidBody: linear_velocity, angular_velocity, sleeping
        - AnimationPlayer: current_animation, is_playing
        - Area2D/3D: overlapping bodies and areas
        - Timer: time_left, is_stopped, wait_time
        - Button: text, disabled
        - And more...

        Args:
            ref: Node ref from latest snapshot (e.g., 'n1'). Preferred.
            path: Node path as alternative (e.g., 'Player').
        """
        err = await _check_runtime()
        if err:
            return {"error": err}

        params: dict[str, str] = {}
        if ref:
            params["ref"] = ref
        if path:
            params["path"] = path
        return await runtime.get("/state", params)

    @mcp.tool
    async def game_call_method(
        method: str,
        ref: str = "",
        path: str = "",
        args: list[Any] | None = None,
    ) -> dict[str, Any]:
        """Call a method on a node in the running game and return the result.

        Useful for calling custom game methods like take_damage(25), reset(), etc.

        Args:
            method: Method name to call (e.g., 'take_damage', 'get_health').
            ref: Node ref from latest snapshot. Preferred.
            path: Node path as alternative.
            args: List of arguments to pass to the method.
        """
        err = await _check_runtime()
        if err:
            return {"error": err}

        body: dict[str, Any] = {"method": method}
        if ref:
            body["ref"] = ref
        if path:
            body["path"] = path
        if args:
            body["args"] = args
        return await runtime.post("/call_method", body)

    # --- Waiting ---

    @mcp.tool
    async def game_wait(
        seconds: float = 1.0,
        snapshot: bool = True,
        screenshot: bool = True,
    ) -> list[Any]:
        """Wait N seconds in the running game, then return a snapshot + screenshot.

        Essential for letting actions play out before checking results. Use after
        input injection, animation triggers, or any action that takes time to complete.

        Args:
            seconds: How long to wait (default 1.0).
            snapshot: Whether to take a snapshot after waiting (default True).
            screenshot: Whether to include a screenshot (default True).
        """
        err = await _check_runtime()
        if err:
            return [err]

        data = await runtime.post("/wait", {
            "seconds": seconds,
            "snapshot": snapshot,
            "screenshot": screenshot,
        }, )

        if "error" in data:
            return [str(data["error"])]

        screenshot_data = data.pop("screenshot", None)
        result: list[Any] = [data]
        if screenshot_data and isinstance(screenshot_data, str):
            result.append(Image(data=screenshot_data, media_type="image/png"))
        return result

    @mcp.tool
    async def game_wait_for(
        condition: str,
        ref: str = "",
        path: str = "",
        property: str = "",
        value: Any = None,
        timeout: float = 10.0,
        poll_interval: float = 0.1,
        snapshot: bool = True,
        screenshot: bool = True,
    ) -> list[Any]:
        """Wait until a condition is met in the running game, then return snapshot + screenshot.

        Conditions:
        - 'node_exists': Wait until a node at the given path exists in the tree.
        - 'node_freed': Wait until a node no longer exists.
        - 'property_equals': Wait until node.property == value.
        - 'property_greater': Wait until node.property > value.
        - 'property_less': Wait until node.property < value.
        - 'signal': Wait until a signal fires on the target node.

        Args:
            condition: One of the condition types listed above.
            ref: Node ref from snapshot.
            path: Node path as alternative.
            property: Property name (for property conditions).
            value: Target value (for property conditions).
            timeout: Max seconds to wait before giving up (default 10).
            poll_interval: How often to check the condition (default 0.1s).
            snapshot: Take snapshot after condition met (default True).
            screenshot: Include screenshot (default True).
        """
        err = await _check_runtime()
        if err:
            return [err]

        body: dict[str, Any] = {
            "condition": condition,
            "timeout": timeout,
            "poll_interval": poll_interval,
            "snapshot": snapshot,
            "screenshot": screenshot,
        }
        if ref:
            body["ref"] = ref
        if path:
            body["path"] = path
        if property:
            body["property"] = property
        if value is not None:
            body["value"] = value

        data = await runtime.post("/wait_for", body)

        if "error" in data:
            return [str(data["error"])]

        # Extract screenshot from nested snapshot if present
        screenshot_data = None
        if "snapshot" in data and isinstance(data["snapshot"], dict):
            screenshot_data = data["snapshot"].pop("screenshot", None)
        elif "screenshot" in data:
            screenshot_data = data.pop("screenshot", None)

        result: list[Any] = [data]
        if screenshot_data and isinstance(screenshot_data, str):
            result.append(Image(data=screenshot_data, media_type="image/png"))
        return result

    # --- Info ---

    @mcp.tool
    async def game_info() -> dict[str, Any]:
        """Get general information about the running game.

        Returns project name, current scene, viewport size, FPS, available actions,
        autoloads, pause state, and more. Useful for orientation.
        """
        err = await _check_runtime()
        if err:
            return {"error": err}

        return await runtime.get("/info")

    @mcp.tool
    async def game_list_actions() -> dict[str, Any]:
        """List all available InputMap actions and their key bindings in the running game.

        Use this to see what actions you can trigger with game_trigger_action.
        """
        err = await _check_runtime()
        if err:
            return {"error": err}

        return await runtime.get("/actions")
