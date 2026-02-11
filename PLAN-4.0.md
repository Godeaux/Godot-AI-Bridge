# Godot AI Bridge 4.0 — Implementation Plan

## Context for the Implementing Agent

You are working on **Godot AI Bridge**, an addon for the Godot 4.6 game engine that lets AI agents (Claude Code, Windsurf, Cursor) control the Godot editor and interact with running games via the **Model Context Protocol (MCP)**.

### Architecture Overview

```
AI Agent (Claude Code / Windsurf / Cursor)
    │
    │  MCP Protocol (stdio)
    │
    ▼
Python MCP Server (FastMCP)                    ← addons/godot_ai_bridge/mcp_server/
    │
    │  HTTP requests (localhost)
    │
    ├──► Editor Bridge (port 9899)             ← addons/godot_ai_bridge/editor/
    │    Always running when plugin is enabled
    │    Scene/script/project editing tools
    │
    └──► Runtime Bridge (port 9900)            ← addons/godot_ai_bridge/runtime/
         Only running when the game is running
         Snapshots, input injection, state, events
```

### Key Files

| File | Role |
|------|------|
| `mcp_server/server.py` | FastMCP entry point, registers tools, contains agent instructions |
| `mcp_server/runtime_tools.py` | ~24 MCP tool definitions for runtime (game_*) |
| `mcp_server/editor_tools.py` | ~30 MCP tool definitions for editor (godot_*) |
| `mcp_server/client.py` | HTTP client (httpx) for talking to Godot bridges |
| `mcp_server/utils.py` | Helpers (base64 image formatting, error line detection) |
| `runtime/runtime_bridge.gd` | Autoload HTTP server (port 9900), route registration |
| `runtime/runtime_routes.gd` | All runtime HTTP endpoint handlers |
| `runtime/snapshot.gd` | Scene tree snapshot with ephemeral refs (n1, n2, ...) |
| `runtime/state_reader.gd` | Deep node inspection (velocities, overlaps, etc.) |
| `runtime/event_accumulator.gd` | Buffers signals/events between AI observations |
| `runtime/input_injector.gd` | Keyboard, mouse, action input injection |
| `runtime/runtime_screenshot.gd` | Viewport capture → resize → JPEG → Base64 |
| `runtime/runtime_annotation.gd` | Draws ref labels + bounding boxes on screenshots |
| `editor/editor_bridge.gd` | Editor HTTP server (port 9899), route registration |
| `editor/editor_routes.gd` | Editor HTTP endpoint handlers |
| `editor/scene_tools.gd` | Scene/node CRUD operations |
| `editor/script_tools.gd` | Script read/write/error checking |
| `editor/project_tools.gd` | Project structure, settings, input map |
| `editor/editor_screenshot.gd` | Editor viewport/window capture |
| `editor/activity_panel.gd` | Live AI activity monitor + director mode UI |
| `shared/config.gd` | Constants (ports, limits, defaults) |
| `shared/http_server.gd` | Custom TCP HTTP server (both bridges extend this) |
| `shared/serialization.gd` | Godot types ↔ JSON conversion |
| `plugin.gd` | EditorPlugin entry point |
| `CLAUDE.md` | Agent instructions (tool reference, examples, patterns) |

### Current Version: 3.0.0

3.0 added the EventAccumulator system (game_events, game_add_watch, etc.). The AI can now see what happened between snapshots — collisions, animations, node lifecycle, property changes.

### How Data Flows (Example: game_snapshot)

1. AI agent calls `game_snapshot()` MCP tool
2. `runtime_tools.py` sends `GET /snapshot?depth=12` to `localhost:9900`
3. `runtime_bridge.gd` routes to `runtime_routes.gd:handle_snapshot()`
4. `snapshot.gd:take_snapshot()` walks the scene tree, assigns refs (n1, n2, ...)
5. Optional: `runtime_screenshot.gd` captures viewport → JPEG → Base64
6. Optional: `runtime_annotation.gd` overlays ref labels on screenshot
7. `event_accumulator.gd:poll()` checks property watches + scene changes
8. Response sent as JSON with node tree, screenshot, pending_events count
9. `runtime_tools.py` formats response, pushes screenshot to editor panel
10. AI agent receives structured data + optional image

