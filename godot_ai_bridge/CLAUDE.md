# Godot AI Bridge — Agent Instructions

You have access to two sets of tools for working with a Godot game project:

## Editor Tools (always available when Godot editor is open)
Use these to edit scenes, scripts, and project files. These control the Godot Editor.

## Runtime Tools (available when the game is running)
Use these to interact with and test the running game. These control the actual gameplay.

## Core Workflow

1. **Edit** — Use editor tools to modify scenes, scripts, and assets
2. **Run** — Use `godot_run_game` to start the game
3. **Observe** — Use `game_snapshot` to get structured state + screenshot
4. **Interact** — Use input tools (click, key, action, sequence) to play the game
5. **Verify** — Use `game_snapshot` again to check results
6. **Fix** — If something's wrong, `godot_stop_game`, edit, and repeat

## Key Principles

- **Always snapshot before and after interactions.** This gives you both structured data and a screenshot each time.
- **Use refs from snapshots to click nodes**, not raw coordinates. Refs like "n5" map to node paths internally.
- **If a ref fails, re-snapshot.** Refs go stale when the scene tree changes.
- **Use `game_wait` after actions** to let animations/physics play out before checking results.
- **Screenshots are included in every snapshot by default.** You don't need to take separate screenshots unless you want a different resolution or to inspect a specific node region.
- **For UI evaluation**, use `game_screenshot_node` to zoom into specific UI elements.
- **Use `game_trigger_action`** instead of raw keys when possible — it maps to the project's InputMap.
- **After editing code**, you must stop and restart the game for changes to take effect.

## Reading Snapshots

Each node in a snapshot has:
- `ref` — short reference like "n1", use with click_node, state, etc.
- `type` — Godot class name (CharacterBody2D, Button, Label, etc.)
- `position` / `global_position` — where it is in the scene
- `visible` — whether it's actually visible in the tree
- `text` — for UI elements (Labels, Buttons)
- `properties` — exported script variables (health, speed, etc.)
- `groups` — group memberships

## Common Patterns

### Testing a gameplay mechanic:
1. `godot_run_game`
2. `game_snapshot` (see initial state)
3. `game_input_sequence` with the inputs to test
4. `game_wait(1.0)` to let it play out
5. `game_snapshot` to verify the result

### Evaluating UI layout:
1. `godot_run_game`
2. `game_snapshot` (see the full screen)
3. `game_screenshot_node(ref="n3")` to zoom into a specific panel
4. Evaluate alignment, spacing, text readability from the screenshot

### Debug loop:
1. `godot_run_game`
2. `game_snapshot` — notice something wrong
3. `godot_stop_game`
4. `godot_read_script` / `godot_write_script` to fix the issue
5. `godot_run_game` again
6. `game_snapshot` to verify the fix

### Building a scene from scratch:
1. `godot_create_scene("Node2D", "res://scenes/my_level.tscn")`
2. `godot_open_scene("res://scenes/my_level.tscn")`
3. `godot_add_node(".", "CharacterBody2D", "Player", {"position": [100, 300]})`
4. `godot_add_node("Player", "Sprite2D", "Sprite", {"texture": "res://icon.svg"})`
5. `godot_add_node("Player", "CollisionShape2D", "Collision")`
6. `godot_save_scene()`
7. `godot_editor_screenshot()` to verify it looks right

### Writing and attaching a script:
1. `godot_create_script("res://scripts/player.gd", "CharacterBody2D", "full")`
2. `godot_read_script("res://scripts/player.gd")` to review the template
3. `godot_write_script("res://scripts/player.gd", "extends CharacterBody2D\n...")` to customize
4. `godot_set_property("Player", "script", "res://scripts/player.gd")` to attach it
5. `godot_save_scene()`
