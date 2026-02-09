## Deep node introspection for the running game.
## Returns extended state information beyond what snapshot provides.
class_name StateReader
extends RefCounted


## Get detailed state for a specific node, including type-specific extra fields.
static func read_state(node: Node) -> Dictionary:
	var state: Dictionary = {
		"name": str(node.name),
		"type": node.get_class(),
		"path": str(node.get_path()),
	}

	# Basic spatial info
	if node is Node2D:
		state["position"] = BridgeSerialization.serialize(node.position)
		state["global_position"] = BridgeSerialization.serialize(node.global_position)
		state["rotation"] = node.rotation
		state["scale"] = BridgeSerialization.serialize(node.scale)
	elif node is Node3D:
		state["position"] = BridgeSerialization.serialize(node.position)
		state["global_position"] = BridgeSerialization.serialize(node.global_position)
		state["rotation"] = BridgeSerialization.serialize(node.rotation)
		state["scale"] = BridgeSerialization.serialize(node.scale)

	if node is Control:
		state["size"] = BridgeSerialization.serialize(node.size)
		state["global_position"] = BridgeSerialization.serialize(node.global_position)
		state["visible"] = node.is_visible_in_tree()

	# CanvasItem properties
	if node is CanvasItem:
		state["modulate"] = BridgeSerialization.serialize(node.modulate)
		state["self_modulate"] = BridgeSerialization.serialize(node.self_modulate)
		state["z_index"] = node.z_index
		state["visible"] = node.is_visible_in_tree()

	# CharacterBody2D / CharacterBody3D
	if node is CharacterBody2D:
		state["velocity"] = BridgeSerialization.serialize(node.velocity)
		state["is_on_floor"] = node.is_on_floor()
		state["is_on_wall"] = node.is_on_wall()
		state["is_on_ceiling"] = node.is_on_ceiling()

	if node is CharacterBody3D:
		state["velocity"] = BridgeSerialization.serialize(node.velocity)
		state["is_on_floor"] = node.is_on_floor()
		state["is_on_wall"] = node.is_on_wall()
		state["is_on_ceiling"] = node.is_on_ceiling()

	# RigidBody2D / RigidBody3D
	if node is RigidBody2D:
		state["linear_velocity"] = BridgeSerialization.serialize(node.linear_velocity)
		state["angular_velocity"] = node.angular_velocity
		state["sleeping"] = node.sleeping

	if node is RigidBody3D:
		state["linear_velocity"] = BridgeSerialization.serialize(node.linear_velocity)
		state["angular_velocity"] = BridgeSerialization.serialize(node.angular_velocity)
		state["sleeping"] = node.sleeping

	# AnimationPlayer
	if node is AnimationPlayer:
		state["current_animation"] = node.current_animation
		state["current_animation_position"] = node.current_animation_position
		state["is_playing"] = node.is_playing()

	# AnimatedSprite2D
	if node is AnimatedSprite2D:
		state["animation"] = str(node.animation)
		state["frame"] = node.frame
		state["is_playing"] = node.is_playing()

	# AnimatedSprite3D
	if node is AnimatedSprite3D:
		state["animation"] = str(node.animation)
		state["frame"] = node.frame
		state["is_playing"] = node.is_playing()

	# Area2D / Area3D
	if node is Area2D:
		var bodies: Array = []
		for body: Node2D in node.get_overlapping_bodies():
			bodies.append(str(body.get_path()))
		state["overlapping_bodies"] = bodies
		var areas: Array = []
		for area: Area2D in node.get_overlapping_areas():
			areas.append(str(area.get_path()))
		state["overlapping_areas"] = areas

	if node is Area3D:
		var bodies: Array = []
		for body: Node3D in node.get_overlapping_bodies():
			bodies.append(str(body.get_path()))
		state["overlapping_bodies"] = bodies
		var areas: Array = []
		for area: Area3D in node.get_overlapping_areas():
			areas.append(str(area.get_path()))
		state["overlapping_areas"] = areas

	# Timer
	if node is Timer:
		state["time_left"] = node.time_left
		state["is_stopped"] = node.is_stopped()
		state["wait_time"] = node.wait_time
		state["one_shot"] = node.one_shot
		state["autostart"] = node.autostart

	# AudioStreamPlayer variants
	if node is AudioStreamPlayer:
		state["playing"] = node.playing
		state["stream"] = node.stream.resource_path if node.stream else null

	if node is AudioStreamPlayer2D:
		state["playing"] = node.playing
		state["stream"] = node.stream.resource_path if node.stream else null

	if node is AudioStreamPlayer3D:
		state["playing"] = node.playing
		state["stream"] = node.stream.resource_path if node.stream else null

	# Camera
	if node is Camera2D:
		state["current"] = node.is_current()

	if node is Camera3D:
		state["current"] = node.current

	# Progress bars
	if node is ProgressBar or node is TextureProgressBar:
		state["value"] = node.value
		state["min_value"] = node.min_value
		state["max_value"] = node.max_value
		state["ratio"] = node.ratio

	# Text input
	if node is LineEdit:
		state["text"] = node.text
		state["placeholder_text"] = node.placeholder_text
		state["editable"] = node.editable

	if node is TextEdit:
		state["text"] = node.text
		state["placeholder_text"] = node.placeholder_text
		state["editable"] = not node.read_only

	if node is Label:
		state["text"] = node.text

	if node is RichTextLabel:
		state["text"] = node.text
		state["visible_characters"] = node.visible_characters

	if node is Button:
		state["text"] = node.text
		state["disabled"] = node.disabled

	# Script variables
	state["properties"] = _get_script_properties(node)

	# Groups
	var groups: Array[String] = []
	for g: StringName in node.get_groups():
		var gs: String = str(g)
		if not gs.begins_with("_"):
			groups.append(gs)
	state["groups"] = groups

	# Connected signals
	state["signals"] = _get_signal_connections(node)

	return state


## Get script-defined variables.
static func _get_script_properties(node: Node) -> Dictionary:
	var props: Dictionary = {}
	for prop: Dictionary in node.get_property_list():
		var usage: int = prop.get("usage", 0)
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and (usage & PROPERTY_USAGE_STORAGE) != 0:
			var prop_name: String = prop["name"]
			var value: Variant = node.get(prop_name)
			props[prop_name] = BridgeSerialization.serialize(value)
	return props


## Get user-connected signal names.
static func _get_signal_connections(node: Node) -> Array:
	var signals: Array = []
	for sig: Dictionary in node.get_signal_list():
		var sig_name: String = sig["name"]
		var connections: Array = node.get_signal_connection_list(sig_name)
		if connections.size() > 0:
			var conn_info: Array = []
			for conn: Dictionary in connections:
				conn_info.append({
					"signal": sig_name,
					"target": str(conn.get("callable", "")).get_base_dir(),
				})
			signals.append_array(conn_info)
	return signals
