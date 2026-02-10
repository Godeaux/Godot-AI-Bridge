# Godot AI Bridge — Agent Instructions

You have access to tools for controlling the Godot game engine. You can edit games in the Godot Editor and play/test them at runtime. Your job is to look at what's happening, decide what to do, do it, and then look again.

## The Loop: Observe → Decide → Act → Observe

This is how you interact with a running game. It is NOT scripted — you look at the screenshot and structured data, understand the current game state in context, and decide what input makes sense for THIS specific game.

```
game_snapshot()          →  See the game (screenshot + node tree + properties)
    ↓
Think about what you see  →  "The player is at the left edge. There's a platform
    ↓                         to the right. I should move right and then jump."
    ↓
game_press_key("d", "hold", 1.5)   →  Hold D to move right
game_trigger_action("jump")         →  Jump onto the platform
    ↓
game_wait(1.0)           →  Let the physics play out
    ↓
game_snapshot()          →  See what happened — did the player land on the platform?
    ↓
Think again              →  "The player overshot. Let me adjust..."
```

Every decision you make should come from what you see in the screenshot and read in the structured data. Different games need different inputs — a platformer needs movement keys, a menu needs button clicks, a puzzle game needs mouse drags. Look at the game, understand what it is, and act accordingly.

## Two Toolsets

### Editor Tools (`godot_*`) — always available when Godot editor is open
Edit scenes, scripts, and project files. Control the Godot Editor itself.
- **Scene/node operations**: `godot_get_scene_tree`, `godot_create_scene`, `godot_open_scene`, `godot_save_scene`, `godot_add_node`, `godot_remove_node`, `godot_rename_node`, `godot_duplicate_node`, `godot_reparent_node`, `godot_instance_scene`, `godot_find_nodes`
- **Properties**: `godot_get_property`, `godot_set_property`, `godot_list_node_properties`
- **Signals**: `godot_list_signals`, `godot_connect_signal`, `godot_disconnect_signal`
- **Groups**: `godot_add_to_group`, `godot_remove_from_group`
- **Scripts**: `godot_read_script`, `godot_write_script`, `godot_create_script`, `godot_get_errors`, `godot_get_debugger_output`
- **Project**: `godot_project_structure`, `godot_search_files`, `godot_get_project_settings`, `godot_get_input_map`, `godot_get_autoloads`
- **Input map editing**: `godot_add_input_action`, `godot_remove_input_action`, `godot_add_input_binding`, `godot_remove_input_binding`
- **Run control**: `godot_run_game`, `godot_stop_game`, `godot_is_game_running`
- **Editor screenshots**: `godot_editor_screenshot` — capture the viewport (2D/3D canvas) or full editor window (with all docks)

### Runtime Tools (`game_*`) — only when game is running
Interact with the actual running game. Take snapshots, inject input, read and modify state.
- **Observation**: `game_snapshot` (node tree + screenshot), `game_screenshot`, `game_screenshot_node`
- **Input**: `game_click`, `game_click_node`, `game_press_key`, `game_trigger_action`, `game_mouse_move`, `game_input_sequence`
- **State**: `game_state` (deep node inspection), `game_set_property` (modify values at runtime), `game_call_method`
- **Waiting**: `game_wait` (wait N seconds), `game_wait_for` (wait for conditions: property equals, node exists, signal)
- **Control**: `game_pause`, `game_set_timescale`
- **Diagnostics**: `game_console_output`, `game_snapshot_diff`, `game_scene_history`, `game_list_actions`

## Core Workflow

1. **Edit** — Use editor tools to modify scenes, scripts, and assets
2. **Run** — `godot_run_game()` starts the game
3. **Observe** — `game_snapshot()` returns structured node tree + screenshot
4. **Decide** — Look at the screenshot. What's on screen? What should you do?
5. **Act** — Use the appropriate input tool for what you decided
6. **Observe again** — `game_snapshot()` or `game_wait()` to see the result
7. **Repeat** — Keep the loop going until you've accomplished your goal
8. **Fix** — If something's broken, `godot_stop_game()`, edit code, restart

## How to Decide What Input to Use

Look at the screenshot and structured data. Then:

- **See a menu with buttons?** → Use `game_click_node(ref="n5")` on the button
- **See a player character in a platformer?** → Use `game_press_key("d", "hold", 2.0)` to walk right, `game_trigger_action("jump")` to jump
- **See a text input field?** → Click it, then type with `game_press_key`
- **See a dialogue box with "Continue"?** → Click the continue button or press the advance key
- **See enemies approaching?** → Use the game's attack action, dodge, etc.
- **Not sure what actions exist?** → Call `game_list_actions()` to see the InputMap

The key insight: **you are looking at a screenshot of a real game and deciding what a player would do.** There is no fixed script. Every game is different.

## Key Principles

