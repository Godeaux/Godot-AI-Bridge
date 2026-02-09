## Scene and node CRUD operations for the editor bridge.
## Provides methods for manipulating scenes and nodes in the Godot editor.
class_name SceneTools
extends RefCounted


## Get the full scene tree of the currently edited scene.
static func get_scene_tree() -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open"}

	var scene_path: String = root.scene_file_path if root.scene_file_path != "" else ""

	return {
		"scene_path": scene_path,
		"root": _walk_node(root),
	}


## Recursively walk a node and build a tree structure.
static func _walk_node(node: Node) -> Dictionary:
	var data: Dictionary = {
		"name": str(node.name),
		"type": node.get_class(),
		"path": str(node.get_path()),
	}

	var children: Array = []
	for child: Node in node.get_children():
		if not str(child.name).begins_with("@"):
			children.append(_walk_node(child))
	data["children"] = children

	return data


## Create a new scene with a given root node type and save it.
static func create_scene(root_type: String, save_path: String) -> Dictionary:
	var node: Node = _create_node_by_type(root_type)
	if node == null:
		return {"error": "Unknown node type: %s" % root_type}

	node.name = save_path.get_file().get_basename()

	var scene := PackedScene.new()
	var err: Error = scene.pack(node)
	if err != OK:
		node.free()
		return {"error": "Failed to pack scene: %s" % error_string(err)}

	err = ResourceSaver.save(scene, save_path)
	node.free()

	if err != OK:
		return {"error": "Failed to save scene to %s: %s" % [save_path, error_string(err)]}

	EditorInterface.get_resource_filesystem().scan()
	return {"ok": true, "path": save_path}


## Add a node to the currently edited scene.
static func add_node(parent_path: String, node_type: String, node_name: String, properties: Dictionary = {}) -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open"}

	var parent: Node = root if parent_path == "." or parent_path == "" else root.get_node_or_null(parent_path)
	if parent == null:
		return {"error": "Parent node not found: %s" % parent_path}

	var new_node: Node = _create_node_by_type(node_type)
	if new_node == null:
		return {"error": "Unknown node type: %s" % node_type}

	new_node.name = node_name
	parent.add_child(new_node)
	new_node.owner = root

	# Apply properties
	for prop_name: String in properties:
		_set_node_property(new_node, prop_name, properties[prop_name])

	return {"ok": true, "path": str(root.get_path_to(new_node))}


## Remove a node from the currently edited scene.
static func remove_node(node_path: String) -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open"}

	var node: Node = root.get_node_or_null(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path}

	if node == root:
		return {"error": "Cannot remove the root node"}

	node.get_parent().remove_child(node)
	node.queue_free()
	return {"ok": true}


## Set a property on a node in the currently edited scene.
static func set_property(node_path: String, property: String, value: Variant) -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open"}

	var node: Node = root if node_path == "." or node_path == "" else root.get_node_or_null(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path}

	_set_node_property(node, property, value)
	return {"ok": true}


## Get a property from a node in the currently edited scene.
static func get_property(node_path: String, property: String) -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open"}

	var node: Node = root if node_path == "." or node_path == "" else root.get_node_or_null(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path}

	var value: Variant = node.get(property)
	return {"value": BridgeSerialization.serialize(value)}


## Save the currently edited scene.
static func save_scene() -> Dictionary:
	var err: Error = EditorInterface.save_scene()
	if err != OK:
		return {"error": "Failed to save scene: %s" % error_string(err)}
	return {"ok": true}


## Open a scene in the editor.
static func open_scene(path: String) -> Dictionary:
	EditorInterface.open_scene_from_path(path)
	return {"ok": true, "path": path}


## Create a node by its class name string.
static func _create_node_by_type(type_name: String) -> Node:
	if not ClassDB.class_exists(type_name):
		return null
	if not ClassDB.can_instantiate(type_name):
		return null
	var obj: Object = ClassDB.instantiate(type_name)
	if obj is Node:
		return obj as Node
	if obj != null:
		obj.free()
	return null


## Set a property on a node, handling type deserialization.
static func _set_node_property(node: Node, prop_name: String, value: Variant) -> void:
	# Special handling for texture loading
	if prop_name == "texture" and value is String:
		var texture: Resource = load(value)
		if texture != null:
			node.set(prop_name, texture)
		return

	# Special handling for script loading
	if prop_name == "script" and value is String:
		var script: Resource = load(value)
		if script != null:
			node.set(prop_name, script)
		return

	# Special handling for material, mesh, etc. (resource paths)
	if value is String and value.begins_with("res://") and ResourceLoader.exists(value):
		var res: Resource = load(value)
		if res != null:
			node.set(prop_name, res)
			return

	# Get the target property type for proper deserialization
	var prop_list: Array[Dictionary] = node.get_property_list()
	for prop: Dictionary in prop_list:
		if prop["name"] == prop_name:
			var target_type: int = prop.get("type", TYPE_NIL)
			if target_type != TYPE_NIL:
				value = BridgeSerialization.deserialize_property_value(value, target_type)
			break

	node.set(prop_name, value)
