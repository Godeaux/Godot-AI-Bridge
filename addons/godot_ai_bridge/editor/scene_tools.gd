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


## Duplicate a node in the currently edited scene.
static func duplicate_node(node_path: String, new_name: String = "") -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open"}

	var node: Node = root.get_node_or_null(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path}

	if node == root:
		return {"error": "Cannot duplicate the root node"}

	var dup: Node = node.duplicate()
	if dup == null:
		return {"error": "Failed to duplicate node"}

	if new_name != "":
		dup.name = new_name

	node.get_parent().add_child(dup)
	dup.owner = root
	_set_owner_recursive(dup, root)

	return {"ok": true, "path": str(root.get_path_to(dup)), "name": str(dup.name)}


## Reparent a node to a different parent in the currently edited scene.
static func reparent_node(node_path: String, new_parent_path: String, keep_global_transform: bool = true) -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open"}

	var node: Node = root.get_node_or_null(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path}

	if node == root:
		return {"error": "Cannot reparent the root node"}

	var new_parent: Node = root if new_parent_path == "." or new_parent_path == "" else root.get_node_or_null(new_parent_path)
	if new_parent == null:
		return {"error": "New parent not found: %s" % new_parent_path}

	if node.is_ancestor_of(new_parent):
		return {"error": "Cannot reparent a node to its own descendant"}

	node.reparent(new_parent, keep_global_transform)
	node.owner = root
	_set_owner_recursive(node, root)

	return {"ok": true, "new_path": str(root.get_path_to(node))}