---

## 4.0 Release Theme: "Stable Identity & Smarter Observation"

The core insight: **AI agents waste most of their context window re-establishing what they already know.** Every snapshot regenerates refs, forcing the agent to re-map node identities. Full tree walks are expensive even when nothing changed. The agent has no way to say "show me only what's different." And critical game systems (TileMap, physics, audio) are invisible.

4.0 fixes this with three pillars:
1. **Stable node IDs** that persist across snapshots
2. **Incremental snapshots** that return only what changed
3. **MCP Resources & Prompts** that give agents richer, more efficient access patterns

---

## Workstream 1: Stable Node IDs

### Problem

Snapshot refs (`n1`, `n2`, `n3`) are regenerated on every `take_snapshot()` call. The AI must re-snapshot to get valid refs before any node interaction. If the AI remembers "the player was n3" from a previous snapshot, that ref is now invalid — n3 might be a completely different node.

### Current Implementation (snapshot.gd)

```gdscript
# In RuntimeSnapshot._walk_tree():
var ref: String = "n%d" % _ref_counter
_ref_counter += 1
_ref_map[ref] = node        # Maps "n5" → Node reference
_path_to_ref[path] = ref    # Maps "Player/Sprite" → "n5"
```

`_ref_counter` resets to 0 on each `take_snapshot()` call. `_ref_map` and `_path_to_ref` are cleared and rebuilt.

### Solution: Instance-ID-Based Stable Refs

Replace the sequential counter with Godot's `node.get_instance_id()`, which is a unique integer for the lifetime of the node object.

#### Changes to `snapshot.gd`

```gdscript
# NEW: Persistent maps (not cleared between snapshots)
var _id_to_node: Dictionary = {}     # Maps stable_id → Node (weak via instance_id)
var _node_to_id: Dictionary = {}     # Maps instance_id → stable_id string

# NEW: Human-friendly prefix + instance_id
func _get_stable_id(node: Node) -> String:
    var iid: int = node.get_instance_id()
    if _node_to_id.has(iid):
        return _node_to_id[iid]
    # Generate a short, readable ID: first 3 chars of class + instance_id
    # e.g., "Cha42981" for CharacterBody2D with instance_id 42981
    var prefix: String = node.get_class().substr(0, 3)
    var stable_id: String = "%s%d" % [prefix, iid]
    _node_to_id[iid] = stable_id
    _id_to_node[iid] = node  # Will become invalid if node freed
    return stable_id
```

In `_walk_tree()`, replace:
```gdscript
# OLD:
var ref: String = "n%d" % _ref_counter
_ref_counter += 1

# NEW:
var ref: String = _get_stable_id(node)
```

In `resolve_ref()`, add instance_id lookup:
```gdscript
func resolve_ref(ref_or_path: String, scene_root: Node) -> Node:
    # Try direct ref lookup (stable ID)
    for iid: int in _node_to_id:
        if _node_to_id[iid] == ref_or_path:
            var node = instance_from_id(iid)
            if node != null and node.is_inside_tree():
                return node
            else:
                # Node was freed — clean up stale entry
                _node_to_id.erase(iid)
                _id_to_node.erase(iid)
                break
    # Fall back to path-based lookup (existing behavior)
    ...
```

#### Cleanup: Prune Freed Nodes

Add a `_prune_stale()` call at the start of `take_snapshot()`:
```gdscript
func _prune_stale() -> void:
    var to_erase: Array[int] = []
    for iid: int in _id_to_node:
        if not is_instance_id_valid(iid) or not instance_from_id(iid).is_inside_tree():
            to_erase.append(iid)
    for iid: int in to_erase:
        _id_to_node.erase(iid)
        _node_to_id.erase(iid)
```

#### Changes to Annotation System (runtime_annotation.gd)

