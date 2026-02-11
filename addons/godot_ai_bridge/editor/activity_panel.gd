## Activity panel for the Godot AI Bridge.
## Shows setup instructions for new users, then transitions to a live
## agent vision dashboard with screenshot preview, interactive director
## controls, and activity feed.
@tool
class_name AIBridgeActivityPanel
extends Control

# --- UI references ---
var _main_vbox: VBoxContainer
var _header_bar: HBoxContainer
var _status_label: Label
var _clear_button: Button
var _copy_config_button: Button
var _setup_display: RichTextLabel

# Split layout (visible after first request)
var _split_container: HSplitContainer
var _vision_panel: VBoxContainer
var _screenshot_container: Control
var _screenshot_rect: TextureRect
var _click_overlay: Control
var _node_info_label: RichTextLabel
var _director_bar: HBoxContainer
var _directive_input: LineEdit
var _directive_send: Button
var _log_display: RichTextLabel

# --- State ---
var _log_entries: Array[String] = []
var _has_received_request: bool = false
var _request_count: int = 0
var _mcp_server_path: String = ""

# Director state
var _markers: Array[Dictionary] = []  # [{id, game_pos: Vector2}]
var _next_marker_id: int = 1
var _pending_directives: Array[Dictionary] = []
var _viewport_size: Vector2 = Vector2.ZERO  # Last known game viewport resolution

const MAX_LOG_ENTRIES: int = 200
const VISION_PANEL_WIDTH: int = 340


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

	# Split container: vision (left) + activity feed (right)
	# Hidden initially — shown when AI connects
	_split_container = HSplitContainer.new()
	_split_container.size_flags_vertical = SIZE_EXPAND_FILL
	_split_container.size_flags_horizontal = SIZE_EXPAND_FILL
	_split_container.split_offset = VISION_PANEL_WIDTH
	_split_container.visible = false
	_main_vbox.add_child(_split_container)

	# Left panel: Agent vision + director controls
	_vision_panel = VBoxContainer.new()
	_vision_panel.custom_minimum_size = Vector2(VISION_PANEL_WIDTH, 0)
	_split_container.add_child(_vision_panel)

	# Screenshot container (houses TextureRect + click overlay)
	_screenshot_container = Control.new()
	_screenshot_container.custom_minimum_size = Vector2(VISION_PANEL_WIDTH, 180)
	_screenshot_container.size_flags_horizontal = SIZE_EXPAND_FILL
	_screenshot_container.size_flags_vertical = SIZE_EXPAND_FILL
	_screenshot_container.resized.connect(_on_screenshot_resized)
	_vision_panel.add_child(_screenshot_container)

	# TextureRect for the screenshot
	_screenshot_rect = TextureRect.new()
	_screenshot_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_screenshot_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screenshot_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_screenshot_rect.mouse_filter = MOUSE_FILTER_IGNORE
	_screenshot_container.add_child(_screenshot_rect)

	# Placeholder when no screenshot yet
	var placeholder := Label.new()
	placeholder.text = "Waiting for game snapshot..."
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placeholder.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	placeholder.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_screenshot_rect.add_child(placeholder)

	# Click overlay — sits on top, captures clicks, draws markers
	_click_overlay = Control.new()
	_click_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_click_overlay.mouse_filter = MOUSE_FILTER_STOP
	_click_overlay.gui_input.connect(_on_overlay_input)
	_click_overlay.draw.connect(_draw_markers)
	_screenshot_container.add_child(_click_overlay)

	# Node info below screenshot
	_node_info_label = RichTextLabel.new()
	_node_info_label.bbcode_enabled = true
	_node_info_label.scroll_following = false
	_node_info_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_node_info_label.selection_enabled = true
	_node_info_label.fit_content = true
	_node_info_label.custom_minimum_size = Vector2(0, 20)
	_vision_panel.add_child(_node_info_label)
	_update_node_info({})

	# Director input bar
	_director_bar = HBoxContainer.new()
	_director_bar.size_flags_horizontal = SIZE_EXPAND_FILL
	_vision_panel.add_child(_director_bar)

	_directive_input = LineEdit.new()
	_directive_input.placeholder_text = "Direct the AI..."
	_directive_input.size_flags_horizontal = SIZE_EXPAND_FILL
	_directive_input.text_submitted.connect(_on_directive_submitted)
	_director_bar.add_child(_directive_input)

	_directive_send = Button.new()
	_directive_send.text = "Send"
	_directive_send.tooltip_text = "Send a directive to the AI agent (also: click on the screenshot to place markers)"
	_directive_send.pressed.connect(_on_directive_send_pressed)
	_director_bar.add_child(_directive_send)

	# Right panel: Activity log
	_log_display = RichTextLabel.new()
	_log_display.bbcode_enabled = true
	_log_display.scroll_following = true
	_log_display.size_flags_vertical = SIZE_EXPAND_FILL
	_log_display.size_flags_horizontal = SIZE_EXPAND_FILL
	_log_display.selection_enabled = true
	_log_display.fit_content = false
	_split_container.add_child(_log_display)


