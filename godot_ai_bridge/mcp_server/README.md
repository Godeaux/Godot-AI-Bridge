# Godot AI Bridge — MCP Server

Python MCP server that bridges AI agents to the Godot editor and running games.

## Setup

### Install Dependencies

```bash
pip install fastmcp httpx
```

Or with [uv](https://docs.astral.sh/uv/):

```bash
cd mcp_server
uv sync
```

### Configure as MCP Server

Add to your AI client config. Replace the path with the actual path to `server.py`.

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

Where to paste:
- **Claude Code:** Settings > MCP Servers
- **Cursor:** `.cursor/mcp.json` in your project root
- **Windsurf:** `~/.codeium/windsurf/mcp_config.json`

### Godot Plugin

The MCP server communicates with the Godot plugin over HTTP:
- **Port 9899** — Editor bridge (always running when plugin is enabled)
- **Port 9900** — Runtime bridge (only when game is running)

See the [main README](../README.md) for Godot plugin installation.

## Tools

**Editor tools** (`godot_*`) — 28 tools:
- Scene/node CRUD: get tree, add, remove, rename, duplicate, reparent, instance scene, find nodes
- Properties: get, set, list all properties
- Scripts: read, write, create, get errors, debugger output
- Project: structure, search files, input map, settings, autoloads
- Run control: run game, stop game, check status
- Screenshots: viewport or full editor

**Runtime tools** (`game_*`) — 20 tools:
- Observation: snapshot (with screenshot), standalone screenshot, node screenshot
- Input: click, click node, key press, action trigger, mouse move, input sequence
- State: detailed node state, call method
- Waiting: wait N seconds, wait for condition
- Control: pause/unpause, time scale
- Diagnostics: console output, snapshot diff, scene history, game info, list actions

## Testing Standalone

```bash
python server.py
```

This starts the MCP server in stdio mode. Useful for verifying the server starts without errors, but you'll need an MCP client to actually use the tools.
