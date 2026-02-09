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

### Runtime Tools (`game_*`) — only when game is running
Interact with the actual running game. Take snapshots, inject input, read state.

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

## Reading Snapshots

Each node in a snapshot has:
- `ref` — short reference like "n1", use with click_node, state, etc.
- `type` — Godot class name (CharacterBody2D, Button, Label, etc.)
- `position` / `global_position` — where it is in the scene
- `visible` — whether it's actually visible in the tree
- `text` — for UI elements (Labels, Buttons) — read these to understand what's on screen
- `properties` — exported script variables (health, speed, score, etc.) — the game's actual state
- `groups` — group memberships (useful for understanding what a node represents)

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
