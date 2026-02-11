## Editor HTTP bridge server — runs on port 9899 inside the Godot editor.
## Extends the shared HTTP server and registers all editor route handlers.
class_name EditorBridge
extends BridgeHTTPServer

var _routes_handler: EditorRoutes


func _ready() -> void:
	_routes_handler = EditorRoutes.new()
	_routes_handler.set_bridge(self)

	# Scene & Node operations
	register_route("GET", "/scene/tree", _routes_handler.handle_get_scene_tree)
	register_route("POST", "/scene/create", _routes_handler.handle_create_scene)
	register_route("POST", "/node/add", _routes_handler.handle_add_node)
	register_route("POST", "/node/remove", _routes_handler.handle_remove_node)
	register_route("POST", "/node/set_property", _routes_handler.handle_set_property)
	register_route("GET", "/node/get_property", _routes_handler.handle_get_property)
	register_route("POST", "/scene/save", _routes_handler.handle_save_scene)
	register_route("POST", "/scene/open", _routes_handler.handle_open_scene)
	register_route("POST", "/node/duplicate", _routes_handler.handle_duplicate_node)
	register_route("POST", "/node/reparent", _routes_handler.handle_reparent_node)
	register_route("POST", "/node/reorder", _routes_handler.handle_reorder_node)
	register_route("GET", "/node/properties", _routes_handler.handle_list_node_properties)
	register_route("POST", "/node/rename", _routes_handler.handle_rename_node)
	register_route("POST", "/node/instance_scene", _routes_handler.handle_instance_scene)
	register_route("GET", "/node/find", _routes_handler.handle_find_nodes)

	# Signal operations
	register_route("GET", "/node/signals", _routes_handler.handle_list_signals)
	register_route("POST", "/node/connect_signal", _routes_handler.handle_connect_signal)
	register_route("POST", "/node/disconnect_signal", _routes_handler.handle_disconnect_signal)

	# Group operations
	register_route("POST", "/node/add_to_group", _routes_handler.handle_add_to_group)
	register_route("POST", "/node/remove_from_group", _routes_handler.handle_remove_from_group)

	# Script operations
	register_route("GET", "/script/read", _routes_handler.handle_read_script)
	register_route("POST", "/script/write", _routes_handler.handle_write_script)
	register_route("POST", "/script/create", _routes_handler.handle_create_script)
	register_route("GET", "/script/errors", _routes_handler.handle_get_errors)
	register_route("GET", "/debugger/output", _routes_handler.handle_debugger_output)

	# Project operations
	register_route("GET", "/project/structure", _routes_handler.handle_project_structure)
	register_route("GET", "/project/search", _routes_handler.handle_project_search)
	register_route("GET", "/project/input_map", _routes_handler.handle_input_map)
	register_route("GET", "/project/settings", _routes_handler.handle_project_settings)
	register_route("GET", "/project/autoloads", _routes_handler.handle_autoloads)

	# Input map editing
	register_route("POST", "/project/input_map/add_action", _routes_handler.handle_add_input_action)
	register_route("POST", "/project/input_map/remove_action", _routes_handler.handle_remove_input_action)
	register_route("POST", "/project/input_map/add_binding", _routes_handler.handle_add_input_binding)
	register_route("POST", "/project/input_map/remove_binding", _routes_handler.handle_remove_input_binding)

	# Run control
	register_route("POST", "/game/run", _routes_handler.handle_run_game)
	register_route("POST", "/game/stop", _routes_handler.handle_stop_game)
	register_route("GET", "/game/is_running", _routes_handler.handle_is_running)

	# Agent vision (receives game screenshots from MCP server)
	register_route("POST", "/agent/vision", _routes_handler.handle_agent_vision)

	# Editor screenshot
	register_route("GET", "/screenshot", _routes_handler.handle_screenshot)

	var err: Error = start(BridgeConfig.EDITOR_PORT)
	if err == OK:
		print("[Godot AI Bridge] Editor bridge listening on port %d" % BridgeConfig.EDITOR_PORT)
	else:
		push_error("[Godot AI Bridge] Failed to start editor bridge on port %d" % BridgeConfig.EDITOR_PORT)
		if activity_panel != null and activity_panel.has_method("set_status"):
			activity_panel.set_status("ERROR — Port %d unavailable (is another Godot instance running?)" % BridgeConfig.EDITOR_PORT)


func _exit_tree() -> void:
	stop()
