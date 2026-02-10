## Screenshot capture for the running game viewport.
class_name RuntimeScreenshot
extends RefCounted


## Capture the running game viewport and return as base64 JPEG.
static func capture(viewport: Viewport, width: int = BridgeConfig.DEFAULT_SCREENSHOT_WIDTH, height: int = BridgeConfig.DEFAULT_SCREENSHOT_HEIGHT, quality: float = BridgeConfig.DEFAULT_SCREENSHOT_QUALITY) -> Dictionary:
	var image: Image = viewport.get_texture().get_image()
	if image == null:
		return {"error": "Failed to capture viewport image"}

	if width > 0 and height > 0:
		image.resize(width, height, Image.INTERPOLATE_LANCZOS)

	var base64: String = _encode_jpeg_with_budget(image, quality)

	return {
		"image": base64,
		"mime": "image/jpeg",
		"size": [image.get_width(), image.get_height()],
		"context": "runtime",
		"frame": Engine.get_frames_drawn(),
		"timestamp": Time.get_ticks_msec() / 1000.0,
	}


## Capture a region of the viewport around a specific node.
static func capture_node(node: Node, viewport: Viewport, width: int = 0, height: int = 0, quality: float = BridgeConfig.DEFAULT_SCREENSHOT_QUALITY) -> Dictionary:
	var image: Image = viewport.get_texture().get_image()
	if image == null:
		return {"error": "Failed to capture viewport image"}

	var crop_rect: Rect2i = _get_node_rect(node, viewport)
	if crop_rect.size.x <= 0 or crop_rect.size.y <= 0:
		return {"error": "Could not determine node region"}

	# Clamp to viewport bounds
	var vp_size: Vector2i = image.get_size()
	crop_rect.position.x = clampi(crop_rect.position.x, 0, vp_size.x)
	crop_rect.position.y = clampi(crop_rect.position.y, 0, vp_size.y)
	crop_rect.size.x = mini(crop_rect.size.x, vp_size.x - crop_rect.position.x)
	crop_rect.size.y = mini(crop_rect.size.y, vp_size.y - crop_rect.position.y)

	if crop_rect.size.x <= 0 or crop_rect.size.y <= 0:
		return {"error": "Node region is outside viewport"}

	var cropped: Image = image.get_region(crop_rect)

	if width > 0 and height > 0:
		cropped.resize(width, height, Image.INTERPOLATE_LANCZOS)

	var base64: String = _encode_jpeg_with_budget(cropped, quality)

	return {
		"image": base64,
		"mime": "image/jpeg",
		"size": [cropped.get_width(), cropped.get_height()],
		"context": "runtime_node",
		"node_rect": BridgeSerialization.serialize(Rect2(crop_rect)),
		"frame": Engine.get_frames_drawn(),
		"timestamp": Time.get_ticks_msec() / 1000.0,
	}


## Encode an image as JPEG base64, reducing quality if the result exceeds the size budget.
static func _encode_jpeg_with_budget(image: Image, quality: float) -> String:
	var buffer: PackedByteArray = image.save_jpg_to_buffer(quality)
	var base64: String = Marshalls.raw_to_base64(buffer)

	# If over budget, re-encode at progressively lower quality
	var q: float = quality - 0.15
	while base64.length() > BridgeConfig.MAX_BASE64_LENGTH and q >= 0.2:
		buffer = image.save_jpg_to_buffer(q)
		base64 = Marshalls.raw_to_base64(buffer)
		q -= 0.15

	return base64


## Determine the screen region for a node.
static func _get_node_rect(node: Node, viewport: Viewport) -> Rect2i:
	if node is Control:
		var rect: Rect2 = node.get_global_rect()
		var padding: float = 10.0
		rect = rect.grow(padding)
		return Rect2i(int(rect.position.x), int(rect.position.y), int(rect.size.x), int(rect.size.y))

	if node is Node2D:
		var pos: Vector2 = node.global_position
		var region_size: float = 200.0
		return Rect2i(
			int(pos.x - region_size / 2),
			int(pos.y - region_size / 2),
			int(region_size),
			int(region_size)
		)

	if node is Node3D:
		var camera: Camera3D = viewport.get_camera_3d()
		if camera:
			var screen_pos: Vector2 = camera.unproject_position(node.global_position)
			var region_size: float = 200.0
			return Rect2i(
				int(screen_pos.x - region_size / 2),
				int(screen_pos.y - region_size / 2),
				int(region_size),
				int(region_size)
			)

	return Rect2i(0, 0, 0, 0)