- **Always snapshot before and after interactions.** This gives you both structured data and a screenshot each time.
- **Use refs from snapshots to click nodes**, not raw coordinates. Refs like "n5" are more reliable.
- **If a ref fails, re-snapshot.** Refs go stale when the scene tree changes.
- **Use `game_wait` after actions** to let animations/physics play out before checking results.
- **Use `game_trigger_action`** instead of raw keys when possible — it maps to the project's InputMap.
- **After editing code**, you must stop and restart the game for changes to take effect.
- **For multi-step actions**, use `game_input_sequence` — but build the sequence dynamically based on what you see, not from a template.
- **Use `game_snapshot_diff`** to efficiently see what changed after an action, instead of manually comparing full snapshots.
- **Use `game_pause` + `game_snapshot`** for freeze-frame debugging — pause, inspect, resume.
- **Use `game_set_timescale(0.2)`** for slow-motion to observe fast gameplay in detail.
- **Use `game_console_output`** to check for errors, warnings, and print() debug output during gameplay.
- **Use `godot_editor_screenshot`** to see the editor state — use `mode="viewport"` for the 2D/3D canvas, `mode="full"` for the entire editor window with all docks and inspector.
- **Use `godot_find_nodes`** to search the scene tree by name, type, or group instead of manually walking the tree.
- **Use `godot_instance_scene`** to add .tscn files as children — this is how you compose scenes (add a player.tscn to a level, enemy.tscn instances, UI components, etc.).
- **Use `game_set_property`** to tweak values at runtime without stopping the game — adjust speed, health, position, etc. like using the Inspector during play.
- **Use `godot_connect_signal`** to wire up signal connections — e.g., connect a button's `pressed` signal to a handler method.
- **Use `godot_add_input_action` + `godot_add_input_binding`** to set up input mappings — create actions and bind keys/buttons to them.
- **Use `godot_add_to_group`** to tag nodes for easy lookup — then find them with `godot_find_nodes(group="enemies")`.

## Reading Snapshots

Each node in a snapshot has:
- `ref` — short reference like "n1", use with click_node, state, set_property, etc.
- `type` — Godot class name (CharacterBody2D, Button, Label, etc.)
- `position` / `global_position` — where it is in the scene
- `visible` — whether it's actually visible in the tree
- `text` — for UI elements (Labels, Buttons) — read these to understand what's on screen
- `properties` — exported script variables (health, speed, score, etc.) — the game's actual state
- `groups` — group memberships (useful for understanding what a node represents)

## Advanced: Editor Screenshots

Use `godot_editor_screenshot` to visually verify your edits without running the game:

```
1. godot_add_node(".", "Sprite2D", "Player", {"position": [400, 300]})
2. godot_editor_screenshot(mode="viewport")     →  See the 2D canvas — is the sprite placed correctly?
3. godot_editor_screenshot(mode="full")          →  See the full editor — check inspector, scene tree dock
```

Use `mode="viewport"` most of the time (node placement, visual layout). Use `mode="full"` when you need to see the inspector panel, scene tree dock, or other editor UI.

## Advanced: Runtime Property Tweaking

Modify values on the fly without stopping the game — like using the Inspector during play:

```
1. game_snapshot()                               →  See current state
2. game_state(ref="n3")                          →  Check player's properties (speed=200, health=100)
3. game_set_property(ref="n3", property="speed", value=500)   →  Double the speed
4. game_snapshot()                               →  See the effect immediately
5. game_set_property(ref="n3", property="position", value=[400, 100])  →  Teleport the player
```

This is especially useful for:
- Balancing gameplay (adjust speed, damage, jump height)
- Testing edge cases (set health to 1, position near boundary)
- Debugging (move player to a specific location, change visibility)

## Advanced: Signal Connections

Wire up signals between nodes in the editor:

```
1. godot_list_signals(path="UI/StartButton")      →  See available signals (pressed, toggled, etc.)
2. godot_connect_signal(
       source="UI/StartButton",
       signal_name="pressed",
       target=".",
       method="_on_start_pressed"
   )                                               →  Connect button press to root's handler
3. godot_list_signals(path="UI/StartButton")      →  Verify the connection was made
```

## Advanced: Input Map Management

Create and configure input actions for the project:

```
1. godot_get_input_map()                          →  See current actions and bindings
2. godot_add_input_action("jump")                 →  Create a new action
3. godot_add_input_binding("jump", "key", "Space")  →  Bind Space key
4. godot_add_input_binding("jump", "joypad_button", "0")  →  Also bind joypad A button
5. godot_get_input_map()                          →  Verify the bindings
```

## Advanced: Pause-and-Inspect Debugging

When something goes wrong or you need to carefully analyze game state:

```
1. game_pause()                    →  Freeze the game world
2. game_snapshot()                 →  See exactly what's happening at this frozen moment
3. game_state(ref="n3")            →  Deep inspect the player node (velocity, is_on_floor, etc.)
4. game_console_output()           →  Check for errors or debug prints
5. game_pause(paused=false)        →  Resume the game
```