The annotation renderer draws ref labels on screenshots. Update to use stable IDs. The change is minimal since annotations read the `ref` field from the snapshot data — as long as snapshot.gd puts the stable ID in the `ref` field, annotations work automatically.

#### Migration: MCP Tool Docstrings

Update all tool docstrings in `runtime_tools.py` that mention refs:
```python
# OLD:
# "Each node gets a short ref like 'n1', 'n5' — use these with game_click_node..."
# "Refs are only valid until the next snapshot call."

# NEW:
# "Each node gets a stable ID like 'Cha42981' — use these with game_click_node..."
# "IDs persist across snapshots for the lifetime of the node."
```

#### Changes to CLAUDE.md

Update the "Reading Snapshots" section and all examples that reference `n1`, `n5` style refs.

---

## Workstream 2: Incremental Snapshots

### Problem

Every `game_snapshot()` call walks the entire scene tree (up to 500 nodes, depth 12). For a game with 300 nodes where only the player moved, the agent gets 300 nodes of data to find the one change. `game_snapshot_diff()` exists but requires two full snapshots and computes the diff client-side in GDScript.

### Solution: Server-Side Dirty Tracking

Track which nodes changed since the last snapshot and return only those.

#### New Class: `DirtyTracker` (new file: `runtime/dirty_tracker.gd`)

```gdscript
class_name DirtyTracker
extends RefCounted

## Tracks which nodes have changed properties since the last snapshot.

var _tree: SceneTree
var _last_snapshot_frame: int = -1
var _dirty_nodes: Dictionary = {}  # instance_id → true
var _active: bool = false

func _init(tree: SceneTree) -> void:
    _tree = tree

func start() -> void:
    _active = true
    _last_snapshot_frame = Engine.get_frames_drawn()

func stop() -> void:
    _active = false
    _dirty_nodes.clear()

func mark_dirty(node: Node) -> void:
    if _active and node != null:
        _dirty_nodes[node.get_instance_id()] = true

func mark_all_dirty() -> void:
    ## Call after scene change — everything is new.
    _dirty_nodes.clear()
    # Special marker meaning "everything changed"
    _dirty_nodes[-1] = true

func consume_dirty() -> Dictionary:
    ## Returns dirty set and clears it. Called by snapshot.
    var result: Dictionary = _dirty_nodes.duplicate()
    _dirty_nodes.clear()
    _last_snapshot_frame = Engine.get_frames_drawn()
    return result

func is_full_dirty() -> bool:
    return _dirty_nodes.has(-1)
```

#### Integration with EventAccumulator

The EventAccumulator already detects node_added, node_removed, signal fires, and property changes. Wire it to the DirtyTracker:

In `event_accumulator.gd`, add:
```gdscript
var _dirty_tracker: DirtyTracker  # Set externally by RuntimeRoutes

func set_dirty_tracker(tracker: DirtyTracker) -> void:
    _dirty_tracker = tracker
```

In `_record()`, after recording the event:
```gdscript
func _record(type: String, source_path: String, detail: Dictionary) -> void:
    ...
    # Mark the source node dirty
    if _dirty_tracker != null:
        var root: Node = _tree.current_scene
        if root != null:
            var node: Node = root.get_node_or_null(source_path)
            if node != null:
                _dirty_tracker.mark_dirty(node)
```

In `_poll_scene_change()`, when a scene changes:
```gdscript
if _dirty_tracker != null:
    _dirty_tracker.mark_all_dirty()
```

#### New Snapshot Mode: `incremental=true`

Add to `runtime_routes.gd:handle_snapshot()`:
```gdscript
var incremental: bool = request.query_params.get("incremental", "false") == "true"
```

When `incremental=true`:
1. Check `_dirty_tracker.is_full_dirty()` — if true, do a full snapshot (scene just changed)
2. Otherwise, get the dirty set from `_dirty_tracker.consume_dirty()`
3. Walk only dirty nodes + their ancestors (to maintain tree structure)
4. Return `"incremental": true` in response so the AI knows it's partial

#### New MCP Parameter

