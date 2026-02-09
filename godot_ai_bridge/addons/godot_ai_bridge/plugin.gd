## Main EditorPlugin entry point for the Godot AI Bridge.
## Starts the editor HTTP bridge and registers the runtime autoload.
@tool
extends EditorPlugin

var _editor_bridge: EditorBridge = null


func _enter_tree() -> void:
	# Register the runtime bridge as an autoload so it activates when the game runs
	add_autoload_singleton("RuntimeBridge", "res://addons/godot_ai_bridge/runtime/runtime_bridge.gd")

	# Start the editor HTTP bridge
	_editor_bridge = EditorBridge.new()
	_editor_bridge.name = "EditorBridge"
	add_child(_editor_bridge)

	print("[Godot AI Bridge] Plugin enabled — editor bridge starting on port %d" % BridgeConfig.EDITOR_PORT)


func _exit_tree() -> void:
	# Remove runtime autoload
	remove_autoload_singleton("RuntimeBridge")

	# Stop and remove editor bridge
	if _editor_bridge != null:
		_editor_bridge.stop()
		remove_child(_editor_bridge)
		_editor_bridge.queue_free()
		_editor_bridge = null

	print("[Godot AI Bridge] Plugin disabled")
