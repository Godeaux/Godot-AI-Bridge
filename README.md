# Godot AI Bridge

A Godot 4.6 addon that gives AI agents full control over the Godot editor and running games via [MCP](https://modelcontextprotocol.io/) (Model Context Protocol).

## Architecture

```
AI Agent (Claude Code / Windsurf / Cursor)
    │
    │  MCP Protocol (stdio)
    │
    ▼
server.py  ←  Python MCP server (FastMCP)
    │
    │  HTTP to localhost:9899 (editor) and localhost:9900 (runtime)
    │
    ├───────────────────┬──────────────────┐
    │                   │                  │
    ▼                   ▼                  ▼
EditorPlugin        Runtime Autoload    Screenshots
(port 9899)         (port 9900)         (both sides)
    │                   │
    ▼                   ▼
Godot Editor        Running Game
```

## Setup

### 1. Install the Godot Plugin

Copy `addons/godot_ai_bridge/` into your Godot project's `addons/` folder:

```
your_project/
├── addons/
│   └── godot_ai_bridge/   ← copy this (includes mcp_server/)
├── scenes/
├── scripts/
└── project.godot
```

Enable it in **Project > Project Settings > Plugins** and check the box next to "Godot AI Bridge".

### 2. Install Python Dependencies

```bash
pip install fastmcp httpx
```

Or if you use [uv](https://docs.astral.sh/uv/):

```bash
cd your_project/addons/godot_ai_bridge/mcp_server
uv sync
```

### 3. Configure Your AI Client

Add the MCP server to your AI client's configuration. Replace `/path/to/your_project` with the actual path.

```json
{
  "mcpServers": {
    "godot": {
      "command": "python",
      "args": ["/path/to/your_project/addons/godot_ai_bridge/mcp_server/server.py"]
    }
  }
}
```

Where to paste this config:
- **Claude Code:** Settings > MCP Servers
- **Cursor:** `.cursor/mcp.json` in your project root
- **Windsurf:** `~/.codeium/windsurf/mcp_config.json`

The "AI Bridge" panel in Godot's bottom dock has a **Copy MCP Config** button that generates this JSON with the correct path for you.

### 4. Use

Editor tools are available whenever the Godot editor is open with the plugin enabled.
Runtime tools become available when you run the game via `godot_run_game`.

## What It Does

**Editor tools** (`godot_*`):
- Create/edit scenes and nodes (add, remove, rename, duplicate, reparent, reorder, instance scenes)
- Read/write/create scripts, check for errors, read debugger output
- Inspect and set node properties, list all editable properties with type info
- Wire up signal connections (list, connect, disconnect)
- Manage node groups (add to group, remove from group)
- Search the scene tree (by name, type, or group)
- Search project files, read project settings, input map, autoloads
- Create and configure input actions and key/button bindings
- Run/stop the game with strict startup gating (auto-fix errors before proceeding)
- Take editor screenshots (viewport or full editor)

**Runtime tools** (`game_*`):
- Scene tree snapshots with stable node refs, targeted subtree queries (`root`/`depth`), and screenshots
- Annotated Vision — ref labels and bounding boxes drawn directly on screenshots so the AI can see which node is which
- Input injection: click (single/double), key press, action trigger, mouse move (absolute + relative), multi-step sequences
- Deep node state reading (velocity, animation state, overlapping bodies, etc.)
- Modify node properties at runtime (speed, health, position — like the Inspector during play)
- Call methods on nodes at runtime
- Wait for time or conditions (property equals/greater/less, node exists/freed, signal)
- Pause/unpause, time scale control
- Console output, snapshot diffs, scene change history

**AI Bridge Panel** (in Godot's bottom dock):
- Live activity log of every MCP request with color-coded methods and human-readable descriptions
- Live Agent Vision — thumbnail of the latest screenshot the AI received, updated in real-time
- Scene info overlay showing the current scene name, node count, FPS, and frame number
- Interactive Director Mode — click the screenshot to place numbered markers, type text directives, and send real-time guidance to the AI agent
- Copy MCP Config button for quick setup

## Director Mode

The AI Bridge panel lets you guide the AI while it works. Click on the live screenshot to drop numbered markers at specific game locations, type instructions in the text field, and hit Send. The AI receives your markers (as game-viewport coordinates) and text on its next observation call, acknowledges them, and adjusts its plan accordingly.

This turns the panel into a collaborative workspace — you watch what the AI sees, point at things, and steer it in real time.

## Ports

- `9899` — Editor bridge (always running when plugin is enabled)
- `9900` — Runtime bridge (only when game is running)

Both bind to `127.0.0.1` only — no external network access.

## Requirements

- Godot 4.6
- Python 3.10+
- [FastMCP](https://pypi.org/project/fastmcp/) 2.x and [httpx](https://pypi.org/project/httpx/)

## License

MIT
