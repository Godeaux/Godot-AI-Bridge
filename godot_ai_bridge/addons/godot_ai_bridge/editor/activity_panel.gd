## Activity panel for the Godot AI Bridge.
## Shows a live log of AI actions in the editor's bottom panel.
@tool
class_name AIBridgeActivityPanel
extends Control

var _log_display: RichTextLabel
var _status_label: Label
var _clear_button: Button
var _log_entries: Array[String] = []
const MAX_LOG_ENTRIES: int = 200


func _ready() -> void:
	_build_ui()
	custom_minimum_size = Vector2(0, 200)


## Build the panel UI programmatically.
func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(vbox)

	# Header bar
	var header := HBoxContainer.new()
	vbox.add_child(header)

	_status_label = Label.new()
	_status_label.text = "AI Bridge — Idle"
	_status_label.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(_status_label)

	_clear_button = Button.new()
	_clear_button.text = "Clear"
	_clear_button.pressed.connect(_on_clear)
	header.add_child(_clear_button)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Log display
	_log_display = RichTextLabel.new()
	_log_display.bbcode_enabled = true
	_log_display.scroll_following = true
	_log_display.size_flags_vertical = SIZE_EXPAND_FILL
	_log_display.size_flags_horizontal = SIZE_EXPAND_FILL
	_log_display.selection_enabled = true
	_log_display.fit_content = false
	vbox.add_child(_log_display)


## Log an AI action to the panel.
func log_action(method: String, path: String, summary: String = "") -> void:
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

	# Update status
	if _status_label:
		_status_label.text = "AI Bridge — Last: %s %s" % [method, path]


## Set the connection status displayed in the header.
func set_status(text: String) -> void:
	if _status_label:
		_status_label.text = "AI Bridge — %s" % text


## Get the color for an HTTP method.
func _color_for_method(method: String) -> String:
	match method:
		"GET":
			return "#4ec9b0"  # teal
		"POST":
			return "#dcdcaa"  # yellow
		_:
			return "#d4d4d4"  # gray


func _on_clear() -> void:
	_log_entries.clear()
	if _log_display:
		_log_display.clear()
	set_status("Log cleared")