# --- Director: Click & Marker System ---

## Handle mouse clicks on the screenshot overlay.
func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var game_pos: Variant = _map_click_to_viewport(event.position)
			if game_pos == null:
				return  # Click in letterbox area
			_markers.append({
				"id": _next_marker_id,
				"game_pos": game_pos as Vector2,
			})
			_next_marker_id += 1
			_click_overlay.queue_redraw()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Right-click clears markers
			if not _markers.is_empty():
				_markers.clear()
				_next_marker_id = 1
				_click_overlay.queue_redraw()


## Map a click position on the TextureRect to game viewport coordinates.
func _map_click_to_viewport(click_pos: Vector2) -> Variant:
	var tex: Texture2D = _screenshot_rect.texture
	if tex == null:
		return null

	var tex_size: Vector2 = tex.get_size()
	var rect_size: Vector2 = _screenshot_container.size

	# STRETCH_KEEP_ASPECT_CENTERED: uniform scale, centered with letterboxing
	var scale_factor: float = minf(rect_size.x / tex_size.x, rect_size.y / tex_size.y)
	var display_w: float = tex_size.x * scale_factor
	var display_h: float = tex_size.y * scale_factor
	var offset_x: float = (rect_size.x - display_w) * 0.5
	var offset_y: float = (rect_size.y - display_h) * 0.5

	var local_x: float = click_pos.x - offset_x
	var local_y: float = click_pos.y - offset_y

	# Reject clicks in letterbox bars
	if local_x < 0.0 or local_x > display_w or local_y < 0.0 or local_y > display_h:
		return null

	# Map to texture pixels
	var tex_x: float = local_x / scale_factor
	var tex_y: float = local_y / scale_factor

	# Scale from screenshot resolution to actual game viewport
	if _viewport_size.x > 0 and _viewport_size.y > 0:
		tex_x = tex_x * (_viewport_size.x / tex_size.x)
		tex_y = tex_y * (_viewport_size.y / tex_size.y)

	return Vector2(tex_x, tex_y)


## Map game viewport coordinates to panel pixel position on the screenshot.
func _map_game_to_panel(game_pos: Vector2) -> Vector2:
	var tex: Texture2D = _screenshot_rect.texture
	if tex == null:
		return Vector2.ZERO

	var tex_size: Vector2 = tex.get_size()
	var rect_size: Vector2 = _screenshot_container.size

	# Game viewport → texture pixels
	var tex_x: float = game_pos.x
	var tex_y: float = game_pos.y
	if _viewport_size.x > 0 and _viewport_size.y > 0:
		tex_x = game_pos.x * (tex_size.x / _viewport_size.x)
		tex_y = game_pos.y * (tex_size.y / _viewport_size.y)

	# Texture pixels → panel display pixels
	var scale_factor: float = minf(rect_size.x / tex_size.x, rect_size.y / tex_size.y)
	var display_w: float = tex_size.x * scale_factor
	var display_h: float = tex_size.y * scale_factor
	var offset_x: float = (rect_size.x - display_w) * 0.5
	var offset_y: float = (rect_size.y - display_h) * 0.5

	return Vector2(offset_x + tex_x * scale_factor, offset_y + tex_y * scale_factor)


