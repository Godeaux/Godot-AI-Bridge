## Input injection system for the running game.
## Uses Input.parse_input_event() so the game cannot distinguish injected input from real input.
class_name InputInjector
extends RefCounted

## Comprehensive key name to Godot keycode mapping.
const KEY_MAP: Dictionary = {
	"a": KEY_A, "b": KEY_B, "c": KEY_C, "d": KEY_D, "e": KEY_E,
	"f": KEY_F, "g": KEY_G, "h": KEY_H, "i": KEY_I, "j": KEY_J,
	"k": KEY_K, "l": KEY_L, "m": KEY_M, "n": KEY_N, "o": KEY_O,
	"p": KEY_P, "q": KEY_Q, "r": KEY_R, "s": KEY_S, "t": KEY_T,
	"u": KEY_U, "v": KEY_V, "w": KEY_W, "x": KEY_X, "y": KEY_Y,
	"z": KEY_Z,
	"0": KEY_0, "1": KEY_1, "2": KEY_2, "3": KEY_3, "4": KEY_4,
	"5": KEY_5, "6": KEY_6, "7": KEY_7, "8": KEY_8, "9": KEY_9,
	"space": KEY_SPACE,
	"enter": KEY_ENTER, "return": KEY_ENTER,
	"escape": KEY_ESCAPE, "esc": KEY_ESCAPE,
	"tab": KEY_TAB,
	"shift": KEY_SHIFT,
	"ctrl": KEY_CTRL, "control": KEY_CTRL,
	"alt": KEY_ALT,
	"meta": KEY_META, "super": KEY_META, "windows": KEY_META, "command": KEY_META,
	"up": KEY_UP,
	"down": KEY_DOWN,
	"left": KEY_LEFT,
	"right": KEY_RIGHT,
	"backspace": KEY_BACKSPACE,
	"delete": KEY_DELETE,
	"insert": KEY_INSERT,
	"home": KEY_HOME,
	"end": KEY_END,
	"pageup": KEY_PAGEUP, "page_up": KEY_PAGEUP,
	"pagedown": KEY_PAGEDOWN, "page_down": KEY_PAGEDOWN,
	"f1": KEY_F1, "f2": KEY_F2, "f3": KEY_F3, "f4": KEY_F4,
	"f5": KEY_F5, "f6": KEY_F6, "f7": KEY_F7, "f8": KEY_F8,
	"f9": KEY_F9, "f10": KEY_F10, "f11": KEY_F11, "f12": KEY_F12,
	"capslock": KEY_CAPSLOCK, "caps_lock": KEY_CAPSLOCK,
	"numlock": KEY_NUMLOCK, "num_lock": KEY_NUMLOCK,
	"scrolllock": KEY_SCROLLLOCK, "scroll_lock": KEY_SCROLLLOCK,
	"minus": KEY_MINUS, "-": KEY_MINUS,
	"equal": KEY_EQUAL, "=": KEY_EQUAL,
	"bracketleft": KEY_BRACKETLEFT, "[": KEY_BRACKETLEFT,
	"bracketright": KEY_BRACKETRIGHT, "]": KEY_BRACKETRIGHT,
	"backslash": KEY_BACKSLASH, "\\": KEY_BACKSLASH,
	"semicolon": KEY_SEMICOLON, ";": KEY_SEMICOLON,
	"apostrophe": KEY_APOSTROPHE, "'": KEY_APOSTROPHE,
	"comma": KEY_COMMA, ",": KEY_COMMA,
	"period": KEY_PERIOD, ".": KEY_PERIOD,
	"slash": KEY_SLASH, "/": KEY_SLASH,
	"quoteleft": KEY_QUOTELEFT, "`": KEY_QUOTELEFT,
}

## Mouse button name to Godot constant mapping.
const MOUSE_BUTTON_MAP: Dictionary = {
	"left": MOUSE_BUTTON_LEFT,
	"right": MOUSE_BUTTON_RIGHT,
	"middle": MOUSE_BUTTON_MIDDLE,
	"wheel_up": MOUSE_BUTTON_WHEEL_UP,
	"wheel_down": MOUSE_BUTTON_WHEEL_DOWN,
}

## Reference to the scene tree for creating timers.
var _tree: SceneTree


func _init(tree: SceneTree) -> void:
	_tree = tree


