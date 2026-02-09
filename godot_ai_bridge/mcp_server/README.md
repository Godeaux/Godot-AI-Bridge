# Godot AI Bridge — MCP Server

## Quick Setup

### Prerequisites
- Python 3.10+
- [uv](https://docs.astral.sh/uv/) (recommended) or pip
- Godot 4.6 with the AI Bridge plugin enabled

### Install Dependencies

```bash
cd mcp_server
uv sync
```

### Run Standalone (for testing)

```bash
uv run server.py
```

### Configure as MCP Server

Add to your MCP client config (Claude Desktop, Windsurf, Claude Code, etc.):

```json
{
  "mcpServers": {
    "godot": {
      "command": "uv",
      "args": ["run", "/absolute/path/to/godot_ai_bridge/mcp_server/server.py"]
    }
  }
}
```

### Godot Plugin Setup

1. Copy the `addons/godot_ai_bridge/` directory into your Godot project's `addons/` folder
2. In the Godot editor: Project → Project Settings → Plugins → Enable "Godot AI Bridge"
3. The editor bridge starts on port 9899
4. When you run the game, the runtime bridge starts on port 9900

### Ports

- **9899** — Editor bridge (always running when plugin is enabled)
- **9900** — Runtime bridge (only when game is running)

### Tools Available

**Editor tools** (`godot_*`): Scene/node CRUD, script read/write, project structure, run control, editor screenshots.

**Runtime tools** (`game_*`): Scene snapshots, input injection (click, key, action, sequence), state reading, waiting, game screenshots.
