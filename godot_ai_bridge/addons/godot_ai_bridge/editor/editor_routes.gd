## Route handlers for the editor HTTP endpoints.
## Handles scene/node operations, script management, project tools, and run control.
class_name EditorRoutes
extends RefCounted


# --- Scene & Node Operations ---

## GET /scene/tree
func handle_get_scene_tree(_request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	return SceneTools.get_scene_tree()


## POST /scene/create
func handle_create_scene(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var root_type: String = str(body.get("root_type", "Node"))
	var save_path: String = str(body.get("save_path", ""))

	if save_path == "":
		return {"error": "Must provide 'save_path'"}

	return SceneTools.create_scene(root_type, save_path)


## POST /node/add
func handle_add_node(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var parent_path: String = str(body.get("parent_path", "."))
	var node_type: String = str(body.get("type", ""))
	var node_name: String = str(body.get("name", ""))
	var properties: Dictionary = body.get("properties", {})

	if node_type == "":
		return {"error": "Must provide 'type'"}
	if node_name == "":
		return {"error": "Must provide 'name'"}

	return SceneTools.add_node(parent_path, node_type, node_name, properties)


## POST /node/remove
func handle_remove_node(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))

	if path == "":
		return {"error": "Must provide 'path'"}

	return SceneTools.remove_node(path)


## POST /node/set_property
func handle_set_property(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))
	var property: String = str(body.get("property", ""))
	var value: Variant = body.get("value")

	if path == "" or property == "":
		return {"error": "Must provide 'path' and 'property'"}

	return SceneTools.set_property(path, property, value)


## GET /node/get_property
func handle_get_property(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var path: String = request.query_params.get("path", "")
	var property: String = request.query_params.get("property", "")

	if path == "" or property == "":
		return {"error": "Must provide 'path' and 'property' query params"}

	return SceneTools.get_property(path, property)


## POST /scene/save
func handle_save_scene(_request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	return SceneTools.save_scene()


## POST /scene/open
func handle_open_scene(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))

	if path == "":
		return {"error": "Must provide 'path'"}

	return SceneTools.open_scene(path)


## POST /node/duplicate
func handle_duplicate_node(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))
	var new_name: String = str(body.get("new_name", ""))

	if path == "":
		return {"error": "Must provide 'path'"}

	return SceneTools.duplicate_node(path, new_name)


## POST /node/reparent
func handle_reparent_node(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))
	var new_parent: String = str(body.get("new_parent", ""))
	var keep_transform: bool = body.get("keep_global_transform", true)

	if path == "":
		return {"error": "Must provide 'path'"}
	if new_parent == "":
		return {"error": "Must provide 'new_parent'"}

	return SceneTools.reparent_node(path, new_parent, keep_transform)


## GET /node/properties
func handle_list_node_properties(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var path: String = request.query_params.get("path", "")
	if path == "":
		return {"error": "Must provide 'path' query param"}
	return SceneTools.list_node_properties(path)


# --- Script Operations ---

## GET /script/read
func handle_read_script(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var path: String = request.query_params.get("path", "")
	if path == "":
		return {"error": "Must provide 'path' query param"}
	return ScriptTools.read_script(path)


## POST /script/write
func handle_write_script(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))
	var content: String = str(body.get("content", ""))

	if path == "":
		return {"error": "Must provide 'path'"}
	if content == "":
		return {"error": "Must provide 'content'"}

	return ScriptTools.write_script(path, content)


## POST /script/create
func handle_create_script(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))
	var extends_class: String = str(body.get("extends", "Node"))
	var template: String = str(body.get("template", "basic"))

	if path == "":
		return {"error": "Must provide 'path'"}

	return ScriptTools.create_script(path, extends_class, template)


## GET /script/errors
func handle_get_errors(_request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	return ScriptTools.get_errors()


## GET /debugger/output
func handle_debugger_output(_request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	return ScriptTools.get_debugger_output()


# --- Project Operations ---

## GET /project/structure
func handle_project_structure(_request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	return ProjectTools.get_structure()


## GET /project/search
func handle_project_search(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var pattern: String = request.query_params.get("pattern", "")
	var query: String = request.query_params.get("query", "")

	if pattern == "" and query == "":
		return {"error": "Must provide 'pattern' or 'query' param"}

	return ProjectTools.search_files(pattern, query)


## GET /project/input_map
func handle_input_map(_request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	return ProjectTools.get_input_map()


## GET /project/settings
func handle_project_settings(_request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	return ProjectTools.get_project_settings()


## GET /project/autoloads
func handle_autoloads(_request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	return ProjectTools.get_autoloads()


# --- Run Control ---

## POST /game/run
func handle_run_game(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var scene: String = str(body.get("scene", ""))

	if scene != "":
		EditorInterface.play_custom_scene(scene)
	else:
		EditorInterface.play_main_scene()

	return {"ok": true, "running": true}


## POST /game/stop
func handle_stop_game(_request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	EditorInterface.stop_playing_scene()
	return {"ok": true, "running": false}


## GET /game/is_running
func handle_is_running(_request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	return {"running": EditorInterface.is_playing_scene()}


# --- Editor Screenshot ---

## GET /screenshot
func handle_screenshot(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var width: int = int(request.query_params.get("width", str(BridgeConfig.DEFAULT_SCREENSHOT_WIDTH)))
	var height: int = int(request.query_params.get("height", str(BridgeConfig.DEFAULT_SCREENSHOT_HEIGHT)))
	return EditorScreenshot.capture(width, height)
