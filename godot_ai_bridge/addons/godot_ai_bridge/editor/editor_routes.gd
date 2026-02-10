## Route handlers for the editor HTTP endpoints.
## Handles scene/node operations, script management, project tools, and run control.
class_name EditorRoutes
extends RefCounted

# Preload tool scripts — bare class_name references don't resolve reliably
# in editor plugins at runtime.
const _SceneTools := preload("res://addons/godot_ai_bridge/editor/scene_tools.gd")
const _ScriptTools := preload("res://addons/godot_ai_bridge/editor/script_tools.gd")
const _ProjectTools := preload("res://addons/godot_ai_bridge/editor/project_tools.gd")
const _EditorScreenshot := preload("res://addons/godot_ai_bridge/editor/editor_screenshot.gd")


# --- Scene & Node Operations ---

## GET /scene/tree
func handle_get_scene_tree(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	return _SceneTools.get_scene_tree()


## POST /scene/create
func handle_create_scene(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var root_type: String = str(body.get("root_type", "Node"))
	var save_path: String = str(body.get("save_path", ""))

	if save_path == "":
		return {"error": "Must provide 'save_path'"}

	return _SceneTools.create_scene(root_type, save_path)


## POST /node/add
func handle_add_node(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var parent_path: String = str(body.get("parent_path", "."))
	var node_type: String = str(body.get("type", ""))
	var node_name: String = str(body.get("name", ""))
	var properties: Dictionary = body.get("properties", {})

	if node_type == "":
		return {"error": "Must provide 'type'"}
	if node_name == "":
		return {"error": "Must provide 'name'"}

	return _SceneTools.add_node(parent_path, node_type, node_name, properties)


## POST /node/remove
func handle_remove_node(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))

	if path == "":
		return {"error": "Must provide 'path'"}

	return _SceneTools.remove_node(path)


## POST /node/set_property
func handle_set_property(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))
	var property: String = str(body.get("property", ""))
	var value: Variant = body.get("value")

	if path == "" or property == "":
		return {"error": "Must provide 'path' and 'property'"}

	return _SceneTools.set_property(path, property, value)


## GET /node/get_property
func handle_get_property(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var path: String = request.query_params.get("path", "")
	var property: String = request.query_params.get("property", "")

	if path == "" or property == "":
		return {"error": "Must provide 'path' and 'property' query params"}

	return _SceneTools.get_property(path, property)


## POST /scene/save
func handle_save_scene(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	return _SceneTools.save_scene()


## POST /scene/open
func handle_open_scene(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))

	if path == "":
		return {"error": "Must provide 'path'"}

	return _SceneTools.open_scene(path)


## POST /node/duplicate
func handle_duplicate_node(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))
	var new_name: String = str(body.get("new_name", ""))

	if path == "":
		return {"error": "Must provide 'path'"}

	return _SceneTools.duplicate_node(path, new_name)


## POST /node/reparent
func handle_reparent_node(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))
	var new_parent: String = str(body.get("new_parent", ""))
	var keep_transform: bool = body.get("keep_global_transform", true)

	if path == "":
		return {"error": "Must provide 'path'"}
	if new_parent == "":
		return {"error": "Must provide 'new_parent'"}

	return _SceneTools.reparent_node(path, new_parent, keep_transform)


## GET /node/properties
func handle_list_node_properties(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var path: String = request.query_params.get("path", "")
	if path == "":
		return {"error": "Must provide 'path' query param"}
	return _SceneTools.list_node_properties(path)


## POST /node/rename
func handle_rename_node(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))
	var new_name: String = str(body.get("new_name", ""))

	if path == "":
		return {"error": "Must provide 'path'"}
	if new_name == "":
		return {"error": "Must provide 'new_name'"}

	return _SceneTools.rename_node(path, new_name)