In `runtime_tools.py`, update `game_snapshot()`:
```python
async def game_snapshot(
    root: str = "",
    depth: int = 12,
    include_screenshot: bool = False,
    annotate: bool = True,
    quality: float = 0.75,
    incremental: bool = False,   # NEW
) -> list[Any]:
```

Update docstring:
```python
"""
...
Args:
    incremental: If True, return only nodes that changed since last snapshot.
        The first call (or after a scene change) returns a full snapshot.
        Subsequent calls return only changed nodes + their ancestors.
        Use this for efficient polling after actions. Default False.
"""
```

#### HTTP Endpoint Change

`GET /snapshot?incremental=true&depth=12`

Response includes:
```json
{
    "incremental": true,
    "changed_count": 3,
    "total_scene_nodes": 287,
    "nodes": [ ... only changed subtrees ... ],
    "pending_events": 5
}
```

---

## Workstream 3: MCP Resources & Prompts

### Problem

The project only uses MCP **tools**. The MCP spec offers two additional primitives — **Resources** (read-only data the AI can pull into context) and **Prompts** (reusable workflow templates). The 118-line instructions string in `server.py` is monolithic and not modular.

### 3A: MCP Resources

Resources let the AI read game state without calling tools. They are exposed as URIs.

#### Add to `server.py` or a new `resources.py`:

```python
from fastmcp import FastMCP

def register_resources(mcp: FastMCP) -> None:

    @mcp.resource("godot://project/settings")
    async def project_settings():
        """Current Godot project settings (name, main scene, physics config)."""
        try:
            return await editor.get("/project_settings")
        except Exception:
            return {"error": "Editor not connected"}

    @mcp.resource("godot://project/input_map")
    async def input_map():
        """All configured input actions and their key bindings."""
        try:
            return await editor.get("/input_map")
        except Exception:
            return {"error": "Editor not connected"}

    @mcp.resource("godot://project/structure")
    async def project_structure():
        """File tree of the Godot project (res:// directory)."""
        try:
            return await editor.get("/project_structure")
        except Exception:
            return {"error": "Editor not connected"}

    @mcp.resource("godot://game/info")
    async def game_info():
        """Current game state: scene, FPS, viewport size, pause state, autoloads."""
        try:
            return await runtime.get("/info")
        except Exception:
            return {"note": "Game not running"}

    @mcp.resource("godot://game/actions")
    async def game_actions():
        """Available InputMap actions and their bindings in the running game."""
        try:
            return await runtime.get("/actions")
        except Exception:
            return {"note": "Game not running"}
```

Register in `server.py`:
```python
from resources import register_resources
register_resources(mcp)
```

### 3B: MCP Prompts

Prompts are user-triggered workflow templates. They modularize the monolithic instructions.

#### Add `prompts.py`:

