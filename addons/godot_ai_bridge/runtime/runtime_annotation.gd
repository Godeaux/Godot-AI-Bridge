## Annotated Vision — draws ref labels and bounding boxes onto game screenshots.
## Uses a temporary SubViewport to render annotations via _draw() calls,
## then alpha-blends the overlay onto the captured game image.
class_name RuntimeAnnotation
extends RefCounted


## Render annotations onto a captured game screenshot.
## image: raw viewport Image (at viewport resolution, BEFORE resize).
## annotations: Array of {ref, screen_pos, screen_rect?, type}.
## tree: SceneTree needed for SubViewport rendering.
## Returns the annotated Image (same object, modified in place).
static func annotate(image: Image, annotations: Array, tree: SceneTree) -> Image:
	if annotations.is_empty():
		return image

	var vp_size := Vector2i(image.get_width(), image.get_height())

	# Create a SubViewport for rendering the overlay
	var sub_vp := SubViewport.new()
	sub_vp.size = vp_size
	sub_vp.transparent_bg = true
	sub_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	sub_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS

	# Add the annotation canvas
	var overlay := _AnnotationCanvas.new()
	overlay.annotations = annotations
	overlay.size = Vector2(vp_size)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub_vp.add_child(overlay)

	# Must be in the tree to render
	tree.root.add_child(sub_vp)

	# Wait for the SubViewport to render
	await RenderingServer.frame_post_draw

	# Get the rendered overlay and composite it
	var overlay_image: Image = sub_vp.get_texture().get_image()
	if overlay_image != null:
		image.blend_rect(overlay_image, Rect2i(Vector2i.ZERO, vp_size), Vector2i.ZERO)

	# Cleanup
	sub_vp.queue_free()

	return image


## Collect annotation data from the scene tree, computing screen-space positions.
## nodes: The nested nodes array from a snapshot.
## snapshot_obj: The RuntimeSnapshot instance (for resolving refs).
## scene_root: The current scene root node.
## viewport: The game viewport.
## Returns an Array of annotation dictionaries.
static func collect_annotations(
	nodes: Array,
	snapshot_obj: RefCounted,
	scene_root: Node,
	viewport: Viewport,
	max_annotations: int = 50,
) -> Array:
	var annotations: Array = []
	var canvas_xform: Transform2D = viewport.get_canvas_transform()
	var camera_3d: Camera3D = viewport.get_camera_3d()
	var vp_size: Vector2 = viewport.get_visible_rect().size

	_collect_from_nodes(
		nodes, annotations, snapshot_obj, scene_root,
		canvas_xform, camera_3d, vp_size, max_annotations
	)

	return annotations


## Recursively walk snapshot nodes and build annotation data.
static func _collect_from_nodes(
	nodes: Array,
	out: Array,
	snapshot_obj: RefCounted,
	scene_root: Node,
	canvas_xform: Transform2D,
	camera_3d: Camera3D,
	vp_size: Vector2,
	max_annotations: int,
) -> void:
	for node_data: Variant in nodes:
		if out.size() >= max_annotations:
			return
		if node_data is not Dictionary:
			continue

		# Skip invisible nodes
		if not node_data.get("visible", true):
			continue

		var ref: String = node_data.get("ref", "")
		var node_type: String = node_data.get("type", "")

		# Resolve the actual Node from the ref
		var node: Node = snapshot_obj.resolve_ref(ref, scene_root)
		if node == null:
			# Recurse into children even if this node can't be resolved
			_collect_from_nodes(
				node_data.get("children", []), out, snapshot_obj, scene_root,
				canvas_xform, camera_3d, vp_size, max_annotations
			)
			continue

		# Skip nodes that aren't useful annotation targets
		if not _should_annotate(node, node_data):
			_collect_from_nodes(
				node_data.get("children", []), out, snapshot_obj, scene_root,
				canvas_xform, camera_3d, vp_size, max_annotations
			)
			continue

		# Compute screen-space position
		var ann: Dictionary = {"ref": ref, "type": node_type}

		if node is Control:
			ann["screen_pos"] = node.global_position + node.size / 2.0
			ann["screen_rect"] = Rect2(node.global_position, node.size)
		elif node is Node2D:
			ann["screen_pos"] = canvas_xform * node.global_position
		elif node is Node3D:
			if camera_3d and not camera_3d.is_position_behind(node.global_position):
				ann["screen_pos"] = camera_3d.unproject_position(node.global_position)

		# Only add if we got a valid screen position within the viewport
		if ann.has("screen_pos"):
			var sp: Vector2 = ann["screen_pos"]
			if sp.x >= 0 and sp.y >= 0 and sp.x <= vp_size.x and sp.y <= vp_size.y:
				out.append(ann)

		# Recurse into children
		_collect_from_nodes(
			node_data.get("children", []), out, snapshot_obj, scene_root,
			canvas_xform, camera_3d, vp_size, max_annotations
		)


