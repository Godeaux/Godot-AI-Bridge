# Godot AI Bridge

A Godot 4.6 addon + MCP server that gives AI agents full control over both the Godot editor and running games.

## Architecture

```
AI Agent (Claude Code / Claude Desktop / Windsurf)
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

Enable it in Project → Project Settings → Plugins.

### 2. Configure the MCP Server

```bash
cd mcp_server
uv sync
```

Add to your MCP client config:

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

### 3. Use

Editor tools are available whenever the Godot editor is open with the plugin enabled.
Runtime tools become available when you run the game via `godot_run_game`.

## What It Does

- **Editor control**: Create/edit scenes and nodes, read/write scripts, search project files, manage input maps, run/stop the game
- **Runtime interaction**: Scene tree snapshots with stable refs, input injection (click, key, action, sequences), deep node state reading, conditional waiting
- **Screenshots everywhere**: Every snapshot includes a screenshot by default. The AI always sees what it's doing.

## Ports

- `9899` — Editor bridge (plugin must be enabled)
- `9900` — Runtime bridge (game must be running)

## Requirements

- Godot 4.6
- Python 3.10+ with FastMCP 2.x and httpx