```python
from fastmcp import FastMCP

def register_prompts(mcp: FastMCP) -> None:

    @mcp.prompt()
    def playtest(objective: str = "explore and find bugs") -> str:
        """Start a gameplay testing session with a specific objective."""
        return f"""You are play-testing a Godot game. Your objective: {objective}

Workflow:
1. godot_run_game(strict=true) — launch the game
2. game_snapshot(include_screenshot=true) — see the initial state
3. game_list_actions() — discover available inputs
4. Interact based on what you see in the screenshot
5. After each action, game_snapshot() to observe results
6. When pending_events > 0, call game_events() to see what happened
7. Report bugs, visual glitches, or gameplay issues you find

Remember: every game is different. Look at the screenshot, understand what kind of game it is, and act accordingly."""

    @mcp.prompt()
    def debug_crash(error_text: str = "") -> str:
        """Diagnose and fix a game crash."""
        return f"""The game crashed or has errors. Diagnose and fix.
{f'Error: {error_text}' if error_text else 'Check godot_get_debugger_output() for errors.'}

Steps:
1. godot_get_debugger_output() — get the full error with stack trace
2. godot_get_errors() — check for script compilation errors
3. godot_read_script() — read the broken script mentioned in the error
4. Identify the root cause from the error message and code
5. godot_write_script() — fix the code
6. godot_stop_game() then godot_save_scene()
7. godot_run_game(strict=true) — relaunch and verify the fix"""

    @mcp.prompt()
    def build_level(level_name: str, style: str = "2D platformer") -> str:
        """Step-by-step guide for building a new game level."""
        return f"""Build a new {style} level called '{level_name}'.

Steps:
1. godot_create_scene("Node2D", "res://scenes/{level_name}.tscn")
2. godot_open_scene("res://scenes/{level_name}.tscn")
3. Add ground: godot_add_node(".", "StaticBody2D", "Ground") + CollisionShape2D
4. Instance the player: godot_instance_scene("res://scenes/player.tscn", ".")
5. Add obstacles, enemies, collectibles as needed
6. Set up a Camera2D following the player
7. godot_editor_screenshot(mode="viewport") — verify the layout visually
8. godot_save_scene()
9. godot_run_game() — test the level"""

    @mcp.prompt()
    def balance_gameplay() -> str:
        """Analyze and tune gameplay balance using runtime property tweaking."""
        return """Analyze the running game's balance and suggest tweaks.

Workflow:
1. game_snapshot(include_screenshot=true) — observe the game
2. game_state(path="Player") — check player stats (speed, health, damage)
3. game_add_watch("Player", "health", "player_hp") — monitor health
4. Play through a section, then game_events() to see combat outcomes
5. Use game_set_property() to tweak values in real-time:
   - Too hard? Increase player health/speed, decrease enemy damage
   - Too easy? The opposite
6. Once values feel good, update the scripts with the tuned values"""
```

Register in `server.py`:
```python
from prompts import register_prompts
register_prompts(mcp)
```

### 3C: Slim Down server.py Instructions

After moving workflow-specific guidance into prompts, trim the `instructions` string in `server.py` to core behavior only (tool overview, error recovery, snapshot efficiency, strict startup). Remove the duplicated workflow patterns that are now in prompts. Target: ~60 lines instead of ~118.

---

## Workstream 4: Extended Node Type Support in StateReader

### Problem

`state_reader.gd` has special handling for ~15 node types but misses many important ones. When the AI inspects a TileMap, physics body properties, or audio node, it gets only generic data.

### Nodes to Add

Add to `StateReader.read_state()` using the existing pattern (check `node is Type`, add relevant properties to the result dict):

#### TileMapLayer (Godot 4.3+)
```gdscript
if node is TileMapLayer:
    result["tile_set"] = str(node.tile_set.resource_path) if node.tile_set else null
    result["enabled"] = node.enabled
    # Note: iterating all used cells is expensive; provide count instead
    result["used_cells_count"] = node.get_used_cells().size()
```

#### RigidBody2D/3D (Extended)
```gdscript
# Add to existing RigidBody handling:
result["mass"] = node.mass
result["gravity_scale"] = node.gravity_scale
result["contact_monitor"] = node.contact_monitor
if node.physics_material_override:
    result["friction"] = node.physics_material_override.friction
    result["bounce"] = node.physics_material_override.bounce
```

#### CharacterBody2D/3D (Extended)
```gdscript
# Add to existing CharacterBody handling:
result["slide_count"] = node.get_slide_collision_count()
var collisions: Array[Dictionary] = []
for i in range(node.get_slide_collision_count()):
    var col = node.get_slide_collision(i)
    collisions.append({
        "collider": str(col.get_collider().name) if col.get_collider() else "null",
        "normal": BridgeSerialization.serialize(col.get_normal()),
    })
result["slide_collisions"] = collisions
```

#### AudioStreamPlayer / AudioStreamPlayer2D / AudioStreamPlayer3D
```gdscript
if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
    result["playing"] = node.playing
    result["stream"] = str(node.stream.resource_path) if node.stream else null
    result["volume_db"] = node.volume_db
    result["bus"] = node.bus
    if node is AudioStreamPlayer2D:
        result["max_distance"] = node.max_distance
        result["attenuation"] = node.attenuation
    if node is AudioStreamPlayer3D:
        result["max_distance"] = node.max_distance
        result["unit_size"] = node.unit_size
        result["attenuation_model"] = node.attenuation_model
```

