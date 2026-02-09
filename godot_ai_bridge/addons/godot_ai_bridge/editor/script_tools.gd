## Script read/write/error checking operations for the editor bridge.
class_name ScriptTools
extends RefCounted


## Read the contents of a script file.
static func read_script(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "File not found: %s" % path}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Cannot open file: %s (%s)" % [path, error_string(FileAccess.get_open_error())]}

	var content: String = file.get_as_text()
	file.close()

	return {"path": path, "content": content, "length": content.length()}


## Write contents to a script file. Creates the file if it doesn't exist.
static func write_script(path: String, content: String) -> Dictionary:
	# Ensure directory exists
	var dir_path: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var err: Error = DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			return {"error": "Cannot create directory: %s (%s)" % [dir_path, error_string(err)]}

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"error": "Cannot write file: %s (%s)" % [path, error_string(FileAccess.get_open_error())]}

	file.store_string(content)
	file.close()

	# Trigger resource filesystem rescan so the editor picks up changes
	EditorInterface.get_resource_filesystem().scan()

	return {"ok": true, "path": path}


## Create a new script with optional boilerplate.
static func create_script(path: String, extends_class: String = "Node", template: String = "basic") -> Dictionary:
	if FileAccess.file_exists(path):
		return {"error": "File already exists: %s" % path}

	var content: String = ""
	match template:
		"basic":
			content = _basic_template(extends_class)
		"empty":
			content = "extends %s\n" % extends_class
		"full":
			content = _full_template(extends_class)
		_:
			content = _basic_template(extends_class)

	return write_script(path, content)


## Get current script errors from the editor.
static func get_errors() -> Dictionary:
	# Try to get errors from the script editor
	var script_editor: ScriptEditor = EditorInterface.get_script_editor()
	if script_editor == null:
		return {"errors": [], "note": "Script editor not available"}

	# Get open script list and check for errors
	var open_scripts: Array[Script] = script_editor.get_open_scripts()
	var errors: Array = []

	for script: Script in open_scripts:
		if script == null:
			continue
		# Check if the script has compilation errors by trying to reload it
		if not script.can_instantiate():
			errors.append({
				"path": script.resource_path,
				"message": "Script has compilation errors",
			})

	return {"errors": errors}


## Get recent debugger/output text by reading the editor log file.
static func get_debugger_output() -> Dictionary:
	# Try reading the editor log file for recent output
	var log_paths: Array[String] = [
		"user://logs/godot.log",
		"user://logs/editor.log",
	]

	for log_path: String in log_paths:
		# Resolve the user:// path to an absolute path
		var abs_path: String = ProjectSettings.globalize_path(log_path)
		if FileAccess.file_exists(abs_path):
			var file: FileAccess = FileAccess.open(abs_path, FileAccess.READ)
			if file != null:
				var content: String = file.get_as_text()
				file.close()
				# Return the last ~4000 characters (recent output)
				if content.length() > 4000:
					content = "...(truncated)\n" + content.substr(content.length() - 4000)
				return {"output": content, "source": log_path, "length": content.length()}

	# Fallback: try the global data dir logs
	var global_log: String = OS.get_user_data_dir().path_join("logs/godot.log")
	if FileAccess.file_exists(global_log):
		var file: FileAccess = FileAccess.open(global_log, FileAccess.READ)
		if file != null:
			var content: String = file.get_as_text()
			file.close()
			if content.length() > 4000:
				content = "...(truncated)\n" + content.substr(content.length() - 4000)
			return {"output": content, "source": global_log, "length": content.length()}

	return {
		"output": "",
		"note": "No log file found. Output panel is not directly accessible via EditorInterface.",
	}


## Generate a basic script template.
static func _basic_template(extends_class: String) -> String:
	return """extends %s


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	pass
""" % extends_class


## Generate a fuller script template with common callbacks.
static func _full_template(extends_class: String) -> String:
	var content: String = "extends %s\n\n" % extends_class

	# Add common exported variables based on type
	match extends_class:
		"CharacterBody2D":
			content += """
@export var speed: float = 200.0
@export var jump_velocity: float = -300.0


func _physics_process(delta: float) -> void:
	# Add gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	# Get input direction.
	var direction: float = Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)

	move_and_slide()
"""
		"CharacterBody3D":
			content += """
@export var speed: float = 5.0
@export var jump_velocity: float = 4.5


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()
"""
		_:
			content += """
func _ready() -> void:
	pass


func _process(delta: float) -> void:
	pass
"""

	return content
