## Buffers significant game events between AI snapshots.
## Captures signals, node lifecycle, property threshold crossings, and scene changes
## so the AI can see *what happened* between observations, not just the end state.
class_name EventAccumulator
extends RefCounted

## Maximum number of events to buffer before oldest are discarded.
const MAX_EVENTS: int = 200

## Signals auto-monitored on physics bodies and areas.
const AUTO_SIGNALS_2D: PackedStringArray = [
	"body_entered", "body_exited",
	"area_entered", "area_exited",
]
const AUTO_SIGNALS_3D: PackedStringArray = [
	"body_entered", "body_exited",
	"area_entered", "area_exited",
]
const AUTO_SIGNALS_ANIM: PackedStringArray = [
	"animation_finished",
]

var _events: Array[Dictionary] = []
var _event_id: int = 0
var _tree: SceneTree

## Property watches: Array of {node_path: String, property: String, last_value: Variant, label: String}
var _watches: Array[Dictionary] = []

## Tracks which nodes we've already connected auto-signals to.
## Maps instance_id → Array[Callable] (the callbacks we connected).
var _connected_nodes: Dictionary = {}

## Track the current scene path to detect scene changes.
var _current_scene_path: String = ""

## Whether the accumulator is actively collecting events.
## Starts false — only start() enables recording, preventing spurious events
## from node additions during bridge initialization.
var _active: bool = false


func _init(tree: SceneTree) -> void:
	_tree = tree
	# Monitor node additions/removals
	_tree.node_added.connect(_on_node_added)
	_tree.node_removed.connect(_on_node_removed)


## Start the accumulator — scan the existing tree and begin monitoring.
func start() -> void:
	_active = true
	var root: Node = _tree.current_scene
	if root:
		_current_scene_path = root.scene_file_path
		_scan_tree(root)


## Stop accumulating events and disconnect all auto-signals.
func stop() -> void:
	_active = false
	_disconnect_all()


## Disconnect tree signals to prevent leaks on shutdown.
func cleanup() -> void:
	stop()
	if _tree.node_added.is_connected(_on_node_added):
		_tree.node_added.disconnect(_on_node_added)
	if _tree.node_removed.is_connected(_on_node_removed):
		_tree.node_removed.disconnect(_on_node_removed)


## Drain all accumulated events. Returns the events array and clears the buffer.
func drain() -> Array[Dictionary]:
	var result: Array[Dictionary] = _events.duplicate()
	_events.clear()
	return result


## Peek at events without clearing them.
func peek() -> Array[Dictionary]:
	return _events.duplicate()


## Get the number of pending events.
func count() -> int:
	return _events.size()


## Clear all accumulated events without returning them.
func clear() -> void:
	_events.clear()


## Register a property to watch for changes. Checked each time poll() is called.
## label: Human-readable name for the watch (e.g., "player_health").
## Returns true if the watch was added, false if it already exists.
func add_watch(node_path: String, property: String, label: String = "") -> bool:
	# Check for duplicates
	for w: Dictionary in _watches:
		if w["node_path"] == node_path and w["property"] == property:
			return false

	var root: Node = _tree.current_scene
	if root == null:
		return false

	var node: Node = root.get_node_or_null(node_path)
	var current_value: Variant = null
	if node != null:
		current_value = node.get(property)

	if label == "":
		label = "%s.%s" % [node_path, property]

	_watches.append({
		"node_path": node_path,
		"property": property,
		"last_value": BridgeSerialization.serialize(current_value),
		"label": label,
	})
	return true


## Remove a property watch. Returns true if it was found and removed.
func remove_watch(node_path: String, property: String) -> bool:
	for i: int in range(_watches.size()):
		if _watches[i]["node_path"] == node_path and _watches[i]["property"] == property:
			_watches.remove_at(i)
			return true
	return false


## Get all current watches.
func get_watches() -> Array[Dictionary]:
	return _watches.duplicate()


## Poll watched properties and detect scene changes. Call this periodically
## (e.g., every N frames from _process, or before returning a snapshot).
func poll() -> void:
	if not _active:
		return

	_poll_scene_change()
	_poll_watches()


# ---------------------------------------------------------------------------
# Internal: Event recording
# ---------------------------------------------------------------------------

func _record(type: String, source_path: String, detail: Dictionary) -> void:
	if not _active:
		return

	_event_id += 1
	var event: Dictionary = {
		"id": _event_id,
		"type": type,
		"time": Time.get_ticks_msec() / 1000.0,
		"frame": Engine.get_frames_drawn(),
		"source": source_path,
		"detail": detail,
	}
	_events.append(event)

	# Cap the buffer size
	while _events.size() > MAX_EVENTS:
		_events.pop_front()


# ---------------------------------------------------------------------------
# Internal: Auto-signal connections
# ---------------------------------------------------------------------------

## Scan the entire scene tree and connect auto-signals to relevant nodes.
func _scan_tree(node: Node) -> void:
	_try_connect_node(node)
	for child: Node in node.get_children():
		_scan_tree(child)