#### GPUParticles2D / GPUParticles3D / CPUParticles2D / CPUParticles3D
```gdscript
if node is GPUParticles2D or node is GPUParticles3D:
    result["emitting"] = node.emitting
    result["amount"] = node.amount
    result["lifetime"] = node.lifetime
    result["one_shot"] = node.one_shot
if node is CPUParticles2D or node is CPUParticles3D:
    result["emitting"] = node.emitting
    result["amount"] = node.amount
    result["lifetime"] = node.lifetime
    result["one_shot"] = node.one_shot
```

#### Camera2D / Camera3D (Extended)
```gdscript
# Add to existing Camera handling:
if node is Camera2D:
    result["zoom"] = BridgeSerialization.serialize(node.zoom)
    result["limit_left"] = node.limit_left
    result["limit_right"] = node.limit_right
    result["limit_top"] = node.limit_top
    result["limit_bottom"] = node.limit_bottom
    result["drag_horizontal_enabled"] = node.drag_horizontal_enabled
if node is Camera3D:
    result["fov"] = node.fov
    result["near"] = node.near
    result["far"] = node.far
    result["projection"] = node.projection
```

#### NavigationAgent2D / NavigationAgent3D
```gdscript
if node is NavigationAgent2D or node is NavigationAgent3D:
    result["target_position"] = BridgeSerialization.serialize(node.target_position)
    result["is_navigation_finished"] = node.is_navigation_finished()
    result["distance_to_target"] = node.distance_to_target()
    result["is_target_reachable"] = node.is_target_reachable()
    result["max_speed"] = node.max_speed
```

#### RayCast2D / RayCast3D
```gdscript
if node is RayCast2D or node is RayCast3D:
    result["enabled"] = node.enabled
    result["is_colliding"] = node.is_colliding()
    if node.is_colliding():
        var collider = node.get_collider()
        result["collider"] = str(collider.name) if collider else null
        result["collision_point"] = BridgeSerialization.serialize(node.get_collision_point())
        result["collision_normal"] = BridgeSerialization.serialize(node.get_collision_normal())
```

---

## Workstream 5: Composite Observation Tool

### Problem

The typical AI observe-act loop requires 3+ separate HTTP round-trips:
1. `game_snapshot()` — see the state
2. `game_events()` — see what happened
3. Some action tool

### Solution: `game_observe()` — One-Stop Observation

Add a new composite MCP tool that returns snapshot + events + screenshot in a single call.

#### New HTTP Endpoint: `GET /observe`

In `runtime_routes.gd`:
```gdscript
func handle_observe(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
    # Take snapshot (reuses existing logic)
    var snap_result: Dictionary = await handle_snapshot(request)

    # Drain events
    _accumulator.poll()
    var events: Array[Dictionary] = _accumulator.drain()
    snap_result["events"] = events
    snap_result["event_count"] = events.size()

    return snap_result
```

#### New MCP Tool: `game_observe()`

In `runtime_tools.py`:
```python
@mcp.tool
async def game_observe(
    root: str = "",
    depth: int = 12,
    include_screenshot: bool = True,
    annotate: bool = True,
    quality: float = 0.75,
    incremental: bool = False,
) -> list[Any]:
    """Primary observation tool — snapshot + events + screenshot in one call.

    Returns the full picture: scene tree structure, any events that happened
    since last observation (collisions, property changes, node lifecycle),
    and optionally an annotated screenshot. This is the recommended way to
    observe the game, replacing separate game_snapshot() + game_events() calls.

    Args:
        root: Focus on subtree (e.g., 'Player'). Empty = full scene.
        depth: Max tree depth (default 12). Use 3-4 for focused observations.
        include_screenshot: Capture a screenshot (default True).
        annotate: Draw ref labels on screenshot (default True).
        quality: JPEG quality 0.0-1.0 (default 0.75).
        incremental: Only return nodes that changed since last observation.
    """
```

Register in `runtime_bridge.gd`:
```gdscript
register_route("GET", "/observe", _on_observe)
```

