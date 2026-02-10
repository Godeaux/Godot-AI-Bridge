## Project-level operations: file search, directory structure, input map, settings.
class_name ProjectTools
extends RefCounted


## Return a directory tree of the project, excluding .godot/ and addons/godot_ai_bridge/.
static func get_structure(base_path: String = "res://", max_depth: int = 5) -> Dictionary:
	var tree: Dictionary = _scan_directory(base_path, 0, max_depth)
	return {"root": base_path, "tree": tree}


## Search project files by glob pattern or filename substring.
static func search_files(pattern: String = "", query: String = "", base_path: String = "res://") -> Dictionary:
	var matches: Array = []
	_search_recursive(base_path, pattern, query, matches, 0, 8)
	return {"matches": matches, "count": matches.size()}


## Return all InputMap actions and their bindings.
static func get_input_map() -> Dictionary:
	var actions: Dictionary = {}

	# Read from ProjectSettings
	var props: Array[Dictionary] = ProjectSettings.get_property_list()
	for prop: Dictionary in props:
		var prop_name: String = prop["name"]
		if prop_name.begins_with("input/"):
			var action_name: String = prop_name.substr(6)  # Remove "input/" prefix
			var action_data: Variant = ProjectSettings.get_setting(prop_name)
			var events: Array = []

			if action_data is Dictionary and action_data.has("events"):
				for event: Variant in action_data["events"]:
					if event is InputEventKey:
						events.append({
							"type": "key",
							"keycode": OS.get_keycode_string(event.keycode) if event.keycode != KEY_NONE else OS.get_keycode_string(event.physical_keycode),
						})
					elif event is InputEventMouseButton:
						events.append({
							"type": "mouse_button",
							"button_index": event.button_index,
						})
					elif event is InputEventJoypadButton:
						events.append({
							"type": "joypad_button",
							"button_index": event.button_index,
						})
					elif event is InputEventJoypadMotion:
						events.append({
							"type": "joypad_motion",
							"axis": event.axis,
							"axis_value": event.axis_value,
						})
					else:
						events.append({"type": str(event)})

			actions[action_name] = events

	return {"actions": actions}


## Return key project settings.
static func get_project_settings() -> Dictionary:
	return {
		"name": ProjectSettings.get_setting("application/config/name", ""),
		"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
		"window_width": ProjectSettings.get_setting("display/window/size/viewport_width", 1152),
		"window_height": ProjectSettings.get_setting("display/window/size/viewport_height", 648),
		"window_mode": ProjectSettings.get_setting("display/window/size/mode", 0),
		"stretch_mode": ProjectSettings.get_setting("display/window/stretch/mode", "disabled"),
		"stretch_aspect": ProjectSettings.get_setting("display/window/stretch/aspect", "keep"),
		"physics_fps": ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60),
		"max_fps": ProjectSettings.get_setting("application/run/max_fps", 0),
		"rendering_method": ProjectSettings.get_setting("rendering/renderer/rendering_method", ""),
	}


## Return registered autoloads.
static func get_autoloads() -> Dictionary:
	var autoloads: Dictionary = {}
	var props: Array[Dictionary] = ProjectSettings.get_property_list()
	for prop: Dictionary in props:
		var prop_name: String = prop["name"]
		if prop_name.begins_with("autoload/"):
			var autoload_name: String = prop_name.substr(9)  # Remove "autoload/" prefix
			var value: String = str(ProjectSettings.get_setting(prop_name))
			# Autoload values start with "*" for enabled singletons
			var enabled: bool = value.begins_with("*")
			var path: String = value.substr(1) if enabled else value
			autoloads[autoload_name] = {"path": path, "enabled": enabled}

	return {"autoloads": autoloads}


## Recursively scan a directory and build a tree structure.
static func _scan_directory(path: String, current_depth: int, max_depth: int) -> Array:
	if current_depth >= max_depth:
		return []

	var entries: Array = []
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return []

	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while file_name != "":
		# Skip hidden, .godot, and our own addon directory
		if file_name.begins_with(".") or file_name == ".godot":
			file_name = dir.get_next()
			continue
		if path == "res://" and file_name == ".godot":
			file_name = dir.get_next()
			continue

		var full_path: String = path.path_join(file_name)

		if dir.current_is_dir():
			# Skip our own addon to avoid noise
			if full_path == "res://addons/godot_ai_bridge":
				file_name = dir.get_next()
				continue

			var children: Array = _scan_directory(full_path, current_depth + 1, max_depth)
			entries.append({
				"name": file_name,
				"type": "directory",
				"path": full_path,
				"children": children,
			})
		else:
			# Skip .import files
			if file_name.ends_with(".import"):
				file_name = dir.get_next()
				continue

			var size: int = 0
			var file: FileAccess = FileAccess.open(full_path, FileAccess.READ)
			if file != null:
				size = file.get_length()
				file.close()

			entries.append({
				"name": file_name,
				"type": "file",
				"path": full_path,
				"size": size,
			})

		file_name = dir.get_next()

	dir.list_dir_end()
	return entries


## Recursively search for files matching a pattern or query.
static func _search_recursive(path: String, pattern: String, query: String, matches: Array, depth: int, max_depth: int) -> void:
	if depth >= max_depth:
		return
	if matches.size() >= 200:  # Limit results
		return

	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while file_name != "":
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue

		var full_path: String = path.path_join(file_name)

		if dir.current_is_dir():
			if full_path != "res://addons/godot_ai_bridge" and full_path != "res://.godot":
				_search_recursive(full_path, pattern, query, matches, depth + 1, max_depth)
		else:
			var match_found: bool = false

			if pattern != "":
				# Simple glob matching
				match_found = _glob_match(file_name, pattern)
			elif query != "":
				# Substring search (case-insensitive)
				match_found = file_name.to_lower().contains(query.to_lower())

			if match_found:
				matches.append(full_path)

		file_name = dir.get_next()

	dir.list_dir_end()


## Simple glob pattern matching (supports * and ?).
static func _glob_match(text: String, pattern: String) -> bool:
	return text.matchn(pattern)
