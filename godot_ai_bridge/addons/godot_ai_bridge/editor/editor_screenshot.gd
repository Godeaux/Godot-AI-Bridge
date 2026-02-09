## Editor viewport screenshot capture.
class_name EditorScreenshot
extends RefCounted


## Capture the editor viewport and return as base64 PNG.
static func capture(width: int = BridgeConfig.DEFAULT_SCREENSHOT_WIDTH, height: int = BridgeConfig.DEFAULT_SCREENSHOT_HEIGHT) -> Dictionary:
	# Try multiple approaches for capturing the editor viewport

	# Approach 1: Get the editor's main screen viewport
	var main_screen: VBoxContainer = EditorInterface.get_editor_main_screen()
	if main_screen != null:
		var viewport: Viewport = main_screen.get_viewport()
		if viewport != null:
			var image: Image = viewport.get_texture().get_image()
			if image != null:
				return _process_image(image, width, height)

	# Approach 2: Use the base control's viewport
	var base_control: Control = EditorInterface.get_base_control()
	if base_control != null:
		var viewport: Viewport = base_control.get_viewport()
		if viewport != null:
			var image: Image = viewport.get_texture().get_image()
			if image != null:
				return _process_image(image, width, height)

	# Approach 3: DisplayServer screen capture (may not be available on all platforms)
	if DisplayServer.has_feature(DisplayServer.FEATURE_SCREEN_CAPTURE):
		var image: Image = DisplayServer.screen_get_image()
		if image != null:
			return _process_image(image, width, height)

	return {"error": "Failed to capture editor screenshot — no available capture method"}


## Process a captured image: resize and encode to base64 PNG.
static func _process_image(image: Image, width: int, height: int) -> Dictionary:
	if width > 0 and height > 0:
		image.resize(width, height, Image.INTERPOLATE_LANCZOS)

	var buffer: PackedByteArray = image.save_png_to_buffer()
	var base64: String = Marshalls.raw_to_base64(buffer)

	return {
		"image": base64,
		"mime": "image/png",
		"size": [image.get_width(), image.get_height()],
		"context": "editor",
	}