---

## Workstream 6: Progress Reporting & Better Errors

### 6A: MCP Progress Reporting

FastMCP provides a `Context` object that tools can use to report progress on long-running operations. This is especially useful for `godot_run_game(strict=true)` which may take several seconds.

#### In `editor_tools.py`:

```python
from fastmcp import Context

@mcp.tool
async def godot_run_game(strict: bool = True, ctx: Context = None) -> dict:
    if ctx:
        await ctx.report_progress(0, 100, "Starting game...")

    result = await editor.post("/run", {"strict": strict})

    if ctx:
        await ctx.report_progress(50, 100, "Checking for startup errors...")

    # ... existing strict-mode error checking ...

    if ctx:
        await ctx.report_progress(100, 100, "Game running")

    return result
```

Add `ctx: Context = None` to other long-running tools: `game_wait`, `game_wait_for`, `game_input_sequence`.

### 6B: Structured Error Responses

Currently `script_tools.gd:get_errors()` reloads scripts and checks `can_instantiate()` but doesn't report which line failed. Improve this.

#### In `script_tools.gd`:

Replace the current error detection with Godot's built-in script error reporting:

```gdscript
func get_errors() -> Dictionary:
    var errors: Array[Dictionary] = []

    # Scan open scripts for parse errors
    var scripts: Array = EditorInterface.get_open_scripts()
    for script: Script in scripts:
        # Force reload from disk
        var fresh: Script = load(script.resource_path)
        if fresh == null:
            errors.append({
                "file": script.resource_path,
                "line": 0,
                "message": "Failed to load script",
            })
            continue

        # Check source_code for parse errors by attempting compilation
        if not fresh.can_instantiate():
            errors.append({
                "file": script.resource_path,
                "line": 0,
                "message": "Script cannot be instantiated (parse error or missing dependencies)",
            })

    # Also check debugger output for runtime errors
    var debugger_output: String = _read_log_tail(4000)
    var runtime_errors: Array[Dictionary] = _parse_error_lines(debugger_output)
    errors.append_array(runtime_errors)

    return {
        "errors": errors,
        "count": errors.size(),
    }

func _parse_error_lines(log_text: String) -> Array[Dictionary]:
    var errors: Array[Dictionary] = []
    var lines: PackedStringArray = log_text.split("\n")
    for line: String in lines:
        # Match patterns like: "res://scripts/player.gd:42 - Invalid call"
        var regex := RegEx.new()
        regex.compile("(res://[^:]+):(\\d+)\\s*[-—]\\s*(.*)")
        var match := regex.search(line)
        if match:
            errors.append({
                "file": match.get_string(1),
                "line": int(match.get_string(2)),
                "message": match.get_string(3).strip_edges(),
            })
    return errors
```

---

## Workstream 7: Configuration & Limits

### Problem

All limits are hardcoded in `config.gd` and some are too restrictive:
- `MAX_NODE_COUNT = 500` silently truncates large scenes
- `MAX_BASE64_LENGTH = 40000` forces aggressive JPEG quality reduction
- No warning when limits are hit

### Changes to `config.gd`:

```gdscript
const MAX_NODE_COUNT: int = 2000      # Was 500 — large 3D games need more
const MAX_BASE64_LENGTH: int = 80000  # Was 40000 — allow higher quality screenshots
```

### Add Truncation Warnings

In `snapshot.gd`, when `MAX_NODE_COUNT` is reached:
```gdscript
if _node_count >= BridgeConfig.MAX_NODE_COUNT:
    result["truncated"] = true
    result["truncated_at"] = BridgeConfig.MAX_NODE_COUNT
    result["note"] = "Scene has more nodes than the limit (%d). Use root= to focus on a subtree." % BridgeConfig.MAX_NODE_COUNT
```

Surface this in `runtime_tools.py`:
```python
if data.get("truncated"):
    summary += f" ⚠️ TRUNCATED at {data['truncated_at']} nodes — use root= to focus"
```

---

## Workstream 8: EventAccumulator Signal Gaps

### Currently Auto-Monitored