## Advanced: Slow-Motion Analysis

For fast-paced games where things happen too quickly to observe:

```
1. game_set_timescale(0.2)         →  Slow to 20% speed
2. game_trigger_action("attack")   →  Perform the action
3. game_snapshot()                 →  See intermediate states clearly
4. game_set_timescale(1.0)         →  Return to normal speed
```

## Advanced: Efficient Change Detection

Use `game_snapshot_diff` instead of comparing full snapshots manually:

```
1. game_snapshot_diff()            →  Baseline (first call stores state)
2. game_trigger_action("jump")
3. game_wait(1.0)
4. game_snapshot_diff()            →  Shows exactly what changed:
   → nodes_changed: {"Player": {"global_position": {"from": [100, 400], "to": [100, 250]}}}
   → properties: {"score": {"from": 0, "to": 100}}
```

## Advanced: Scene Composition

Use `godot_instance_scene` and `godot_find_nodes` to build complex scenes:

```
1. godot_instance_scene("res://scenes/player.tscn", ".")          →  Add player to level
2. godot_instance_scene("res://scenes/enemy.tscn", "Enemies")     →  Add enemy under Enemies node
3. godot_find_nodes(type="CharacterBody2D")                        →  Find all character bodies
4. godot_find_nodes(name="Enemy*", group="enemies")                →  Find enemies by name + group
5. godot_rename_node("Enemies/Enemy", "Goblin")                    →  Rename for clarity
6. godot_add_to_group("Enemies/Goblin", "enemies")                →  Tag it for group lookup
```

## Example: Playing a Platformer

```
1. godot_run_game()
2. game_snapshot()
   → I see a character on the left side of a 2D level. There are platforms
     above and to the right. The score shows 0. Health bar is full.

3. game_list_actions()
   → move_left, move_right, jump, attack are available

4. game_trigger_action("move_right", pressed=true)
   game_wait(2.0)
   game_trigger_action("move_right", pressed=false)
   → Held move_right for 2 seconds

5. game_snapshot()
   → The character moved to the right. There's a gap ahead with a platform.
     I need to jump.

6. game_trigger_action("jump")
   game_wait(0.5)
   game_trigger_action("move_right", pressed=true)
   game_wait(1.0)
   game_trigger_action("move_right", pressed=false)

7. game_snapshot()
   → The character made it across the gap. Score is now 100.
     There's an enemy ahead.

8. game_trigger_action("attack")
   game_wait(1.0)
   game_snapshot()
   → Enemy defeated. Health still full. Moving on...
```

## Example: Navigating a Menu

```
1. godot_run_game()
2. game_snapshot()
   → I see a main menu with three buttons: "Start Game" (n3), "Settings" (n4), "Quit" (n5)

3. game_click_node(ref="n3")  — click "Start Game"
4. game_wait(1.0)
5. game_snapshot()
   → The menu transitioned to a level select screen. I see Level 1, Level 2, Level 3.
```

## Example: Debugging a Visual Issue

```
1. godot_run_game()
2. game_snapshot()
   → The screenshot shows the player sprite is clipping through the floor.
     The structured data shows position.y = 500 but the floor is at y = 480.

3. godot_stop_game()
4. godot_read_script("res://scripts/player.gd")
   → Found the issue: gravity constant is too high

5. godot_write_script("res://scripts/player.gd", "...")  — fix the gravity
6. godot_run_game()
7. game_snapshot()
   → Player is now standing correctly on the floor. Position.y = 468. Looks good.
```

## Example: Building a Scene

```
1. godot_create_scene("Node2D", "res://scenes/level_2.tscn")
2. godot_open_scene("res://scenes/level_2.tscn")
3. godot_instance_scene("res://scenes/player.tscn", ".")
4. godot_add_node(".", "StaticBody2D", "Ground")
5. godot_add_node("Ground", "CollisionShape2D", "GroundCollision")
6. godot_find_nodes(type="StaticBody2D")  →  Verify the ground node exists
7. godot_editor_screenshot(mode="viewport")  →  Check the visual layout
8. godot_save_scene()
```

## Example: Runtime Balancing

```
1. godot_run_game()
2. game_snapshot()
   → Player moves too slowly, enemies are too fast.

3. game_state(ref="n3")
   → Player has speed=200, jump_force=400

4. game_set_property(ref="n3", property="speed", value=350)
5. game_set_property(ref="n3", property="jump_force", value=600)
   → Tweaked values without restarting

6. game_snapshot()
   → Player feels much better now. Update the script with these values.

7. godot_stop_game()
8. godot_read_script("res://scripts/player.gd")
9. godot_write_script("res://scripts/player.gd", "...")  — update the defaults
```
