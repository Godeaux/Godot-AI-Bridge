## Main EditorPlugin entry point for the Godot AI Bridge.
## Starts the editor HTTP bridge and registers the runtime autoload.
## Adds a bottom panel for live AI activity monitoring.
@tool
extends EditorPlugin

var _editor_bridge: EditorBridge = null
var _activity_panel: AIBridgeActivityPanel = null


func _enter_tree() -> void:
	# Register the runtime bridge as an autoload so it activates when the game runs
	add_autoload_singleton("RuntimeBridge", "res://addons/godot_ai_bridge/runtime/runtime_bridge.gd")

	# Create the activity panel (shows in the editor's bottom dock)
	_activity_panel = AIBridgeActivityPanel.new()
	_activity_panel.name = "AIBridgeActivity"
	add_control_to_bottom_panel(_activity_panel, "AI Bridge")
	_activity_panel.set_status("Editor bridge starting...")

	# Start the editor HTTP bridge
	_editor_bridge = EditorBridge.new()
	_editor_bridge.name = "EditorBridge"
	_editor_bridge.activity_panel = _activity_panel
	add_child(_editor_bridge)

	_activity_panel.set_status("Editor bridge on port %d — Waiting for AI" % BridgeConfig.EDITOR_PORT)
	_activity_panel.log_action("SYSTEM", "/startup", "Editor bridge ready on port %d" % BridgeConfig.EDITOR_PORT)

	print("[Godot AI Bridge] Plugin enabled — editor bridge on port %d" % BridgeConfig.EDITOR_PORT)


func _exit_tree() -> void:
	# Remove runtime autoload
	remove_autoload_singleton("RuntimeBridge")

	# Remove activity panel
	if _activity_panel != null:
		remove_control_from_bottom_panel(_activity_panel)
		_activity_panel.queue_free()
		_activity_panel = null

	# Stop and remove editor bridge
	if _editor_bridge != null:
		_editor_bridge.stop()
		remove_child(_editor_bridge)
		_editor_bridge.queue_free()
		_editor_bridge = null

	print("[Godot AI Bridge] Plugin disabled")