## Try to connect auto-signals to a single node based on its type.
func _try_connect_node(node: Node) -> void:
	var iid: int = node.get_instance_id()
	if _connected_nodes.has(iid):
		return

	# Skip internal nodes and the runtime bridge
	if str(node.name).begins_with("@"):
		return
	if node is BridgeHTTPServer:
		return

	var callbacks: Array[Callable] = []

	# Helper: create a callback once and connect it
	var _connect_1arg := func(n: Node, sig: String) -> void:
		if n.has_signal(sig):
			var cb: Callable = _make_signal_callback(n, sig)
			n.connect(sig, cb)
			callbacks.append(cb)

	var _connect_noarg := func(n: Node, sig: String) -> void:
		if n.has_signal(sig):
			var cb: Callable = _make_signal_callback_noarg(n, sig)
			n.connect(sig, cb)
			callbacks.append(cb)

	# Area2D / Area3D — body/area enter/exit
	if node is Area2D:
		for sig: String in AUTO_SIGNALS_2D:
			_connect_1arg.call(node, sig)

	if node is Area3D:
		for sig: String in AUTO_SIGNALS_3D:
			_connect_1arg.call(node, sig)

	# CollisionObject2D (StaticBody2D, RigidBody2D, CharacterBody2D) — body signals
	if node is CollisionObject2D and not node is Area2D:
		for sig_name: String in ["body_entered", "body_exited"]:
			_connect_1arg.call(node, sig_name)

	if node is CollisionObject3D and not node is Area3D:
		for sig_name: String in ["body_entered", "body_exited"]:
			_connect_1arg.call(node, sig_name)

	# AnimationPlayer — animation_finished
	if node is AnimationPlayer:
		for sig: String in AUTO_SIGNALS_ANIM:
			_connect_1arg.call(node, sig)

	# AnimatedSprite2D / AnimatedSprite3D — animation_finished
	if node is AnimatedSprite2D or node is AnimatedSprite3D:
		_connect_1arg.call(node, "animation_finished")

	# VisibleOnScreenNotifier2D / VisibleOnScreenNotifier3D
	if node is VisibleOnScreenNotifier2D:
		for sig: String in ["screen_entered", "screen_exited"]:
			_connect_noarg.call(node, sig)

	if node is VisibleOnScreenNotifier3D:
		for sig: String in ["screen_entered", "screen_exited"]:
			_connect_noarg.call(node, sig)

	# Timer — timeout
	if node is Timer:
		_connect_noarg.call(node, "timeout")

	# Button — pressed
	if node is BaseButton:
		_connect_noarg.call(node, "pressed")

	if not callbacks.is_empty():
		_connected_nodes[iid] = callbacks


## Create a callback for signals that pass one Node argument (body_entered, etc.).
func _make_signal_callback(source_node: Node, signal_name: String) -> Callable:
	var source_path: String = _relative_path(source_node)
	return func(arg: Variant) -> void:
		var arg_str: String = ""
		if arg is Node:
			arg_str = _relative_path(arg)
		else:
			arg_str = str(arg)
		_record("signal", source_path, {
			"signal": signal_name,
			"args": [arg_str],
		})


## Create a callback for signals with no arguments (pressed, timeout, screen_entered, etc.).
func _make_signal_callback_noarg(source_node: Node, signal_name: String) -> Callable:
	var source_path: String = _relative_path(source_node)
	return func() -> void:
		_record("signal", source_path, {
			"signal": signal_name,
			"args": [],
		})


## Disconnect all auto-connected signals.
func _disconnect_all() -> void:
	# We can't easily disconnect lambdas by reference, so just clear tracking.
	# Nodes will be freed naturally when the scene tree changes.
	_connected_nodes.clear()


# ---------------------------------------------------------------------------
# Internal: Node lifecycle
# ---------------------------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if not _active:
		return
	# Skip internal nodes
	if str(node.name).begins_with("@"):
		return
	if node is BridgeHTTPServer:
		return

	var path: String = _relative_path(node)
	_record("node_added", path, {
		"type": node.get_class(),
		"name": str(node.name),
	})

	# Auto-connect signals on the new node
	# Use call_deferred so the node is fully in the tree
	_try_connect_node.call_deferred(node)


func _on_node_removed(node: Node) -> void:
	if not _active:
		return
	# Skip internal nodes
	if str(node.name).begins_with("@"):
		return
	if node is BridgeHTTPServer:
		return

	var path: String = _relative_path(node)
	_record("node_removed", path, {
		"type": node.get_class(),
		"name": str(node.name),
	})

	# Clean up tracking
	var iid: int = node.get_instance_id()
	_connected_nodes.erase(iid)


# ---------------------------------------------------------------------------
# Internal: Property watches
# ---------------------------------------------------------------------------

func _poll_watches() -> void:
	var root: Node = _tree.current_scene
	if root == null:
		return

	for watch: Dictionary in _watches:
		var node: Node = root.get_node_or_null(watch["node_path"])
		if node == null:
			continue

		var current_value: Variant = BridgeSerialization.serialize(node.get(watch["property"]))
		if current_value != watch["last_value"]:
			_record("property_changed", watch["node_path"], {
				"property": watch["property"],
				"label": watch["label"],
				"old_value": watch["last_value"],
				"new_value": current_value,
			})
			watch["last_value"] = current_value


# ---------------------------------------------------------------------------
# Internal: Scene change detection
# ---------------------------------------------------------------------------

func _poll_scene_change() -> void:
	var root: Node = _tree.current_scene
	if root == null:
		return

	var new_path: String = root.scene_file_path
	if new_path != _current_scene_path:
		var old_path: String = _current_scene_path
		_current_scene_path = new_path
		_record("scene_changed", ".", {
			"from": old_path,
			"to": new_path,
			"scene_name": str(root.name),
		})
		# Re-scan the new scene tree for auto-signals
		_connected_nodes.clear()
		_scan_tree(root)


# ---------------------------------------------------------------------------
# Internal: Utilities
# ---------------------------------------------------------------------------

## Get path relative to current scene root.
func _relative_path(node: Node) -> String:
	if _tree.current_scene == null or node == _tree.current_scene:
		return "."
	if not node.is_inside_tree():
		return str(node.name)
	return str(_tree.current_scene.get_path_to(node))
