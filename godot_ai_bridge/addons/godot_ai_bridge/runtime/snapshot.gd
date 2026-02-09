## Scene tree snapshot system with stable ephemeral refs.
## Walks the scene tree and produces structured JSON data for AI consumption.
class_name RuntimeSnapshot
extends RefCounted

## Maps ref string (e.g. "n1") to NodePath for the current snapshot.
var ref_map: Dictionary = {}
var _ref_counter: int = 0


## Take a full snapshot of the scene tree.
func take_snapshot(root: Node, max_depth: int = BridgeConfig.MAX_SNAPSHOT_DEPTH) -> Dictionary:
	ref_map.clear()
	_ref_counter = 0

	var viewport: Viewport = root.get_viewport()
	var viewport_size: Vector2 = viewport.get_visible_rect().size if viewport else Vector2.ZERO
	var mouse_pos: Vector2 = viewport.get_mouse_position() if viewport else Vector2.ZERO

	var nodes: Array = []
	var node_count: int = 0
	_walk_tree(root, nodes, max_depth, 0, node_count)

	var scene_file: String = ""
	if root.scene_file_path != "":
		scene_file = root.scene_file_path

	return {
		"scene_name": root.name,
		"scene_path": scene_file,
		"viewport_size": BridgeSerialization.serialize(viewport_size),
		"mouse_position": BridgeSerialization.serialize(mouse_pos),
		"frame": Engine.get_frames_drawn(),
		"fps": Engine.get_frames_per_second(),
		"time": Time.get_ticks_msec() / 1000.0,
		"paused": root.get_tree().paused,
		"nodes": nodes,
	}


## Recursively walk the scene tree and build node data.
func _walk_tree(node: Node, out_nodes: Array, max_depth: int, current_depth: int, node_count: int) -> int:
	if node_count >= BridgeConfig.MAX_NODE_COUNT:
		return node_count

	# Skip Godot internal nodes (names starting with @)
	if node.name.begins_with("@"):
		return node_count

	# Skip the runtime bridge itself
	if node is BridgeHTTPServer:
		return node_count

	var ref: String = _next_ref()
	var node_path: String = str(node.get_path())
	ref_map[ref] = node_path

	var data: Dictionary = {
		"ref": ref,
		"name": str(node.name),
		"type": node.get_class(),
		"path": _relative_path(node),
		"visible": _get_visibility(node),
	}

	# Position for spatial nodes
	if node is Node2D:
		data["position"] = BridgeSerialization.serialize(node.position)
		data["global_position"] = BridgeSerialization.serialize(node.global_position)
		data["rotation"] = node.rotation
		data["scale"] = BridgeSerialization.serialize(node.scale)
	elif node is Node3D:
		data["position"] = BridgeSerialization.serialize(node.position)
		data["global_position"] = BridgeSerialization.serialize(node.global_position)
		data["rotation"] = BridgeSerialization.serialize(node.rotation)
		data["scale"] = BridgeSerialization.serialize(node.scale)
	else:
		data["position"] = null
		data["global_position"] = null
		data["rotation"] = null
		data["scale"] = null

	# Size for Control nodes
	if node is Control:
		data["size"] = BridgeSerialization.serialize(node.size)
		data["position"] = BridgeSerialization.serialize(node.position)
		data["global_position"] = BridgeSerialization.serialize(node.global_position)
	else:
		data["size"] = null

	# Text property for UI elements
	data["text"] = _get_text_property(node)

	# Groups (filter internal ones starting with _)
	var groups: Array[String] = []
	for g: StringName in node.get_groups():
		var gs: String = str(g)
		if not gs.begins_with("_"):
			groups.append(gs)
	data["groups"] = groups

	# Script variables (exported / stored)
	data["properties"] = _get_script_properties(node)

	# Children
	var children: Array = []
	node_count += 1

	if current_depth < max_depth:
		for child: Node in node.get_children():
			node_count = _walk_tree(child, children, max_depth, current_depth + 1, node_count)
			if node_count >= BridgeConfig.MAX_NODE_COUNT:
				break

	data["children"] = children
	out_nodes.append(data)
	return node_count


## Generate next ref string.
func _next_ref() -> String:
	_ref_counter += 1
	return "n%d" % _ref_counter


## Get relative path from scene root.
func _relative_path(node: Node) -> String:
	var root: Node = node.get_tree().current_scene
	if root == null or node == root:
		return "."
	var path: String = str(root.get_path_to(node))
	return path


## Get visibility of a node.
func _get_visibility(node: Node) -> bool:
	if node is CanvasItem:
		return node.is_visible_in_tree()
	if node is Node3D:
		return node.is_visible_in_tree()
	return true


## Get the text property if the node has one.
func _get_text_property(node: Node) -> Variant:
	if node is Label or node is Button or node is LineEdit or node is TextEdit:
		return node.text
	if node is RichTextLabel:
		return node.text
	if "text" in node:
		return str(node.text)
	return null


## Get script-defined properties (exports and stored variables).
func _get_script_properties(node: Node) -> Dictionary:
	var props: Dictionary = {}
	var prop_list: Array[Dictionary] = node.get_property_list()

	for prop: Dictionary in prop_list:
		var usage: int = prop.get("usage", 0)
		# PROPERTY_USAGE_SCRIPT_VARIABLE = 4096, PROPERTY_USAGE_STORAGE = 2
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and (usage & PROPERTY_USAGE_STORAGE) != 0:
			var prop_name: String = prop["name"]
			var value: Variant = node.get(prop_name)
			props[prop_name] = BridgeSerialization.serialize(value)

	return props


## Resolve a ref string or node path to an actual Node.
func resolve_ref(ref_or_path: String, scene_root: Node) -> Node:
	# Try as ref first
	if ref_map.has(ref_or_path):
		var path: String = ref_map[ref_or_path]
		return scene_root.get_node_or_null(path)

	# Try as node path
	var node: Node = scene_root.get_node_or_null(ref_or_path)
	if node != null:
		return node

	# Try relative to scene root
	if scene_root.get_tree() and scene_root.get_tree().current_scene:
		var current: Node = scene_root.get_tree().current_scene
		return current.get_node_or_null(ref_or_path)

	return null
