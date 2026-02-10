## Activity panel for the Godot AI Bridge.
## Shows setup instructions for new users, then transitions to a live
## activity log once the AI client connects.
@tool
class_name AIBridgeActivityPanel
extends Control

var _main_vbox: VBoxContainer
var _header_bar: HBoxContainer
var _status_label: Label
var _clear_button: Button
var _copy_config_button: Button
var _log_display: RichTextLabel
var _setup_display: RichTextLabel

var _log_entries: Array[String] = []
var _has_received_request: bool = false
var _request_count: int = 0
var _mcp_server_path: String = ""

const MAX_LOG_ENTRIES: int = 200


func _ready() -> void:
	custom_minimum_size = Vector2(0, 200)
	_compute_mcp_server_path()
	_build_ui()
	_show_setup_instructions()


## Build the panel UI.
func _build_ui() -> void:
	_main_vbox = VBoxContainer.new()
	_main_vbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_main_vbox)

	# Header bar
	_header_bar = HBoxContainer.new()
	_main_vbox.add_child(_header_bar)

	_status_label = Label.new()
	_status_label.text = "AI Bridge — Setup Required"
	_status_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_header_bar.add_child(_status_label)

	_copy_config_button = Button.new()
	_copy_config_button.text = "Copy MCP Config"
	_copy_config_button.tooltip_text = "Copy the MCP server configuration JSON to clipboard"
	_copy_config_button.pressed.connect(_on_copy_config)
	_header_bar.add_child(_copy_config_button)

	_clear_button = Button.new()
	_clear_button.text = "Clear"
	_clear_button.pressed.connect(_on_clear)
	_header_bar.add_child(_clear_button)

	# Separator
	var sep := HSeparator.new()
	_main_vbox.add_child(sep)

	# Setup instructions (shown initially)
	_setup_display = RichTextLabel.new()
	_setup_display.bbcode_enabled = true
	_setup_display.scroll_following = false
	_setup_display.size_flags_vertical = SIZE_EXPAND_FILL
	_setup_display.size_flags_horizontal = SIZE_EXPAND_FILL
	_setup_display.selection_enabled = true
	_setup_display.fit_content = false
	_main_vbox.add_child(_setup_display)

	# Activity log (hidden initially)
	_log_display = RichTextLabel.new()
	_log_display.bbcode_enabled = true
	_log_display.scroll_following = true
	_log_display.size_flags_vertical = SIZE_EXPAND_FILL
	_log_display.size_flags_horizontal = SIZE_EXPAND_FILL
	_log_display.selection_enabled = true
	_log_display.fit_content = false
	_log_display.visible = false
	_main_vbox.add_child(_log_display)


## Show setup instructions for first-time users.
func _show_setup_instructions() -> void:
	if _setup_display == null:
		return

	var abs_path: String = _mcp_server_path
	var text: String = ""

	text += "[b][color=#569cd6]Godot AI Bridge — Setup Guide[/color][/b]\n\n"

	text += "[color=#4ec9b0]Step 1:[/color] [b]Install Python dependencies[/b]\n"
	text += "  Open a terminal and run:\n"
	text += "  [code]pip install fastmcp httpx[/code]\n"
	text += "  (Or use [code]uv pip install fastmcp httpx[/code] if you have uv)\n\n"

	text += "[color=#4ec9b0]Step 2:[/color] [b]Configure your AI client[/b]\n"
	text += "  Click [b]\"Copy MCP Config\"[/b] above, then paste into your AI client's MCP settings.\n\n"

	text += "  [color=gray]For Claude Code:[/color] Settings > MCP Servers > paste the config\n"
	text += "  [color=gray]For Cursor:[/color] .cursor/mcp.json in your project root\n"
	text += "  [color=gray]For Windsurf:[/color] ~/.codeium/windsurf/mcp_config.json\n\n"

	text += "[color=#4ec9b0]Step 3:[/color] [b]Start using it[/b]\n"
	text += "  Open your AI client and ask it to interact with your Godot project.\n"
	text += "  This panel will show live activity once the AI connects.\n\n"

	text += "[color=gray]Editor bridge listening on port %d\n" % BridgeConfig.EDITOR_PORT
	text += "Runtime bridge will start on port %d when the game runs\n" % BridgeConfig.RUNTIME_PORT
	text += "MCP server path: %s[/color]\n" % abs_path

	_setup_display.clear()
	_setup_display.append_text(text)


