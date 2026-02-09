## Route handlers for the runtime HTTP endpoints.
## Handles all game interaction: snapshots, input, state reading, waiting.
class_name RuntimeRoutes
extends RefCounted

var _snapshot: RuntimeSnapshot
var _injector: InputInjector
var _tree: SceneTree
var _previous_snapshot: Dictionary = {}
var _scene_history: Array[Dictionary] = []
var _scene_history_max: int = 50


func _init(tree: SceneTree) -> void:
	_tree = tree
	_snapshot = RuntimeSnapshot.new()
	_injector = InputInjector.new(tree)

	# Track scene changes for history
	_tree.tree_changed.connect(_on_tree_changed)


## GET /snapshot — Primary observation channel.
func handle_snapshot(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var root: Node = _get_scene_root()
	if root == null:
		return {"error": "No active scene"}

	var custom_root: String = request.query_params.get("root", "")
	var depth: int = int(request.query_params.get("depth", str(BridgeConfig.MAX_SNAPSHOT_DEPTH)))
	var include_screenshot: bool = request.query_params.get("include_screenshot", "true") == "true"

	var target: Node = root
	if custom_root != "":
		var found: Node = root.get_node_or_null(custom_root)
		if found != null:
			target = found
		else:
			return {"error": "Root node not found: %s" % custom_root}

	var result: Dictionary = _snapshot.take_snapshot(target, depth)

	if include_screenshot:
		var viewport: Viewport = _tree.root
		# Wait two frames for rendering to complete
		await _tree.process_frame
		await _tree.process_frame
		var screenshot: Dictionary = RuntimeScreenshot.capture(viewport)
		result["screenshot"] = screenshot.get("image", null)
	else:
		result["screenshot"] = null

	return result


## GET /screenshot — Capture the running game viewport.
func handle_screenshot(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var width: int = int(request.query_params.get("width", str(BridgeConfig.DEFAULT_SCREENSHOT_WIDTH)))
	var height: int = int(request.query_params.get("height", str(BridgeConfig.DEFAULT_SCREENSHOT_HEIGHT)))
	var viewport: Viewport = _tree.root

	await _tree.process_frame
	await _tree.process_frame

	return RuntimeScreenshot.capture(viewport, width, height)


## GET /screenshot/node — Capture a specific node's region.
func handle_screenshot_node(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var ref: String = request.query_params.get("ref", "")
	var path: String = request.query_params.get("path", "")
	var width: int = int(request.query_params.get("width", "0"))
	var height: int = int(request.query_params.get("height", "0"))

	var root: Node = _get_scene_root()
	if root == null:
		return {"error": "No active scene"}

	var target_key: String = ref if ref != "" else path
	if target_key == "":
		return {"error": "Must provide 'ref' or 'path' parameter"}

	var node: Node = _snapshot.resolve_ref(target_key, root)
	if node == null:
		return {"error": "Node not found: %s" % target_key}

	await _tree.process_frame
	await _tree.process_frame

	return RuntimeScreenshot.capture_node(node, _tree.root, width, height)


## POST /click — Click at screen coordinates.
func handle_click(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var x: float = float(body.get("x", 0))
	var y: float = float(body.get("y", 0))
	var button: String = str(body.get("button", "left"))
	var double: bool = body.get("double", false)

	await _injector.click(x, y, button, double)

	if body.get("snapshot", false):
		await _tree.create_timer(0.1).timeout
		return await handle_snapshot(request)

	return {"ok": true}


## POST /click_node — Click a node by ref or path.
func handle_click_node(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var ref: String = str(body.get("ref", ""))
	var path: String = str(body.get("path", ""))

	var root: Node = _get_scene_root()
	if root == null:
		return {"error": "No active scene"}

	var target_key: String = ref if ref != "" else path
	if target_key == "":
		return {"error": "Must provide 'ref' or 'path'"}

	var node: Node = _snapshot.resolve_ref(target_key, root)
	if node == null:
		return {"error": "Node not found: %s" % target_key}

	await _injector.click_node(node)

	if body.get("snapshot", false):
		await _tree.create_timer(0.1).timeout
		return await handle_snapshot(request)

	return {"ok": true}


## POST /key — Inject a key event.
func handle_key(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var key_name: String = str(body.get("key", ""))
	var action: String = str(body.get("action", "tap"))
	var duration: float = float(body.get("duration", 0.0))

	if key_name == "":
		return {"error": "Must provide 'key'"}

	await _injector.key(key_name, action, duration)
	return {"ok": true}


## POST /action — Inject an InputMap action.
func handle_action(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var action_name: String = str(body.get("action", ""))
	var pressed: bool = body.get("pressed", true)
	var strength: float = float(body.get("strength", 1.0))

	if action_name == "":
		return {"error": "Must provide 'action'"}

	_injector.trigger_action(action_name, pressed, strength)
	return {"ok": true}


## GET /actions — List available InputMap actions.
func handle_actions(_request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var actions: Dictionary = {}
	for action_name: StringName in InputMap.get_actions():
		var name_str: String = str(action_name)
		# Skip built-in UI actions if they start with "ui_" — include them, they're useful
		var events: Array = InputMap.action_get_events(action_name)
		var keys: Array[String] = []
		for event: InputEvent in events:
			if event is InputEventKey:
				keys.append(OS.get_keycode_string(event.keycode))
			elif event is InputEventMouseButton:
				keys.append("Mouse%d" % event.button_index)
			elif event is InputEventJoypadButton:
				keys.append("Joy%d" % event.button_index)
			else:
				keys.append(str(event))
		actions[name_str] = {"keys": keys}
	return {"actions": actions}


## POST /mouse_move — Inject mouse motion.
func handle_mouse_move(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var x: float = float(body.get("x", 0))
	var y: float = float(body.get("y", 0))
	var rel_x: float = float(body.get("relative_x", 0))
	var rel_y: float = float(body.get("relative_y", 0))

	_injector.mouse_move(x, y, rel_x, rel_y)
	return {"ok": true}


## POST /sequence — Execute a sequence of input steps.
func handle_sequence(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var steps: Array = body.get("steps", [])
	var snapshot_after: bool = body.get("snapshot_after", false)
	var screenshot_after: bool = body.get("screenshot_after", false)

	if steps.is_empty():
		return {"error": "Must provide 'steps' array"}

	var root: Node = _get_scene_root()
	if root == null:
		return {"error": "No active scene"}

	await _injector.execute_sequence(steps, _snapshot, root)

	if snapshot_after or screenshot_after:
		await _tree.create_timer(0.1).timeout
		if snapshot_after:
			var snap_request := BridgeHTTPServer.HTTPRequest.new()
			snap_request.query_params = {"include_screenshot": "true" if screenshot_after else "false"}
			return await handle_snapshot(snap_request)
		elif screenshot_after:
			var ss_request := BridgeHTTPServer.HTTPRequest.new()
			return await handle_screenshot(ss_request)

	return {"ok": true}


## GET /state — Deep state for a single node.
func handle_state(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var ref: String = request.query_params.get("ref", "")
	var path: String = request.query_params.get("path", "")

	var root: Node = _get_scene_root()
	if root == null:
		return {"error": "No active scene"}

	var target_key: String = ref if ref != "" else path
	if target_key == "":
		return {"error": "Must provide 'ref' or 'path' parameter"}

	var node: Node = _snapshot.resolve_ref(target_key, root)
	if node == null:
		return {"error": "Node not found: %s" % target_key}

	return StateReader.read_state(node)


## POST /call_method — Call a method on a node.
func handle_call_method(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var ref: String = str(body.get("ref", ""))
	var path: String = str(body.get("path", ""))
	var method_name: String = str(body.get("method", ""))
	var args: Array = body.get("args", [])

	if method_name == "":
		return {"error": "Must provide 'method'"}

	var root: Node = _get_scene_root()
	if root == null:
		return {"error": "No active scene"}

	var target_key: String = ref if ref != "" else path
	if target_key == "":
		return {"error": "Must provide 'ref' or 'path'"}

	var node: Node = _snapshot.resolve_ref(target_key, root)
	if node == null:
		return {"error": "Node not found: %s" % target_key}

	if not node.has_method(method_name):
		return {"error": "Node does not have method: %s" % method_name}

	var result: Variant = node.callv(method_name, args)
	return {"result": BridgeSerialization.serialize(result)}


## POST /wait — Wait then return snapshot/screenshot.
func handle_wait(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var seconds: float = float(body.get("seconds", 1.0))
	var do_snapshot: bool = body.get("snapshot", true)
	var do_screenshot: bool = body.get("screenshot", true)

	await _tree.create_timer(seconds).timeout

	var result: Dictionary = {"waited": seconds}

	if do_snapshot:
		var snap_request := BridgeHTTPServer.HTTPRequest.new()
		snap_request.query_params = {"include_screenshot": "true" if do_screenshot else "false"}
		var snap: Dictionary = await handle_snapshot(snap_request)
		result.merge(snap)
	elif do_screenshot:
		var ss_request := BridgeHTTPServer.HTTPRequest.new()
		var ss: Dictionary = await handle_screenshot(ss_request)
		result["screenshot"] = ss.get("image", null)

	return result


## POST /wait_for — Wait for a condition then return.
func handle_wait_for(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var condition: String = str(body.get("condition", ""))
	var ref: String = str(body.get("ref", ""))
	var path: String = str(body.get("path", ""))
	var property: String = str(body.get("property", ""))
	var value: Variant = body.get("value", null)
	var timeout: float = float(body.get("timeout", 10.0))
	var poll_interval: float = float(body.get("poll_interval", 0.1))
	var do_snapshot: bool = body.get("snapshot", true)
	var do_screenshot: bool = body.get("screenshot", true)
	var signal_name: String = str(body.get("signal", ""))

	var root: Node = _get_scene_root()
	if root == null:
		return {"error": "No active scene"}

	var elapsed: float = 0.0
	var condition_met: bool = false

	while elapsed < timeout:
		match condition:
			"node_exists":
				var target_path: String = path if path != "" else ref
				var node: Node = root.get_node_or_null(target_path)
				if node != null:
					condition_met = true
					break

			"node_freed":
				var target_key: String = ref if ref != "" else path
				var node: Node = _snapshot.resolve_ref(target_key, root)
				if node == null:
					condition_met = true
					break

			"property_equals":
				var target_key: String = ref if ref != "" else path
				var node: Node = _snapshot.resolve_ref(target_key, root)
				if node != null and node.get(property) == value:
					condition_met = true
					break

			"property_greater":
				var target_key: String = ref if ref != "" else path
				var node: Node = _snapshot.resolve_ref(target_key, root)
				if node != null and node.get(property) > value:
					condition_met = true
					break

			"property_less":
				var target_key: String = ref if ref != "" else path
				var node: Node = _snapshot.resolve_ref(target_key, root)
				if node != null and node.get(property) < value:
					condition_met = true
					break

			"signal":
				var target_key: String = ref if ref != "" else path
				var node: Node = _snapshot.resolve_ref(target_key, root)
				if node != null and signal_name != "":
					# Wait for signal with timeout
					var remaining: float = timeout - elapsed
					var signal_list: Array = node.get_signal_list()
					var has_signal: bool = false
					for sig: Dictionary in signal_list:
						if sig["name"] == signal_name:
							has_signal = true
							break
					if has_signal:
						var result_arr: Array = await _wait_for_signal_with_timeout(node, signal_name, remaining)
						condition_met = result_arr[0]
						elapsed += result_arr[1]
					break
			_:
				return {"error": "Unknown condition: %s" % condition}

		await _tree.create_timer(poll_interval).timeout
		elapsed += poll_interval

	var result: Dictionary = {
		"condition_met": condition_met,
		"elapsed": elapsed,
	}

	if do_snapshot:
		var snap_request := BridgeHTTPServer.HTTPRequest.new()
		snap_request.query_params = {"include_screenshot": "true" if do_screenshot else "false"}
		var snap: Dictionary = await handle_snapshot(snap_request)
		result["snapshot"] = snap
	if do_screenshot and not do_snapshot:
		var ss_request := BridgeHTTPServer.HTTPRequest.new()
		var ss: Dictionary = await handle_screenshot(ss_request)
		result["screenshot"] = ss.get("image", null)

	return result


## GET /info — General game information.
func handle_info(_request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var root: Node = _get_scene_root()
	var current_scene_path: String = ""
	if root and root.scene_file_path != "":
		current_scene_path = root.scene_file_path

	var viewport: Viewport = _tree.root
	var vp_size: Vector2 = viewport.get_visible_rect().size

	# Get available actions
	var actions: Array[String] = []
	for action_name: StringName in InputMap.get_actions():
		actions.append(str(action_name))

	# Get autoloads
	var autoloads: Array[String] = []
	for child: Node in _tree.root.get_children():
		if child != _tree.current_scene:
			autoloads.append(str(child.name))

	return {
		"project_name": ProjectSettings.get_setting("application/config/name", ""),
		"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
		"current_scene": current_scene_path,
		"viewport_size": BridgeSerialization.serialize(vp_size),
		"physics_fps": Engine.physics_ticks_per_second,
		"target_fps": Engine.max_fps,
		"actual_fps": Engine.get_frames_per_second(),
		"time_since_start": Time.get_ticks_msec() / 1000.0,
		"paused": _tree.paused,
		"debug_build": OS.is_debug_build(),
		"available_actions": actions,
		"autoloads": autoloads,
	}


## POST /pause — Pause or unpause the game.
func handle_pause(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var paused: bool = body.get("paused", true)

	_tree.paused = paused
	return {"ok": true, "paused": _tree.paused}


## POST /timescale — Set the game time scale.
func handle_timescale(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var body: Dictionary = request.json_body if request.json_body is Dictionary else {}
	var scale: float = float(body.get("scale", 1.0))

	# Clamp to safe range (0.01 to 10.0)
	scale = clampf(scale, 0.01, 10.0)
	Engine.time_scale = scale
	return {"ok": true, "time_scale": Engine.time_scale}


## GET /console — Get recent game console/log output.
func handle_console(_request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	# Read from the game's log file
	var log_path: String = OS.get_user_data_dir().path_join("logs/godot.log")
	if not FileAccess.file_exists(log_path):
		# Try alternate paths
		var alt_paths: Array[String] = [
			ProjectSettings.globalize_path("user://logs/godot.log"),
			ProjectSettings.globalize_path("user://logs/editor.log"),
		]
		for alt: String in alt_paths:
			if FileAccess.file_exists(alt):
				log_path = alt
				break

	if not FileAccess.file_exists(log_path):
		return {"output": "", "note": "No log file found"}

	var file: FileAccess = FileAccess.open(log_path, FileAccess.READ)
	if file == null:
		return {"output": "", "error": "Cannot open log file"}

	var content: String = file.get_as_text()
	file.close()

	# Return last ~6000 characters (recent output)
	if content.length() > 6000:
		content = "...(truncated)\n" + content.substr(content.length() - 6000)

	return {"output": content, "source": log_path, "length": content.length()}


## GET /snapshot/diff — Compare current snapshot to previous one.
func handle_snapshot_diff(request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	var root: Node = _get_scene_root()
	if root == null:
		return {"error": "No active scene"}

	var depth: int = int(request.query_params.get("depth", str(BridgeConfig.MAX_SNAPSHOT_DEPTH)))

	# Take current snapshot
	var current: Dictionary = _snapshot.take_snapshot(root, depth)

	if _previous_snapshot.is_empty():
		_previous_snapshot = current
		return {
			"diff": "first_snapshot",
			"note": "No previous snapshot to compare. This snapshot is now stored as baseline.",
			"snapshot": current,
		}

	# Compare snapshots
	var diff: Dictionary = _compute_snapshot_diff(_previous_snapshot, current)
	_previous_snapshot = current

	return {
		"diff": diff,
		"snapshot": current,
	}


## GET /scene_history — Get recent scene tree change events.
func handle_scene_history(_request: BridgeHTTPServer.HTTPRequest) -> Dictionary:
	return {
		"events": _scene_history,
		"count": _scene_history.size(),
	}


## Helper to get the current scene root.
func _get_scene_root() -> Node:
	if _tree.current_scene:
		return _tree.current_scene
	return null


## Wait for a signal with a timeout, returns [condition_met, elapsed_time].
func _wait_for_signal_with_timeout(node: Node, sig_name: String, timeout_sec: float) -> Array:
	var start: float = Time.get_ticks_msec() / 1000.0

	# Use a mutable container so the lambda can set the flag
	var signal_received: Array = [false]

	# Determine signal argument count so we can unbind them from our 0-arg callback
	var arg_count: int = 0
	for sig: Dictionary in node.get_signal_list():
		if sig["name"] == sig_name:
			arg_count = sig["args"].size()
			break

	# Connect a one-shot callback that sets the flag when the signal fires.
	# unbind(n) drops the n signal arguments so our no-arg lambda works.
	var callback: Callable = (func() -> void: signal_received[0] = true).unbind(arg_count)
	node.connect(sig_name, callback, CONNECT_ONE_SHOT)

	# Poll until the signal fires or we time out
	while not signal_received[0]:
		var elapsed: float = (Time.get_ticks_msec() / 1000.0) - start
		if elapsed >= timeout_sec:
			# Clean up the connection on timeout (one-shot auto-disconnects on fire)
			if node.is_connected(sig_name, callback):
				node.disconnect(sig_name, callback)
			return [false, elapsed]
		await _tree.create_timer(0.05).timeout

	var total_elapsed: float = (Time.get_ticks_msec() / 1000.0) - start
	return [true, total_elapsed]


## Compute a diff between two snapshots.
func _compute_snapshot_diff(old_snap: Dictionary, new_snap: Dictionary) -> Dictionary:
	var diff: Dictionary = {}

	# Top-level changes
	if old_snap.get("paused") != new_snap.get("paused"):
		diff["paused_changed"] = {"from": old_snap.get("paused"), "to": new_snap.get("paused")}
	if old_snap.get("scene_name") != new_snap.get("scene_name"):
		diff["scene_changed"] = {"from": old_snap.get("scene_name"), "to": new_snap.get("scene_name")}

	# Build lookup of old nodes by path
	var old_nodes: Dictionary = {}
	_flatten_nodes(old_snap.get("nodes", []), old_nodes)
	var new_nodes: Dictionary = {}
	_flatten_nodes(new_snap.get("nodes", []), new_nodes)

	# Find added nodes
	var added: Array[String] = []
	for path: String in new_nodes:
		if not old_nodes.has(path):
			added.append(path)
	if not added.is_empty():
		diff["nodes_added"] = added

	# Find removed nodes
	var removed: Array[String] = []
	for path: String in old_nodes:
		if not new_nodes.has(path):
			removed.append(path)
	if not removed.is_empty():
		diff["nodes_removed"] = removed

	# Find changed properties on existing nodes
	var changed: Dictionary = {}
	for path: String in new_nodes:
		if old_nodes.has(path):
			var node_changes: Dictionary = _diff_node(old_nodes[path], new_nodes[path])
			if not node_changes.is_empty():
				changed[path] = node_changes
	if not changed.is_empty():
		diff["nodes_changed"] = changed

	if diff.is_empty():
		diff["no_changes"] = true

	return diff


## Flatten a nested nodes array into a path → data dictionary.
func _flatten_nodes(nodes: Array, out: Dictionary) -> void:
	for node_data: Variant in nodes:
		if node_data is Dictionary:
			var path: String = str(node_data.get("path", ""))
			if path != "":
				out[path] = node_data
			var children: Array = node_data.get("children", [])
			if not children.is_empty():
				_flatten_nodes(children, out)


## Diff two node data dictionaries, returning only changed fields.
func _diff_node(old_node: Dictionary, new_node: Dictionary) -> Dictionary:
	var changes: Dictionary = {}
	var check_keys: Array[String] = ["visible", "text", "position", "global_position", "rotation"]

	for key: String in check_keys:
		var old_val: Variant = old_node.get(key)
		var new_val: Variant = new_node.get(key)
		if old_val != new_val and old_val != null and new_val != null:
			changes[key] = {"from": old_val, "to": new_val}

	# Check script properties
	var old_props: Dictionary = old_node.get("properties", {})
	var new_props: Dictionary = new_node.get("properties", {})
	var prop_changes: Dictionary = {}
	for prop_name: String in new_props:
		if old_props.get(prop_name) != new_props[prop_name]:
			prop_changes[prop_name] = {"from": old_props.get(prop_name), "to": new_props[prop_name]}
	if not prop_changes.is_empty():
		changes["properties"] = prop_changes

	return changes


## Callback for scene tree changes — records events for history.
func _on_tree_changed() -> void:
	var root: Node = _get_scene_root()
	var scene_name: String = str(root.name) if root else "unknown"

	_scene_history.append({
		"time": Time.get_ticks_msec() / 1000.0,
		"frame": Engine.get_frames_drawn(),
		"scene": scene_name,
		"event": "tree_changed",
	})

	# Cap history size
	while _scene_history.size() > _scene_history_max:
		_scene_history.pop_front()