| Signal | Node Types |
|--------|-----------|
| body_entered/exited | Area2D, Area3D, CollisionObject2D, CollisionObject3D |
| area_entered/exited | Area2D, Area3D |
| animation_finished | AnimationPlayer, AnimatedSprite2D, AnimatedSprite3D |
| screen_entered/exited | VisibleOnScreenNotifier2D, VisibleOnScreenNotifier3D |
| pressed | BaseButton |
| timeout | Timer |

### Add These Signals

In `event_accumulator.gd:_try_connect_node()`:

```gdscript
# NavigationAgent — target reached
if node is NavigationAgent2D or node is NavigationAgent3D:
    _connect_noarg.call(node, "navigation_finished")
    _connect_noarg.call(node, "target_reached")

# AnimationTree — animation_finished (if present)
if node is AnimationTree:
    _connect_1arg.call(node, "animation_finished")

# AudioStreamPlayer — finished
if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
    _connect_noarg.call(node, "finished")

# RigidBody — sleeping_state_changed
if (node is RigidBody2D or node is RigidBody3D) and node.has_signal("sleeping_state_changed"):
    _connect_noarg.call(node, "sleeping_state_changed")
```

---

## Implementation Order

Do these in sequence. Each workstream should be a separate commit.

| Order | Workstream | Effort | Files Changed |
|-------|-----------|--------|--------------|
| 1 | Stable Node IDs | Medium | snapshot.gd, runtime_tools.py, CLAUDE.md |
| 2 | Extended StateReader | Small | state_reader.gd |
| 3 | EventAccumulator Signal Gaps | Small | event_accumulator.gd |
| 4 | Configuration & Limits | Small | config.gd, snapshot.gd, runtime_tools.py |
| 5 | Composite game_observe() | Medium | runtime_routes.gd, runtime_bridge.gd, runtime_tools.py, CLAUDE.md |
| 6 | Incremental Snapshots | Large | dirty_tracker.gd (new), event_accumulator.gd, runtime_routes.gd, snapshot.gd, runtime_tools.py, CLAUDE.md |
| 7 | MCP Resources & Prompts | Medium | resources.py (new), prompts.py (new), server.py |
| 8 | Progress & Better Errors | Medium | editor_tools.py, runtime_tools.py, script_tools.gd |
| 9 | Version bump to 4.0.0 | Small | plugin.cfg, pyproject.toml, server.py |

---

## Testing Checklist

After all workstreams, verify:

- [ ] **Stable IDs**: Take two snapshots — same node has same ID in both
- [ ] **Stable IDs**: Free a node between snapshots — old ID resolves to null, not wrong node
- [ ] **Stable IDs**: Annotation labels on screenshots show stable IDs
- [ ] **Incremental**: `game_snapshot(incremental=true)` returns full on first call
- [ ] **Incremental**: After moving player, incremental snapshot returns only player subtree
- [ ] **Incremental**: After scene change, incremental returns full snapshot
- [ ] **game_observe()**: Returns snapshot + events + screenshot in one call
- [ ] **game_observe()**: Events are drained (not duplicated on next call)
- [ ] **StateReader**: TileMapLayer reports used_cells_count
- [ ] **StateReader**: RigidBody shows mass, friction, bounce
- [ ] **StateReader**: RayCast shows is_colliding + collider name
- [ ] **StateReader**: NavigationAgent shows is_navigation_finished
- [ ] **Events**: AudioStreamPlayer "finished" signal captured
- [ ] **Events**: NavigationAgent "target_reached" captured
- [ ] **Config**: Scene with 1500 nodes not truncated (new limit 2000)
- [ ] **Config**: Truncation warning shown when limit is exceeded
- [ ] **Resources**: `godot://project/settings` readable by AI
- [ ] **Prompts**: "playtest", "debug_crash", "build_level" available as prompts
- [ ] **Errors**: Script errors include file path and line number
- [ ] **Progress**: `godot_run_game(strict=true)` reports progress stages
- [ ] **Version**: plugin.cfg and pyproject.toml show 4.0.0
