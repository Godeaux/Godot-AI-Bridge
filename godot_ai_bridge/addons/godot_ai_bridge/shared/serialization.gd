## Static utility class for converting Godot types to/from JSON-safe values.
class_name BridgeSerialization


## Serialize any Godot Variant into a JSON-safe value.
static func serialize(value: Variant) -> Variant:
	if value == null:
		return null

	if value is bool or value is int or value is float or value is String:
		return value

	if value is Vector2:
		return [value.x, value.y]

	if value is Vector2i:
		return [value.x, value.y]

	if value is Vector3:
		return [value.x, value.y, value.z]

	if value is Vector3i:
		return [value.x, value.y, value.z]

	if value is Vector4:
		return [value.x, value.y, value.z, value.w]

	if value is Vector4i:
		return [value.x, value.y, value.z, value.w]

	if value is Color:
		return {"r": value.r, "g": value.g, "b": value.b, "a": value.a}

	if value is Rect2:
		return {"position": [value.position.x, value.position.y], "size": [value.size.x, value.size.y]}

	if value is Rect2i:
		return {"position": [value.position.x, value.position.y], "size": [value.size.x, value.size.y]}

	if value is Transform2D:
		return {"origin": [value.origin.x, value.origin.y], "rotation": value.get_rotation()}

	if value is Transform3D:
		var b: Basis = value.basis
		return {
			"origin": [value.origin.x, value.origin.y, value.origin.z],
			"basis": [
				[b.x.x, b.x.y, b.x.z],
				[b.y.x, b.y.y, b.y.z],
				[b.z.x, b.z.y, b.z.z]
			]
		}

	if value is Basis:
		return [
			[value.x.x, value.x.y, value.x.z],
			[value.y.x, value.y.y, value.y.z],
			[value.z.x, value.z.y, value.z.z]
		]

	if value is NodePath:
		return str(value)

	if value is StringName:
		return str(value)

	if value is Quaternion:
		return [value.x, value.y, value.z, value.w]

	if value is AABB:
		return {
			"position": [value.position.x, value.position.y, value.position.z],
			"size": [value.size.x, value.size.y, value.size.z]
		}

	if value is Plane:
		return {"normal": [value.normal.x, value.normal.y, value.normal.z], "d": value.d}

	if value is PackedByteArray:
		return Marshalls.raw_to_base64(value)

	if value is PackedInt32Array or value is PackedInt64Array or value is PackedFloat32Array or value is PackedFloat64Array:
		var arr: Array = []
		for element in value:
			arr.append(element)
		return arr

	if value is PackedStringArray:
		var arr: Array = []
		for element in value:
			arr.append(element)
		return arr

	if value is PackedVector2Array:
		var arr: Array = []
		for element: Vector2 in value:
			arr.append([element.x, element.y])
		return arr

	if value is PackedVector3Array:
		var arr: Array = []
		for element: Vector3 in value:
			arr.append([element.x, element.y, element.z])
		return arr

	if value is PackedColorArray:
		var arr: Array = []
		for element: Color in value:
			arr.append({"r": element.r, "g": element.g, "b": element.b, "a": element.a})
		return arr

	if value is Array:
		var arr: Array = []
		for element: Variant in value:
			arr.append(serialize(element))
		return arr

	if value is Dictionary:
		var dict: Dictionary = {}
		for key: Variant in value:
			dict[str(key)] = serialize(value[key])
		return dict

	if value is Resource:
		if value.resource_path != "":
			return value.resource_path
		return str(value)

	# Fallback for any unhandled type
	return str(value)


## Deserialize a JSON array back to Vector2.
static func deserialize_vector2(arr: Array) -> Vector2:
	return Vector2(float(arr[0]), float(arr[1]))


## Deserialize a JSON array back to Vector2i.
static func deserialize_vector2i(arr: Array) -> Vector2i:
	return Vector2i(int(arr[0]), int(arr[1]))


## Deserialize a JSON array back to Vector3.
static func deserialize_vector3(arr: Array) -> Vector3:
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


## Deserialize a JSON array back to Vector3i.
static func deserialize_vector3i(arr: Array) -> Vector3i:
	return Vector3i(int(arr[0]), int(arr[1]), int(arr[2]))


## Deserialize a JSON array back to Vector4.
static func deserialize_vector4(arr: Array) -> Vector4:
	return Vector4(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))


## Deserialize a JSON dictionary back to Color.
static func deserialize_color(dict: Dictionary) -> Color:
	return Color(float(dict.get("r", 0)), float(dict.get("g", 0)), float(dict.get("b", 0)), float(dict.get("a", 1)))


## Deserialize a JSON dictionary back to Rect2.
static func deserialize_rect2(dict: Dictionary) -> Rect2:
	var pos: Array = dict.get("position", [0, 0])
	var s: Array = dict.get("size", [0, 0])
	return Rect2(float(pos[0]), float(pos[1]), float(s[0]), float(s[1]))


## Attempt to deserialize a JSON value into the appropriate Godot type based on a property hint.
## Used when setting node properties from JSON data.
static func deserialize_property_value(value: Variant, target_type: int) -> Variant:
	if value is Array:
		match target_type:
			TYPE_VECTOR2:
				return deserialize_vector2(value)
			TYPE_VECTOR2I:
				return deserialize_vector2i(value)
			TYPE_VECTOR3:
				return deserialize_vector3(value)
			TYPE_VECTOR3I:
				return deserialize_vector3i(value)
			TYPE_VECTOR4:
				return deserialize_vector4(value)
	if value is Dictionary:
		if value.has("r"):
			return deserialize_color(value)
		if value.has("position") and value.has("size"):
			return deserialize_rect2(value)
	return value