## POST /node/instance_scene
func handle_instance_scene(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var scene_path: String = str(body.get("scene_path", ""))
	var parent_path: String = str(body.get("parent_path", "."))
	var node_name: String = str(body.get("name", ""))

	if scene_path == "":
		return {"error": "Must provide 'scene_path'"}

	return _SceneTools.instance_scene(scene_path, parent_path, node_name)


## GET /node/find
func handle_find_nodes(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var name_pattern: String = request.query_params.get("name", "")
	var type_name: String = request.query_params.get("type", "")
	var group: String = request.query_params.get("group", "")
	var in_path: String = request.query_params.get("in", "")

	if name_pattern == "" and type_name == "" and group == "":
		return {"error": "Must provide at least one of: 'name', 'type', 'group'"}

	return _SceneTools.find_nodes(name_pattern, type_name, group, in_path)


# --- Script Operations ---

## GET /script/read
func handle_read_script(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var path: String = request.query_params.get("path", "")
	if path == "":
		return {"error": "Must provide 'path' query param"}
	return _ScriptTools.read_script(path)


## POST /script/write
func handle_write_script(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))
	var content: String = str(body.get("content", ""))

	if path == "":
		return {"error": "Must provide 'path'"}
	if content == "":
		return {"error": "Must provide 'content'"}

	return _ScriptTools.write_script(path, content)


## POST /script/create
func handle_create_script(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))
	var extends_class: String = str(body.get("extends", "Node"))
	var template: String = str(body.get("template", "basic"))

	if path == "":
		return {"error": "Must provide 'path'"}

	return _ScriptTools.create_script(path, extends_class, template)


## GET /script/errors
func handle_get_errors(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	return _ScriptTools.get_errors()


## GET /debugger/output
func handle_debugger_output(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	return _ScriptTools.get_debugger_output()


# --- Project Operations ---

## GET /project/structure
func handle_project_structure(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	return _ProjectTools.get_structure()


## GET /project/search
func handle_project_search(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var pattern: String = request.query_params.get("pattern", "")
	var query: String = request.query_params.get("query", "")

	if pattern == "" and query == "":
		return {"error": "Must provide 'pattern' or 'query' param"}

	return _ProjectTools.search_files(pattern, query)


## GET /project/input_map
func handle_input_map(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	return _ProjectTools.get_input_map()


## GET /project/settings
func handle_project_settings(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	return _ProjectTools.get_project_settings()


## GET /project/autoloads
func handle_autoloads(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	return _ProjectTools.get_autoloads()


# --- Run Control ---

## POST /game/run
func handle_run_game(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var scene: String = str(body.get("scene", ""))

	# Defer the play call to the next frame so the HTTP response is sent first.
	# Calling play_*_scene() synchronously inside an HTTP handler blocks the main
	# thread during game compilation/launch, preventing the TCP server from
	# servicing connections and causing editor crashes (especially on Windows).
	if scene != "":
		EditorInterface.play_custom_scene.call_deferred(scene)
	else:
		EditorInterface.play_main_scene.call_deferred()

	return {"ok": true, "running": true}


## POST /game/stop
func handle_stop_game(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	# Defer the stop call so the HTTP response is sent before the editor
	# tears down the running game (same rationale as handle_run_game).
	EditorInterface.call_deferred("stop_playing_scene")
	return {"ok": true, "running": false}


## GET /game/is_running
func handle_is_running(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	return {"running": EditorInterface.is_playing_scene()}


# --- Editor Screenshot ---

## GET /screenshot — mode=viewport (just 2D/3D canvas) or mode=full (entire editor window)
func handle_screenshot(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var width: int = int(request.query_params.get("width", str(BridgeConfig.DEFAULT_SCREENSHOT_WIDTH)))
	var height: int = int(request.query_params.get("height", str(BridgeConfig.DEFAULT_SCREENSHOT_HEIGHT)))
	var quality: float = float(request.query_params.get("quality", str(BridgeConfig.DEFAULT_SCREENSHOT_QUALITY)))
	var mode: String = request.query_params.get("mode", "viewport")
	return _EditorScreenshot.capture(width, height, mode, quality)