## Transition from setup view to activity log view.
func _switch_to_activity_view() -> void:
	if _has_received_request:
		return
	_has_received_request = true
	if _setup_display:
		_setup_display.visible = false
	if _log_display:
		_log_display.visible = true
	set_status("Connected")


## Log an AI action to the panel.
func log_action(method: String, path: String, summary: String = "") -> void:
	# First real request (not our own startup log) triggers the transition
	if method != "SYSTEM":
		_switch_to_activity_view()
		_request_count += 1

	var timestamp: String = Time.get_time_string_from_system()
	var color: String = _color_for_method(method)
	var entry: String = "[color=gray]%s[/color] [color=%s][b]%s[/b][/color] %s" % [timestamp, color, method, path]
	if summary != "":
		entry += " — [color=white]%s[/color]" % summary

	_log_entries.append(entry)
	while _log_entries.size() > MAX_LOG_ENTRIES:
		_log_entries.pop_front()

	if _log_display:
		_log_display.append_text(entry + "\n")

	# Update status with request count
	if _status_label and method != "SYSTEM":
		_status_label.text = "AI Bridge — Active (%d requests) — Last: %s %s" % [_request_count, method, path]


## Set the status text in the header.
func set_status(text: String) -> void:
	if _status_label:
		_status_label.text = "AI Bridge — %s" % text


## Copy the MCP server configuration JSON to the clipboard.
func _on_copy_config() -> void:
	var config: String = _generate_mcp_config()
	DisplayServer.clipboard_set(config)
	set_status("MCP config copied to clipboard!")
	log_action("SYSTEM", "/clipboard", "MCP config copied")


## Generate the MCP server JSON config for the user's AI client.
func _generate_mcp_config() -> String:
	var server_path: String = _mcp_server_path

	# Use python3 on macOS/Linux since "python" often points to Python 2 or
	# doesn't exist. On Windows, "python" is the standard command.
	var python_cmd: String = "python"
	if OS.get_name() != "Windows":
		python_cmd = "python3"

	var config: String = """{
  "mcpServers": {
    "godot": {
      "command": "%s",
      "args": ["%s"]
    }
  }
}""" % [python_cmd, server_path]

	return config


## Compute the absolute path to the MCP server.py file.
func _compute_mcp_server_path() -> void:
	# The MCP server is bundled inside the addon at:
	# res://addons/godot_ai_bridge/mcp_server/server.py
	var server_res_path: String = "res://addons/godot_ai_bridge/mcp_server/server.py"
	_mcp_server_path = ProjectSettings.globalize_path(server_res_path)


## Get the color for an HTTP method.
func _color_for_method(method: String) -> String:
	match method:
		"GET":
			return "#4ec9b0"  # teal
		"POST":
			return "#dcdcaa"  # yellow
		"SYSTEM":
			return "#569cd6"  # blue
		_:
			return "#d4d4d4"  # gray


func _exit_tree() -> void:
	if _copy_config_button != null and _copy_config_button.pressed.is_connected(_on_copy_config):
		_copy_config_button.pressed.disconnect(_on_copy_config)
	if _clear_button != null and _clear_button.pressed.is_connected(_on_clear):
		_clear_button.pressed.disconnect(_on_clear)


func _on_clear() -> void:
	_log_entries.clear()
	_request_count = 0
	if _log_display:
		_log_display.clear()
	set_status("Log cleared")
