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

# Reference to the EditorBridge so route handlers can access the activity panel.
var _bridge_ref: Node = null

func set_bridge(bridge: Node) -> void:
	_bridge_ref = bridge


# --- Scene & Node Operations ---

## GET /scene/tree
func handle_get_scene_tree(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var result: Dictionary = _SceneTools.get_scene_tree()
	if result.has("root"):
		var root: Dictionary = result["root"]
		result["_description"] = "🌳 Scene tree of '%s' (%s)" % [root.get("name", "?"), root.get("type", "?")]
	return result


## POST /scene/create
func handle_create_scene(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var root_type: String = str(body.get("root_type", "Node"))
	var save_path: String = str(body.get("save_path", ""))

	if save_path == "":
		return {"error": "Must provide 'save_path'"}

	var result: Dictionary = _SceneTools.create_scene(root_type, save_path)
	if result.has("ok"):
		result["_description"] = "🆕 Created scene '%s' (root: %s)" % [save_path, root_type]
	return result


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

	var result: Dictionary = _SceneTools.add_node(parent_path, node_type, node_name, properties)
	if result.has("ok"):
		result["_description"] = "➕ Added %s '%s' under '%s'" % [node_type, node_name, parent_path]
	return result


## POST /node/remove
func handle_remove_node(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))

	if path == "":
		return {"error": "Must provide 'path'"}

	var result: Dictionary = _SceneTools.remove_node(path)
	if result.has("ok"):
		result["_description"] = "🗑️ Removed node '%s'" % path
	return result


## POST /node/set_property
func handle_set_property(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))
	var property: String = str(body.get("property", ""))
	var value: Variant = body.get("value")

	if path == "" or property == "":
		return {"error": "Must provide 'path' and 'property'"}

	var result: Dictionary = _SceneTools.set_property(path, property, value)
	if result.has("ok"):
		result["_description"] = "✏️ Set '%s'.%s" % [path, property]
	return result


## GET /node/get_property
func handle_get_property(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var path: String = request.query_params.get("path", "")
	var property: String = request.query_params.get("property", "")

	if path == "" or property == "":
		return {"error": "Must provide 'path' and 'property' query params"}

	var result: Dictionary = _SceneTools.get_property(path, property)
	if not result.has("error"):
		result["_description"] = "🔍 '%s'.%s = %s" % [path, property, str(result.get("value", "?"))]
	return result


## POST /scene/save
func handle_save_scene(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var result: Dictionary = _SceneTools.save_scene()
	if result.has("ok"):
		result["_description"] = "💾 Scene saved"
	return result


## POST /scene/open
func handle_open_scene(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))

	if path == "":
		return {"error": "Must provide 'path'"}

	var result: Dictionary = _SceneTools.open_scene(path)
	if result.has("ok"):
		result["_description"] = "📂 Opened scene '%s'" % path
	return result


## POST /node/duplicate
func handle_duplicate_node(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))
	var new_name: String = str(body.get("new_name", ""))

	if path == "":
		return {"error": "Must provide 'path'"}

	var result: Dictionary = _SceneTools.duplicate_node(path, new_name)
	if result.has("ok"):
		result["_description"] = "📋 Duplicated '%s' → '%s'" % [path, result.get("name", "?")]
	return result


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

	var result: Dictionary = _SceneTools.reparent_node(path, new_parent, keep_transform)
	if result.has("ok"):
		result["_description"] = "📦 Reparented '%s' → under '%s'" % [path, new_parent]
	return result


## POST /node/reorder
func handle_reorder_node(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))
	var position: Variant = body.get("position", "")

	if path == "":
		return {"error": "Must provide 'path'"}
	if position is String and position == "":
		return {"error": "Must provide 'position' (integer index, or 'up'/'down'/'first'/'last')"}

	var result: Dictionary = _SceneTools.reorder_node(path, position)
	if result.has("ok"):
		result["_description"] = "↕️ Reordered '%s' → index %s" % [path, str(result.get("new_index", "?"))]
	return result