## List all properties of a node in the currently edited scene.
static func list_node_properties(node_path: String) -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open"}

	var node: Node = root if node_path == "." or node_path == "" else root.get_node_or_null(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path}

	var properties: Array = []
	var prop_list: Array[Dictionary] = node.get_property_list()
	for prop: Dictionary in prop_list:
		var usage: int = prop.get("usage", 0)
		# Include editor-visible properties (PROPERTY_USAGE_EDITOR = 4) and script vars
		if (usage & PROPERTY_USAGE_EDITOR) != 0 or (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			var prop_info: Dictionary = {
				"name": prop["name"],
				"type": type_string(prop.get("type", TYPE_NIL)),
				"value": BridgeSerialization.serialize(node.get(prop["name"])),
			}
			if prop.has("hint_string") and prop["hint_string"] != "":
				prop_info["hint"] = prop["hint_string"]
			properties.append(prop_info)

	return {
		"node": str(node.name),
		"type": node.get_class(),
		"properties": properties,
		"count": properties.size(),
	}


## Rename a node in the currently edited scene.
static func rename_node(node_path: String, new_name: String) -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open"}

	var node: Node = root.get_node_or_null(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path}

	var old_name: String = str(node.name)
	node.name = new_name

	return {"ok": true, "old_name": old_name, "new_name": str(node.name), "new_path": str(root.get_path_to(node))}


## Instance a PackedScene as a child of a node in the currently edited scene.
static func instance_scene(scene_path: String, parent_path: String, node_name: String = "") -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open"}

	var parent: Node = root if parent_path == "." or parent_path == "" else root.get_node_or_null(parent_path)
	if parent == null:
		return {"error": "Parent node not found: %s" % parent_path}

	if not ResourceLoader.exists(scene_path):
		return {"error": "Scene file not found: %s" % scene_path}

	var packed: PackedScene = load(scene_path)
	if packed == null:
		return {"error": "Failed to load scene: %s" % scene_path}

	var instance: Node = packed.instantiate()
	if instance == null:
		return {"error": "Failed to instantiate scene: %s" % scene_path}

	if node_name != "":
		instance.name = node_name

	parent.add_child(instance)
	instance.owner = root
	_set_owner_recursive(instance, root)

	return {"ok": true, "path": str(root.get_path_to(instance)), "name": str(instance.name), "type": instance.get_class()}


## Find nodes in the current scene by name pattern, type, or group.
static func find_nodes(name_pattern: String = "", type_name: String = "", group: String = "", in_path: String = "") -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open"}

	var search_root: Node = root
	if in_path != "" and in_path != ".":
		search_root = root.get_node_or_null(in_path)
		if search_root == null:
			return {"error": "Search root not found: %s" % in_path}

	var results: Array = []
	_find_nodes_recursive(search_root, root, name_pattern, type_name, group, results)

	return {"matches": results, "count": results.size()}


## Recursively search for matching nodes.
static func _find_nodes_recursive(node: Node, scene_root: Node, name_pattern: String, type_name: String, group: String, results: Array) -> void:
	if str(node.name).begins_with("@"):
		return

	var matches: bool = true

	if name_pattern != "":
		if name_pattern.contains("*"):
			matches = str(node.name).matchn(name_pattern)
		else:
			matches = str(node.name).to_lower().contains(name_pattern.to_lower())

	if matches and type_name != "":
		matches = node.is_class(type_name)

	if matches and group != "":
		matches = node.is_in_group(group)

	if matches:
		var info: Dictionary = {
			"name": str(node.name),
			"type": node.get_class(),
			"path": str(scene_root.get_path_to(node)),
		}
		results.append(info)

	for child: Node in node.get_children():
		_find_nodes_recursive(child, scene_root, name_pattern, type_name, group, results)


## Recursively set owner on all children (so they save with the scene).
static func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner
		_set_owner_recursive(child, owner)


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


## List all signals on a node, including their current connections.
static func list_signals(node_path: String) -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open"}

	var node: Node = root if node_path == "." or node_path == "" else root.get_node_or_null(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path}

	var signals: Array = []
	for sig: Dictionary in node.get_signal_list():
		var sig_name: String = sig["name"]
		var connections: Array = []
		for conn: Dictionary in node.get_signal_connection_list(sig_name):
			connections.append({
				"target": str(root.get_path_to(conn["callable"].get_object())),
				"method": conn["callable"].get_method(),
			})
		var sig_info: Dictionary = {
			"name": sig_name,
			"args": [],
			"connections": connections,
		}
		for arg: Dictionary in sig.get("args", []):
			sig_info["args"].append({
				"name": arg.get("name", ""),
				"type": type_string(arg.get("type", TYPE_NIL)),
			})
		signals.append(sig_info)

	return {
		"node": str(node.name),
		"type": node.get_class(),
		"signals": signals,
		"count": signals.size(),
	}


## Connect a signal from one node to a method on another node.
static func connect_signal(source_path: String, signal_name: String, target_path: String, method_name: String) -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open"}

	var source: Node = root if source_path == "." or source_path == "" else root.get_node_or_null(source_path)
	if source == null:
		return {"error": "Source node not found: %s" % source_path}

	var target: Node = root if target_path == "." or target_path == "" else root.get_node_or_null(target_path)
	if target == null:
		return {"error": "Target node not found: %s" % target_path}

	if not source.has_signal(signal_name):
		return {"error": "Signal '%s' does not exist on node '%s' (%s)" % [signal_name, source.name, source.get_class()]}

	if source.is_connected(signal_name, Callable(target, method_name)):
		return {"error": "Signal '%s' is already connected to '%s.%s'" % [signal_name, target_path, method_name]}

	var err: Error = source.connect(signal_name, Callable(target, method_name))
	if err != OK:
		return {"error": "Failed to connect signal: %s" % error_string(err)}

	return {"ok": true}


## Disconnect a signal between two nodes.
static func disconnect_signal(source_path: String, signal_name: String, target_path: String, method_name: String) -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open"}

	var source: Node = root if source_path == "." or source_path == "" else root.get_node_or_null(source_path)
	if source == null:
		return {"error": "Source node not found: %s" % source_path}

	var target: Node = root if target_path == "." or target_path == "" else root.get_node_or_null(target_path)
	if target == null:
		return {"error": "Target node not found: %s" % target_path}

	if not source.has_signal(signal_name):
		return {"error": "Signal '%s' does not exist on node '%s' (%s)" % [signal_name, source.name, source.get_class()]}

	var callable: Callable = Callable(target, method_name)
	if not source.is_connected(signal_name, callable):
		return {"error": "Signal '%s' is not connected to '%s.%s'" % [signal_name, target_path, method_name]}

	source.disconnect(signal_name, callable)
	return {"ok": true}


## Add a node to a group.
static func add_to_group(node_path: String, group_name: String) -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open"}

	var node: Node = root if node_path == "." or node_path == "" else root.get_node_or_null(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path}

	if node.is_in_group(group_name):
		return {"error": "Node '%s' is already in group '%s'" % [node.name, group_name]}

	node.add_to_group(group_name, true)
	return {"ok": true, "groups": _get_node_groups(node)}


## Remove a node from a group.
static func remove_from_group(node_path: String, group_name: String) -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open"}

	var node: Node = root if node_path == "." or node_path == "" else root.get_node_or_null(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path}

	if not node.is_in_group(group_name):
		return {"error": "Node '%s' is not in group '%s'" % [node.name, group_name]}

	node.remove_from_group(group_name)
	return {"ok": true, "groups": _get_node_groups(node)}


## Get all persistent groups for a node (excluding internal groups).
static func _get_node_groups(node: Node) -> Array:
	var groups: Array = []
	for g: StringName in node.get_groups():
		var gs: String = str(g)
		if not gs.begins_with("_"):
			groups.append(gs)
	return groups


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
