## Editor viewport screenshot capture.
## Supports two modes: "viewport" (just the 2D/3D canvas) and "full" (entire editor window).
class_name EditorScreenshot
extends RefCounted


## Capture the editor and return as base64 PNG.
## mode: "viewport" = just the 2D/3D main screen canvas, "full" = entire editor window.
static func capture(width: int = BridgeConfig.DEFAULT_SCREENSHOT_WIDTH, height: int = BridgeConfig.DEFAULT_SCREENSHOT_HEIGHT, mode: String = "viewport") -> Dictionary:
	var image: Image = null
	var actual_mode: String = mode

	if mode == "viewport":
		image = _capture_viewport()
		if image == null:
			# Viewport capture failed — fall back to full
			image = _capture_full()
			actual_mode = "full"
	elif mode == "full":
		image = _capture_full()
		if image == null:
			# Full capture failed — try viewport as fallback
			image = _capture_viewport()
			actual_mode = "viewport"
	else:
		return {"error": "Invalid mode '%s' — use 'viewport' or 'full'" % mode}

	if image == null:
		return {"error": "Failed to capture editor screenshot — no available capture method"}

	return _process_image(image, width, height, actual_mode)


## Capture just the 2D/3D editor main screen canvas.
static func _capture_viewport() -> Image:
	var main_screen: VBoxContainer = EditorInterface.get_editor_main_screen()
	if main_screen == null:
		return null
	var viewport: Viewport = main_screen.get_viewport()
	if viewport == null:
		return null
	return viewport.get_texture().get_image()


## Capture the entire editor window (all docks, inspector, scene tree, etc.).
static func _capture_full() -> Image:
	var base_control: Control = EditorInterface.get_base_control()
	if base_control != null:
		var viewport: Viewport = base_control.get_viewport()
		if viewport != null:
			var image: Image = viewport.get_texture().get_image()
			if image != null:
				return image

	# Last resort: OS-level screen capture (not available on all platforms)
	if DisplayServer.has_feature(DisplayServer.FEATURE_SCREEN_CAPTURE):
		return DisplayServer.screen_get_image()

	return null


## Process a captured image: resize and encode to base64 PNG.
static func _process_image(image: Image, width: int, height: int, mode: String) -> Dictionary:
	if width > 0 and height > 0:
		image.resize(width, height, Image.INTERPOLATE_LANCZOS)

	var buffer: PackedByteArray = image.save_png_to_buffer()
	var base64: String = Marshalls.raw_to_base64(buffer)

	return {
		"image": base64,
		"mime": "image/png",
		"size": [image.get_width(), image.get_height()],
		"context": "editor",
		"mode": mode,
	}