## GET /node/properties
func handle_list_node_properties(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var path: String = request.query_params.get("path", "")
	if path == "":
		return {"error": "Must provide 'path' query param"}
	var result: Dictionary = _SceneTools.list_node_properties(path)
	if not result.has("error"):
		result["_description"] = "📜 %s properties on '%s' (%s)" % [str(result.get("count", "?")), result.get("node", path), result.get("type", "?")]
	return result


## POST /node/rename
func handle_rename_node(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))
	var new_name: String = str(body.get("new_name", ""))

	if path == "":
		return {"error": "Must provide 'path'"}
	if new_name == "":
		return {"error": "Must provide 'new_name'"}

	var result: Dictionary = _SceneTools.rename_node(path, new_name)
	if result.has("ok"):
		result["_description"] = "✏️ Renamed '%s' → '%s'" % [result.get("old_name", path), new_name]
	return result


## POST /node/instance_scene
func handle_instance_scene(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var scene_path: String = str(body.get("scene_path", ""))
	var parent_path: String = str(body.get("parent_path", "."))
	var node_name: String = str(body.get("name", ""))

	if scene_path == "":
		return {"error": "Must provide 'scene_path'"}

	var result: Dictionary = _SceneTools.instance_scene(scene_path, parent_path, node_name)
	if result.has("ok"):
		result["_description"] = "🔗 Instanced '%s' as '%s' under '%s'" % [scene_path, result.get("name", "?"), parent_path]
	return result


## GET /node/find
func handle_find_nodes(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var name_pattern: String = request.query_params.get("name", "")
	var type_name: String = request.query_params.get("type", "")
	var group: String = request.query_params.get("group", "")
	var in_path: String = request.query_params.get("in", "")

	if name_pattern == "" and type_name == "" and group == "":
		return {"error": "Must provide at least one of: 'name', 'type', 'group'"}

	var result: Dictionary = _SceneTools.find_nodes(name_pattern, type_name, group, in_path)
	if not result.has("error"):
		var criteria: PackedStringArray = []
		if name_pattern != "":
			criteria.append("name='%s'" % name_pattern)
		if type_name != "":
			criteria.append("type='%s'" % type_name)
		if group != "":
			criteria.append("group='%s'" % group)
		result["_description"] = "🔍 Found %s node(s) matching %s" % [str(result.get("count", 0)), " + ".join(criteria)]
	return result


# --- Signal Operations ---

## GET /node/signals
func handle_list_signals(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var path: String = request.query_params.get("path", "")
	if path == "":
		return {"error": "Must provide 'path' query param"}
	var result: Dictionary = _SceneTools.list_signals(path)
	if not result.has("error"):
		var connected: int = 0
		for sig: Dictionary in result.get("signals", []):
			connected += sig.get("connections", []).size()
		result["_description"] = "📡 %d signal(s) on '%s' (%s), %d connection(s)" % [result.get("count", 0), result.get("node", path), result.get("type", "?"), connected]
	return result


## POST /node/connect_signal
func handle_connect_signal(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var source: String = str(body.get("source", ""))
	var signal_name: String = str(body.get("signal", ""))
	var target: String = str(body.get("target", ""))
	var method: String = str(body.get("method", ""))

	if source == "":
		return {"error": "Must provide 'source'"}
	if signal_name == "":
		return {"error": "Must provide 'signal'"}
	if target == "":
		return {"error": "Must provide 'target'"}
	if method == "":
		return {"error": "Must provide 'method'"}

	var result: Dictionary = _SceneTools.connect_signal(source, signal_name, target, method)
	if result.has("ok"):
		result["_description"] = "🔗 Connected '%s'.%s → '%s'.%s()" % [source, signal_name, target, method]
	return result


## POST /node/disconnect_signal
func handle_disconnect_signal(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var source: String = str(body.get("source", ""))
	var signal_name: String = str(body.get("signal", ""))
	var target: String = str(body.get("target", ""))
	var method: String = str(body.get("method", ""))

	if source == "":
		return {"error": "Must provide 'source'"}
	if signal_name == "":
		return {"error": "Must provide 'signal'"}
	if target == "":
		return {"error": "Must provide 'target'"}
	if method == "":
		return {"error": "Must provide 'method'"}

	var result: Dictionary = _SceneTools.disconnect_signal(source, signal_name, target, method)
	if result.has("ok"):
		result["_description"] = "🔌 Disconnected '%s'.%s → '%s'.%s()" % [source, signal_name, target, method]
	return result


# --- Group Operations ---

## POST /node/add_to_group
func handle_add_to_group(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))
	var group: String = str(body.get("group", ""))

	if path == "":
		return {"error": "Must provide 'path'"}
	if group == "":
		return {"error": "Must provide 'group'"}

	var result: Dictionary = _SceneTools.add_to_group(path, group)
	if result.has("ok"):
		result["_description"] = "🏷️ Added '%s' to group '%s'" % [path, group]
	return result


## POST /node/remove_from_group
func handle_remove_from_group(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))
	var group: String = str(body.get("group", ""))

	if path == "":
		return {"error": "Must provide 'path'"}
	if group == "":
		return {"error": "Must provide 'group'"}

	var result: Dictionary = _SceneTools.remove_from_group(path, group)
	if result.has("ok"):
		result["_description"] = "🏷️ Removed '%s' from group '%s'" % [path, group]
	return result


# --- Script Operations ---

## GET /script/read
func handle_read_script(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var path: String = request.query_params.get("path", "")
	if path == "":
		return {"error": "Must provide 'path' query param"}
	var result: Dictionary = _ScriptTools.read_script(path)
	if not result.has("error"):
		var lines: int = result.get("content", "").count("\n") + 1
		result["_description"] = "📄 Read '%s' (%d lines)" % [path, lines]
	return result


## POST /script/write
func handle_write_script(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))
	var content: String = str(body.get("content", ""))

	if path == "":
		return {"error": "Must provide 'path'"}
	if content == "":
		return {"error": "Must provide 'content'"}

	var result: Dictionary = _ScriptTools.write_script(path, content)
	if result.has("ok"):
		var lines: int = content.count("\n") + 1
		result["_description"] = "✍️ Wrote '%s' (%d lines)" % [path, lines]
	return result


## POST /script/create
func handle_create_script(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var path: String = str(body.get("path", ""))
	var extends_class: String = str(body.get("extends", "Node"))
	var template: String = str(body.get("template", "basic"))

	if path == "":
		return {"error": "Must provide 'path'"}

	var result: Dictionary = _ScriptTools.create_script(path, extends_class, template)
	if result.has("ok"):
		result["_description"] = "🆕 Created script '%s' (extends %s)" % [path, extends_class]
	return result


## GET /script/errors
func handle_get_errors(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var result: Dictionary = _ScriptTools.get_errors()
	var errors: Array = result.get("errors", [])
	if errors.size() > 0:
		result["_description"] = "❌ %d script error(s)" % errors.size()
	else:
		result["_description"] = "✅ No script errors"
	return result


## GET /debugger/output
func handle_debugger_output(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var result: Dictionary = _ScriptTools.get_debugger_output()
	result["_description"] = "📟 Debugger output"
	return result


# --- Project Operations ---

## GET /project/structure
func handle_project_structure(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var result: Dictionary = _ProjectTools.get_structure()
	if not result.has("error"):
		result["_description"] = "📁 Project structure"
	return result


## GET /project/search
func handle_project_search(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var pattern: String = request.query_params.get("pattern", "")
	var query: String = request.query_params.get("query", "")

	if pattern == "" and query == "":
		return {"error": "Must provide 'pattern' or 'query' param"}

	var result: Dictionary = _ProjectTools.search_files(pattern, query)
	if not result.has("error"):
		var term: String = pattern if pattern != "" else query
		result["_description"] = "🔎 Search '%s' — %s match(es)" % [term, str(result.get("count", 0))]
	return result


## GET /project/input_map
func handle_input_map(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var result: Dictionary = _ProjectTools.get_input_map()
	if not result.has("error"):
		result["_description"] = "🎮 Input map — %d action(s)" % result.get("actions", {}).size()
	return result


## GET /project/settings
func handle_project_settings(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var result: Dictionary = _ProjectTools.get_project_settings()
	result["_description"] = "⚙️ Project settings for '%s'" % result.get("name", "?")
	return result


## GET /project/autoloads
func handle_autoloads(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var result: Dictionary = _ProjectTools.get_autoloads()
	if not result.has("error"):
		result["_description"] = "🔌 %d autoload(s)" % result.get("autoloads", {}).size()
	return result


# --- Input Map Operations ---

## POST /project/input_map/add_action
func handle_add_input_action(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var action: String = str(body.get("action", ""))
	var deadzone: float = float(body.get("deadzone", 0.5))

	if action == "":
		return {"error": "Must provide 'action'"}

	var result: Dictionary = _ProjectTools.add_input_action(action, deadzone)
	if result.has("ok"):
		result["_description"] = "🎮 Added input action '%s' (deadzone: %s)" % [action, str(deadzone)]
	return result


## POST /project/input_map/remove_action
func handle_remove_input_action(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var action: String = str(body.get("action", ""))

	if action == "":
		return {"error": "Must provide 'action'"}

	var result: Dictionary = _ProjectTools.remove_input_action(action)
	if result.has("ok"):
		result["_description"] = "🎮 Removed input action '%s'" % action
	return result


## POST /project/input_map/add_binding
func handle_add_input_binding(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var action: String = str(body.get("action", ""))
	var event_type: String = str(body.get("event_type", ""))
	var value: String = str(body.get("value", ""))

	if action == "":
		return {"error": "Must provide 'action'"}
	if event_type == "":
		return {"error": "Must provide 'event_type'"}
	if value == "":
		return {"error": "Must provide 'value'"}

	var result: Dictionary = _ProjectTools.add_input_binding(action, event_type, value)
	if result.has("ok"):
		result["_description"] = "🎮 Added %s binding '%s' to action '%s'" % [event_type, value, action]
	return result


## POST /project/input_map/remove_binding
func handle_remove_input_binding(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var action: String = str(body.get("action", ""))
	var index: int = int(body.get("index", -1))

	if action == "":
		return {"error": "Must provide 'action'"}
	if index < 0:
		return {"error": "Must provide 'index' (0-based binding index)"}

	var result: Dictionary = _ProjectTools.remove_input_binding(action, index)
	if result.has("ok"):
		result["_description"] = "🎮 Removed binding #%d from action '%s'" % [index, action]
	return result


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

	var desc: String = "▶️ Game started"
	if scene != "":
		desc += " — '%s'" % scene
	return {"ok": true, "running": true, "_description": desc}


## POST /game/stop
func handle_stop_game(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	# Defer the stop call so the HTTP response is sent before the editor
	# tears down the running game (same rationale as handle_run_game).
	EditorInterface.call_deferred("stop_playing_scene")
	return {"ok": true, "running": false, "_description": "⏹️ Game stopped"}


## GET /game/is_running
func handle_is_running(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var running: bool = EditorInterface.is_playing_scene()
	var desc: String = "🟢 Game is running" if running else "⚫ Game is not running"
	return {"running": running, "_description": desc}


# --- Agent Vision ---

## POST /agent/vision — Receive a game screenshot to display in the activity panel.
func handle_agent_vision(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var image: String = str(body.get("image", ""))
	var summary: Dictionary = body.get("summary", {})

	if image == "":
		return {"error": "Must provide 'image' (base64-encoded screenshot)"}

	# Forward to the activity panel
	var bridge: Node = get_bridge()
	if bridge and bridge.activity_panel != null and bridge.activity_panel.has_method("update_vision"):
		bridge.activity_panel.update_vision(image, summary)

	return {"ok": true, "_description": "👁️ Agent vision updated"}


## GET /agent/director — Retrieve and clear pending developer directives.
func handle_get_director(_request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var bridge: Node = get_bridge()
	if bridge == null or bridge.activity_panel == null:
		return {"directives": []}

	if not bridge.activity_panel.has_method("drain_directives"):
		return {"directives": []}

	var directives: Array = bridge.activity_panel.drain_directives()
	if directives.is_empty():
		return {"directives": []}

	return {
		"directives": directives,
		"_description": "Director: %d directive(s) from developer" % directives.size(),
	}


## Get a reference to the parent EditorBridge node.
func get_bridge() -> Node:
	return _bridge_ref


# --- Editor Screenshot ---

## GET /screenshot — mode=viewport (just 2D/3D canvas) or mode=full (entire editor window)
func handle_screenshot(request: BridgeHTTPServer.BridgeRequest) -> Dictionary:
	var width: int = int(request.query_params.get("width", str(BridgeConfig.DEFAULT_SCREENSHOT_WIDTH)))
	var height: int = int(request.query_params.get("height", str(BridgeConfig.DEFAULT_SCREENSHOT_HEIGHT)))
	var quality: float = float(request.query_params.get("quality", str(BridgeConfig.DEFAULT_SCREENSHOT_QUALITY)))
	var mode: String = request.query_params.get("mode", "viewport")
	var result: Dictionary = _EditorScreenshot.capture(width, height, mode, quality)
	if not result.has("error"):
		var mode_label: String = "viewport" if mode == "viewport" else "full editor"
		var size: Array = result.get("size", [width, height])
		result["_description"] = "📸 Editor screenshot — %s (%sx%s)" % [mode_label, str(size[0]), str(size[1])]
	return result