## Inject a mouse button click at the given position.
func click(x: float, y: float, button: String = "left", double_click: bool = false) -> void:
	var button_index: MouseButton = MOUSE_BUTTON_MAP.get(button.to_lower(), MOUSE_BUTTON_LEFT)

	# Press
	var press_event := InputEventMouseButton.new()
	press_event.position = Vector2(x, y)
	press_event.global_position = Vector2(x, y)
	press_event.button_index = button_index
	press_event.pressed = true
	press_event.double_click = double_click
	Input.parse_input_event(press_event)

	# Wait a frame
	await _tree.process_frame

	# Release
	var release_event := InputEventMouseButton.new()
	release_event.position = Vector2(x, y)
	release_event.global_position = Vector2(x, y)
	release_event.button_index = button_index
	release_event.pressed = false
	Input.parse_input_event(release_event)


## Click at the center of a node (Control or Node2D).
func click_node(node: Node) -> void:
	var pos: Vector2 = Vector2.ZERO

	if node is Control:
		var rect: Rect2 = node.get_global_rect()
		pos = rect.position + rect.size / 2.0
	elif node is Node2D:
		pos = node.global_position
	elif node is Node3D:
		# For 3D nodes, project to screen space using the active camera
		var camera: Camera3D = node.get_viewport().get_camera_3d()
		if camera:
			pos = camera.unproject_position(node.global_position)
	else:
		push_warning("InputInjector: Cannot determine click position for node type: %s" % node.get_class())
		return

	await click(pos.x, pos.y)


## Inject a key event.
## action: "tap" (press+release), "press" (hold down), "release", "hold" (press for duration then release)
func key(key_name: String, action: String = "tap", duration: float = 0.0) -> void:
	var keycode: Key = _resolve_key(key_name)
	if keycode == KEY_NONE:
		push_warning("InputInjector: Unknown key: %s" % key_name)
		return

	match action:
		"tap":
			_send_key_event(keycode, true)
			await _tree.process_frame
			_send_key_event(keycode, false)
		"press":
			_send_key_event(keycode, true)
		"release":
			_send_key_event(keycode, false)
		"hold":
			_send_key_event(keycode, true)
			if duration > 0.0:
				await _tree.create_timer(duration).timeout
			else:
				await _tree.process_frame
			_send_key_event(keycode, false)


## Inject an InputEventAction (maps to the project's InputMap).
func trigger_action(action_name: String, pressed: bool = true, strength: float = 1.0) -> void:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = pressed
	event.strength = strength
	Input.parse_input_event(event)


## Inject a mouse motion event.
func mouse_move(x: float, y: float, relative_x: float = 0.0, relative_y: float = 0.0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = Vector2(x, y)
	event.global_position = Vector2(x, y)
	event.relative = Vector2(relative_x, relative_y)
	Input.parse_input_event(event)


## Execute a sequence of input steps with proper timing.
## Each step is a Dictionary with one of: "key", "action", "click", "click_node", "mouse_move", "wait"
func execute_sequence(steps: Array, snapshot_ref: RuntimeSnapshot, scene_root: Node) -> void:
	for step: Dictionary in steps:
		if step.has("wait"):
			await _tree.create_timer(float(step["wait"])).timeout
		elif step.has("key"):
			var dur: float = float(step.get("duration", 0.0))
			var act: String = "tap" if dur == 0.0 else "hold"
			if step.has("action"):
				act = step["action"]
			await key(str(step["key"]), act, dur)
		elif step.has("action"):
			trigger_action(str(step["action"]), step.get("pressed", true), float(step.get("strength", 1.0)))
			await _tree.process_frame
		elif step.has("click"):
			var coords: Array = step["click"]
			await click(float(coords[0]), float(coords[1]))
		elif step.has("click_node"):
			var ref: String = str(step["click_node"])
			var node: Node = snapshot_ref.resolve_ref(ref, scene_root)
			if node:
				await click_node(node)
		elif step.has("mouse_move"):
			var coords: Array = step["mouse_move"]
			mouse_move(float(coords[0]), float(coords[1]))
			await _tree.process_frame


## Resolve a key name string to a Godot Key constant.
func _resolve_key(key_name: String) -> Key:
	var lower: String = key_name.to_lower()
	if KEY_MAP.has(lower):
		return KEY_MAP[lower]
	# Try single character
	if key_name.length() == 1:
		var code: int = key_name.to_upper().unicode_at(0)
		if code >= 65 and code <= 90:  # A-Z
			return code as Key
	return KEY_NONE


## Send a key press or release event.
func _send_key_event(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