## Draw all placed markers on the overlay.
func _draw_markers() -> void:
	if _click_overlay == null:
		return

	var font: Font = ThemeDB.fallback_font
	var font_size: int = 11

	for marker: Dictionary in _markers:
		var panel_pos: Vector2 = _map_game_to_panel(marker["game_pos"])
		var radius: float = 8.0

		# White ring + red fill
		_click_overlay.draw_circle(panel_pos, radius + 2.0, Color(1, 1, 1, 0.8))
		_click_overlay.draw_circle(panel_pos, radius, Color(0.9, 0.2, 0.2, 0.9))

		# Number label centered in the circle
		var label_str: String = str(marker["id"])
		var text_size: Vector2 = font.get_string_size(label_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos: Vector2 = Vector2(
			panel_pos.x - text_size.x * 0.5,
			panel_pos.y + text_size.y * 0.3
		)
		_click_overlay.draw_string(font, text_pos, label_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


## Refresh marker positions when the screenshot container resizes.
func _on_screenshot_resized() -> void:
	if _click_overlay:
		_click_overlay.queue_redraw()


# --- Director: Text Directives ---

func _on_directive_submitted(_text: String) -> void:
	_submit_directive()


func _on_directive_send_pressed() -> void:
	_submit_directive()


## Bundle text + markers into a directive and queue it for the AI.
func _submit_directive() -> void:
	var text: String = _directive_input.text.strip_edges()
	if text == "" and _markers.is_empty():
		return

	var directive: Dictionary = {
		"text": text,
		"markers": [],
		"timestamp": Time.get_unix_time_from_system(),
	}

	for marker: Dictionary in _markers:
		directive["markers"].append({
			"id": marker["id"],
			"x": snapf(marker["game_pos"].x, 0.5),
			"y": snapf(marker["game_pos"].y, 0.5),
		})

	_pending_directives.append(directive)

	# Log it in the activity feed
	var summary: String = text.substr(0, 60)
	if _markers.size() > 0:
		summary += " [%d marker(s)]" % _markers.size()
	log_action("DIRECTOR", "/directive", summary)

	# Reset UI
	_directive_input.text = ""
	_markers.clear()
	_next_marker_id = 1
	_click_overlay.queue_redraw()


## Return all pending director directives and clear the queue.
func drain_directives() -> Array[Dictionary]:
	var result: Array[Dictionary] = _pending_directives.duplicate()
	_pending_directives.clear()
	return result


# --- Setup & Lifecycle ---

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
	if _split_container:
		_split_container.visible = true
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


## Update the agent vision screenshot.
func update_vision(image_base64: String, node_summary: Dictionary = {}) -> void:
	_switch_to_activity_view()

	# Decode the base64 JPEG into an ImageTexture
	var raw: PackedByteArray = Marshalls.base64_to_raw(image_base64)
	var img := Image.new()
	var err: Error = img.load_jpg_from_buffer(raw)
	if err != OK:
		# Try PNG as fallback
		err = img.load_png_from_buffer(raw)
		if err != OK:
			return

	var tex := ImageTexture.create_from_image(img)
	if _screenshot_rect:
		_screenshot_rect.texture = tex
		# Remove the placeholder label once we have a real image
		for child: Node in _screenshot_rect.get_children():
			if child is Label:
				child.queue_free()

	# Store viewport size for coordinate mapping
	var vp_w: float = float(node_summary.get("viewport_w", 0))
	var vp_h: float = float(node_summary.get("viewport_h", 0))
	if vp_w > 0 and vp_h > 0:
		_viewport_size = Vector2(vp_w, vp_h)

	_update_node_info(node_summary)


## Update the node info display below the screenshot.
func _update_node_info(summary: Dictionary) -> void:
	if _node_info_label == null:
		return

	_node_info_label.clear()

	if summary.is_empty():
		_node_info_label.append_text("[color=gray][i]No snapshot data yet[/i][/color]")
		return

	var text: String = ""

	# Scene name and node count
	var scene_name: String = str(summary.get("scene", ""))
	var node_count: int = int(summary.get("node_count", 0))
	var fps: Variant = summary.get("fps", "?")
	var paused: bool = summary.get("paused", false)
	var frame: Variant = summary.get("frame", "?")

	if scene_name != "":
		text += "[b]%s[/b]" % scene_name
		if paused:
			text += " [color=#dcdcaa](PAUSED)[/color]"
		text += "\n"

	var info_parts: PackedStringArray = []
	if node_count > 0:
		info_parts.append("%d nodes" % node_count)
	if str(fps) != "?":
		info_parts.append("%s FPS" % str(fps))
	if str(frame) != "?":
		info_parts.append("frame %s" % str(frame))
	if info_parts.size() > 0:
		text += "[color=gray]%s[/color]" % " · ".join(info_parts)

	_node_info_label.append_text(text)


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
		"DIRECTOR":
			return "#c586c0"  # purple
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
	_markers.clear()
	_next_marker_id = 1
	_pending_directives.clear()
	if _log_display:
		_log_display.clear()
	if _screenshot_rect:
		_screenshot_rect.texture = null
		# Re-add placeholder
		for child: Node in _screenshot_rect.get_children():
			if child is Label:
				child.queue_free()
		var placeholder := Label.new()
		placeholder.text = "Waiting for game snapshot..."
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		placeholder.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		placeholder.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_screenshot_rect.add_child(placeholder)
	if _click_overlay:
		_click_overlay.queue_redraw()
	if _node_info_label:
		_update_node_info({})
	set_status("Log cleared")
