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
│   └── godot_ai_bridge/   ← copy this
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
cd mcp_server
uv sync
```

### 3. Configure Your AI Client

Add the MCP server to your AI client's configuration. Replace `/path/to` with the actual path.

**Using pip:**
```json
{
  "mcpServers": {
    "godot": {
      "command": "python",
      "args": ["/path/to/godot_ai_bridge/mcp_server/server.py"]
    }
  }
}
```

**Using uv:**
```json
{
  "mcpServers": {
    "godot": {
      "command": "uv",
      "args": ["run", "/path/to/godot_ai_bridge/mcp_server/server.py"]
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
- Create/edit scenes and nodes (add, remove, rename, duplicate, reparent, instance scenes)
- Read/write/create scripts
- Search the scene tree (by name, type, or group)
- Search project files, read project settings, input map, autoloads
- Run/stop the game
- Take editor screenshots (viewport or full editor)

**Runtime tools** (`game_*`):
- Scene tree snapshots with stable node refs and screenshots
- Input injection: click, key press, action trigger, mouse move, multi-step sequences
- Deep node state reading (velocity, animation state, overlapping bodies, etc.)
- Wait for time or conditions (property equals, node exists/freed, signal)
- Pause/unpause, time scale control
- Console output, snapshot diffs, scene change history

## Ports

- `9899` — Editor bridge (always running when plugin is enabled)
- `9900` — Runtime bridge (only when game is running)

Both bind to `127.0.0.1` only — no external network access.

## Testing

Tests use [GdUnit4](https://github.com/godot-gdunit-labs/gdUnit4) (v6.1.1+). Install it before running tests:

```bash
# From the godot_ai_bridge/ directory:
./install_gdunit4.sh
```

Or install manually:

1. Download [GdUnit4 v6.1.1](https://github.com/godot-gdunit-labs/gdUnit4/releases/tag/v6.1.1) (`v6.1.1.zip`)
2. Extract the `addons/gdUnit4/` folder into `godot_ai_bridge/addons/`
3. Open the project in Godot and enable the GdUnit4 plugin under **Project > Project Settings > Plugins**

Test files live in `test/` and extend `GdUnitTestSuite`:

```gdscript
extends GdUnitTestSuite

func test_something() -> void:
    assert_str("hello").is_equal("hello")
```

Run from Godot's GdUnit4 inspector panel, or headless:

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test/
```

## Requirements

- Godot 4.6
- Python 3.10+
- [FastMCP](https://pypi.org/project/fastmcp/) 2.x and [httpx](https://pypi.org/project/httpx/)
- [GdUnit4](https://github.com/godot-gdunit-labs/gdUnit4) 6.1.1+ (for tests only)

## License

MIT