## Decide whether a node is worth annotating.
static func _should_annotate(node: Node, node_data: Dictionary) -> bool:
	# Must be visible
	if not node_data.get("visible", true):
		return false

	# Skip organizational containers with no game logic
	var skip_types: Array[String] = ["Node", "CanvasLayer", "ParallaxBackground"]
	if node_data.get("type", "") in skip_types:
		if node_data.get("properties", {}).is_empty():
			return false

	# Always annotate nodes with text content (Labels, Buttons)
	if node_data.get("text") != null:
		return true

	# Always annotate nodes with script properties (game logic)
	if not node_data.get("properties", {}).is_empty():
		return true

	# Annotate common visual/interactive types
	if node is Control:
		return true
	if node is Sprite2D or node is AnimatedSprite2D:
		return true
	if node is CharacterBody2D or node is RigidBody2D or node is Area2D:
		return true
	if node is CharacterBody3D or node is RigidBody3D or node is Area3D:
		return true
	if node is Camera2D or node is Camera3D:
		return true

	# Skip everything else (pure Node2D/Node3D containers, etc.)
	return false


## Internal overlay Control that renders all annotations via _draw().
class _AnnotationCanvas extends Control:
	var annotations: Array = []

	func _draw() -> void:
		var font: Font = ThemeDB.fallback_font
		var font_size: int = 14

		for ann: Variant in annotations:
			if ann is not Dictionary:
				continue
			var pos: Variant = ann.get("screen_pos")
			if pos is not Vector2:
				continue

			var ref: String = ann.get("ref", "")
			var screen_pos: Vector2 = pos

			# Draw bounding rect for Control nodes (green outline)
			if ann.has("screen_rect") and ann["screen_rect"] is Rect2:
				var rect: Rect2 = ann["screen_rect"]
				draw_rect(rect, Color(0.0, 1.0, 0.0, 0.4), false, 1.5)

			# Measure the ref label text
			var text_size: Vector2 = font.get_string_size(
				ref, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
			)

			# Position label above the node center
			var label_pos := Vector2(screen_pos.x - text_size.x / 2.0, screen_pos.y - 12.0)

			# Clamp to viewport bounds
			label_pos.x = clampf(label_pos.x, 2.0, size.x - text_size.x - 2.0)
			label_pos.y = clampf(label_pos.y, text_size.y + 2.0, size.y - 2.0)

			# Background pill behind the label
			var bg_rect := Rect2(
				label_pos.x - 2.0,
				label_pos.y - text_size.y - 1.0,
				text_size.x + 4.0,
				text_size.y + 4.0
			)
			draw_rect(bg_rect, Color(0.0, 0.0, 0.0, 0.75))

			# Text with outline for readability
			draw_string_outline(
				font, label_pos, ref, HORIZONTAL_ALIGNMENT_LEFT,
				-1, font_size, 3, Color.BLACK
			)
			draw_string(
				font, label_pos, ref, HORIZONTAL_ALIGNMENT_LEFT,
				-1, font_size, Color.WHITE
			)

			# Small dot at the exact node position
			draw_circle(screen_pos, 3.0, Color(1.0, 0.3, 0.3, 0.9))
